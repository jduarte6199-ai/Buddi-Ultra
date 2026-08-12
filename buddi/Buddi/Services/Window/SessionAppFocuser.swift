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

            // Prefer the shared terminal registry (same source of truth the
            // focus-detection code uses), then fall back to the first regular
            // GUI app in the ancestry.
            var hostPid = ProcessTreeBuilder.shared.findTerminalPid(forProcess: sessionPid, tree: tree)
            if hostPid == nil {
                var pid = sessionPid
                var hops = 0
                while hops < 20, pid > 1, let info = tree[pid] {
                    if let app = NSRunningApplication(processIdentifier: pid_t(info.pid)),
                       app.activationPolicy == .regular {
                        hostPid = info.pid
                        break
                    }
                    pid = info.ppid
                    hops += 1
                }
            }

            guard let hostPid else {
                NSLog("[SessionAppFocuser] no GUI host found for session pid %d", sessionPid)
                return
            }

            // For VS Code-style editors, `<cli> <folder>` raises the window
            // that already has the project open. Use the project root (nearest
            // ancestor with .git) so a session started in a subdirectory does
            // not open a brand-new window on that subfolder.
            let bundleInfo = await MainActor.run { () -> (bundleId: String?, bundleURL: URL?) in
                guard let app = NSRunningApplication(processIdentifier: pid_t(hostPid)) else {
                    return (nil, nil)
                }
                return (app.bundleIdentifier, app.bundleURL)
            }

            if let bundleURL = bundleInfo.bundleURL,
               let cli = editorCLI(in: bundleURL) {
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
            }
        }
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
