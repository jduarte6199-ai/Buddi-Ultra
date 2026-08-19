//
//  InboxProviders.swift
//  Buddi
//
//  One provider per integration. Each returns pending items or throws;
//  a missing token is signalled with InboxProviderError.missingToken so the
//  UI can show the setup hint instead of an error.
//

import Foundation

enum InboxProviderError: Error {
    case missingToken
    case badResponse(String)
}

protocol InboxProvider: Sendable {
    var source: InboxSource { get }
    func fetch() async throws -> [InboxItem]
}

private func getJSON(_ url: URL, headers: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: url)
    request.timeoutInterval = 15
    for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw InboxProviderError.badResponse("HTTP \(code)")
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw InboxProviderError.badResponse("not a JSON object")
    }
    return json
}

// MARK: - Slack (unread DMs and group DMs)

struct SlackInboxProvider: InboxProvider {
    let source = InboxSource.slack
    /// Caps the per-conversation info calls so a huge DM list can't stall a refresh.
    private let maxConversations = 30

    func fetch() async throws -> [InboxItem] {
        guard let token = IntegrationTokens.read(.slack) else {
            throw InboxProviderError.missingToken
        }
        let headers = ["Authorization": "Bearer \(token)"]

        let auth = try await getJSON(
            URL(string: "https://slack.com/api/auth.test")!, headers: headers)
        guard auth["ok"] as? Bool == true else {
            throw InboxProviderError.badResponse(auth["error"] as? String ?? "auth failed")
        }
        let teamId = auth["team_id"] as? String ?? ""

        let list = try await getJSON(
            URL(string: "https://slack.com/api/conversations.list?types=im,mpim&exclude_archived=true&limit=100")!,
            headers: headers)
        guard list["ok"] as? Bool == true,
              let channels = list["channels"] as? [[String: Any]] else {
            throw InboxProviderError.badResponse(list["error"] as? String ?? "conversations.list failed")
        }

        var items: [InboxItem] = []
        for channel in channels.prefix(maxConversations) {
            guard let channelId = channel["id"] as? String else { continue }
            let info = try await getJSON(
                URL(string: "https://slack.com/api/conversations.info?channel=\(channelId)")!,
                headers: headers)
            guard info["ok"] as? Bool == true,
                  let detail = info["channel"] as? [String: Any] else { continue }
            let unread = detail["unread_count_display"] as? Int ?? 0
            guard unread > 0 else { continue }

            let name: String
            if let userId = detail["user"] as? String {
                name = await displayName(for: userId, headers: headers) ?? userId
            } else {
                name = detail["name"] as? String ?? "Group DM"
            }

            items.append(InboxItem(
                id: "slack-\(channelId)",
                source: .slack,
                title: name,
                subtitle: unread == 1 ? "1 unread message" : "\(unread) unread messages",
                url: URL(string: "slack://channel?team=\(teamId)&id=\(channelId)"),
                date: nil
            ))
        }
        return items
    }

    private func displayName(for userId: String, headers: [String: String]) async -> String? {
        guard let info = try? await getJSON(
            URL(string: "https://slack.com/api/users.info?user=\(userId)")!, headers: headers),
            info["ok"] as? Bool == true,
            let user = info["user"] as? [String: Any]
        else { return nil }
        let profile = user["profile"] as? [String: Any]
        return (profile?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? user["real_name"] as? String
            ?? user["name"] as? String
    }
}

// MARK: - ClickUp (my tasks due today or overdue)

struct ClickUpInboxProvider: InboxProvider {
    let source = InboxSource.clickUp

    func fetch() async throws -> [InboxItem] {
        guard let token = IntegrationTokens.read(.clickUp) else {
            throw InboxProviderError.missingToken
        }
        let headers = ["Authorization": token]

        let me = try await getJSON(
            URL(string: "https://api.clickup.com/api/v2/user")!, headers: headers)
        guard let user = me["user"] as? [String: Any],
              let userId = user["id"] else {
            throw InboxProviderError.badResponse("token rejected")
        }

        let teams = try await getJSON(
            URL(string: "https://api.clickup.com/api/v2/team")!, headers: headers)
        guard let teamList = teams["teams"] as? [[String: Any]] else {
            throw InboxProviderError.badResponse("no teams")
        }

        let endOfToday = Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(24 * 60 * 60)
        let dueBefore = Int(endOfToday.timeIntervalSince1970 * 1000)

        var items: [InboxItem] = []
        for team in teamList {
            guard let teamId = team["id"] as? String else { continue }
            let url = URL(string:
                "https://api.clickup.com/api/v2/team/\(teamId)/task?assignees%5B%5D=\(userId)&due_date_lt=\(dueBefore)&include_closed=false")!
            let result = try await getJSON(url, headers: headers)
            for task in result["tasks"] as? [[String: Any]] ?? [] {
                guard let taskId = task["id"] as? String,
                      let name = task["name"] as? String else { continue }
                var due: Date?
                if let dueMs = task["due_date"] as? String, let ms = Double(dueMs) {
                    due = Date(timeIntervalSince1970: ms / 1000)
                }
                let overdue = due.map { $0 < Date() } ?? false
                let listName = ((task["list"] as? [String: Any])?["name"] as? String) ?? ""
                items.append(InboxItem(
                    id: "clickup-\(taskId)",
                    source: .clickUp,
                    title: name,
                    subtitle: [listName, overdue ? "overdue" : "due today"]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    url: (task["url"] as? String).flatMap(URL.init(string:)),
                    date: due
                ))
            }
        }
        return items.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

// MARK: - BOA hub tickets

/// Reads open tickets from the boa-hub dev board. Requires the hub to accept
/// the agent bearer token (see docs/INTEGRATIONS.md for the hub-side spec).
struct HubTicketsInboxProvider: InboxProvider {
    let source = InboxSource.hubTickets
    /// Hub base URL, e.g. https://hub.buildauthority.co
    static var baseURL: String {
        UserDefaults.standard.string(forKey: "hubBaseURL") ?? ""
    }

    func fetch() async throws -> [InboxItem] {
        guard let token = IntegrationTokens.read(.hub) else {
            throw InboxProviderError.missingToken
        }
        guard !Self.baseURL.isEmpty, let url = URL(string: "\(Self.baseURL)/api/dev/tickets") else {
            throw InboxProviderError.missingToken
        }

        let json = try await getJSON(url, headers: ["Authorization": "Bearer \(token)"])
        let tickets = (json["tickets"] as? [[String: Any]])
            ?? (json["data"] as? [[String: Any]])
            ?? []

        return tickets.compactMap { ticket in
            guard let id = ticket["id"] else { return nil }
            let status = (ticket["status"] as? String) ?? ""
            // Closed work is not "pending".
            if ["closed", "done", "resolved"].contains(status.lowercased()) { return nil }
            let title = (ticket["title"] as? String) ?? "Ticket \(id)"
            let severity = (ticket["severity"] as? String) ?? ""
            let department = (ticket["department"] as? String) ?? ""
            return InboxItem(
                id: "hub-\(id)",
                source: .hubTickets,
                title: title,
                subtitle: [severity, department, status]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                url: URL(string: "\(Self.baseURL)/dev"),
                date: nil
            )
        }
    }
}
