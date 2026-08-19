//
//  InboxViewModel.swift
//  Buddi
//
//  Polls the integration providers and exposes per-section state plus a
//  total pending count (used for the closed-notch badge someday).
//

import Combine
import Foundation

@MainActor
final class InboxViewModel: ObservableObject {
    static let shared = InboxViewModel()

    @Published private(set) var sections: [InboxSource: InboxSectionState] = [:]
    @Published private(set) var lastRefresh: Date?

    private let providers: [any InboxProvider] = [
        SlackInboxProvider(),
        ClickUpInboxProvider(),
        HubTicketsInboxProvider(),
    ]
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?

    var pendingCount: Int {
        sections.values.reduce(0) { total, state in
            if case .loaded(let items) = state { return total + items.count }
            return total
        }
    }

    /// Starts the 60s polling loop; safe to call repeatedly (tab appears).
    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [providers] in
            for provider in providers {
                let source = provider.source
                if sections[source] == nil {
                    sections[source] = .loading
                }
                do {
                    let items = try await provider.fetch()
                    guard !Task.isCancelled else { return }
                    sections[source] = .loaded(items)
                } catch InboxProviderError.missingToken {
                    sections[source] = .needsToken
                } catch {
                    guard !Task.isCancelled else { return }
                    sections[source] = .failed("\(error)")
                }
            }
            lastRefresh = Date()
        }
    }
}
