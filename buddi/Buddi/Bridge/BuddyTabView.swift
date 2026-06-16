import Defaults
import SwiftUI

struct BuddyTabView: View {
    @EnvironmentObject var vm: BuddiViewModel
    @ObservedObject private var bridge = BuddiSessionBridge.shared
    @ObservedObject private var panelVM = BuddiSessionBridge.shared.panelViewModel
    @ObservedObject private var usageService = UsageService.shared
    @Default(.showUsage) private var showUsage
    @State private var suppressionToken = UUID()
    @State private var isSuppressing = false

    private var isInChat: Bool {
        if case .chat = panelVM.contentType { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            if isInChat, case .chat(let session) = panelVM.contentType {
                ChatView(
                    sessionId: session.sessionId,
                    initialSession: session,
                    sessionMonitor: bridge.sessionMonitor,
                    viewModel: panelVM
                )
                .onHover { hovering in
                    updateSuppression(for: hovering)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                homeContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isInChat)
        .onDisappear {
            updateSuppression(for: false)
            panelVM.saveChatState()
            panelVM.exitChat()
        }
    }

    private var homeContent: some View {
        HStack(alignment: .top, spacing: 15) {
            VStack(spacing: 3) {
                ASCIIFullSpriteView(
                    animator: BuddyManager.shared.animator,
                    identity: BuddyManager.shared.effectiveIdentity,
                    fontSize: 8
                )

                Text(BuddyManager.shared.effectiveIdentity.name
                     ?? BuddyManager.shared.effectiveIdentity.species.rawValue.capitalized)
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundColor(Color(nsColor: BuddyManager.shared.effectiveIdentity.rarity.nsColor).opacity(0.8))

                if usageService.isAvailable && showUsage {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        VStack(spacing: 3) {
                            usageBars(now: context.date)
                        }
                    }
                }
            }
            .frame(width: 100)

            ClaudeInstancesView(
                sessionMonitor: bridge.sessionMonitor,
                viewModel: panelVM
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
        .padding(.leading, 5)
        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity))
        .blur(radius: vm.notchState == .closed ? 30 : 0)
        .onHover { hovering in
            updateSuppression(for: hovering)
        }
    }

    @ViewBuilder
    private func usageBars(now: Date) -> some View {
        if let fh = usageService.usage.fiveHour {
            UsageBar(
                label: "Session",
                percent: fh.utilization / 100,
                detail: fh.resetsAt.map { "\(Int(fh.utilization))% · \(formatResetTime($0, now: now))" } ?? "\(Int(fh.utilization))%",
                color: fh.utilization > 80 ? .red : fh.utilization > 60 ? .yellow : Color(red: 0.35, green: 0.55, blue: 1.0)
            )
        }
        if let sd = usageService.usage.sevenDay {
            UsageBar(
                label: "Weekly",
                percent: sd.utilization / 100,
                detail: sd.resetsAt.map { "\(Int(sd.utilization))% · \(formatResetTime($0, now: now))" } ?? "\(Int(sd.utilization))%",
                color: sd.utilization > 80 ? .red : sd.utilization > 60 ? .yellow : Color(red: 0.35, green: 0.55, blue: 1.0)
            )
        }
    }

    private var sessions: [SessionState] { bridge.sessionMonitor.instances }

    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE h a"
        return f
    }()

    private func formatResetTime(_ date: Date, now: Date = Date()) -> String {
        let remaining = date.timeIntervalSince(now)
        if remaining <= 0 { return "now" }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 24 {
            return Self.dayTimeFormatter.string(from: date)
        }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func updateSuppression(for hovering: Bool) {
        guard hovering != isSuppressing else { return }
        isSuppressing = hovering
        vm.setScrollGestureSuppression(hovering, token: suppressionToken)
    }
}

struct UsageBar: View {
    let label: String
    let percent: Double
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * percent))
                }
            }
            .frame(height: 4)
        }
    }
}
