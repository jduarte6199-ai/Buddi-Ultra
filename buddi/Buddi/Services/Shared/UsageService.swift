import Combine
import Foundation
import Security

// MARK: - Models

struct UsageData: Equatable, Codable {
    var fiveHour: QuotaPeriod?
    var sevenDay: QuotaPeriod?

    static let empty = UsageData()
}

struct QuotaPeriod: Equatable, Codable {
    let utilization: Double     // 0-100
    let resetsAt: Date?
}

// MARK: - Usage Service

@MainActor
final class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published private(set) var usage = UsageData.empty
    @Published private(set) var isAvailable = false
    /// True once the token could not be read. The poll loop is stopped at that
    /// point, so the UI has to offer a Reconnect button to try again.
    @Published private(set) var needsAuthorization = false

    private var pollTimer: Timer?
    private var pollTask: Task<Void, Never>?
    private let baseInterval: TimeInterval = 300
    private var currentInterval: TimeInterval = 300
    private var backoffCount = 0
    private var consecutiveFailures = 0
    /// Set after a failed token read; polling stays stopped until reconnect().
    private var interactiveReadUsed = false
    private var cachedToken: String?

    private static let isoFormatterFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterBasic = ISO8601DateFormatter()

    private init() {}

    func startPolling() {
        guard pollTimer == nil else { return }
        loadCache()
        poll()
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollTask?.cancel()
        pollTask = nil
        backoffCount = 0
        consecutiveFailures = 0
        currentInterval = baseInterval
    }

    /// User-initiated retry after the token read failed. This is the only place
    /// that re-arms the interactive read, so the dialog can never come back on
    /// its own. It takes a click.
    func reconnect() {
        stopPolling()
        needsAuthorization = false
        interactiveReadUsed = false
        cachedToken = nil
        poll()
    }

    private func scheduleNextPoll() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: currentInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
    }

    /// The token, held in memory and otherwise read through Apple's
    /// /usr/bin/security tool. Claude Code creates its credentials item with
    /// that tool, so the item's access list trusts it and the read is silent,
    /// including right after Claude Code logs in again and rewrites the item.
    /// Reading through Buddi's own process instead is what kept prompting:
    /// Buddi is not in that list, and every rebuild changes its code hash.
    /// After a FAILED read the loop stops and waits for reconnect(), so an
    /// unexpected access-list change can never become a dialog loop.
    private func currentToken() -> String? {
        if let cachedToken { return cachedToken }
        guard !interactiveReadUsed else { return nil }

        if let token = Self.readOAuthToken() {
            cachedToken = token
            return token
        }
        interactiveReadUsed = true
        return nil
    }

    private func poll() {
        guard let token = currentToken() else {
            // Unreadable: the user dismissed the dialog, or this app is not in
            // the item's access list. Retrying on the timer is exactly what
            // produced the dialog storm, so stop and wait for reconnect().
            isAvailable = false
            needsAuthorization = true
            stopPolling()
            return
        }

        needsAuthorization = false

        pollTask = Task {
            if !isAvailable { isAvailable = true }

            do {
                let result = try await Self.fetchUsage(token: token)
                usage = result
                consecutiveFailures = 0
                backoffCount = 0
                currentInterval = baseInterval
                saveCache()
            } catch let error as URLError where error.code.rawValue == 429 {
                backoffCount += 1
                currentInterval = min(1800, baseInterval * pow(2.0, Double(backoffCount)))
            } catch let error as URLError where error.code.rawValue == 401 {
                // The token rotated: drop BOTH the memory cache and the stale
                // keychain copy, or the copy would feed the dead token back
                // forever. The next poll re-reads the source; silently when the
                // access list allows it, otherwise with at most one dialog per
                // run before stopping for reconnect().
                cachedToken = nil
                consecutiveFailures += 1
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures > 5 && usage.fiveHour == nil && usage.sevenDay == nil {
                    isAvailable = false
                }
            }
            scheduleNextPoll()
        }
    }

    // MARK: - Cache

    private static let cacheURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Buddi", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-cache.json")
    }()

    private struct CachedUsage: Codable {
        let usage: UsageData
        let fetchedAt: Date
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode(CachedUsage.self, from: data) else { return }
        usage = cached.usage
        isAvailable = true
    }

    private func saveCache() {
        let cached = CachedUsage(usage: usage, fetchedAt: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Keychain

    private static func readOAuthToken() -> String? {
        guard let output = IntegrationTokens.run(
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ),
            let data = output.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return extractToken(from: json)
    }

    private static func extractToken(from json: [String: Any]) -> String? {
        guard let oauth = json["claudeAiOauth"] as? [String: Any],
              let rawToken = oauth["accessToken"] as? String else { return nil }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    // MARK: - API Call

    private static func fetchUsage(token: String) async throws -> UsageData {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            throw URLError(.init(rawValue: http.statusCode))
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        return UsageData(
            fiveHour: parseQuotaPeriod(json["five_hour"]),
            sevenDay: parseQuotaPeriod(json["seven_day"])
        )
    }

    private static func parseQuotaPeriod(_ value: Any?) -> QuotaPeriod? {
        guard let dict = value as? [String: Any],
              let utilization = dict["utilization"] as? Double else { return nil }

        var resetsAt: Date?
        if let dateStr = dict["resets_at"] as? String {
            resetsAt = isoFormatterFrac.date(from: dateStr) ?? isoFormatterBasic.date(from: dateStr)
        }

        return QuotaPeriod(utilization: utilization, resetsAt: resetsAt)
    }
}
