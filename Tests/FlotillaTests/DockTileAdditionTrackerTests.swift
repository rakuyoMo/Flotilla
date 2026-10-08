import Foundation
import Testing

@testable import Flotilla

// MARK: - DockTileAdditionTrackerTests

/// 添加 tile 的条件：用户拖出 Dock 的 tile 不能被自动加回，新出现的与用户要求添加的根文件夹却必须出现在 Dock 上，
/// 在确认新 Dock 读到 tile 之前还要保持待添加；新建的根文件夹在名称定下来之前不能出现在 Dock 上
struct DockTileAdditionTrackerTests {
    /// 启动时就在的根文件夹
    private let existingID = UUID()

    /// 启动后新出现的根文件夹
    private let newID = UUID()

    // MARK: 启动

    /// 启动时缺少 tile 的根文件夹：是用户在 Flotilla 没运行时拖出去的，不添加
    @Test
    func missingTileAtLaunchIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])

        let folderIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID],
            onDockFolderIDs: []
        )

        #expect(folderIDs.isEmpty)
    }

    // MARK: 新出现的根文件夹

    /// 新建的根文件夹、被拖成根文件夹的子文件夹：上一次同步时还不是根文件夹，添加
    @Test
    func newRootFolderIsAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])

        let folderIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID, newID],
            onDockFolderIDs: [existingID]
        )

        #expect(folderIDs == [newID])
    }

    /// 添加之后还没确认新 Dock 读到了 tile（补写一直赶不上新 Dock 读取偏好）：tile 不在 Dock 上时不算被拖出，
    /// 设置窗口不显示状态，下一次同步再加
    @Test
    func unconfirmedTileIsAddedAgain() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])

        let firstIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])

        let removedIDs = tracker.removedFolderIDs(rootFolderIDs: [newID], onDockFolderIDs: [])
        let nextIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])

        #expect(firstIDs == [newID])
        #expect(removedIDs.isEmpty)
        #expect(nextIDs == [newID])
    }

    /// 重启后的 Dock 读到了含有 tile 的偏好，tile 已经加上。
    /// 之后、下一次同步之前用户把 tile 拖出：设置窗口随即显示它不在 Dock 上，下一次同步不加回
    @Test
    func tileConfirmedByRelaunchedDockThenDraggedOutIsNotAddedAgain() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let rootIDs: Set = [existingID, newID]

        let firstIDs = tracker.folderIDsToAdd(rootFolderIDs: rootIDs, onDockFolderIDs: [])
        tracker.recordDockRelaunch(onDockFolderIDs: rootIDs)

        // 两个 tile 都在下一次同步之前被拖出 Dock
        let removedIDs = tracker.removedFolderIDs(rootFolderIDs: rootIDs, onDockFolderIDs: [])
        let nextIDs = tracker.folderIDsToAdd(rootFolderIDs: rootIDs, onDockFolderIDs: [])

        #expect(firstIDs == rootIDs)
        #expect(removedIDs == rootIDs)
        #expect(nextIDs.isEmpty)
    }

    /// 新 Dock 读到的偏好里只有部分 tile（例如某个 stub 写入失败没能添加）：只确认读到的，其余仍待添加
    @Test
    func relaunchConfirmsOnlyTilesOnDock() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let rootIDs: Set = [existingID, newID]

        _ = tracker.folderIDsToAdd(rootFolderIDs: rootIDs, onDockFolderIDs: [])
        tracker.recordDockRelaunch(onDockFolderIDs: [newID])

        let nextIDs = tracker.folderIDsToAdd(rootFolderIDs: rootIDs, onDockFolderIDs: [])

        #expect(nextIDs == [existingID])
    }

    /// 看到 tile 在 Dock 上之后它又不在了：是用户拖出去的，不再添加
    @Test
    func tileRemovedAfterBeingSeenIsNotAddedAgain() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])

        _ = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])
        let seenIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [newID])
        let draggedOutIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])

        #expect(seenIDs.isEmpty)
        #expect(draggedOutIDs.isEmpty)
    }

    // MARK: 用户请求

    /// 用户在设置窗口要求添加：tile 不在 Dock 上的根文件夹重新添加，并同样保持待添加直到看到 tile
    @Test
    func requestedFolderIsAddedUntilTileIsSeen() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let firstIDs = tracker.folderIDsToAdd(rootFolderIDs: [existingID], onDockFolderIDs: [])
        let nextIDs = tracker.folderIDsToAdd(rootFolderIDs: [existingID], onDockFolderIDs: [])
        let seenIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID],
            onDockFolderIDs: [existingID]
        )

        #expect(firstIDs == [existingID])
        #expect(nextIDs == [existingID])
        #expect(seenIDs.isEmpty)
    }

    /// 要求添加的根文件夹 tile 已在 Dock 上：不再添加，也不留作待添加
    @Test
    func requestedFolderAlreadyOnDockIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let onDockIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID],
            onDockFolderIDs: [existingID]
        )
        let draggedOutIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID],
            onDockFolderIDs: []
        )

        #expect(onDockIDs.isEmpty)
        #expect(draggedOutIDs.isEmpty)
    }

    // MARK: 搁置

    /// 新建后正在输入名称的根文件夹：搁置期间的同步不添加 tile，也不算被拖出；
    /// 名称定下来解除搁置后，下一次同步把它当作新出现的根文件夹添加
    @Test
    func heldFolderIsAddedOnlyAfterRelease() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.hold(folderID: newID)

        let rootIDs: Set = [existingID, newID]

        let heldIDs = tracker.folderIDsToAdd(rootFolderIDs: rootIDs, onDockFolderIDs: [existingID])
        let heldRemovedIDs = tracker.removedFolderIDs(
            rootFolderIDs: rootIDs,
            onDockFolderIDs: [existingID]
        )

        tracker.release(folderID: newID)
        let releasedIDs = tracker.folderIDsToAdd(
            rootFolderIDs: rootIDs,
            onDockFolderIDs: [existingID]
        )

        #expect(heldIDs.isEmpty)
        #expect(heldRemovedIDs.isEmpty)
        #expect(releasedIDs == [newID])
    }

    /// 解除搁置时告知它是否在搁置中：只有搁置过的根文件夹才需要为它再同步一次
    @Test
    func releaseReportsWhetherFolderWasHeld() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.hold(folderID: newID)

        let isHeld = tracker.release(folderID: newID)
        let isHeldAgain = tracker.release(folderID: newID)
        let isExistingHeld = tracker.release(folderID: existingID)

        #expect(isHeld)
        #expect(!isHeldAgain)
        #expect(!isExistingHeld)
    }

    /// 搁置期间被删除或被拖成子文件夹的根文件夹：解除搁置后不添加
    @Test
    func heldFolderNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])
        tracker.hold(folderID: newID)

        _ = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])
        tracker.release(folderID: newID)

        let folderIDs = tracker.folderIDsToAdd(rootFolderIDs: [], onDockFolderIDs: [])

        #expect(folderIDs.isEmpty)
    }

    // MARK: 不再是根文件夹

    /// 新出现、还没看到 tile 的根文件夹被删除或被拖成子文件夹：不再添加
    @Test
    func pendingFolderNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])

        let pendingIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])
        let removedIDs = tracker.folderIDsToAdd(rootFolderIDs: [], onDockFolderIDs: [])

        #expect(pendingIDs == [newID])
        #expect(removedIDs.isEmpty)
    }

    /// 要求添加之后、同步之前，该根文件夹被删除或被拖成子文件夹：不添加
    @Test
    func requestedFolderNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let folderIDs = tracker.folderIDsToAdd(rootFolderIDs: [], onDockFolderIDs: [])

        #expect(folderIDs.isEmpty)
    }

    /// 被拖成子文件夹的根文件夹再被拖回根层级：又是新出现的根文件夹，添加
    @Test
    func folderBecomingRootAgainIsAdded() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])

        _ = tracker.folderIDsToAdd(rootFolderIDs: [], onDockFolderIDs: [])
        let folderIDs = tracker.folderIDsToAdd(rootFolderIDs: [existingID], onDockFolderIDs: [])

        #expect(folderIDs == [existingID])
    }

    // MARK: 被拖出 Dock 的判定

    /// 启动时就缺少 tile 的根文件夹算被拖出：设置窗口要显示 “不在 Dock 上”
    @Test
    func missingTileAtLaunchIsRemoved() {
        let tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])

        let removedIDs = tracker.removedFolderIDs(
            rootFolderIDs: [existingID],
            onDockFolderIDs: []
        )

        #expect(removedIDs == [existingID])
    }

    /// 新建后还没同步的根文件夹不算被拖出：tile 只是还没加上，状态文字不该闪现
    @Test
    func newRootFolderBeforeSyncIsNotRemoved() {
        let tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])

        let removedIDs = tracker.removedFolderIDs(
            rootFolderIDs: [existingID, newID],
            onDockFolderIDs: [existingID]
        )

        #expect(removedIDs.isEmpty)
    }

    /// 添加过、还没看到 tile 的根文件夹不算被拖出；看到之后 tile 又不在了才算
    @Test
    func pendingFolderIsNotRemovedUntilTileDisappearsAfterBeingSeen() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])

        _ = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])
        let pendingRemovedIDs = tracker.removedFolderIDs(
            rootFolderIDs: [newID],
            onDockFolderIDs: []
        )

        _ = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [newID])
        let draggedOutIDs = tracker.removedFolderIDs(rootFolderIDs: [newID], onDockFolderIDs: [])

        #expect(pendingRemovedIDs.isEmpty)
        #expect(draggedOutIDs == [newID])
    }

    /// 用户要求添加之后立即不再算被拖出：点了 “添加到 Dock” 状态文字随即消失
    @Test
    func requestedFolderIsNotRemoved() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [existingID])
        tracker.request(folderID: existingID)

        let removedIDs = tracker.removedFolderIDs(
            rootFolderIDs: [existingID],
            onDockFolderIDs: []
        )

        #expect(removedIDs.isEmpty)
    }
}
