//
//  ClaudeInstancesView.swift
//  Buddi
//
//  Minimal instances list
//

import Combine
import SwiftUI

struct ClaudeInstancesView: View {
    @ObservedObject var sessionMonitor: ClaudeSessionMonitor
    @ObservedObject var viewModel: BuddyPanelViewModel

    /// "all", "reply" (needs my reply), or "project:<name>".
    @AppStorage("chatListFilter") private var filter = "all"
    @AppStorage("chatFolderTabsVisible") private var tabsVisible = true

    var body: some View {
        if sessionMonitor.instances.isEmpty {
            emptyState
        } else {
            VStack(spacing: 4) {
                if tabsVisible {
                    filterStrip
                }
                if visibleInstances.isEmpty {
                    Text(filter == "reply" ? "Nothing waiting on you" : "No chats here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    instancesList
                }
            }
            .overlay(alignment: .topTrailing) {
                if !tabsVisible {
                    Button {
                        withAnimation(.smooth) { tabsVisible = true }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Show folder tabs and filters")
                    .padding(.trailing, 6)
                }
            }
        }
    }

    // MARK: - Filters and folder tabs

    private func needsReply(_ session: SessionState) -> Bool {
        session.phase.needsAttention
    }

    /// Project folders present, most chats first, then alphabetical.
    private var projects: [(name: String, count: Int)] {
        let counts = Dictionary(grouping: sessionMonitor.instances, by: \.projectName)
            .mapValues(\.count)
        return counts.map { ($0.key, $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }

    private var visibleInstances: [SessionState] {
        switch filter {
        case "all":
            return sortedInstances
        case "reply":
            return sortedInstances.filter(needsReply)
        default:
            let project = String(filter.dropFirst("project:".count))
            return sortedInstances.filter { $0.projectName == project }
        }
    }

    private var filterStrip: some View {
        let replyCount = sessionMonitor.instances.filter(needsReply).count
        return HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    FilterChip(label: "All", count: sessionMonitor.instances.count,
                               selected: filter == "all") { filter = "all" }
                    FilterChip(label: "Needs reply", count: replyCount,
                               selected: filter == "reply",
                               glow: replyCount > 0 ? TerminalColors.green : nil) { filter = "reply" }
                    ForEach(projects, id: \.name) { project in
                        FilterChip(label: project.name, count: project.count,
                                   selected: filter == "project:\(project.name)",
                                   icon: "folder") { filter = "project:\(project.name)" }
                    }
                }
                .padding(.horizontal, 2)
            }
            Button {
                withAnimation(.smooth) { tabsVisible = false }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Hide folder tabs")
        }
        .padding(.horizontal, 6)
        .onAppear {
            // A remembered project tab whose chats are all gone falls back to All.
            if filter.hasPrefix("project:"),
               !projects.contains(where: { "project:\($0.name)" == filter }) {
                filter = "all"
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text("Run claude in terminal")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Instances List

    /// Priority: active (approval/processing/compacting) > waitingForInput > idle
    /// Secondary sort: by last user message date (stable - doesn't change when agent responds)
    /// Note: approval requests stay in their date-based position to avoid layout shift
    private var sortedInstances: [SessionState] {
        sessionMonitor.instances.sorted { a, b in
            let priorityA = phasePriority(a.phase)
            let priorityB = phasePriority(b.phase)
            if priorityA != priorityB {
                return priorityA < priorityB
            }
            // Sort by last user message date (more recent first)
            // Fall back to lastActivity if no user messages yet
            let dateA = a.lastUserMessageDate ?? a.lastActivity
            let dateB = b.lastUserMessageDate ?? b.lastActivity
            return dateA > dateB
        }
    }

    /// Lower number = higher priority
    /// Approval requests share priority with processing to maintain stable ordering
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval, .processing, .compacting: return 0
        case .waitingForInput: return 1
        case .idle, .ended: return 2
        }
    }

    private var instancesList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(visibleInstances) { session in
                    InstanceRow(
                        session: session,
                        onFocus: { focusSession(session) },
                        onChat: { openChat(session) },
                        onArchive: { archiveSession(session) },
                        onApprove: { approveSession(session) },
                        onReject: { rejectSession(session) }
                    )
                    .id(session.stableId)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    private func focusSession(_ session: SessionState) {
        SessionAppFocuser.focus(session)
    }

    private func openChat(_ session: SessionState) {
        viewModel.showChat(for: session)
    }

    private func approveSession(_ session: SessionState) {
        sessionMonitor.approvePermission(sessionId: session.sessionId)
    }

    private func rejectSession(_ session: SessionState) {
        sessionMonitor.denyPermission(sessionId: session.sessionId, reason: nil)
    }

    private func archiveSession(_ session: SessionState) {
        sessionMonitor.archiveSession(sessionId: session.sessionId)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let count: Int
    let selected: Bool
    var icon: String? = nil
    /// When set, the chip glows in this color (e.g. chats waiting on you).
    var glow: Color? = nil
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 9))
                }
                if glow != nil {
                    Circle()
                        .fill(glow ?? .clear)
                        .frame(width: 5, height: 5)
                        .opacity(pulse ? 1 : 0.4)
                }
                Text(label).lineLimit(1)
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(selected ? Color.white.opacity(0.16) : Color.white.opacity(0.05)))
            .overlay(
                Capsule().stroke((glow ?? .clear).opacity(pulse ? 0.7 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            guard glow != nil else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever()) { pulse = true }
        }
    }
}

// MARK: - Instance Row

struct InstanceRow: View {
    let session: SessionState
    let onFocus: () -> Void
    let onChat: () -> Void
    let onArchive: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isHovered = false
    @State private var glowPulse = false
    @State private var spinnerPhase = 0
    @State private var isYabaiAvailable = false

    private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let spinnerSymbols = ["·", "✢", "✳", "∗", "✻", "✽"]
    private let spinnerTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()

    /// Whether we're showing the approval UI
    private var isWaitingForApproval: Bool {
        session.phase.isWaitingForApproval
    }

    /// Whether the pending tool requires interactive input (not just approve/deny)
    private var isInteractiveTool: Bool {
        guard let toolName = session.pendingToolName else { return false }
        return toolName == "AskUserQuestion"
    }

    /// Glow color for chats waiting on the user, nil otherwise.
    private var glowColor: Color? {
        switch session.phase {
        case .waitingForApproval: return TerminalColors.amber
        case .waitingForInput: return TerminalColors.green
        default: return nil
        }
    }

    /// Whether a jump-to-session route exists: yabai for multiplexer
    /// sessions, host-app raise (needs a pid) for everything else.
    private var canFocusSession: Bool {
        session.isInMultiplexer ? isYabaiAvailable : session.pid != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // State indicator on left
            stateIndicator
                .frame(width: 14)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                // Chat title first (like the Claude Code tab); the project is
                // a small secondary label so it stays readable but discreet.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if session.displayTitle != session.projectName {
                        Text(session.projectName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .layoutPriority(-1)
                    }
                }
                // Hover shows the full chat name plus the project.
                .help("\(session.displayTitle) · \(session.projectName)")

                // Show tool call when waiting for approval, otherwise last activity
                if isWaitingForApproval, let toolName = session.pendingToolName {
                    // Show tool name in amber + input on same line
                    HStack(spacing: 4) {
                        Text(MCPToolFormatter.formatToolName(toolName))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(TerminalColors.amber.opacity(0.9))
                        if isInteractiveTool {
                            Text("Needs your input")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let input = session.pendingToolInput {
                            Text(input)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if let role = session.lastMessageRole {
                    switch role {
                    case "tool":
                        // Tool call - show tool name + input
                        HStack(spacing: 4) {
                            if let toolName = session.lastToolName {
                                Text(MCPToolFormatter.formatToolName(toolName))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            if let input = session.lastMessage {
                                Text(input)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    case "user":
                        // User message - prefix with "You:"
                        HStack(spacing: 4) {
                            Text("You:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let msg = session.lastMessage {
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    default:
                        // Assistant message - just show text
                        if let msg = session.lastMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } else if let lastMsg = session.lastMessage {
                    Text(lastMsg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Action icons or approval buttons
            if isWaitingForApproval && isInteractiveTool {
                // Interactive tools like AskUserQuestion - show chat + terminal buttons
                HStack(spacing: 8) {
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Jump to the session: tmux window via yabai, or the host
                    // app (VS Code, Terminal, ...) via its pid. Hidden for
                    // multiplexer sessions without yabai, where neither route
                    // can reach the right window.
                    if canFocusSession {
                        TerminalButton(
                            isEnabled: true,
                            onTap: { onFocus() }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isWaitingForApproval {
                InlineApprovalButtons(
                    onChat: onChat,
                    onApprove: onApprove,
                    onReject: onReject
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                HStack(spacing: 8) {
                    // Row click jumps to VS Code; this previews in the notch.
                    IconButton(icon: "bubble.left") {
                        onChat()
                    }

                    // Archive button - only for idle or completed sessions
                    if session.phase == .idle || session.phase == .waitingForInput {
                        IconButton(icon: "archivebox") {
                            onArchive()
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        // Click takes you to the chat itself in VS Code (window + exact
        // session); without a route there, fall back to the notch preview.
        .onTapGesture {
            if canFocusSession { onFocus() } else { onChat() }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isWaitingForApproval)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.gray.opacity(0.15) : glowColor.map { $0.opacity(0.06) } ?? .clear)
        )
        // Chats waiting on you glow: green when Claude finished, amber when
        // a tool needs approval.
        .overlay {
            if let glowColor {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(glowColor.opacity(glowPulse ? 0.75 : 0.25), lineWidth: 1.2)
                    .shadow(color: glowColor.opacity(glowPulse ? 0.45 : 0.1), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever()) { glowPulse = true }
        }
        .help(canFocusSession ? "Open this chat in VS Code" : "Show this chat")
        .onHover { isHovered = $0 }
        .task {
            isYabaiAvailable = await WindowFinder.shared.isYabaiAvailable()
        }
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch session.phase {
        case .processing, .compacting:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.footnote.weight(.bold))
                .foregroundColor(claudeOrange)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForApproval:
            Text(spinnerSymbols[spinnerPhase % spinnerSymbols.count])
                .font(.footnote.weight(.bold))
                .foregroundColor(TerminalColors.amber)
                .onReceive(spinnerTimer) { _ in
                    spinnerPhase = (spinnerPhase + 1) % spinnerSymbols.count
                }
        case .waitingForInput:
            Circle()
                .fill(TerminalColors.green)
                .frame(width: 6, height: 6)
        case .idle, .ended:
            Circle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 6, height: 6)
        }
    }

}

// MARK: - Inline Approval Buttons

/// Compact inline approval buttons with staggered animation
struct InlineApprovalButtons: View {
    let onChat: () -> Void
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var showChatButton = false
    @State private var showDenyButton = false
    @State private var showAllowButton = false

    var body: some View {
        HStack(spacing: 6) {
            // Chat button
            IconButton(icon: "bubble.left") {
                onChat()
            }
            .opacity(showChatButton ? 1 : 0)
            .scaleEffect(showChatButton ? 1 : 0.8)

            Button {
                onReject()
            } label: {
                Text("Deny")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showDenyButton ? 1 : 0)
            .scaleEffect(showDenyButton ? 1 : 0.8)

            Button {
                onApprove()
            } label: {
                Text("Allow")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(showAllowButton ? 1 : 0)
            .scaleEffect(showAllowButton ? 1 : 0.8)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.0)) {
                showChatButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.05)) {
                showDenyButton = true
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.1)) {
                showAllowButton = true
            }
        }
    }
}

// MARK: - Icon Button

struct IconButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .foregroundColor(isHovered ? .white.opacity(0.8) : .white.opacity(0.4))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovered ? Color.white.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact Terminal Button (inline in description)

struct CompactTerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: "terminal")
                    .font(.caption2.weight(.medium))
                Text("Go to Terminal")
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(isEnabled ? .white.opacity(0.9) : .white.opacity(0.3))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isEnabled ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Terminal Button

struct TerminalButton: View {
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                onTap()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "terminal")
                    .font(.system(size: 9, weight: .medium))
                Text("Terminal")
                    .font(.caption.weight(.medium))
            }
            .foregroundColor(isEnabled ? .black : .white.opacity(0.4))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isEnabled ? Color.white.opacity(0.95) : Color.white.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
