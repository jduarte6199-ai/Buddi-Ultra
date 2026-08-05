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

        let hasNewPendingPermission = currentPendingPermissionIDs.contains {
            !knownPendingPermissionIDs.contains($0)
        }

        guard hasNewPendingPermission,
              buddiViewModel?.notchState == .closed,
              !TerminalVisibilityDetector.isTerminalVisibleOnCurrentSpace()
        else {
            return
        }

        BuddiViewCoordinator.shared.toggleExpandingView(status: true, type: .buddy)
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
            BuddiViewCoordinator.shared.showSessionDonePopup(
                projectName: session.projectName,
                sessionId: session.sessionId
            )
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
