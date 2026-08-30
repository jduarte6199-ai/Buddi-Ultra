//
//  UnattendedChatsReminder.swift
//  Buddi
//
//  Recurring dynamic-island balloons for chats still waiting for a reply.
//  The one-shot "Ready" bubble fires when a chat finishes; this service
//  re-surfaces anything the user has NOT attended since, every N minutes
//  (configurable, on by default). Tapping the balloon jumps to the chat
//  that has been waiting the longest.
//

import Defaults
import Foundation

@MainActor
final class UnattendedChatsReminder {
    static let shared = UnattendedChatsReminder()

    private var timer: Timer?
    private var lastReminderAt: Date = .distantPast

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                UnattendedChatsReminder.shared.check()
            }
        }
    }

    private func check() {
        guard Defaults[.unattendedRemindersEnabled] else { return }
        let interval = TimeInterval(max(1, Defaults[.unattendedReminderMinutes])) * 60
        let now = Date()

        guard now.timeIntervalSince(lastReminderAt) >= interval else { return }

        // Unattended = still waiting for input, and quiet for at least the
        // reminder interval (lastActivity moves when the user replies or the
        // session progresses, which is what "attended" means here).
        let unattended = BuddiSessionBridge.shared.sessionMonitor.instances
            .filter { $0.phase == .waitingForInput }
            .filter { now.timeIntervalSince($0.lastActivity) >= interval }
            .sorted { $0.lastActivity < $1.lastActivity }

        guard let oldest = unattended.first else { return }
        lastReminderAt = now

        let title: String
        let detail: String
        if unattended.count == 1 {
            title = oldest.displayTitle
            detail = "waiting \(Self.waitingText(since: oldest.lastActivity, now: now))"
        } else {
            title = "\(unattended.count) chats need your reply"
            detail = unattended.prefix(3).map { $0.projectName }.joined(separator: " · ")
        }

        BuddiViewCoordinator.shared.showSessionPopup(
            kind: .ready,
            title: title,
            projectName: oldest.projectName,
            sessionId: oldest.sessionId,
            detail: detail
        )
    }

    private static func waitingText(since date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes >= 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
