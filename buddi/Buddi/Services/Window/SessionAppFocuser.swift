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
            let chatTitle = session.displayTitle

            // With Accessibility granted: find the editor tab named after this
            // chat (Claude Code tabs carry the session title), raise its
            // window and press the tab. Failing that, raise the window whose
            // title carries the project folder. Never opens anything new.
            let raisedViaAX = await MainActor.run { () -> Bool in
                guard ensureAccessibility() else { return false }
                return pressChatTab(hostPid: hostPid, title: chatTitle)
                    || raiseWindowViaAX(hostPid: hostPid, matching: projectFolder)
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

            }
        }
    }

    private static var accessibilityPrompted = false

    /// True when Buddi may read other apps' windows. The first time it is
    /// missing, macOS's own dialog points to System Settings (once per run).
    @MainActor
    private static func ensureAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !accessibilityPrompted {
            accessibilityPrompted = true
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        return false
    }

    /// Find the editor tab whose label is this chat's title, raise its window
    /// and select it. VS Code truncates long tab labels with "…", so a label
    /// matches when the full title starts with it.
    @MainActor
    private static func pressChatTab(hostPid: Int, title: String) -> Bool {
        let wanted = title.trimmingCharacters(in: .whitespaces)
        guard wanted.count >= 3 else { return false }
        let app = AXUIElementCreateApplication(pid_t(hostPid))
        // Chromium builds its accessibility tree only when asked.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else { return false }

        for window in windows {
            var budget = 8000
            guard let tab = findTab(in: window, matching: wanted, depth: 0, budget: &budget) else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementPerformAction(tab, kAXPressAction as CFString)
            NSLog("[SessionAppFocuser] selected chat tab: %@", wanted)
            return true
        }
        return false
    }

    @MainActor
    private static func findTab(in element: AXUIElement, matching title: String,
                                depth: Int, budget: inout Int,
                                insideWebArea: Bool = false) -> AXUIElement? {
        budget -= 1
        guard depth < 32, budget > 0 else { return nil }
        let role = axString(element, kAXRoleAttribute) ?? ""
        // Tabs live in the workbench chrome. Nested web areas (each chat's
        // webview, thousands of nodes), file trees and tables never hold
        // editor tabs, and walking them is what made the search take seconds.
        if role == "AXWebArea" && insideWebArea { return nil }
        if role == "AXOutline" || role == "AXTable" { return nil }
        if axString(element, kAXSubroleAttribute) == "AXTabButton" {
            return tabLabels(element).contains(where: { labelMatches($0, title: title) }) ? element : nil
        }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            if let found = findTab(in: child, matching: title, depth: depth + 1, budget: &budget,
                                   insideWebArea: insideWebArea || role == "AXWebArea") {
                return found
            }
        }
        return nil
    }

    /// Text inside a tab button (its own attributes and a few levels down).
    @MainActor
    private static func tabLabels(_ element: AXUIElement, depth: Int = 0) -> [String] {
        guard depth < 4 else { return [] }
        var labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
            .compactMap { axString(element, $0) }
            .filter { !$0.isEmpty }
        var childrenRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        for child in (childrenRef as? [AXUIElement]) ?? [] {
            labels += tabLabels(child, depth: depth + 1)
        }
        return labels
    }

    private static func labelMatches(_ label: String, title: String) -> Bool {
        // "Chat name…, Window 2: Editor Group 1" -> "Chat name"
        var text = label.components(separatedBy: ", Window ").first ?? label
        text = text.trimmingCharacters(in: .whitespaces)
        let truncated = text.hasSuffix("…")
        if truncated { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard text.count >= 3 else { return false }
        return truncated ? title.hasPrefix(text) : title == text
    }

    @MainActor
    private static func axString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        return ref as? String
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
