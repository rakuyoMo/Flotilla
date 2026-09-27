import Testing

@testable import Flotilla

// MARK: - DockSynchronizationScheduleTests

/// 同步时机：Dock 重启后会把启动时读到的偏好写回一次，在此之前写入的改动会被覆盖，
/// 因此静默期内的变更必须推迟到静默期结束；重启之后还要复查一次，复查却不能让 Dock 被反复重启
struct DockSynchronizationScheduleTests {
    /// 测试的起始时刻
    private let start = ContinuousClock.now

    /// 防抖间隔
    private let debounce = DockSynchronizationSchedule.debounceInterval

    /// Dock 重启后的静默期
    private let settle = DockSynchronizationSchedule.settleInterval

    // MARK: 防抖

    /// 本次运行还没有重启过 Dock：变更只等防抖间隔
    @Test
    func changeWithoutRestartOnlyDebounces() {
        let schedule = DockSynchronizationSchedule()

        #expect(schedule.synchronizationTime(forChangeAt: start) == start + debounce)
    }

    // MARK: 静默期

    /// 重启 Dock 后很快到来的变更（新建文件夹后立即改名）：推迟到静默期结束，不赶在 Dock 写回之前写入
    @Test
    func changeRightAfterRestartWaitsForSettleEnd() {
        let schedule = restartedSchedule()
        let changeTime = start + .seconds(1)

        #expect(schedule.synchronizationTime(forChangeAt: changeTime) == start + settle)
    }

    /// 静默期内先后到来的多个变更：都合并到静默期结束时的同一次同步
    @Test
    func changesDuringSettleMergeIntoOneSynchronization() {
        let schedule = restartedSchedule()

        let times = [1, 2, 3].map {
            schedule.synchronizationTime(forChangeAt: start + .seconds($0))
        }

        #expect(times.allSatisfy { $0 == start + settle })
    }

    /// 临近静默期结束才到来的变更：仍要等满防抖间隔
    @Test
    func changeNearSettleEndStillDebounces() {
        let schedule = restartedSchedule()
        let changeTime = start + settle - .milliseconds(100)

        #expect(schedule.synchronizationTime(forChangeAt: changeTime) == changeTime + debounce)
    }

    /// 静默期过后到来的变更：只等防抖间隔
    @Test
    func changeAfterSettleOnlyDebounces() {
        let schedule = restartedSchedule()
        let changeTime = start + settle + .seconds(1)

        #expect(schedule.synchronizationTime(forChangeAt: changeTime) == changeTime + debounce)
    }

    /// 静默期要长于实测的 Dock 写回时刻（重启后约 4.2 秒），并留有余量
    @Test
    func settleOutlastsDockWriteBack() {
        #expect(settle >= .seconds(5))
    }

    // MARK: 复查

    /// 同步重启了 Dock：静默期结束时复查一次，把可能被 Dock 写回覆盖的改动重新写上
    @Test
    func restartSchedulesRecheckAtSettleEnd() {
        var schedule = DockSynchronizationSchedule()

        let recheckTime = schedule.recordSynchronization(
            at: start,
            didRestartDock: true,
            isRecheck: false
        )

        #expect(recheckTime == start + settle)
    }

    /// 同步没有重启 Dock（包括没有差异的复查）：不复查，也不开启静默期
    @Test(arguments: [false, true])
    func synchronizationWithoutRestartNeedsNoRecheck(isRecheck: Bool) {
        var schedule = DockSynchronizationSchedule()

        let recheckTime = schedule.recordSynchronization(
            at: start,
            didRestartDock: false,
            isRecheck: isRecheck
        )

        let changeTime = start + .seconds(1)

        #expect(recheckTime == nil)
        #expect(schedule.synchronizationTime(forChangeAt: changeTime) == changeTime + debounce)
    }

    /// 复查自己重启了 Dock：不再安排复查，Dock 不会被反复重启；之后的变更仍要等这次重启的静默期结束
    @Test
    func recheckRestartSchedulesNoFurtherRecheck() {
        var schedule = restartedSchedule()
        let recheckStart = start + settle

        let recheckTime = schedule.recordSynchronization(
            at: recheckStart,
            didRestartDock: true,
            isRecheck: true
        )

        let changeTime = recheckStart + .seconds(1)

        #expect(recheckTime == nil)
        #expect(schedule.synchronizationTime(forChangeAt: changeTime) == recheckStart + settle)
    }
}

// MARK: - Helpers

extension DockSynchronizationScheduleTests {
    /// 在 start 时刻因变更同步、并重启过一次 Dock 的时机
    private func restartedSchedule() -> DockSynchronizationSchedule {
        var schedule = DockSynchronizationSchedule()

        _ = schedule.recordSynchronization(
            at: start,
            didRestartDock: true,
            isRecheck: false
        )

        return schedule
    }
}
