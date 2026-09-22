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

/// Minimal Keychain-backed storage for integration tokens.
enum IntegrationTokens {
    enum Key: String, CaseIterable {
        case slack = "buddi.integration.slack"
        case clickUp = "buddi.integration.clickup"
        case hub = "buddi.integration.hub"
    }

    static func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    @discardableResult
    static func write(_ key: Key, token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        delete(key)
        guard !trimmed.isEmpty else { return true }
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.rawValue,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
