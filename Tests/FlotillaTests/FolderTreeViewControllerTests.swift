import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeViewControllerTests

/// 设置窗口的文件夹区：树的宽度必须始终与滚动区一致，行尾的“不在 Dock 上”才不会被右缘裁掉
@MainActor
final class FolderTreeViewControllerTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的数据源：根文件夹“工作”下有子文件夹“开发”与一个 App
    private let store: FolderStore

    /// 建立“工作 / [开发, Chess]”的树
    init() throws {
        store = FolderStore(fileURL: directory.appending(path: "folders.json"))

        let work = store.addRootFolder(named: "工作")
        _ = try #require(store.addSubfolder(named: "开发", to: work.id))

        store.addApps([URL(filePath: "/System/Applications/Chess.app")], to: work.id)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 展开文件夹后树不得比滚动区宽：outline view 默认会随展开的子层级加宽大纲列，超出的部分被滚动区裁掉
    @Test
    func expandingFolderKeepsOutlineWithinScrollView() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let scrollView = try #require(
            controller.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let outlineView = try #require(scrollView.documentView as? NSOutlineView)

        outlineView.expandItem(outlineView.item(atRow: 0))
        controller.view.layoutSubtreeIfNeeded()

        #expect(outlineView.frame.width <= scrollView.contentView.bounds.width)
    }
}
