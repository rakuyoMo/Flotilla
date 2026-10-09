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
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])

        let groupIDs = tracker.groupIDsToAdd(
            rootGroupIDs: [existingID],
            onDockGroupIDs: []
        )

        #expect(groupIDs.isEmpty)
    }

    // MARK: 新出现的根文件夹

    /// 新建的根文件夹、被拖成根文件夹的子文件夹：上一次同步时还不是根文件夹，添加
    @Test
    func newRootGroupIsAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])

        let groupIDs = tracker.groupIDsToAdd(
            rootGroupIDs: [existingID, newID],
            onDockGroupIDs: [existingID]
        )

        #expect(groupIDs == [newID])
    }

    /// 添加之后还没确认新 Dock 读到了 tile（补写一直赶不上新 Dock 读取偏好）：tile 不在 Dock 上时不算被拖出，
    /// 设置窗口不显示状态，下一次同步再加
    @Test
    func unconfirmedTileIsAddedAgain() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [])

        let firstIDs = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])

        let removedIDs = tracker.removedGroupIDs(rootGroupIDs: [newID], onDockGroupIDs: [])
        let nextIDs = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])

        #expect(firstIDs == [newID])
        #expect(removedIDs.isEmpty)
        #expect(nextIDs == [newID])
    }

    /// 重启后的 Dock 读到了含有 tile 的偏好，tile 已经加上。
    /// 之后、下一次同步之前用户把 tile 拖出：设置窗口随即显示它不在 Dock 上，下一次同步不加回
    @Test
    func tileConfirmedByRelaunchedDockThenDraggedOutIsNotAddedAgain() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let rootIDs: Set = [existingID, newID]

        let firstIDs = tracker.groupIDsToAdd(rootGroupIDs: rootIDs, onDockGroupIDs: [])
        tracker.recordDockRelaunch(onDockGroupIDs: rootIDs)

        // 两个 tile 都在下一次同步之前被拖出 Dock
        let removedIDs = tracker.removedGroupIDs(rootGroupIDs: rootIDs, onDockGroupIDs: [])
        let nextIDs = tracker.groupIDsToAdd(rootGroupIDs: rootIDs, onDockGroupIDs: [])

        #expect(firstIDs == rootIDs)
        #expect(removedIDs == rootIDs)
        #expect(nextIDs.isEmpty)
    }

    /// 新 Dock 读到的偏好里只有部分 tile（例如某个 stub 写入失败没能添加）：只确认读到的，其余仍待添加
    @Test
    func relaunchConfirmsOnlyTilesOnDock() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let rootIDs: Set = [existingID, newID]

        _ = tracker.groupIDsToAdd(rootGroupIDs: rootIDs, onDockGroupIDs: [])
        tracker.recordDockRelaunch(onDockGroupIDs: [newID])

        let nextIDs = tracker.groupIDsToAdd(rootGroupIDs: rootIDs, onDockGroupIDs: [])

        #expect(nextIDs == [existingID])
    }

    /// 看到 tile 在 Dock 上之后它又不在了：是用户拖出去的，不再添加
    @Test
    func tileRemovedAfterBeingSeenIsNotAddedAgain() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [])

        _ = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])
        let seenIDs = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [newID])
        let draggedOutIDs = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])

        #expect(seenIDs.isEmpty)
        #expect(draggedOutIDs.isEmpty)
    }

    // MARK: 用户请求

    /// 用户在设置窗口要求添加：tile 不在 Dock 上的根文件夹重新添加，并同样保持待添加直到看到 tile
    @Test
    func requestedGroupIsAddedUntilTileIsSeen() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let firstIDs = tracker.groupIDsToAdd(rootGroupIDs: [existingID], onDockGroupIDs: [])
        let nextIDs = tracker.groupIDsToAdd(rootGroupIDs: [existingID], onDockGroupIDs: [])
        let seenIDs = tracker.groupIDsToAdd(
            rootGroupIDs: [existingID],
            onDockGroupIDs: [existingID]
        )

        #expect(firstIDs == [existingID])
        #expect(nextIDs == [existingID])
        #expect(seenIDs.isEmpty)
    }

    /// 要求添加的根文件夹 tile 已在 Dock 上：不再添加，也不留作待添加
    @Test
    func requestedGroupAlreadyOnDockIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let onDockIDs = tracker.groupIDsToAdd(
            rootGroupIDs: [existingID],
            onDockGroupIDs: [existingID]
        )
        let draggedOutIDs = tracker.groupIDsToAdd(
            rootGroupIDs: [existingID],
            onDockGroupIDs: []
        )

        #expect(onDockIDs.isEmpty)
        #expect(draggedOutIDs.isEmpty)
    }

    // MARK: 搁置

    /// 新建后正在输入名称的根文件夹：搁置期间的同步不添加 tile，也不算被拖出；
    /// 名称定下来解除搁置后，下一次同步把它当作新出现的根文件夹添加
    @Test
    func heldGroupIsAddedOnlyAfterRelease() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.hold(groupID: newID)

        let rootIDs: Set = [existingID, newID]

        let heldIDs = tracker.groupIDsToAdd(rootGroupIDs: rootIDs, onDockGroupIDs: [existingID])
        let heldRemovedIDs = tracker.removedGroupIDs(
            rootGroupIDs: rootIDs,
            onDockGroupIDs: [existingID]
        )

        tracker.release(groupID: newID)
        let releasedIDs = tracker.groupIDsToAdd(
            rootGroupIDs: rootIDs,
            onDockGroupIDs: [existingID]
        )

        #expect(heldIDs.isEmpty)
        #expect(heldRemovedIDs.isEmpty)
        #expect(releasedIDs == [newID])
    }

    /// 解除搁置时告知它是否在搁置中：只有搁置过的根文件夹才需要为它再同步一次
    @Test
    func releaseReportsWhetherGroupWasHeld() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.hold(groupID: newID)

        let isHeld = tracker.release(groupID: newID)
        let isHeldAgain = tracker.release(groupID: newID)
        let isExistingHeld = tracker.release(groupID: existingID)

        #expect(isHeld)
        #expect(!isHeldAgain)
        #expect(!isExistingHeld)
    }

    /// 搁置期间被删除或被拖成子文件夹的根文件夹：解除搁置后不添加
    @Test
    func heldGroupNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [])
        tracker.hold(groupID: newID)

        _ = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])
        tracker.release(groupID: newID)

        let groupIDs = tracker.groupIDsToAdd(rootGroupIDs: [], onDockGroupIDs: [])

        #expect(groupIDs.isEmpty)
    }

    // MARK: 不再是根文件夹

    /// 新出现、还没看到 tile 的根文件夹被删除或被拖成子文件夹：不再添加
    @Test
    func pendingGroupNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [])

        let pendingIDs = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])
        let removedIDs = tracker.groupIDsToAdd(rootGroupIDs: [], onDockGroupIDs: [])

        #expect(pendingIDs == [newID])
        #expect(removedIDs.isEmpty)
    }

    /// 要求添加之后、同步之前，该根文件夹被删除或被拖成子文件夹：不添加
    @Test
    func requestedGroupNoLongerRootIsNotAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let groupIDs = tracker.groupIDsToAdd(rootGroupIDs: [], onDockGroupIDs: [])

        #expect(groupIDs.isEmpty)
    }

    /// 被拖成子文件夹的根文件夹再被拖回根层级：又是新出现的根文件夹，添加
    @Test
    func groupBecomingRootAgainIsAdded() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])

        _ = tracker.groupIDsToAdd(rootGroupIDs: [], onDockGroupIDs: [])
        let groupIDs = tracker.groupIDsToAdd(rootGroupIDs: [existingID], onDockGroupIDs: [])

        #expect(groupIDs == [existingID])
    }

    // MARK: 被拖出 Dock 的判定

    /// 启动时就缺少 tile 的根文件夹算被拖出：设置窗口要显示 “不在 Dock 上”
    @Test
    func missingTileAtLaunchIsRemoved() {
        let tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])

        let removedIDs = tracker.removedGroupIDs(
            rootGroupIDs: [existingID],
            onDockGroupIDs: []
        )

        #expect(removedIDs == [existingID])
    }

    /// 新建后还没同步的根文件夹不算被拖出：tile 只是还没加上，状态文字不该闪现
    @Test
    func newRootGroupBeforeSyncIsNotRemoved() {
        let tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])

        let removedIDs = tracker.removedGroupIDs(
            rootGroupIDs: [existingID, newID],
            onDockGroupIDs: [existingID]
        )

        #expect(removedIDs.isEmpty)
    }

    /// 添加过、还没看到 tile 的根文件夹不算被拖出；看到之后 tile 又不在了才算
    @Test
    func pendingGroupIsNotRemovedUntilTileDisappearsAfterBeingSeen() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [])

        _ = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [])
        let pendingRemovedIDs = tracker.removedGroupIDs(
            rootGroupIDs: [newID],
            onDockGroupIDs: []
        )

        _ = tracker.groupIDsToAdd(rootGroupIDs: [newID], onDockGroupIDs: [newID])
        let draggedOutIDs = tracker.removedGroupIDs(rootGroupIDs: [newID], onDockGroupIDs: [])

        #expect(pendingRemovedIDs.isEmpty)
        #expect(draggedOutIDs == [newID])
    }

    /// 用户要求添加之后立即不再算被拖出：点了 “添加到 Dock” 状态文字随即消失
    @Test
    func requestedGroupIsNotRemoved() {
        var tracker = DockTileAdditionTracker(rootGroupIDs: [existingID])
        tracker.request(groupID: existingID)

        let removedIDs = tracker.removedGroupIDs(
            rootGroupIDs: [existingID],
            onDockGroupIDs: []
        )

        #expect(removedIDs.isEmpty)
    }
}
