//
//  SessionAppFocuser.swift
//  Buddi
//
//  Single entry point for "jump to this session": multiplexer sessions go
//  through yabai window targeting first; everything else raises the GUI app
//  hosting the session's process tree (VS Code, Terminal, iTerm, ...).
//

import AppKit

enum SessionAppFocuser {
    /// Editors that ship a `code`-style CLI able to raise the window that has
    /// a given folder open. Checked in order inside Contents/Resources/app/bin.
    private static let editorCLINames = ["code", "cursor", "codium", "windsurf"]

    /// Unified jump-to-session used by the popup bubble and the instances
    /// list, so both surfaces always land in the same place.
    static func focus(_ session: SessionState) {
        guard session.isInMultiplexer else {
            focusHostApp(of: session)
            return
        }
        Task {
            let focused: Bool
            if let pid = session.pid {
                focused = await YabaiController.shared.focusWindow(forClaudePid: pid)
            } else {
                focused = await YabaiController.shared.focusWindow(forWorkingDirectory: session.cwd)
            }
            if !focused {
                focusHostApp(of: session)
            }
        }
    }

    /// Focus the GUI app that owns a session's process (e.g. VS Code for
    /// sessions started from its integrated terminal or extension).
    static func focusHostApp(of session: SessionState) {
        guard let sessionPid = session.pid else { return }

        Task.detached(priority: .userInitiated) {
            let tree = ProcessTreeBuilder.shared.buildTree()

            // Walk to the first REAL GUI app in the ancestry. Deliberately not
            // TerminalAppRegistry here: its substring matching ("code") hits
            // the claude CLI path (~/.vscode/extensions/...claude-code...) and
            // the "Code Helper" processes, none of which can be activated, so
            // the jump would silently no-op. NSRunningApplication + .regular
            // is the ground truth for "something we can raise".
            let hostPid: Int? = await MainActor.run {
                var pid = sessionPid
                var hops = 0
                while hops < 20, pid > 1, let info = tree[pid] {
                    if let app = NSRunningApplication(processIdentifier: pid_t(info.pid)),
                       app.activationPolicy == .regular {
                        return info.pid
                    }
                    pid = info.ppid
                    hops += 1
                }
                return nil
            }

            guard let hostPid else {
                NSLog("[SessionAppFocuser] no GUI host found for session pid %d", sessionPid)
                return
            }

            let projectFolder = URL(fileURLWithPath: projectRoot(for: session.cwd)).lastPathComponent

            // With Accessibility granted, raise the exact window whose title
            // carries the project folder; works for any host app and never
            // opens new windows. Silently skipped without the permission.
            let raisedViaAX = await MainActor.run {
                raiseWindowViaAX(hostPid: hostPid, matching: projectFolder)
            }

            // For VS Code-style editors, `<cli> <folder>` raises the window
            // that already has the project open. Use the project root (nearest
            // ancestor with .git) so a session started in a subdirectory does
            // not open a brand-new window on that subfolder.
            let bundleURL = await MainActor.run {
                NSRunningApplication(processIdentifier: pid_t(hostPid))?.bundleURL
            }

            if !raisedViaAX, let bundleURL, let cli = editorCLI(in: bundleURL) {
                let process = Process()
                process.executableURL = cli
                process.arguments = [projectRoot(for: session.cwd)]
                do {
                    try process.run()
                } catch {
                    NSLog("[SessionAppFocuser] editor CLI failed: %@", "\(error)")
                }
            }

            await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: pid_t(hostPid)) else { return }
                NSLog("[SessionAppFocuser] focusing %@ (pid %d) for cwd %@",
                      app.bundleIdentifier ?? "?", hostPid, session.cwd)

                // The notch overlay never becomes the active app, so a plain
                // activate() is dropped by macOS cooperative activation.
                // NSWorkspace.openApplication counts as user-initiated and
                // reliably raises the (already running) app.
                if let bundleURL = app.bundleURL {
                    let config = NSWorkspace.OpenConfiguration()
                    config.activates = true
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
                        if let error {
                            NSLog("[SessionAppFocuser] openApplication failed: %@", "\(error)")
                            DispatchQueue.main.async {
                                app.activate(options: [.activateIgnoringOtherApps])
                            }
                        }
                    }
                } else {
                    app.activate(options: [.activateIgnoringOtherApps])
                }

                // Sessions started from the Claude Code extension can be
                // opened exactly: its URI handler takes ?session=<id> and
                // brings that chat up in the editor. Sent after the right
                // window is raised so the window that receives it is the one
                // with this project. Terminal sessions are skipped on purpose:
                // opening those in the extension would resume them a second time.
                if let url = exactSessionURL(for: session, hostBundleId: app.bundleIdentifier) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    /// `<scheme>://anthropic.claude-code/open?session=<id>` for extension
    /// sessions in a VS Code-family editor, else nil.
    private static func exactSessionURL(for session: SessionState, hostBundleId: String?) -> URL? {
        let schemes: [String: String] = [
            "com.microsoft.VSCode": "vscode",
            "com.microsoft.VSCodeInsiders": "vscode-insiders",
            "com.todesktop.230313mzl4w4u92": "cursor",
            "com.exafunction.windsurf": "windsurf",
            "com.vscodium": "vscodium",
        ]
        guard let bundleId = hostBundleId,
              let scheme = schemes[bundleId],
              let pid = session.pid,
              isExtensionSession(pid: pid),
              UUID(uuidString: session.sessionId) != nil
        else { return nil }
        return URL(string: "\(scheme)://anthropic.claude-code/open?session=\(session.sessionId)")
    }

    /// Claude Code records each live process in ~/.claude/sessions/<pid>.json
    /// with its entrypoint; the extension's sessions say "claude-vscode".
    private static func isExtensionSession(pid: Int) -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions/\(pid).json")
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entrypoint = json["entrypoint"] as? String
        else { return false }
        return entrypoint.hasPrefix("claude-vscode")
    }

    /// Raise the host app window whose title mentions the project folder.
    /// Needs the Accessibility permission (System Settings > Privacy &
    /// Security > Accessibility > Buddi); returns false when not granted or
    /// no window matches.
    @MainActor
    private static func raiseWindowViaAX(hostPid: Int, matching folderName: String) -> Bool {
        guard AXIsProcessTrusted(), !folderName.isEmpty else { return false }
        let app = AXUIElementCreateApplication(pid_t(hostPid))
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return false }

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String,
                  title.localizedCaseInsensitiveContains(folderName)
            else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            NSLog("[SessionAppFocuser] raised window via AX: %@", title)
            return true
        }
        return false
    }

    /// Locate a `code`-style CLI inside an editor bundle, if any.
    private nonisolated static func editorCLI(in bundleURL: URL) -> URL? {
        let binDir = bundleURL.appendingPathComponent("Contents/Resources/app/bin")
        for name in editorCLINames {
            let candidate = binDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    /// Nearest ancestor of cwd containing .git (max 5 hops), else cwd itself.
    private nonisolated static func projectRoot(for cwd: String) -> String {
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
                return dir.path
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return cwd
    }
}
