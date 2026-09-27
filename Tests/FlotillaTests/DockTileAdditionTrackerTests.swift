import Foundation
import Testing

@testable import Flotilla

// MARK: - DockTileAdditionTrackerTests

/// 添加 tile 的条件：用户拖出 Dock 的 tile 不能被自动加回，新出现的与用户要求添加的根文件夹却必须出现在 Dock 上，
/// 而且在 Dock 写回偏好盖掉刚加的条目时还要再加一次
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

    /// 添加过的根文件夹在看到 tile 之前保持待添加：Dock 重启后写回偏好盖掉了刚加的条目，复查时再加一次
    @Test
    func addedFolderStaysPendingUntilTileIsSeen() {
        var tracker = DockTileAdditionTracker(rootFolderIDs: [])

        let firstIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])
        let recheckIDs = tracker.folderIDsToAdd(rootFolderIDs: [newID], onDockFolderIDs: [])

        #expect(firstIDs == [newID])
        #expect(recheckIDs == [newID])
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
        let recheckIDs = tracker.folderIDsToAdd(rootFolderIDs: [existingID], onDockFolderIDs: [])
        let seenIDs = tracker.folderIDsToAdd(
            rootFolderIDs: [existingID],
            onDockFolderIDs: [existingID]
        )

        #expect(firstIDs == [existingID])
        #expect(recheckIDs == [existingID])
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
}
