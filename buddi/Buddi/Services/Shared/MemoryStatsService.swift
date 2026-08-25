//
//  MemoryStatsService.swift
//  Buddi
//
//  Polls RAM and swap pressure (the numbers behind macOS's "out of
//  application memory" dialog) and offers a one-click cleanup of zombie
//  Claude CLI sessions: processes not tracked by the session monitor that
//  have been alive for hours, each quietly holding memory.
//

import Foundation

struct MemoryStats: Equatable {
    /// 0...1 fraction of physical RAM in use (approximation from mach stats).
    var ramUsed: Double = 0
    /// 0...1 fraction of swap in use. High values plus low disk space are
    /// what produce the force-quit dialog.
    var swapUsed: Double = 0
    var swapUsedBytes: UInt64 = 0
    var swapTotalBytes: UInt64 = 0
}

@MainActor
final class MemoryStatsService: ObservableObject {
    static let shared = MemoryStatsService()

    @Published private(set) var stats = MemoryStats()
    @Published private(set) var zombieSessionCount = 0
    /// One-line outcome of the last cleanup, shown briefly under the button
    /// so a tap always has visible feedback.
    @Published private(set) var lastCleanupMessage: String?

    private var timer: Timer?
    /// A Claude CLI process must be at least this old AND untracked to count
    /// as a zombie; young untracked processes may be sessions still starting.
    private let zombieMinimumAge: TimeInterval = 6 * 60 * 60

    func startPolling() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        stats = Self.readStats()
        zombieSessionCount = zombiePids().count
    }

    /// Terminates zombie Claude sessions with SIGTERM. Never touches a pid
    /// the session monitor knows about (those are the user's live chats).
    func cleanZombieSessions() {
        let pids = zombiePids()
        NSLog("[MemoryStats] cleaning %d zombie sessions: %@", pids.count, "\(pids)")
        for pid in pids {
            kill(pid_t(pid), SIGTERM)
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            refresh()
            lastCleanupMessage = pids.isEmpty
                ? "Nothing to clean"
                : "Ended \(pids.count) session\(pids.count == 1 ? "" : "s")"
            try? await Task.sleep(for: .seconds(6))
            lastCleanupMessage = nil
        }
    }

    // MARK: - Zombies

    private func zombiePids() -> [Int] {
        let trackedPids = Set(
            BuddiSessionBridge.shared.sessionMonitor.instances.compactMap { $0.pid }
        )
        let ownPid = Int(ProcessInfo.processInfo.processIdentifier)

        guard let output = ProcessExecutor.shared.runSyncOrNil(
            "/bin/ps", arguments: ["-Axo", "pid=,etime=,command="]
        ) else { return [] }

        var zombies: [Int] = []
        for line in output.components(separatedBy: "\n") {
            guard line.contains("native-binary/claude") else { continue }
            let parts = line.trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces)
                .filter { !$0.isEmpty }
            guard parts.count >= 2,
                  let pid = Int(parts[0]),
                  pid != ownPid,
                  !trackedPids.contains(pid),
                  Self.elapsedSeconds(fromEtime: parts[1]) >= zombieMinimumAge
            else { continue }
            zombies.append(pid)
        }
        return zombies
    }

    /// Parses ps etime formats: "mm:ss", "hh:mm:ss", "dd-hh:mm:ss".
    static func elapsedSeconds(fromEtime etime: String) -> TimeInterval {
        var days = 0.0
        var clock = etime
        if let dashIndex = etime.firstIndex(of: "-") {
            days = Double(etime[..<dashIndex]) ?? 0
            clock = String(etime[etime.index(after: dashIndex)...])
        }
        let fields = clock.components(separatedBy: ":").compactMap(Double.init)
        var seconds = 0.0
        for field in fields {
            seconds = seconds * 60 + field
        }
        return days * 86_400 + seconds
    }

    // MARK: - Stats

    private static func readStats() -> MemoryStats {
        var result = MemoryStats()

        // Swap via sysctl vm.swapusage.
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0, swap.xsu_total > 0 {
            result.swapTotalBytes = swap.xsu_total
            result.swapUsedBytes = swap.xsu_used
            result.swapUsed = Double(swap.xsu_used) / Double(swap.xsu_total)
        }

        // RAM via mach host statistics: used = active + wired + compressed.
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let pageSize = Double(vm_kernel_page_size)
            let used = (Double(vmStats.active_count)
                + Double(vmStats.wire_count)
                + Double(vmStats.compressor_page_count)) * pageSize
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            if total > 0 {
                result.ramUsed = min(1, used / total)
            }
        }

        return result
    }
}
