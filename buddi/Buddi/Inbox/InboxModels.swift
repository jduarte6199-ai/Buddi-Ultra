//
//  InboxModels.swift
//  Buddi
//
//  Models and token storage for the Inbox tab: Slack unreads, ClickUp tasks
//  due, and BOA hub tickets. Tokens live in the login Keychain, never in
//  UserDefaults, never in the repo.
//

import Defaults
import Foundation
import Security

// MARK: - Items

enum InboxSource: String, CaseIterable, Identifiable {
    case slack
    case clickUp
    case hubTickets

    var id: String { rawValue }

    var label: String {
        switch self {
        case .slack: return "Slack"
        case .clickUp: return "ClickUp"
        case .hubTickets: return "Hub Tickets"
        }
    }

    var icon: String {
        switch self {
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .clickUp: return "checklist"
        case .hubTickets: return "ticket.fill"
        }
    }

    /// Per-source on/off switch (Inbox gear panel). Off means the section is
    /// hidden and its provider is never polled.
    var enabledKey: Defaults.Key<Bool> {
        switch self {
        case .slack: return .slackInboxEnabled
        case .clickUp: return .clickUpInboxEnabled
        case .hubTickets: return .hubTicketsInboxEnabled
        }
    }

    var isEnabled: Bool {
        Defaults[enabledKey]
    }
}

struct InboxItem: Identifiable, Equatable {
    let id: String
    let source: InboxSource
    let title: String
    let subtitle: String
    /// Opened when the row is clicked (slack:// deep link, task URL, hub board).
    let url: URL?
    let date: Date?
}

/// Per-provider fetch outcome, driving the section UI.
enum InboxSectionState: Equatable {
    /// No token configured yet; shows the setup hint.
    case needsToken
    case loading
    case loaded([InboxItem])
    case failed(String)
}

// MARK: - Token storage (Keychain)

/// Keychain-backed storage for integration tokens, done entirely through
/// Apple's /usr/bin/security tool. Items it creates trust that tool in their
/// access list, so every later read is silent. Items created by Buddi's own
/// process are bound to the binary's code hash instead, and since every
/// rebuild changes that hash, each update would re-prompt for the password.
enum IntegrationTokens {
    enum Key: String, CaseIterable {
        case slack = "buddi.integration.slack"
        case clickUp = "buddi.integration.clickup"
        case hub = "buddi.integration.hub"
    }

    static func read(_ key: Key) -> String? {
        guard let output = run(["find-generic-password", "-s", key.rawValue, "-w"]) else {
            return nil
        }
        let token = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// Note: the value is passed as an argument, so it is visible in the
    /// process list for the few milliseconds the tool runs. Acceptable for a
    /// single-user machine; `security` offers no stdin form for -w.
    @discardableResult
    static func write(_ key: Key, token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(key)
            return true
        }
        return run([
            "add-generic-password", "-U",
            "-a", NSUserName(),
            "-s", key.rawValue,
            "-w", trimmed,
        ]) != nil
    }

    static func delete(_ key: Key) {
        _ = run(["delete-generic-password", "-s", key.rawValue])
    }

    /// Runs /usr/bin/security; returns stdout on exit 0, nil otherwise.
    static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
