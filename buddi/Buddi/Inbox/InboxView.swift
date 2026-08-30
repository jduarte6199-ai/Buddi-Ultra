//
//  InboxView.swift
//  Buddi
//
//  The Inbox tab: pending Slack messages, ClickUp tasks due, and hub
//  tickets, each section with its own state. Sections without a token show
//  an inline setup field that stores the token in the Keychain.
//

import AppKit
import Defaults
import SwiftUI

struct InboxView: View {
    @ObservedObject private var viewModel = InboxViewModel.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                SessionActivitySection()
                ForEach(InboxSource.allCases) { source in
                    InboxSection(
                        source: source,
                        state: viewModel.sections[source] ?? .loading,
                        onTokenSaved: { viewModel.refresh() }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { viewModel.startPolling() }
    }
}

/// History of notch popups (ready chats, approvals, meetings), so anything
/// missed while away is still reviewable. Click jumps to the session when it
/// is still alive.
private struct SessionActivitySection: View {
    @ObservedObject private var log = SessionEventLog.shared
    @Default(.unattendedRemindersEnabled) private var remindersEnabled
    @Default(.unattendedReminderMinutes) private var reminderMinutes
    @State private var showsConfig = false

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Claude activity")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showsConfig.toggle()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Configure unanswered-chat reminders")
                if !log.events.isEmpty {
                    Button("Clear") { log.clear() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if showsConfig {
                HStack(spacing: 8) {
                    Toggle("Remind unanswered chats", isOn: $remindersEnabled)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Picker("every", selection: $reminderMinutes) {
                        Text("3 min").tag(3)
                        Text("5 min").tag(5)
                        Text("10 min").tag(10)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .frame(width: 110)
                    .disabled(!remindersEnabled)
                }
                .padding(.vertical, 2)
            }

            if log.events.isEmpty {
                Text("No recent notifications")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(log.events.prefix(12)) { event in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: event.kind))
                            .font(.caption2)
                            .foregroundStyle(color(for: event.kind))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(event.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(event.projectName) · \(Self.timeFormatter.string(from: event.date))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let session = BuddiSessionBridge.shared.sessionMonitor.instances
                            .first(where: { $0.sessionId == event.sessionId }) {
                            SessionAppFocuser.focus(session)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "approval": return "hand.raised.fill"
        case "meeting": return "calendar"
        default: return "checkmark.circle.fill"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "approval": return TerminalColors.amber
        case "meeting": return Color(red: 0.35, green: 0.55, blue: 1.0)
        default: return .green
        }
    }
}

private struct InboxSection: View {
    let source: InboxSource
    let state: InboxSectionState
    let onTokenSaved: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: source.icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(source.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if case .loaded(let items) = state, !items.isEmpty {
                    Text("\(items.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .background(Capsule().fill(TerminalColors.green))
                }
            }

            switch state {
            case .loading:
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .needsToken:
                TokenSetupRow(source: source, onSaved: onTokenSaved)
            case .failed(let message):
                Text("Error: \(message)")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            case .loaded(let items):
                if items.isEmpty {
                    Text("All clear")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(items.prefix(8)) { item in
                        InboxRow(item: item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
    }
}

private struct InboxRow: View {
    let item: InboxItem
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.url != nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Color.gray.opacity(0.18) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture {
            if let url = item.url {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Inline token entry: pasted value goes straight to the Keychain.
private struct TokenSetupRow: View {
    let source: InboxSource
    let onSaved: () -> Void

    @State private var token = ""
    @State private var hubURL = HubTicketsInboxProvider.baseURL

    private var keychainKey: IntegrationTokens.Key {
        switch source {
        case .slack: return .slack
        case .clickUp: return .clickUp
        case .hubTickets: return .hub
        }
    }

    private var placeholder: String {
        switch source {
        case .slack: return "xoxp-… (User OAuth Token)"
        case .clickUp: return "pk_… (ClickUp API token)"
        case .hubTickets: return "hub agent token"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if source == .hubTickets {
                TextField("https://hub.example.com", text: $hubURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }
            HStack(spacing: 6) {
                SecureField(placeholder, text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("Save") {
                    if source == .hubTickets {
                        UserDefaults.standard.set(
                            hubURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            forKey: "hubBaseURL"
                        )
                    }
                    IntegrationTokens.write(keychainKey, token: token)
                    token = ""
                    onSaved()
                }
                .font(.caption)
                .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Stored in your Mac's Keychain only.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
