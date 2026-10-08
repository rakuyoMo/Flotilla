import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeViewControllerTests

/// 设置窗口的文件夹区：树的宽度必须始终与滚动区一致，行尾的 “不在 Dock 上” 才不会被右缘裁掉；
/// 窗口缩到最窄时，底部按钮行在每种语言下都完整显示
@MainActor
final class FolderTreeViewControllerTests {
    /// 设置窗口缩到最窄时文件夹区的宽度：内容区最小宽度扣除左右边距
    private static let minimumWidth = SettingsWindowController.minimumContentSize.width
        - 2 * SettingsWindowController.contentInset

    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的数据源：根文件夹 “工作” 下有子文件夹 “开发” 与一个 App
    private let store: FolderStore

    /// 建立根文件夹 “工作”，其下依次是子文件夹 “开发” 与 Chess.app
    init() throws {
        store = FolderStore(fileURL: directory.appending(path: "folders.json"))

        let work = store.addRootFolder(named: "工作")
        _ = try #require(store.addSubfolder(named: "开发", to: work.id))

        let chess = try #require(
            FolderItem(url: URL(filePath: "/System/Applications/Chess.app"), title: nil)
        )

        store.addItems([chess], to: work.id)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 展开文件夹后树不得比滚动区宽：outline view 默认会随展开的子层级加宽大纲列，超出的部分被滚动区裁掉
    @Test
    func expandingFolderKeepsOutlineWithinScrollView() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

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

    /// 窗口缩到最窄时，每种语言的按钮都按完整标题的宽度排开，互不重叠，也不超出文件夹区：
    /// 按钮行放不下时，按钮保持完整宽度，把文件夹区撑宽，最右边的按钮越出最窄时的文件夹区
    @Test(arguments: LocalizationTests.languages)
    func buttonRowFitsMinimumWidth(language: String) throws {
        let table = try LocalizationTests.table(for: language)
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)

        let buttonRow = try #require(
            (controller.view as? NSStackView)?.arrangedSubviews.last as? NSStackView
        )
        let buttons = buttonRow.views.compactMap { $0 as? NSButton }

        // 测试进程读不到 `.lproj` 里的译文，按钮标题就是键名，按键名换成这种语言的文字；
        // “添加到 Dock” 在没有同步器时隐藏，这里也显示出来
        for button in buttons {
            button.title = try #require(table[button.title], "表里没有 \(button.title)")
            button.isHidden = false
        }

        #expect(buttons.count == 5)

        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        // 按从左到右的顺序排好，坐标换算到文件夹区
        let placed = buttons
            .map { (button: $0, frame: buttonRow.convert($0.frame, to: controller.view)) }
            .sorted { $0.frame.minX < $1.frame.minX }

        // 每个按钮都不窄于完整标题需要的宽度
        for (button, frame) in placed {
            #expect(frame.width >= button.intrinsicContentSize.width, "\(button.title) 被压窄")
        }

        // 相邻按钮不重叠，最右边的不越出文件夹区
        for (left, right) in zip(placed, placed.dropFirst()) {
            #expect(left.frame.maxX <= right.frame.minX)
        }

        #expect(try #require(placed.last).frame.maxX <= Self.minimumWidth)
    }
}

// MARK: - Private

extension FolderTreeViewControllerTests {
    /// 放文件夹区的离屏窗口，内容区宽 `width`
    private func makeWindow(width: CGFloat) -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }
}
