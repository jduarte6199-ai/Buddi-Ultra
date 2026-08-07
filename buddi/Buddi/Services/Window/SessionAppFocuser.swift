//
//  SessionAppFocuser.swift
//  Buddi
//
//  Brings the app hosting a Claude session (VS Code, Terminal, iTerm, ...)
//  to the front by walking the session's process ancestry up to the first
//  regular GUI application.
//

import AppKit

enum SessionAppFocuser {
    /// Focus the GUI app that owns a session's process (e.g. VS Code for
    /// sessions started from its integrated terminal or extension).
    static func focusHostApp(of session: SessionState) {
        guard let sessionPid = session.pid else { return }

        Task.detached(priority: .userInitiated) {
            let tree = ProcessTreeBuilder.shared.buildTree()

            var pid = sessionPid
            var hops = 0
            var hostPid: Int?
            while hops < 20, pid > 1, let info = tree[pid] {
                if isGUIApp(pid: info.pid) {
                    hostPid = info.pid
                    break
                }
                pid = info.ppid
                hops += 1
            }

            guard let hostPid else {
                NSLog("[SessionAppFocuser] no GUI host found for session pid %d", sessionPid)
                return
            }
            let cwd = session.cwd
            await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: pid_t(hostPid)) else { return }
                NSLog("[SessionAppFocuser] focusing %@ (pid %d) for cwd %@",
                      app.bundleIdentifier ?? "?", hostPid, cwd)

                // For VS Code, `code <folder>` reuses (and raises) the window
                // that already has the session's project open, so we land on
                // the right window instead of just the last-used one.
                if let bundleId = app.bundleIdentifier,
                   bundleId.hasPrefix("com.microsoft.VSCode"),
                   let cliURL = app.bundleURL?
                       .appendingPathComponent("Contents/Resources/app/bin/code"),
                   FileManager.default.fileExists(atPath: cliURL.path)
                {
                    let process = Process()
                    process.executableURL = cliURL
                    process.arguments = [cwd]
                    do {
                        try process.run()
                    } catch {
                        NSLog("[SessionAppFocuser] code CLI failed: %@", "\(error)")
                    }
                }

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

    private nonisolated static func isGUIApp(pid: Int) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else {
            return false
        }
        return app.activationPolicy == .regular
    }
}
