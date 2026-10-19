//
//  SessionEventLog.swift
//  Buddi
//
//  Persistent history of every notch popup (chat ready, approvals,
//  meetings), so events dismissed or missed are still reviewable in the
//  Inbox tab. Capped and stored in UserDefaults as JSON.
//

import Foundation

struct NotchEventRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    /// "ready", "approval" or "meeting".
    let kind: String
    let title: String
    let projectName: String
    let sessionId: String
}

@MainActor
final class SessionEventLog: ObservableObject {
    static let shared = SessionEventLog()

    @Published private(set) var events: [NotchEventRecord] = []

    private let storageKey = "sessionEventLog"
    private let cap = 50

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([NotchEventRecord].self, from: data) {
            events = stored
        }
    }

    func record(_ popup: SessionDonePopup) {
        let kind: String
        switch popup.kind {
        case .ready: kind = "ready"
        case .approval: kind = "approval"
        case .meeting: kind = "meeting"
        case .usage: kind = "usage"
        }
        let event = NotchEventRecord(
            id: UUID(),
            date: Date(),
            kind: kind,
            title: popup.title,
            projectName: popup.projectName,
            sessionId: popup.sessionId
        )
        events.insert(event, at: 0)
        if events.count > cap {
            events.removeLast(events.count - cap)
        }
        persist()
    }

    func clear() {
        events = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
