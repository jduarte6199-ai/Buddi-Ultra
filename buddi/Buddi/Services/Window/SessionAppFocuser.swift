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

            guard let hostPid else { return }
            let cwd = session.cwd
            await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: pid_t(hostPid)) else { return }

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
                    try? process.run()
                }

                app.activate()
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
