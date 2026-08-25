//
//  MeetingReminderService.swift
//  Buddi
//
//  Pops the notch bubble ten minutes before a calendar event starts.
//  Piggybacks on the session popup pipeline (kind .meeting), so reminders
//  queue politely behind approvals and land in the event log.
//

import Foundation

@MainActor
final class MeetingReminderService {
    static let shared = MeetingReminderService()

    private var timer: Timer?
    /// Event IDs already announced; reset daily so recurring events re-fire.
    private var notifiedEventIds: Set<String> = []
    private var notifiedDay = Calendar.current.startOfDay(for: Date())
    private let leadTime: TimeInterval = 10 * 60
    private let calendarService = CalendarService()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                await MeetingReminderService.shared.checkUpcomingEvents()
            }
        }
    }

    private func checkUpcomingEvents() async {
        let today = Calendar.current.startOfDay(for: Date())
        if today != notifiedDay {
            notifiedDay = today
            notifiedEventIds = []
        }

        let now = Date()
        let horizon = now.addingTimeInterval(leadTime)
        let selected = CalendarManager.shared.selectedCalendarIDs
        guard !selected.isEmpty else { return }

        let events = await calendarService.events(
            from: now, to: horizon, calendars: Array(selected))

        for event in events {
            guard !event.isAllDay,
                  event.start > now,
                  event.start <= horizon,
                  !notifiedEventIds.contains(event.id)
            else { continue }
            notifiedEventIds.insert(event.id)

            let minutes = max(1, Int(event.start.timeIntervalSince(now) / 60))
            BuddiViewCoordinator.shared.showSessionPopup(
                kind: .meeting,
                title: event.title,
                projectName: "in \(minutes) min · \(Self.timeFormatter.string(from: event.start))",
                sessionId: "",
                detail: event.location ?? ""
            )
        }
    }
}
