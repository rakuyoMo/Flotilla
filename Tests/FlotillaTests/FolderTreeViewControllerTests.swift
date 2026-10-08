import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeViewControllerTests

/// 设置窗口的文件夹区：树的宽度必须始终与滚动区一致，行尾的 “不在 Dock 上” 才不会被右缘裁掉；
/// 添加 App、文件与网页都从 “添加…” 的菜单进入；窗口缩到最窄时，底部按钮行在每种语言下都完整显示；
/// 网页的标题晚到时补上，但不打断正在编辑的文件夹名
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

        let row = try buttonRow(of: controller)
        let buttons = row.views.compactMap { $0 as? NSButton }

        // 测试进程读不到 `.lproj` 里的译文，按钮标题就是键名，按键名换成这种语言的文字；
        // “添加到 Dock” 在没有同步器时隐藏，这里也显示出来
        for button in buttons {
            button.title = try #require(table[button.title], "表里没有 \(button.title)")
            button.isHidden = false
        }

        #expect(buttons.count == 4)

        // pull-down 显示的是第一项的标题：给 `title` 赋值换掉的正是这一项，宽度按译文重新计算
        let addPopUp = try #require(buttons[1] as? NSPopUpButton)
        let translatedPopUpButton = NSPopUpButton(frame: .zero, pullsDown: true)
        translatedPopUpButton.addItem(withTitle: try #require(table["folders.add"]))

        #expect(addPopUp.itemTitles.first == table["folders.add"])

        #expect(
            addPopUp.intrinsicContentSize.width
                == translatedPopUpButton.intrinsicContentSize.width
        )

        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        // 按从左到右的顺序排好，坐标换算到文件夹区
        let placed = buttons
            .map { (button: $0, frame: row.convert($0.frame, to: controller.view)) }
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

    /// 按钮行从左到右是 新建文件夹、添加…、添加到 Dock、删除；“添加…” 是点击后在下方弹出菜单的 pull-down
    @Test
    func buttonRowListsFourControlsInOrder() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let controls = try buttonRow(of: controller).views

        // 测试进程读不到译文，标题就是键名；pull-down 的标题是它的第一项
        #expect(controls.map { ($0 as? NSButton)?.title } == [
            "folders.newFolder",
            "folders.add",
            "folders.addToDock",
            "folders.remove",
        ])

        #expect(try #require(controls[1] as? NSPopUpButton).pullsDown)
    }

    /// “添加…” 的菜单依次是 添加 App…、添加文件…、添加网页…，各自调用对应的方法
    @Test
    func addMenuItemsCallTheirActions() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let addPopUp = try addPopUpButton(of: controller)

        // 第一项是按钮上显示的 “添加…”，菜单里列出的是其后的各项
        let menuItems = addPopUp.itemArray.dropFirst()

        #expect(menuItems.map(\.title) == [
            "folders.addApps",
            "folders.addFiles",
            "folders.addWebPage",
        ])

        #expect(menuItems.map(\.action) == [
            NSSelectorFromString("addApps"),
            NSSelectorFromString("addFiles"),
            NSSelectorFromString("addWebPage"),
        ])

        #expect(menuItems.allSatisfy { $0.target === controller })
    }

    /// 三项都加入选中项所属的文件夹：没有选中项时 “添加…” 禁用，选中一行后可用
    @Test
    func addIsEnabledOnlyWithSelection() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let addPopUp = try addPopUpButton(of: controller)

        #expect(!addPopUp.isEnabled)

        let scrollView = try #require(
            controller.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let outlineView = try #require(scrollView.documentView as? NSOutlineView)

        outlineView.selectRowIndexes([0], byExtendingSelection: false)

        #expect(addPopUp.isEnabled)
    }

    // MARK: 补标题

    /// 没在编辑文件夹名时，取到的网页标题立刻补上
    @Test
    func fillTitleAppliesImmediatelyWhenNotEditing() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let webPage = try addUntitledWebPage()

        controller.fillTitle("Apple", ofWebPageWithID: webPage.id)

        #expect(try lastItemOfWork() == titled(webPage, "Apple"))
    }

    /// 正在编辑文件夹名时取到的标题先不补：补标题会重建树，重建会结束编辑并提交输入到一半的名称；
    /// 编辑结束、名称定下来之后补上
    @Test
    func fillTitleWaitsUntilFolderNameEditingEnds() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let webPage = try addUntitledWebPage()
        let fieldEditor = try beginEditingWorkName(in: controller)

        fieldEditor.insertText("工作区", replacementRange: NSRange(location: NSNotFound, length: 0))

        controller.fillTitle("Apple", ofWebPageWithID: webPage.id)

        #expect(window.firstResponder === fieldEditor)
        #expect(store.rootFolders.first?.name == "工作")
        #expect(try lastItemOfWork() == .webPage(webPage))

        // 点别处结束编辑
        window.makeFirstResponder(nil)

        #expect(store.rootFolders.first?.name == "工作区")
        #expect(try lastItemOfWork() == titled(webPage, "Apple"))
    }

    /// 按 Esc 取消编辑同样算编辑结束：名称保持原样，取到的标题随后补上
    @Test
    func fillTitleWaitsUntilEscapeCancelsEditing() async throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let webPage = try addUntitledWebPage()
        let fieldEditor = try beginEditingWorkName(in: controller)

        fieldEditor.insertText("工作区", replacementRange: NSRange(location: NSNotFound, length: 0))

        controller.fillTitle("Apple", ofWebPageWithID: webPage.id)
        fieldEditor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))

        // outline view 收到 Esc 之后才结束编辑，补标题经主线程上排着的任务进行
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        #expect(window.firstResponder !== fieldEditor)
        #expect(store.rootFolders.first?.name == "工作")
        #expect(try lastItemOfWork() == titled(webPage, "Apple"))
    }
}

// MARK: - Private

extension FolderTreeViewControllerTests {
    /// 文件夹区底部的按钮行
    private func buttonRow(of controller: FolderTreeViewController) throws -> NSStackView {
        try #require(
            (controller.view as? NSStackView)?.arrangedSubviews.last as? NSStackView
        )
    }

    /// 按钮行里的 “添加…”
    private func addPopUpButton(of controller: FolderTreeViewController) throws -> NSPopUpButton {
        try #require(
            buttonRow(of: controller).views.compactMap { $0 as? NSPopUpButton }.first
        )
    }

    /// 在 “工作” 末尾加入一个不带标题的网页，像 “添加网页…” 标题框留空时那样
    private func addUntitledWebPage() throws -> WebPageReference {
        let work = try #require(store.rootFolders.first)
        let url = try #require(URL(string: "https://apple.com"))
        let webPage = WebPageReference(id: UUID(), url: url, title: nil)

        store.addItems([.webPage(webPage)], to: work.id)

        return webPage
    }

    /// 补上标题之后的网页项
    private func titled(_ webPage: WebPageReference, _ title: String) -> FolderItem {
        .webPage(WebPageReference(id: webPage.id, url: webPage.url, title: title))
    }

    /// “工作” 末尾的那一项
    private func lastItemOfWork() throws -> FolderItem? {
        try #require(store.rootFolders.first).items.last
    }

    /// 开始编辑第一行 “工作” 的名称，返回正在编辑它的字段编辑器
    private func beginEditingWorkName(in controller: FolderTreeViewController) throws -> NSTextView {
        let scrollView = try #require(
            controller.view.subviews.compactMap { $0 as? NSScrollView }.first
        )
        let outlineView = try #require(scrollView.documentView as? NSOutlineView)

        outlineView.editColumn(0, row: 0, with: nil, select: true)

        return try #require(outlineView.window?.firstResponder as? NSTextView)
    }

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
