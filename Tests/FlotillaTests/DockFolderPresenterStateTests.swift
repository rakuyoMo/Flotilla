import CoreGraphics
import Foundation
import Testing

@testable import Flotilla

// MARK: - DockFolderPresenterStateTests

/// 展开状态的迁移：同一次点击 tile 会先后经过快速路径与 URL 两条路径，必须只生效一次，
/// 否则再次点击会变成“先收起再展开”，按下后拖动 tile 也会误展开
struct DockFolderPresenterStateTests {
    /// 根文件夹 A
    private let folderA = UUID()

    /// 根文件夹 B
    private let folderB = UUID()

    /// tile 上的一个按下位置
    private let tilePoint = CGPoint(x: 700, y: 40)

    // MARK: 快速路径

    /// 在 tile 上按下不展开，抬起才展开
    @Test
    func tileClickExpandsOnMouseUp() {
        var state = DockFolderPresenterState()

        #expect(pressTile(folderA, in: &state) == .unchanged)
        #expect(state.mouseUp(time: 0) == .expand(folderA))
        #expect(state.presentedFolderID == folderA)
    }

    /// 按下后拖动超过阈值（调整 Dock 顺序）：抬起时不展开
    @Test
    func draggingTileDoesNotExpand() {
        var state = DockFolderPresenterState()
        let farPoint = CGPoint(x: tilePoint.x + FolderPanelMetrics.dragThreshold + 1, y: tilePoint.y)

        _ = pressTile(folderA, in: &state)

        #expect(state.mouseDragged(to: farPoint, time: 0) == .unchanged)
        #expect(state.mouseUp(time: 0) == .unchanged)
        #expect(state.presentedFolderID == nil)
    }

    /// 阈值以内的抖动仍算一次点击
    @Test
    func jitterWithinThresholdStillClicks() {
        var state = DockFolderPresenterState()
        let nearPoint = CGPoint(x: tilePoint.x + FolderPanelMetrics.dragThreshold, y: tilePoint.y)

        _ = pressTile(folderA, in: &state)

        #expect(state.mouseDragged(to: nearPoint, time: 0) == .unchanged)
        #expect(state.mouseUp(time: 0) == .expand(folderA))
    }

    /// 展开时从另一个 tile 按下拖动：视同点击其它位置，收起面板
    @Test
    func draggingTileWhilePresentingCollapses() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 0, in: &state)

        _ = pressTile(folderB, in: &state)

        #expect(state.mouseDragged(to: CGPoint(x: 900, y: 40), time: 1) == .collapse)
        #expect(state.mouseUp(time: 1) == .unchanged)
    }

    /// 展开时再次点击同一 tile：按下时不动，抬起时收起，随后到达的 URL 不会再展开
    @Test
    func clickingSameTileCollapsesWithoutReopening() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 0, in: &state)

        #expect(pressTile(folderA, in: &state) == .unchanged)
        #expect(state.mouseUp(time: 2) == .collapse)
        #expect(state.receiveURL(folderID: folderA, time: 2.3) == .unchanged)
        #expect(state.presentedFolderID == nil)
    }

    /// 展开时点击另一个 tile：直接切换，中间没有收起
    @Test
    func clickingOtherTileSwitchesDirectly() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 0, in: &state)

        #expect(pressTile(folderB, in: &state) == .unchanged)
        #expect(state.mouseUp(time: 2) == .expand(folderB))
        #expect(state.presentedFolderID == folderB)
    }

    /// 展开时点击面板以外的位置（任一按键）：收起；已收起时再点不再有动作
    @Test
    func outsideClickCollapsesOnce() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 0, in: &state)

        #expect(state.mouseDown(onTile: nil, at: .zero, isInDockArea: false, time: 1) == .collapse)
        #expect(state.mouseDown(onTile: nil, at: .zero, isInDockArea: false, time: 2) == .unchanged)
    }

    // MARK: 两路信号合并

    /// 快速路径处理过的点击，其 URL 在 1 秒内到达时忽略
    @Test
    func urlFollowingFastPathClickIsIgnored() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 10, in: &state)

        #expect(state.receiveURL(folderID: folderA, time: 10.5) == .unchanged)
        #expect(state.presentedFolderID == folderA)
    }

    /// 超过 1 秒才到达的 URL 视为新的点击
    @Test
    func lateURLTogglesAgain() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 10, in: &state)

        let late = 10 + DockFolderPresenterState.signalMergeInterval + 0.1

        #expect(state.receiveURL(folderID: folderA, time: late) == .collapse)
    }

    /// 一次点击只合并它自己的那一个 URL
    @Test
    func onlyOneURLMergesPerClick() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 10, in: &state)

        #expect(state.receiveURL(folderID: folderA, time: 10.2) == .unchanged)
        #expect(state.receiveURL(folderID: folderA, time: 10.4) == .collapse)
    }

    /// 快速路径点击的是 A，随后到达 B 的 URL 不会被合并
    @Test
    func urlOfOtherFolderIsNotMerged() {
        var state = DockFolderPresenterState()
        clickTile(folderA, at: 10, in: &state)

        #expect(state.receiveURL(folderID: folderB, time: 10.2) == .expand(folderB))
    }

    // MARK: URL 路径（无辅助功能权限）

    /// URL 依次到达：展开、收起；展开时到达另一个文件夹的 URL 则切换
    @Test
    func urlTogglesAndSwitches() {
        var state = DockFolderPresenterState()

        #expect(state.receiveURL(folderID: folderA, time: 0) == .expand(folderA))
        #expect(state.receiveURL(folderID: folderA, time: 5) == .collapse)
        #expect(state.receiveURL(folderID: folderB, time: 10) == .expand(folderB))
        #expect(state.receiveURL(folderID: folderA, time: 15) == .expand(folderA))
    }

    /// 再次点击 tile 先被当作点击 Dock 区域而收起，1 秒内到达的同一文件夹 URL 属于这次点击，不再展开
    @Test
    func urlAfterDockAreaDismissalIsIgnored() {
        var state = DockFolderPresenterState()
        _ = state.receiveURL(folderID: folderA, time: 0)

        #expect(state.mouseDown(onTile: nil, at: tilePoint, isInDockArea: true, time: 5) == .collapse)
        #expect(state.receiveURL(folderID: folderA, time: 5.3) == .unchanged)
        #expect(state.presentedFolderID == nil)
    }

    /// 收起后点击的是 Dock 上另一个 Flotilla tile：它的 URL 照常展开
    @Test
    func urlOfOtherFolderAfterDockAreaDismissalExpands() {
        var state = DockFolderPresenterState()
        _ = state.receiveURL(folderID: folderA, time: 0)
        _ = state.mouseDown(onTile: nil, at: tilePoint, isInDockArea: true, time: 5)

        #expect(state.receiveURL(folderID: folderB, time: 5.3) == .expand(folderB))
    }

    /// 点击桌面收起后很快点击 tile：不是 Dock 区域的收起，URL 照常展开
    @Test
    func urlAfterNonDockDismissalExpands() {
        var state = DockFolderPresenterState()
        _ = state.receiveURL(folderID: folderA, time: 0)
        _ = state.mouseDown(onTile: nil, at: .zero, isInDockArea: false, time: 5)

        #expect(state.receiveURL(folderID: folderA, time: 5.3) == .expand(folderA))
    }

    /// Dock 区域的收起超过 1 秒后才到达的 URL 视为新的点击
    @Test
    func lateURLAfterDockAreaDismissalExpands() {
        var state = DockFolderPresenterState()
        _ = state.receiveURL(folderID: folderA, time: 0)
        _ = state.mouseDown(onTile: nil, at: tilePoint, isInDockArea: true, time: 5)

        let late = 5 + DockFolderPresenterState.signalMergeInterval + 0.1

        #expect(state.receiveURL(folderID: folderA, time: late) == .expand(folderA))
    }

    // MARK: 其它收起

    /// Esc、启动 App 等原因收起：展开时收起，已收起时不动
    @Test
    func dismissCollapsesOnlyWhenPresenting() {
        var state = DockFolderPresenterState()

        #expect(state.dismiss() == .unchanged)

        _ = state.receiveURL(folderID: folderA, time: 0)

        #expect(state.dismiss() == .collapse)
        #expect(state.presentedFolderID == nil)
    }
}

// MARK: - Helpers

extension DockFolderPresenterStateTests {
    /// 在 tile 上按下（快速路径已识别出该 tile）
    private func pressTile(_ folderID: UUID, in state: inout DockFolderPresenterState) -> DockFolderPresenterTransition {
        state.mouseDown(onTile: folderID, at: tilePoint, isInDockArea: true, time: 0)
    }

    /// 通过快速路径完整点击一次 tile
    private func clickTile(_ folderID: UUID, at time: TimeInterval, in state: inout DockFolderPresenterState) {
        _ = pressTile(folderID, in: &state)
        _ = state.mouseUp(time: time)
    }
}
