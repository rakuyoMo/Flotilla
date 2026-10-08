import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeViewControllerTests

/// 设置窗口的文件夹区：树的宽度必须始终与滚动区一致，行尾的 “不在 Dock 上” 才不会被右缘裁掉；
/// 添加 App、文件与网页都从 “添加…” 的菜单进入；窗口缩到最窄时，底部按钮行在每种语言下都完整显示；
/// 右键菜单按点到的那一行给出各项，作用于点到的那一项，不论之后选中项与树怎样变；
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

        let outlineView = try outlineView(of: controller)
        let scrollView = try #require(outlineView.enclosingScrollView)

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

        // 测试进程读不到 `.lproj` 里的译文，按钮标题就是键名，按键名换成这种语言的文字
        for button in buttons {
            button.title = try #require(table[button.title], "表里没有 \(button.title)")
        }

        #expect(buttons.count == 2)

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

    /// 按钮行从左到右是 新建文件夹、添加…；“添加…” 是点击后在下方弹出菜单的 pull-down。
    /// “添加到 Dock” 与 “删除” 在右键菜单里，不在按钮行
    @Test
    func buttonRowListsNewFolderAndAdd() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let controls = try buttonRow(of: controller).views

        // 测试进程读不到译文，标题就是键名；pull-down 的标题是它的第一项
        #expect(controls.map { ($0 as? NSButton)?.title } == [
            "folders.newFolder",
            "folders.add",
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

        try outlineView(of: controller).selectRowIndexes([0], byExtendingSelection: false)

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

// MARK: - Context Menu

extension FolderTreeViewControllerTests {
    /// 右键菜单按点到的那一行的类型给出各项，“删除” 隔开放在最后；各项接到文件夹区的方法，记下点到的那一项。
    /// 没有 Dock 集成时没有 “添加到 Dock”，文件夹的菜单只有 “删除”，也没有分隔线
    @Test
    func contextMenuFollowsClickedRowKind() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view

        let addedIDs = try addWebPageFileAndFinderFolder()
        let outlineView = try outlineView(of: controller)

        outlineView.expandItem(outlineView.item(atRow: 0))
        controller.view.layoutSubtreeIfNeeded()

        let work = try #require(store.rootFolders.first)
        let showInFinder = ["folders.showInFinder", "—", "folders.remove"]

        // 行依次是 工作、开发、Chess、网页、文件、访达里的文件夹
        let expectations: [(row: Int, itemID: UUID, titles: [String])] = [
            (0, work.id, ["folders.remove"]),
            (1, work.items[0].id, ["folders.remove"]),
            (2, work.items[1].id, showInFinder),
            (3, addedIDs[0], ["folders.openInDefaultBrowser", "—", "folders.remove"]),
            (4, addedIDs[1], showInFinder),
            (5, addedIDs[2], showInFinder),
        ]

        for (row, itemID, titles) in expectations {
            let menu = try contextMenu(of: outlineView, clickingRow: row)

            #expect(outlineView.clickedRow == row)
            #expect(Self.titles(of: menu) == titles, "第 \(row) 行的菜单不对")
            #expect(menu.items.map(\.action) == titles.map(Self.action(forTitle:)))

            for menuItem in menu.items where !menuItem.isSeparatorItem {
                #expect(menuItem.target === controller)
                #expect(menuItem.representedObject as? UUID == itemID)
                #expect(menuItem.isEnabled)
            }
        }
    }

    /// 右键点在没有行的空白处：菜单没有项，不弹出；之前点过某一行留下的项也不留着
    @Test
    func blankAreaContextMenuHasNoItems() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        let outlineView = try outlineView(of: controller)

        #expect(try !contextMenu(of: outlineView, clickingRow: 0).items.isEmpty)

        let menu = try contextMenu(of: outlineView, clickingRow: nil)

        #expect(outlineView.clickedRow == -1)
        #expect(menu.items.isEmpty)
    }

    /// 有 Dock 集成时文件夹的菜单是 “添加到 Dock” 与 “删除”：只有被拖出 Dock 的根文件夹能添加，
    /// 在 Dock 上的根文件夹与子文件夹置灰
    ///
    /// 同步器只读、不启动，也不点 “添加到 Dock”：添加会安排同步，同步会重启真实的 Dock
    @Test
    func addToDockIsEnabledOnlyForRootFolderRemovedFromDock() throws {
        let work = try #require(store.rootFolders.first)
        let life = store.addRootFolder(named: "生活")

        let synchronizer = try makeSynchronizer(tilesOnDock: [work.id])
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: synchronizer)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view

        let outlineView = try outlineView(of: controller)

        outlineView.expandItem(outlineView.item(atRow: 0))
        controller.view.layoutSubtreeIfNeeded()

        #expect(synchronizer.rootFolderIDsRemovedFromDock() == [life.id])

        // 行依次是 工作（在 Dock 上）、开发（子文件夹）、Chess、生活（被拖出 Dock）
        let expectations = [
            (row: 0, canAddToDock: false),
            (row: 1, canAddToDock: false),
            (row: 3, canAddToDock: true),
        ]

        let titles = ["folders.addToDock", "—", "folders.remove"]

        for (row, canAddToDock) in expectations {
            let menu = try contextMenu(of: outlineView, clickingRow: row)

            #expect(Self.titles(of: menu) == titles, "第 \(row) 行的菜单不对")
            #expect(menu.items.map(\.action) == titles.map(Self.action(forTitle:)))
            #expect(menu.items.first?.isEnabled == canAddToDock, "第 \(row) 行的 “添加到 Dock” 可用状态不对")
            #expect(try #require(menu.items.last).isEnabled)
        }
    }

    /// “删除” 删掉的是右键点到的那一项，不是选中项：右键不改变选中项，删除之后选中项仍选中
    @Test
    func removeDeletesClickedItemAndKeepsSelection() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view

        let outlineView = try outlineView(of: controller)

        outlineView.expandItem(outlineView.item(atRow: 0))
        controller.view.layoutSubtreeIfNeeded()

        let development = try #require(store.rootFolders.first?.items.first)

        // 选中 “开发”，右键点 Chess
        outlineView.selectRowIndexes([1], byExtendingSelection: false)

        let menu = try contextMenu(of: outlineView, clickingRow: 2)

        #expect(outlineView.selectedRow == 1)

        menu.performActionForItem(at: menu.items.count - 1)

        #expect(store.rootFolders.first?.items == [development])

        let selectedNode = outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode

        #expect(selectedNode?.item.id == development.id)
    }

    /// 菜单开着时树重建、行号错位：“删除” 仍删掉原来点到的那一项，不删此刻占着那一行的项
    @Test
    func removeAfterTreeReloadDeletesOriginallyClickedItem() throws {
        let controller = FolderTreeViewController(store: store, dockTileSynchronizer: nil)
        let window = makeWindow(width: Self.minimumWidth)

        window.contentView = controller.view

        let outlineView = try outlineView(of: controller)

        outlineView.expandItem(outlineView.item(atRow: 0))
        controller.view.layoutSubtreeIfNeeded()

        let work = try #require(store.rootFolders.first)
        let development = work.items[0]

        // 右键点 Chess（第 2 行）
        let menu = try contextMenu(of: outlineView, clickingRow: 2)

        // 菜单开着时，“工作” 最前面多了一个网页：树重建，Chess 下移一行，第 2 行换成 “开发”
        let url = try #require(URL(string: "https://apple.com"))
        let webPage = try #require(FolderItem(url: url, title: nil))

        store.addItems([webPage], to: work.id)
        store.move(itemID: webPage.id, to: work.id, at: 0)

        #expect((outlineView.item(atRow: 2) as? FolderTreeNode)?.item.id == development.id)

        menu.performActionForItem(at: menu.items.count - 1)

        #expect(store.rootFolders.first?.items.map(\.id) == [webPage.id, development.id])
    }
}

// MARK: - Private

extension FolderTreeViewControllerTests {
    /// 菜单各项的标题，分隔线记为 “—”
    private static func titles(of menu: NSMenu) -> [String] {
        menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
    }

    /// 右键菜单里各标题的项应当接到的方法；分隔线没有
    private static func action(forTitle title: String) -> Selector? {
        let actionNames = [
            "folders.addToDock": "addClickedFolderToDock:",
            "folders.showInFinder": "showClickedItemInFinder:",
            "folders.openInDefaultBrowser": "openClickedWebPageInDefaultBrowser:",
            "folders.remove": "removeClickedItem:",
        ]

        return actionNames[title].map(NSSelectorFromString)
    }

    /// 文件夹区里的文件夹树
    private func outlineView(of controller: FolderTreeViewController) throws -> NSOutlineView {
        let scrollView = try #require(
            controller.view.subviews.compactMap { $0 as? NSScrollView }.first
        )

        return try #require(scrollView.documentView as? NSOutlineView)
    }

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
        let outlineView = try outlineView(of: controller)

        outlineView.editColumn(0, row: 0, with: nil, select: true)

        return try #require(outlineView.window?.firstResponder as? NSTextView)
    }

    /// 像在某一行上按右键那样取得右键菜单：把合成的右键事件交给 outline view，它记下点到的那一行；
    /// 再像菜单弹出之前那样让 delegate 重建
    /// - Parameters:
    ///   - outlineView: 文件夹树，已放进窗口并排好布局
    ///   - row: 右键点到的行；nil 表示点在最后一行下方的空白处
    private func contextMenu(of outlineView: NSOutlineView, clickingRow row: Int?) throws -> NSMenu {
        let lastRowRect = outlineView.rect(ofRow: outlineView.numberOfRows - 1)
        let rowRect = row.map { outlineView.rect(ofRow: $0) }

        // outline view 的坐标是翻转的：最后一行下方的空白处 y 更大
        let point = rowRect.map { NSPoint(x: $0.midX, y: $0.midY) }
            ?? NSPoint(x: lastRowRect.midX, y: lastRowRect.maxY + outlineView.rowHeight)

        try #require(outlineView.bounds.contains(point))

        let window = try #require(outlineView.window)

        let event = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown,
                location: outlineView.convert(point, to: nil),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )

        let menu = try #require(outlineView.menu(for: event))

        menu.delegate?.menuNeedsUpdate?(menu)

        return menu
    }

    /// 在 “工作” 末尾依次加入网页、文件与访达里的文件夹，返回它们的 id；文件与访达里的文件夹建在临时目录里
    private func addWebPageFileAndFinderFolder() throws -> [UUID] {
        let work = try #require(store.rootFolders.first)
        let fileURL = directory.appending(path: "报告.txt")
        let folderURL = directory.appending(path: "资料", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("报告".utf8).write(to: fileURL)

        let items = [
            FolderItem(url: try #require(URL(string: "https://apple.com")), title: "Apple"),
            FolderItem(url: fileURL, title: nil),
            FolderItem(url: folderURL, title: nil),
        ]

        let addedItems = try items.map { try #require($0) }

        store.addItems(addedItems, to: work.id)

        return addedItems.map(\.id)
    }

    /// 只读的 Dock tile 同步器：Dock 偏好与 stub 目录都在本用例的临时目录里，不碰真实的 Dock；
    /// 不调用 `start()`，不会同步
    /// - Parameter folderIDs: Dock 偏好里有 tile 的根文件夹
    private func makeSynchronizer(tilesOnDock folderIDs: [UUID]) throws -> DockTileSynchronizer {
        let builder = DockTileBundleBuilder(
            directory: directory.appending(path: "DockTiles", directoryHint: .isDirectory),
            executableURL: URL(filePath: "/usr/bin/true")
        )

        // 以临时目录下的绝对路径作域名，偏好写进该目录的 plist
        let dockDomain = directory.appending(path: "dock").path(percentEncoded: false)

        let tiles = folderIDs.map {
            DockPreferences.tileEntry(
                tileURL: builder.directory.appending(path: "\($0.uuidString)/工作.app"),
                label: "工作",
                guid: 42
            )
        }

        try #require(UserDefaults(suiteName: dockDomain)).set(tiles, forKey: DockDefaults.tilesKey)

        let dockPreferences = try #require(
            DockPreferences(
                domainName: dockDomain,
                backupDirectory: directory.appending(path: "Backups")
            )
        )

        let defaults = try #require(
            UserDefaults(suiteName: directory.appending(path: "defaults").path(percentEncoded: false))
        )

        return DockTileSynchronizer(
            store: store,
            preferences: Preferences(defaults: defaults),
            builder: builder,
            dockPreferences: dockPreferences
        )
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
