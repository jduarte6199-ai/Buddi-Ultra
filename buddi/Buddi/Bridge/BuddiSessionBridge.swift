import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class BuddiSessionBridge: ObservableObject {
    static let shared = BuddiSessionBridge()

    let sessionMonitor = ClaudeSessionMonitor()
    let panelViewModel = BuddyPanelViewModel()
    weak var buddiViewModel: BuddiViewModel?

    private var cancellables = Set<AnyCancellable>()
    private var knownWaitingForInputSessionIDs = Set<String>()
    private var hasSeededWaitingForInputSessions = false
    private var knownPendingPermissionIDs = Set<String>()
    private var hasSeededPendingPermissions = false

    private init() {
        sessionMonitor.$instances
            .map { instances -> BuddyTask in
                guard let top = instances.first(where: { $0.phase.isActive })
                    ?? instances.first(where: { $0.phase.needsAttention })
                    ?? instances.first
                else {
                    return .idle
                }
                return top.phase.buddyTask
            }
            .removeDuplicates()
            .sink { task in
                BuddyManager.shared.animator.task = task
            }
            .store(in: &cancellables)

        panelViewModel.$contentType
            .sink { contentType in
                let height: CGFloat
                switch contentType {
                case .chat:
                    height = 500
                case .instances, .menu:
                    height = openNotchSize.height
                }

                if BuddiViewCoordinator.shared.buddyPanelHeight != height {
                    BuddiViewCoordinator.shared.buddyPanelHeight = height
                }
            }
            .store(in: &cancellables)

        sessionMonitor.$instances
            .sink { [weak self] (instances: [SessionState]) in
                self?.handleWaitingForInputSessions(instances)
            }
            .store(in: &cancellables)

        sessionMonitor.$pendingInstances
            .sink { [weak self] (pendingInstances: [SessionState]) in
                self?.handlePendingPermissionSessions(pendingInstances)
            }
            .store(in: &cancellables)

        sessionMonitor.$instances
            .map { instances in
                instances.contains { $0.phase.isActive || $0.phase.needsAttention }
            }
            .removeDuplicates()
            .sink { hasActive in
                BuddiViewCoordinator.shared.toggleExpandingView(
                    status: hasActive,
                    type: .buddy
                )
            }
            .store(in: &cancellables)
    }

    func startMonitoring() {
        sessionMonitor.startMonitoring()
    }

    func stopMonitoring() {
        sessionMonitor.stopMonitoring()
    }

    private func handleWaitingForInputSessions(_ instances: [SessionState]) {
        let waitingSessions = instances.filter { $0.phase == .waitingForInput }
        let currentWaitingSessionIDs = Set(waitingSessions.map { $0.sessionId })

        defer {
            knownWaitingForInputSessionIDs = currentWaitingSessionIDs
            hasSeededWaitingForInputSessions = true
        }

        guard hasSeededWaitingForInputSessions else { return }

        let newlyWaitingSessions = waitingSessions.filter {
            !knownWaitingForInputSessionIDs.contains($0.sessionId)
        }

        guard !newlyWaitingSessions.isEmpty else { return }

        // The banner always pops for a freshly ready chat, even if its host
        // app is frontmost (VS Code is usually frontmost anyway). Only the
        // sound stays gated on focus, handled below. Every session gets its
        // banner; the coordinator queues them when the slot is busy.
        for session in newlyWaitingSessions {
            BuddiViewCoordinator.shared.showSessionPopup(
                kind: .ready,
                title: session.displayTitle,
                projectName: session.projectName,
                sessionId: session.sessionId,
                detail: Self.popupDetail(from: session.lastMessage)
            )
        }

        Task { [weak self] in
            await self?.playWaitingForInputNotificationIfNeeded(for: newlyWaitingSessions)
        }
    }

    private func handlePendingPermissionSessions(_ pendingInstances: [SessionState]) {
        let currentPendingPermissionIDs = Set(pendingInstances.compactMap { $0.pendingToolId })

        defer {
            knownPendingPermissionIDs = currentPendingPermissionIDs
            hasSeededPendingPermissions = true
        }

        guard hasSeededPendingPermissions else { return }

        // Approval popups whose permission got resolved elsewhere must not
        // linger on screen or in the queue with live-looking buttons.
        BuddiViewCoordinator.shared.invalidateApprovalPopups(
            stillPending: currentPendingPermissionIDs
        )

        // One pass decides both "is there anything new" and "which sessions".
        let newPendingSessions = pendingInstances.filter { session in
            guard let id = session.pendingToolId else { return false }
            return !knownPendingPermissionIDs.contains(id)
        }

        guard !newPendingSessions.isEmpty else { return }

        // Approval popup with inline approve/deny, always shown, so quick
        // decisions never require opening the panel or the terminal.
        for session in newPendingSessions {
            guard let toolName = session.pendingToolName,
                  let toolUseId = session.pendingToolId else { continue }
            BuddiViewCoordinator.shared.showSessionPopup(
                kind: .approval(toolName: MCPToolFormatter.formatToolName(toolName)),
                title: session.displayTitle,
                projectName: session.projectName,
                sessionId: session.sessionId,
                detail: Self.approvalDetail(for: session),
                toolUseId: toolUseId
            )
        }

        guard buddiViewModel?.notchState == .closed,
              !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()
        else {
            return
        }

        BuddiViewCoordinator.shared.toggleExpandingView(status: true, type: .buddy)
    }

    /// Deterministic one-line context for an approval popup. Prefers the
    /// payload the human actually needs to see (the command, the path, the
    /// URL) over Dictionary iteration order, which would otherwise pick a
    /// random key like "description" and hide the real action.
    private static func approvalDetail(for session: SessionState) -> String {
        if let input = session.activePermission?.toolInput {
            let preferredKeys = ["command", "file_path", "path", "url", "pattern", "prompt", "query"]
            for key in preferredKeys {
                if let value = input[key]?.value as? String, !value.isEmpty {
                    return popupDetail(from: value)
                }
            }
        }
        return popupDetail(from: session.pendingToolInput)
    }

    /// Single-line, length-capped context string for the notch popup.
    private static func popupDetail(from text: String?) -> String {
        guard let text else { return "" }
        let firstLine = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return firstLine.count > 90 ? String(firstLine.prefix(90)) + "…" : firstLine
    }

    private func playWaitingForInputNotificationIfNeeded(for sessions: [SessionState]) async {
        for session in sessions {
            let isFocused: Bool
            if let pid = session.pid {
                isFocused = await TerminalVisibilityDetector.isSessionFocused(sessionPid: pid)
            } else {
                isFocused = false
            }

            guard !isFocused else { continue }

            if let soundName = BuddiSettings.notificationSound.soundName {
                NSSound(named: soundName)?.play()
            }
            return
        }
    }
}

extension SessionPhase {
    var buddyTask: BuddyTask {
        switch self {
        case .idle, .ended, .waitingForInput:
            return .idle
        case .processing:
            return .working
        case .waitingForApproval:
            return .waiting
        case .compacting:
            return .compacting
        }
    }
}
