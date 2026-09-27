import Foundation

// MARK: - DockSynchronizationSchedule

/// 同步时机的纯逻辑：连续变更防抖合并；Dock 重启后的静默期内不写 Dock 偏好，静默期结束时复查一次
///
/// 实测（macOS 27）Dock 重启后会把启动时读到的偏好写回一次，约在重启后 4 秒，或在此之前被终止时；
/// 在这次写回之前写入 Dock 偏好的改动会被覆盖，随后重启的 Dock 读到的仍是旧条目
struct DockSynchronizationSchedule {
    /// 合并连续变更的防抖间隔
    static let debounceInterval = Duration.milliseconds(500)

    /// Dock 重启后不写 Dock 偏好的静默期：多次实测重启到写回为 4.1–4.2 秒，留出近一倍的余量
    static let settleInterval = Duration.seconds(8)

    /// 最近一次重启 Dock 的时刻；nil 表示本次运行还没有重启过
    private var lastDockRestart: ContinuousClock.Instant? = nil
}

// MARK: - Timing

extension DockSynchronizationSchedule {
    /// 变更到达后执行同步的时刻：防抖间隔之后，且不早于最近一次重启 Dock 的静默期结束
    ///
    /// 静默期内到来的变更都合并到静默期结束时的那一次同步
    /// - Parameter time: 变更到达的时刻
    func synchronizationTime(
        forChangeAt time: ContinuousClock.Instant
    ) -> ContinuousClock.Instant {
        let debouncedTime = time + Self.debounceInterval

        guard let lastDockRestart else { return debouncedTime }

        return max(debouncedTime, lastDockRestart + Self.settleInterval)
    }

    /// 记下一次同步的结果，给出复查的时刻
    ///
    /// 同步重启了 Dock 时，静默期结束再对账一次，把被 Dock 写回覆盖的改动重新写上；
    /// 复查本身重启了 Dock 时不再安排复查：Dock 写回的条目与写入的始终不一致时，Dock 也不会被反复重启
    /// - Parameters:
    ///   - time: 同步执行的时刻
    ///   - didRestartDock: 这次同步是否重启了 Dock
    ///   - isRecheck: 这次同步是否本身就是复查
    /// - Returns: 复查的时刻；nil 表示不需要复查
    mutating func recordSynchronization(
        at time: ContinuousClock.Instant,
        didRestartDock: Bool,
        isRecheck: Bool
    ) -> ContinuousClock.Instant? {
        guard didRestartDock else { return nil }

        // 复查重启 Dock 同样开启新的静默期，之后的变更仍要等它结束
        lastDockRestart = time

        guard !isRecheck else { return nil }

        return time + Self.settleInterval
    }
}
