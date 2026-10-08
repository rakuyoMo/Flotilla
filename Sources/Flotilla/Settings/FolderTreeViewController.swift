import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeViewController

/// 设置窗口的文件夹区：
/// 展示完整的文件夹树；底部按钮行提供新建文件夹与添加 App、文件与网页，
/// 右键菜单提供添加到 Dock、在访达中显示、在默认浏览器中打开、编辑网页与删除；另有重命名与拖放；
/// 被拖出 Dock 的根文件夹标出 “不在 Dock 上”
@MainActor
final class FolderTreeViewController: NSViewController {
    /// 新建文件夹的默认名称
    private static let untitledFolderName = String(
        localized: "folders.untitledFolder",
        comment: "新建文件夹的默认名称，新建后立即进入重命名"
    )

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// Dock tile 同步器；Dock 集成不可用时为 nil，此时不显示 tile 的状态，也没有 “添加到 Dock”
    private let dockTileSynchronizer: DockTileSynchronizer?

    /// outline view 的数据源，持有全部行节点
    private let dataSource: FolderTreeDataSource

    /// 展示文件夹树
    private let outlineView = NSOutlineView()

    /// “添加…” 下拉按钮，菜单里是 “添加 App…” “添加文件…” “添加网页…”；无选中项时禁用
    private let addPopUpButton = NSPopUpButton(frame: .zero, pullsDown: true)

    /// 最近一次读取到的、被拖出 Dock 的根文件夹；行的状态与右键菜单里 “添加到 Dock” 的可用状态都按它判断
    private var rootFolderIDsRemovedFromDock: Set<UUID> = []

    /// 正在编辑文件夹名时取到的网页标题，连同取标题时那一份网页按先后记下，编辑结束时依次补上。
    /// 同一项先后记下的几条都留着：旧网址的标题可能晚到，不能把新网址的挤掉，补哪一条由数据源核对网址决定
    private var pendingWebPageTitles: [(title: String, webPage: WebPageReference)] = []

    /// 当前选中行的节点
    private var selectedNode: FolderTreeNode? {
        outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode
    }

    /// 是否正在编辑文件夹名：第一响应者是字段编辑器，且它正在编辑的文本框在树里
    private var isEditingFolderName: Bool {
        guard
            let fieldEditor = outlineView.window?.firstResponder as? NSTextView,
            fieldEditor.isFieldEditor,
            let textField = fieldEditor.delegate as? NSTextField
        else {
            return false
        }

        return textField.isDescendant(of: outlineView)
    }

    /// 创建文件夹区
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - dockTileSynchronizer: Dock tile 同步器；Dock 集成不可用时传 nil
    init(store: FolderStore, dockTileSynchronizer: DockTileSynchronizer?) {
        self.store = store
        self.dockTileSynchronizer = dockTileSynchronizer
        dataSource = FolderTreeDataSource(store: store)

        super.init(nibName: nil, bundle: nil)
    }

    /// 文件夹区完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("不支持从归档解码")
    }

    /// 搭建界面；文件夹树变化时重建，每次同步 Dock tile 之后与 Dock 偏好里的 tile 变化时刷新 tile 的状态
    override func loadView() {
        configureOutlineView()
        view = makeContentView()
        updateAddPopUpButton()
        refreshDockStatus()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadTree),
            name: FolderStore.didChangeNotification,
            object: store
        )

        guard let dockTileSynchronizer else { return }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshDockStatus),
            name: DockTileSynchronizer.didSynchronizeNotification,
            object: dockTileSynchronizer
        )

        // 用户把 tile 拖出 Dock 后，Dock 写入删除时就刷新，不必等窗口重新成为 key
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshDockStatus),
            name: DockTileSynchronizer.dockTilesDidChangeNotification,
            object: dockTileSynchronizer
        )
    }

    /// 重新读取被拖出 Dock 的根文件夹，原地更新各行的状态文字
    ///
    /// 不重建树：新建的根文件夹正在重命名时，随后的同步会发出通知，
    /// 重建会结束编辑并提交输入到一半的名称
    @objc
    func refreshDockStatus() {
        rootFolderIDsRemovedFromDock = dockTileSynchronizer?.rootFolderIDsRemovedFromDock() ?? []

        // 只更新已经创建出来的行，其余行在出现时按新的结果配置
        outlineView.enumerateAvailableRowViews {
            guard
                let cell = $0.view(atColumn: 0) as? FolderTreeCellView,
                let node = outlineView.item(atRow: $1) as? FolderTreeNode
            else {
                return
            }

            cell.showsNotOnDockLabel = isRemovedFromDock(node)
        }
    }

    /// 按书签把整棵树里的 App 与文件跟到新位置
    ///
    /// 正在编辑文件夹名时跳过：有变化就会重建树，重建会结束编辑并提交输入到一半的名称
    func updateItemLocations() {
        guard !isEditingFolderName else { return }

        store.updateItemLocations()
    }

    /// 给不带标题加入或保存的网页补上取到的标题；这一项的网址已不是取标题的那个时，由数据源丢掉
    ///
    /// 正在编辑文件夹名时先记下，编辑结束再补：补上标题会重建树，重建会结束编辑并提交输入到一半的名称
    /// - Parameters:
    ///   - title: 取到的标题，已去掉首尾空白
    ///   - webPage: 不带标题交出的那一份网页：id 与取标题的网址
    func fillTitle(_ title: String, of webPage: WebPageReference) {
        guard !isEditingFolderName else {
            pendingWebPageTitles.append((title, webPage))
            return
        }

        store.fillTitle(title, of: webPage)
    }
}

// MARK: NSOutlineViewDelegate

extension FolderTreeViewController: NSOutlineViewDelegate {
    /// 每一行显示图标、名称、访达里的文件夹的位置，
    /// 以及被拖出 Dock 的根文件夹的 “不在 Dock 上”
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor _: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? FolderTreeNode else { return nil }

        let reusedCell = outlineView.makeView(
            withIdentifier: FolderTreeCellView.reuseIdentifier,
            owner: self
        )
        let cell = reusedCell as? FolderTreeCellView ?? FolderTreeCellView()
        cell.configure(with: node)
        cell.showsNotOnDockLabel = isRemovedFromDock(node)
        cell.textField?.delegate = self

        return cell
    }

    /// 选中项变化时更新 “添加…” 的可用状态
    func outlineViewSelectionDidChange(_: Notification) {
        updateAddPopUpButton()
    }
}

// MARK: NSTextFieldDelegate

extension FolderTreeViewController: NSTextFieldDelegate {
    /// 结束编辑文件夹名时写回数据源；新建的根文件夹名称就此定下，解除搁置，tile 带着这个名称出现。
    /// 编辑期间取到的网页标题随后补上
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        let row = outlineView.row(for: textField)
        let node = outlineView.item(atRow: row) as? FolderTreeNode

        guard let folder = node?.folder else { return }

        store.rename(folderID: folder.id, to: textField.stringValue)
        dockTileSynchronizer?.releaseTile(for: folder.id)

        fillPendingWebPageTitles()
    }

    /// 按 Esc 取消编辑时名称保持原样，同样算名称定下来了：解除搁置，tile 带着原名出现；
    /// 编辑期间取到的网页标题等编辑结束后补上
    ///
    /// 实测 outline view 取消编辑时不发 `controlTextDidEndEditing`，只能在这里得知
    func control(
        _ control: NSControl,
        textView _: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }

        let row = outlineView.row(for: control)
        let node = outlineView.item(atRow: row) as? FolderTreeNode

        if let folder = node?.folder {
            dockTileSynchronizer?.releaseTile(for: folder.id)
        }

        // outline view 在这之后才结束编辑，补标题要等到那时
        Task { [weak self] in
            guard
                let self,
                !isEditingFolderName
            else {
                return
            }

            fillPendingWebPageTitles()
        }

        // 取消编辑本身仍交给 outline view 处理
        return false
    }
}

// MARK: NSMenuDelegate

extension FolderTreeViewController: NSMenuDelegate {
    /// 右键菜单弹出之前，按右键点到的那一行重建：按这一行的类型给出各项，“删除” 隔开放在最后；
    /// 点在没有行的空白处时菜单没有项，不弹出
    ///
    /// 各项记下点到的那一项的 id，执行时按 id 找：菜单开着时树可能重建，重建之后行号可能对上别的项
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? FolderTreeNode else {
            return
        }

        let leadingItems = contextMenuItems(for: node)

        for menuItem in leadingItems {
            menu.addItem(menuItem)
        }

        // “删除” 与其它项隔开、放在最后，免得点第一项时误删
        if !leadingItems.isEmpty {
            menu.addItem(.separator())
        }

        menu.addItem(
            NSMenuItem(
                title: String(
                    localized: "folders.remove",
                    comment: "文件夹树右键菜单的一项：删除右键点到的文件夹、App、文件或网页"
                ),
                action: #selector(removeClickedItem(_:)),
                keyEquivalent: ""
            )
        )

        for menuItem in menu.items where !menuItem.isSeparatorItem {
            menuItem.target = self
            menuItem.representedObject = node.item.id
        }
    }
}

// MARK: - Actions

extension FolderTreeViewController {
    /// 新建文件夹：有选中项时建在其所属文件夹内，否则建为根文件夹；建好后立即进入重命名
    ///
    /// 新建的根文件夹在名称编辑结束之前搁置，不添加 tile：tile 带着最终名称出现，Dock 只重启一次
    @objc
    private func addFolder() {
        if let parentID = selectedNode?.containingFolderID {
            guard
                let folder = store.addSubfolder(named: Self.untitledFolderName, to: parentID)
            else {
                return
            }

            beginRenaming(folderID: folder.id)
            return
        }

        let folder = store.addRootFolder(named: Self.untitledFolderName)

        // 同步器收到变更通知后要等防抖间隔才同步，此时搁置赶得上这次同步
        dockTileSynchronizer?.holdTile(for: folder.id)

        beginRenaming(folderID: folder.id)
    }

    /// 选择 App 并加入选中项所属的文件夹
    @objc
    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")

        addItems(chosenIn: panel)
    }

    /// 选择文件与访达里的文件夹，加入选中项所属的文件夹；不限类型，选到的 App 按分类规则成为 App
    @objc
    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        addItems(chosenIn: panel)
    }

    /// 输入网址与可选的标题，把网页加入弹出时选中项所属的文件夹；
    /// 不带标题加入的网页，取到标题后补上
    ///
    /// 弹出期间这个文件夹被删掉时，`addItems` 找不到它，什么都不做；之后取到的标题同样找不到这一项
    @objc
    private func addWebPage() {
        guard
            let folderID = selectedNode?.containingFolderID,
            let window = view.window
        else {
            return
        }

        WebPageAlert().beginSheetModal(
            for: window,
            completionHandler: { [weak self] in
                self?.store.addItems([.webPage($0)], to: folderID)
            },
            titleHandler: { [weak self] in
                self?.fillTitle($0, of: $1)
            }
        )
    }

    /// 把右键点到的根文件夹重新添加到 Dock；记为待添加后它就不再算被拖出，状态随即刷新
    @objc
    private func addClickedFolderToDock(_ sender: NSMenuItem) {
        guard let folder = clickedNode(of: sender)?.folder else { return }

        dockTileSynchronizer?.addTile(for: folder.id)
        refreshDockStatus()
    }

    /// 访达打开右键点到的 App 或文件所在的位置并选中它；访达里的文件夹同样是选中，不是打开
    ///
    /// 先按书签找到当前位置，找不到时用记录的位置；只读，不改数据源：
    /// 右键点后台窗口不会让设置窗口成为 key，按书签更新数据源的时机赶不上
    @objc
    private func showClickedItemInFinder(_ sender: NSMenuItem) {
        guard let node = clickedNode(of: sender) else { return }

        let url: URL

        switch node.item {
        case .app(let app):
            url = app.relocatedApp()?.url ?? app.url

        case .file(let file):
            url = file.relocated()?.url ?? file.url

        case .folder, .webPage:
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 用系统的默认浏览器打开右键点到的网页：先取打开这个网址的默认浏览器，再交给它打开；取不到时什么都不做
    @objc
    private func openClickedWebPageInDefaultBrowser(_ sender: NSMenuItem) {
        guard
            case .webPage(let webPage) = clickedNode(of: sender)?.item,
            let browserURL = NSWorkspace.shared.urlForApplication(toOpen: webPage.url)
        else {
            return
        }

        NSWorkspace.shared.open(
            [webPage.url],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// 编辑右键点到的网页：以 sheet 弹出网页的提示框，填着它的网址与标题；保存后原地换成改好的网址与标题，id 与位置不变。
    /// 不带标题保存的网页，取到标题后补上
    ///
    /// 弹出期间这个网页被删掉时，保存与之后取到的标题都找不到这一项，什么都不做
    @objc
    private func editClickedWebPage(_ sender: NSMenuItem) {
        guard
            case .webPage(let webPage) = clickedNode(of: sender)?.item,
            let window = view.window
        else {
            return
        }

        WebPageAlert(editing: webPage).beginSheetModal(
            for: window,
            completionHandler: { [weak self] in
                self?.store.updateWebPage($0)
            },
            titleHandler: { [weak self] in
                self?.fillTitle($0, of: $1)
            }
        )
    }

    /// 删除右键点到的那一项；文件夹连同内容一起删除。选中项不变：重建树时按 id 恢复选中
    @objc
    private func removeClickedItem(_ sender: NSMenuItem) {
        guard let node = clickedNode(of: sender) else { return }

        store.remove(itemID: node.item.id)
    }

    /// 双击文件夹行时进入重命名；App、文件与网页的名称不可编辑
    @objc
    private func renameClickedFolder() {
        let row = outlineView.clickedRow
        let node = outlineView.item(atRow: row) as? FolderTreeNode

        guard node?.folder != nil else { return }

        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    /// 按数据源的最新内容重建整棵树，尽量保留展开状态与选中项；重建时重新读取被拖出 Dock 的根文件夹
    @objc
    private func reloadTree() {
        // 节点会整体重建，先按 id 记下展开的文件夹与选中项
        let expandedIDs = expandedFolderIDs(in: dataSource.rootNodes)
        let selectedID = selectedNode?.item.id

        rootFolderIDsRemovedFromDock = dockTileSynchronizer?.rootFolderIDsRemovedFromDock() ?? []

        dataSource.reloadNodes()
        outlineView.reloadData()

        restoreExpansion(of: dataSource.rootNodes, expandedIDs: expandedIDs)

        // 选中项已被删除时清空选择，避免选中恰好落在同一行号上的其它项
        let selectedRow = selectedID
            .flatMap { dataSource.node(withID: $0) }
            .map { outlineView.row(forItem: $0) } ?? -1

        outlineView.selectRowIndexes(
            selectedRow >= 0 ? [selectedRow] : [],
            byExtendingSelection: false
        )

        updateAddPopUpButton()
    }
}

// MARK: - Private

extension FolderTreeViewController {
    /// 配置 outline view：单列、无表头、支持树内拖动、从访达拖入与从浏览器拖入
    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask

        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // 展开子层级时不加宽大纲列：加宽后树比滚动区宽，行尾的 “不在 Dock 上” 会被右缘裁掉
        outlineView.autoresizesOutlineColumn = false

        outlineView.headerView = nil
        outlineView.rowHeight = 26
        outlineView.dataSource = dataSource
        outlineView.delegate = self

        outlineView.target = self
        outlineView.doubleAction = #selector(renameClickedFolder)

        // 右键菜单在弹出前按点到的那一行重建；各项的可用状态自己设，不经 `validateMenuItem`
        let contextMenu = NSMenu()
        contextMenu.autoenablesItems = false
        contextMenu.delegate = self

        outlineView.menu = contextMenu

        outlineView.registerForDraggedTypes([
            FolderTreeDataSource.itemIDPasteboardType,
            .fileURL,
            .URL,
        ])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
    }

    /// 区块标题、树与底部按钮自上而下排列
    private func makeContentView() -> NSView {
        let titleLabel = NSTextField(
            labelWithString: String(
                localized: "folders.sectionTitle",
                comment: "设置窗口文件夹区的区块标题"
            )
        )
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        // 底部按钮：新建文件夹与 “添加…”，靠左
        let newFolderButton = NSButton(
            title: String(
                localized: "folders.newFolder",
                comment: "文件夹区的按钮：新建文件夹"
            ),
            target: self,
            action: #selector(addFolder)
        )

        configureAddPopUpButton()

        let buttonRow = NSStackView()
        buttonRow.setViews([newFolderButton, addPopUpButton], in: .leading)

        let stackView = NSStackView(views: [titleLabel, scrollView, buttonRow])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8

        // 树与按钮行占满整个区块的宽度，树的高度随窗口伸缩
        NSLayoutConstraint.activate([
            scrollView.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            buttonRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
        ])

        return stackView
    }

    /// 配置 “添加…”：pull-down 按钮上显示的是第一项的标题，点击后在按钮下方弹出其后的各项
    private func configureAddPopUpButton() {
        addPopUpButton.addItem(
            withTitle: String(
                localized: "folders.add",
                comment: "文件夹区的下拉按钮：点击后弹出菜单，选择添加 App、文件或网页"
            )
        )

        let menuItems = [
            NSMenuItem(
                title: String(
                    localized: "folders.addApps",
                    comment: "“添加…” 菜单的一项：选择 App 加入选中项所属的文件夹"
                ),
                action: #selector(addApps),
                keyEquivalent: ""
            ),

            NSMenuItem(
                title: String(
                    localized: "folders.addFiles",
                    comment: "“添加…” 菜单的一项：选择文件或访达里的文件夹，加入选中项所属的文件夹"
                ),
                action: #selector(addFiles),
                keyEquivalent: ""
            ),

            NSMenuItem(
                title: String(
                    localized: "folders.addWebPage",
                    comment: "“添加…” 菜单的一项：输入网址，把网页加入选中项所属的文件夹"
                ),
                action: #selector(addWebPage),
                keyEquivalent: ""
            ),
        ]

        // 各项自带 target 与 action，选中后直接调用对应的方法
        for menuItem in menuItems {
            menuItem.target = self
            addPopUpButton.menu?.addItem(menuItem)
        }
    }

    /// 根据选中项更新 “添加…” 的可用状态：有选中项时可用
    private func updateAddPopUpButton() {
        addPopUpButton.isEnabled = selectedNode != nil
    }

    /// 右键菜单里 “删除” 之前的各项，按右键点到的那一行的类型给出：
    /// 文件夹是 “添加到 Dock”，App 与文件是 “在访达中显示”，网页是 “在默认浏览器中打开” 与 “编辑…”
    private func contextMenuItems(for node: FolderTreeNode) -> [NSMenuItem] {
        switch node.item {
        // Dock 集成不可用时没有 “添加到 Dock”；只有被拖出 Dock 的根文件夹可用，其余文件夹置灰
        case .folder:
            guard dockTileSynchronizer != nil else { return [] }

            let addToDockItem = NSMenuItem(
                title: String(
                    localized: "folders.addToDock",
                    comment: "文件夹行右键菜单的一项：把 tile 不在 Dock 上的根文件夹重新添加到 Dock"
                ),
                action: #selector(addClickedFolderToDock(_:)),
                keyEquivalent: ""
            )

            addToDockItem.isEnabled = isRemovedFromDock(node)

            return [addToDockItem]

        case .app, .file:
            return [
                NSMenuItem(
                    title: String(
                        localized: "folders.showInFinder",
                        comment: "App、文件与访达里的文件夹这一行右键菜单的一项：在访达里选中它"
                    ),
                    action: #selector(showClickedItemInFinder(_:)),
                    keyEquivalent: ""
                ),
            ]

        case .webPage:
            return [
                NSMenuItem(
                    title: String(
                        localized: "folders.openInDefaultBrowser",
                        comment: "网页这一行右键菜单的一项：用系统的默认浏览器打开它"
                    ),
                    action: #selector(openClickedWebPageInDefaultBrowser(_:)),
                    keyEquivalent: ""
                ),

                NSMenuItem(
                    title: String(
                        localized: "folders.editWebPage",
                        comment: "网页这一行右键菜单的一项：在提示框里编辑它的网址与标题"
                    ),
                    action: #selector(editClickedWebPage(_:)),
                    keyEquivalent: ""
                ),
            ]
        }
    }

    /// 右键菜单项记下的那一项此刻在树里的行节点；这一项已不在时为 nil
    private func clickedNode(of menuItem: NSMenuItem) -> FolderTreeNode? {
        guard let itemID = menuItem.representedObject as? UUID else { return nil }

        return dataSource.node(withID: itemID)
    }

    /// 以 sheet 弹出选择面板，把选中的 URL 分类后加入选中项所属的文件夹
    private func addItems(chosenIn panel: NSOpenPanel) {
        guard
            let folderID = selectedNode?.containingFolderID,
            let window = view.window
        else {
            return
        }

        panel.beginSheetModal(for: window) { [weak self, panel] response in
            guard response == .OK else { return }

            // 分类交给 `FolderItem(url:title:)`，与拖入走同一套规则
            let items = panel.urls.compactMap {
                FolderItem(url: $0, title: nil)
            }

            self?.store.addItems(items, to: folderID)
        }
    }

    /// 这一行是否为被拖出 Dock 的根文件夹；Dock 集成不可用时一律为否
    private func isRemovedFromDock(_ node: FolderTreeNode) -> Bool {
        guard let folder = node.folder else { return false }

        return rootFolderIDsRemovedFromDock.contains(folder.id)
    }

    /// 选中新建的文件夹并进入名称编辑
    private func beginRenaming(folderID: UUID) {
        guard let node = dataSource.node(withID: folderID) else { return }

        // 自上而下展开全部祖先，让新行可见
        var ancestors: [FolderTreeNode] = []
        var next = node.parent
        while let parent = next {
            ancestors.insert(parent, at: 0)
            next = parent.parent
        }

        for ancestor in ancestors {
            outlineView.expandItem(ancestor)
        }

        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }

        outlineView.selectRowIndexes([row], byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        outlineView.editColumn(0, row: row, with: nil, select: true)
    }

    /// 按记下的先后，补上编辑文件夹名期间取到的网页标题
    private func fillPendingWebPageTitles() {
        let titles = pendingWebPageTitles
        pendingWebPageTitles = []

        for (title, webPage) in titles {
            store.fillTitle(title, of: webPage)
        }
    }

    /// 收集当前展开的文件夹 id；收起的文件夹不再深入
    private func expandedFolderIDs(in nodes: [FolderTreeNode]) -> Set<UUID> {
        nodes
            .filter { outlineView.isItemExpanded($0) }
            .reduce(into: Set<UUID>()) {
                $0.insert($1.item.id)
                $0.formUnion(expandedFolderIDs(in: $1.children))
            }
    }

    /// 自上而下展开 id 在 expandedIDs 中的文件夹
    private func restoreExpansion(of nodes: [FolderTreeNode], expandedIDs: Set<UUID>) {
        for node in nodes where expandedIDs.contains(node.item.id) {
            outlineView.expandItem(node)
            restoreExpansion(of: node.children, expandedIDs: expandedIDs)
        }
    }
}
