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
            await MainActor.run {
                NSRunningApplication(processIdentifier: pid_t(hostPid))?.activate()
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
