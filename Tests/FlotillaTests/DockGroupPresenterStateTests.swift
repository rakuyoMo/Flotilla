import CoreGraphics
import Foundation
import Testing

@testable import Flotilla

// MARK: - DockGroupPresenterStateTests

/// 展开状态的迁移：同一次点击 tile 会先后经过快速路径与 URL 两条路径，必须只生效一次，
/// 否则再次点击会变成 “先收起再展开”；按下后拖动 tile、按住 tile 弹出 Dock 菜单也不能误展开
struct DockGroupPresenterStateTests {
    /// 一次普通点击从按下到抬起的时长
    private static let clickDuration: TimeInterval = 0.1

    /// 根组 A
    private let groupA = UUID()

    /// 根组 B
    private let groupB = UUID()

    /// tile 上的一个按下位置
    private let tilePoint = CGPoint(x: 700, y: 40)

    // MARK: 快速路径

    /// 在 tile 上按下不展开，抬起才展开
    @Test
    func tileClickExpandsOnMouseUp() {
        var state = DockGroupPresenterState()

        #expect(pressTile(groupA, at: 0, in: &state) == .unchanged)
        #expect(state.mouseUp(time: Self.clickDuration) == .expand(groupA))
        #expect(state.presentedGroupID == groupA)
    }

    /// 按下后拖动超过阈值（调整 Dock 顺序）：抬起时不展开
    @Test
    func draggingTileDoesNotExpand() {
        var state = DockGroupPresenterState()
        let farPoint = CGPoint(
            x: tilePoint.x + GroupPanelMetrics.dragThreshold + 1,
            y: tilePoint.y
        )

        _ = pressTile(groupA, at: 0, in: &state)

        #expect(state.mouseDragged(to: farPoint, time: 0.05) == .unchanged)
        #expect(state.mouseUp(time: Self.clickDuration) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 阈值以内的抖动仍算一次点击
    @Test
    func jitterWithinThresholdStillClicks() {
        var state = DockGroupPresenterState()
        let nearPoint = CGPoint(
            x: tilePoint.x + GroupPanelMetrics.dragThreshold,
            y: tilePoint.y
        )

        _ = pressTile(groupA, at: 0, in: &state)

        #expect(state.mouseDragged(to: nearPoint, time: 0.05) == .unchanged)
        #expect(state.mouseUp(time: Self.clickDuration) == .expand(groupA))
    }

    /// 展开时从另一个 tile 按下拖动：视同面板以外的点击，收起面板
    @Test
    func draggingTileWhilePresentingCollapses() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        _ = pressTile(groupB, at: 5, in: &state)

        #expect(state.mouseDragged(to: CGPoint(x: 900, y: 40), time: 5.05) == .collapse)
        #expect(state.mouseUp(time: 5.1) == .unchanged)
    }

    /// 展开时再次点击同一 tile：按下时不动，抬起时收起，随后到达的 URL 不会再展开
    @Test
    func clickingSameTileCollapsesWithoutReopening() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        #expect(pressTile(groupA, at: 2, in: &state) == .unchanged)
        #expect(state.mouseUp(time: 2 + Self.clickDuration) == .collapse)
        #expect(state.receiveURL(groupID: groupA, time: 2.3) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 展开时点击另一个 tile：直接切换，中间没有收起
    @Test
    func clickingOtherTileSwitchesDirectly() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        #expect(pressTile(groupB, at: 2, in: &state) == .unchanged)
        #expect(state.mouseUp(time: 2 + Self.clickDuration) == .expand(groupB))
        #expect(state.presentedGroupID == groupB)
    }

    /// 展开时点击面板以外的位置（任一按键）：收起；已收起时再点不再有动作
    @Test
    func outsideClickCollapsesOnce() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        let firstClick = state.mouseDown(
            onTile: nil,
            at: .zero,
            isInDockArea: false,
            time: 1
        )

        #expect(firstClick == .collapse)

        let secondClick = state.mouseDown(
            onTile: nil,
            at: .zero,
            isInDockArea: false,
            time: 2
        )

        #expect(secondClick == .unchanged)
    }

    // MARK: 长按

    /// 按住超过 Dock 弹出 App 菜单的时长后抬起：不算点击，不展开
    @Test
    func longPressDoesNotExpand() {
        var state = DockGroupPresenterState()

        _ = pressTile(groupA, at: 0, in: &state)

        let release = GroupPanelMetrics.longPressDuration + 0.1

        #expect(state.mouseUp(time: release) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 按住时长恰好等于阈值仍算点击：超过才不算
    @Test
    func pressUpToLongPressDurationStillClicks() {
        var state = DockGroupPresenterState()

        _ = pressTile(groupA, at: 0, in: &state)

        let release = GroupPanelMetrics.longPressDuration

        #expect(state.mouseUp(time: release) == .expand(groupA))
    }

    /// 展开时长按同一 tile：视同面板以外的点击而收起，随后到达的同一个组的 URL 不会再展开
    @Test
    func longPressOnPresentedTileCollapses() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        _ = pressTile(groupA, at: 5, in: &state)

        let release = 5 + GroupPanelMetrics.longPressDuration + 0.1

        #expect(state.mouseUp(time: release) == .collapse)
        #expect(state.receiveURL(groupID: groupA, time: release + 0.3) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 展开时长按另一个 tile：收起，不切换到那个组
    @Test
    func longPressOnOtherTileCollapsesWithoutSwitching() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 0, in: &state)

        _ = pressTile(groupB, at: 5, in: &state)

        let release = 5 + GroupPanelMetrics.longPressDuration + 0.1

        #expect(state.mouseUp(time: release) == .collapse)
        #expect(state.presentedGroupID == nil)
    }

    // MARK: 两路信号合并

    /// 快速路径处理过的点击，其 URL 在 1 秒内到达时忽略
    @Test
    func urlFollowingFastPathClickIsIgnored() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 10, in: &state)

        #expect(state.receiveURL(groupID: groupA, time: 10.5) == .unchanged)
        #expect(state.presentedGroupID == groupA)
    }

    /// 超过 1 秒才到达的 URL 视为新的点击
    @Test
    func lateURLTogglesAgain() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 10, in: &state)

        let late = 10 + DockGroupPresenterState.signalMergeInterval + 0.1

        #expect(state.receiveURL(groupID: groupA, time: late) == .collapse)
    }

    /// 一次点击只合并它自己的那一个 URL
    @Test
    func onlyOneURLMergesPerClick() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 10, in: &state)

        #expect(state.receiveURL(groupID: groupA, time: 10.2) == .unchanged)
        #expect(state.receiveURL(groupID: groupA, time: 10.4) == .collapse)
    }

    /// 快速路径点击的是 A，随后到达 B 的 URL 不会被合并
    @Test
    func urlOfOtherGroupIsNotMerged() {
        var state = DockGroupPresenterState()
        clickTile(groupA, at: 10, in: &state)

        #expect(state.receiveURL(groupID: groupB, time: 10.2) == .expand(groupB))
    }

    /// 1 秒内先点 A 再点 B、两个 URL 随后才到达：每个 URL 只与自己那次点击合并，最终展示最后点击的 B
    @Test
    func urlsOfConsecutiveClicksOnDifferentTilesAreMerged() {
        var state = DockGroupPresenterState()

        clickTile(groupA, at: 10, in: &state)
        clickTile(groupB, at: 10.3, in: &state)

        #expect(state.receiveURL(groupID: groupA, time: 10.5) == .unchanged)
        #expect(state.receiveURL(groupID: groupB, time: 10.6) == .unchanged)
        #expect(state.presentedGroupID == groupB)
    }

    /// 1 秒内在同一 tile 上连点两次（展开再收起）、两个 URL 随后才到达：每次点击各合并一个 URL，面板保持收起
    @Test
    func urlsOfDoubleClickOnSameTileAreMerged() {
        var state = DockGroupPresenterState()

        clickTile(groupA, at: 10, in: &state)
        clickTile(groupA, at: 10.3, in: &state)

        #expect(state.receiveURL(groupID: groupA, time: 10.5) == .unchanged)
        #expect(state.receiveURL(groupID: groupA, time: 10.6) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 同一 tile 连点两次、只到达一个 URL：它照样合并；没等到 URL 的那条记录超出时间窗后不再吞掉新的 URL
    @Test
    func unmatchedClickOnSameTileExpires() {
        var state = DockGroupPresenterState()

        clickTile(groupA, at: 10, in: &state)
        clickTile(groupA, at: 10.3, in: &state)

        #expect(state.receiveURL(groupID: groupA, time: 10.5) == .unchanged)
        #expect(state.presentedGroupID == nil)

        let late = 10.3 + DockGroupPresenterState.signalMergeInterval + 0.1

        #expect(state.receiveURL(groupID: groupA, time: late) == .expand(groupA))
    }

    // MARK: URL 路径（无辅助功能权限）

    /// URL 依次到达：展开、收起；展开时到达另一个组的 URL 则切换
    @Test
    func urlTogglesAndSwitches() {
        var state = DockGroupPresenterState()

        #expect(state.receiveURL(groupID: groupA, time: 0) == .expand(groupA))
        #expect(state.receiveURL(groupID: groupA, time: 5) == .collapse)
        #expect(state.receiveURL(groupID: groupB, time: 10) == .expand(groupB))
        #expect(state.receiveURL(groupID: groupA, time: 15) == .expand(groupA))
    }

    /// 再次点击 tile 先被当作点击 Dock 区域而收起，1 秒内到达的同一个组的 URL 属于这次点击，不再展开
    @Test
    func urlAfterDockAreaDismissalIsIgnored() {
        var state = DockGroupPresenterState()
        _ = state.receiveURL(groupID: groupA, time: 0)

        let dockAreaClick = state.mouseDown(
            onTile: nil,
            at: tilePoint,
            isInDockArea: true,
            time: 5
        )

        #expect(dockAreaClick == .collapse)
        #expect(state.receiveURL(groupID: groupA, time: 5.3) == .unchanged)
        #expect(state.presentedGroupID == nil)
    }

    /// 收起后点击的是 Dock 上另一个 Flotilla tile：它的 URL 照常展开
    @Test
    func urlOfOtherGroupAfterDockAreaDismissalExpands() {
        var state = DockGroupPresenterState()
        _ = state.receiveURL(groupID: groupA, time: 0)
        _ = state.mouseDown(onTile: nil, at: tilePoint, isInDockArea: true, time: 5)

        #expect(state.receiveURL(groupID: groupB, time: 5.3) == .expand(groupB))
    }

    /// 点击桌面收起后很快点击 tile：不是 Dock 区域的收起，URL 照常展开
    @Test
    func urlAfterNonDockDismissalExpands() {
        var state = DockGroupPresenterState()
        _ = state.receiveURL(groupID: groupA, time: 0)
        _ = state.mouseDown(onTile: nil, at: .zero, isInDockArea: false, time: 5)

        #expect(state.receiveURL(groupID: groupA, time: 5.3) == .expand(groupA))
    }

    /// Dock 区域的收起超过 1 秒后才到达的 URL 视为新的点击
    @Test
    func lateURLAfterDockAreaDismissalExpands() {
        var state = DockGroupPresenterState()
        _ = state.receiveURL(groupID: groupA, time: 0)
        _ = state.mouseDown(onTile: nil, at: tilePoint, isInDockArea: true, time: 5)

        let late = 5 + DockGroupPresenterState.signalMergeInterval + 0.1

        #expect(state.receiveURL(groupID: groupA, time: late) == .expand(groupA))
    }

    // MARK: 其它收起

    /// Esc、启动 App 等原因收起：展开时收起，已收起时不动
    @Test
    func dismissCollapsesOnlyWhenPresenting() {
        var state = DockGroupPresenterState()

        #expect(state.dismiss() == .unchanged)

        _ = state.receiveURL(groupID: groupA, time: 0)

        #expect(state.dismiss() == .collapse)
        #expect(state.presentedGroupID == nil)
    }
}

// MARK: - Helpers

extension DockGroupPresenterStateTests {
    /// 在 tile 上按下（快速路径已识别出该 tile），返回状态机给出的结论
    private func pressTile(
        _ groupID: UUID,
        at time: TimeInterval,
        in state: inout DockGroupPresenterState
    ) -> DockGroupPresenterTransition {
        state.mouseDown(onTile: groupID, at: tilePoint, isInDockArea: true, time: time)
    }

    /// 通过快速路径完整点击一次 tile，在 `time` 抬起
    private func clickTile(
        _ groupID: UUID,
        at time: TimeInterval,
        in state: inout DockGroupPresenterState
    ) {
        _ = pressTile(groupID, at: time - Self.clickDuration, in: &state)
        _ = state.mouseUp(time: time)
    }
}
