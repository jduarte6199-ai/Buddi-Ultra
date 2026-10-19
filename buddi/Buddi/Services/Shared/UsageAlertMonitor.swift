//
//  UsageAlertMonitor.swift
//  Buddi
//
//  Watches Claude usage samples for two things:
//
//  1. High consumption: the burn rate of the 5-hour session limit. A pace
//     of 20%/h exactly lasts the window, so 30%/h or more counts as high.
//     A detection opens a 15-minute cooldown (shown as a bar that starts
//     full and drains right to left) and pops one alert; detecting again
//     while it runs refills the bar without re-alerting.
//  2. Thresholds: one popup when the session or weekly limit crosses 75, 80
//     or 90%, remembered per reset window so it never repeats in a window.
//

import AppKit
import Defaults
import SwiftUI

@MainActor
final class UsageAlertMonitor: ObservableObject {
    static let shared = UsageAlertMonitor()

    @Published private(set) var cooldownStart: Date?
    @Published private(set) var cooldownEnd: Date?
    /// Latest measured session pace in %/hour (nil until two samples exist).
    @Published private(set) var pacePerHour: Double?

    static let highPacePerHour: Double = 30
    static let cooldown: TimeInterval = 15 * 60
    static let thresholds: [Double] = [75, 80, 90]

    private var samples: [(date: Date, utilization: Double)] = []

    var isCoolingDown: Bool {
        guard let cooldownEnd else { return false }
        return cooldownEnd > Date()
    }

    /// Called after every successful usage fetch.
    func record(_ usage: UsageData, now: Date = Date()) {
        if let session = usage.fiveHour {
            checkBurn(session.utilization, now: now)
            checkThreshold(period: "session", label: "Session", quota: session)
        }
        if let weekly = usage.sevenDay {
            checkThreshold(period: "weekly", label: "Weekly", quota: weekly)
        }
    }

    // MARK: - Burn rate

    private func checkBurn(_ utilization: Double, now: Date) {
        // A drop means the 5h window reset: old samples no longer apply.
        if let last = samples.last, utilization < last.utilization - 1 {
            samples.removeAll()
        }
        samples.append((now, utilization))
        samples.removeAll { now.timeIntervalSince($0.date) > 60 * 60 }

        // Pace against the oldest sample from the last 8-25 minutes.
        guard let reference = samples.first(where: {
            let age = now.timeIntervalSince($0.date)
            return age >= 8 * 60 && age <= 25 * 60
        }) else { return }

        let minutes = now.timeIntervalSince(reference.date) / 60
        let pace = (utilization - reference.utilization) / minutes * 60
        pacePerHour = pace

        guard Defaults[.highUsageAlertsEnabled],
              pace >= Self.highPacePerHour,
              utilization >= 10
        else { return }

        let wasActive = isCoolingDown
        cooldownStart = now
        cooldownEnd = now.addingTimeInterval(Self.cooldown)
        guard !wasActive else { return }

        let hoursLeft = max(0, 100 - utilization) / pace
        BuddiViewCoordinator.shared.showSessionPopup(
            kind: .usage,
            title: "High Claude usage detected",
            projectName: "~\(Int(pace))%/h",
            sessionId: "",
            detail: "Session limit in ~\(Self.durationText(hoursLeft * 3600)) at this pace"
        )
    }

    // MARK: - Thresholds

    private func checkThreshold(period: String, label: String, quota: QuotaPeriod) {
        guard Defaults[.usageThresholdAlertsEnabled] else { return }
        // Keyed by reset time so each window alerts at most once per level.
        let window = quota.resetsAt.map { String(Int($0.timeIntervalSince1970)) } ?? "none"
        let key = "usageAlerted.\(period).\(window)"
        let alreadyAlerted = UserDefaults.standard.double(forKey: key)

        guard let crossed = Self.thresholds.last(where: { quota.utilization >= $0 }),
              crossed > alreadyAlerted
        else { return }
        UserDefaults.standard.set(crossed, forKey: key)

        let reset = quota.resetsAt.map { "resets in \(Self.durationText($0.timeIntervalSinceNow))" } ?? ""
        BuddiViewCoordinator.shared.showSessionPopup(
            kind: .usage,
            title: "\(label) usage at \(Int(quota.utilization))%",
            projectName: "Claude limit",
            sessionId: "",
            detail: reset
        )
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }
}

// MARK: - Alert color (customizable, stored as hex)

extension Color {
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .systemYellow
        return String(
            format: "#%02X%02X%02X",
            Int(round(ns.redComponent * 255)),
            Int(round(ns.greenComponent * 255)),
            Int(round(ns.blueComponent * 255))
        )
    }

    static var usageAlert: Color {
        Color(hex: Defaults[.usageAlertColorHex]) ?? Color(red: 0.95, green: 0.70, blue: 0.24)
    }
}
