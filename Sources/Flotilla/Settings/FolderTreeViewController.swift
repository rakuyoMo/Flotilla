import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeViewController

/// 设置窗口的文件夹区：展示完整的文件夹树，提供新建、添加 App、添加到 Dock、删除、重命名与拖拽；
/// tile 不在 Dock 上的根文件夹标出“不在 Dock 上”
@MainActor
final class FolderTreeViewController: NSViewController {
    /// 新建文件夹的默认名称
    private static let untitledFolderName = String(
        localized: "folders.untitledFolder",
        comment: "新建文件夹的默认名称，新建后立即进入改名"
    )

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// Dock tile 同步器；Dock 集成不可用时为 nil，此时不显示 tile 的状态，也没有“添加到 Dock”
    private let dockTileSynchronizer: DockTileSynchronizer?

    /// outline view 的数据源，持有全部行节点
    private let dataSource: FolderTreeDataSource

    /// 展示文件夹树
    private let outlineView = NSOutlineView()

    /// “添加 App…”按钮，无选中项时禁用
    private let addAppsButton = NSButton(
        title: String(
            localized: "folders.addApps",
            comment: "文件夹区的按钮：选择 App 加入选中项所属的文件夹"
        ),
        target: nil,
        action: nil
    )

    /// “添加到 Dock”按钮，只有选中 tile 不在 Dock 上的根文件夹时可用
    private let addToDockButton = NSButton(
        title: String(
            localized: "folders.addToDock",
            comment: "文件夹区的按钮：把 tile 不在 Dock 上的根文件夹重新添加到 Dock"
        ),
        target: nil,
        action: nil
    )

    /// “删除”按钮，无选中项时禁用
    private let removeButton = NSButton(
        title: String(
            localized: "folders.remove",
            comment: "文件夹区的按钮：删除选中的文件夹或 App"
        ),
        target: nil,
        action: nil
    )

    /// 最近一次读取到的、被拖出 Dock 的根文件夹；行的状态与按钮的可用状态都按它判断
    private var rootFolderIDsRemovedFromDock: Set<UUID> = []

    /// 当前选中行的节点
    private var selectedNode: FolderTreeNode? {
        outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode
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
        fatalError("init(coder:) has not been implemented")
    }

    /// 搭建界面；文件夹树变化时重建，每次同步 Dock tile 之后与 Dock 偏好变化时刷新 tile 的状态
    override func loadView() {
        configureOutlineView()
        view = makeContentView()
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
            name: DockTileSynchronizer.dockPreferencesDidChangeNotification,
            object: dockTileSynchronizer
        )
    }

    /// 重新读取被拖出 Dock 的根文件夹，原地更新各行的状态文字与按钮的可用状态
    ///
    /// 不重建树：新建的根文件夹正在改名时，随后的同步会发出通知，重建会结束编辑并提交输入到一半的名称
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

        updateButtons()
    }
}

// MARK: NSOutlineViewDelegate

extension FolderTreeViewController: NSOutlineViewDelegate {
    /// 每一行显示图标与名称
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

    /// 选中项变化时更新按钮的可用状态
    func outlineViewSelectionDidChange(_: Notification) {
        updateButtons()
    }
}

// MARK: NSTextFieldDelegate

extension FolderTreeViewController: NSTextFieldDelegate {
    /// 结束编辑文件夹名时写回数据源；新建的根文件夹名称就此定下，解除搁置，tile 带着这个名称出现
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        let row = outlineView.row(for: textField)
        let node = outlineView.item(atRow: row) as? FolderTreeNode

        guard let folder = node?.folder else { return }

        store.rename(folderID: folder.id, to: textField.stringValue)
        dockTileSynchronizer?.releaseTile(for: folder.id)
    }

    /// 按 Esc 取消编辑时名称保持原样，同样算名称定下来了：解除搁置，tile 带着原名出现
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

        // 取消编辑本身仍交给 outline view 处理
        return false
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
        guard
            let folderID = selectedNode?.containingFolderID,
            let window = view.window
        else {
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")

        panel.beginSheetModal(for: window) { [weak self, panel] response in
            guard response == .OK else { return }

            self?.store.addApps(panel.urls, to: folderID)
        }
    }

    /// 把选中的根文件夹重新添加到 Dock；记为待添加后它就不再算被拖出，状态随即刷新
    @objc
    private func addSelectedFolderToDock() {
        guard let folder = selectedNode?.folder else { return }

        dockTileSynchronizer?.addTile(for: folder.id)
        refreshDockStatus()
    }

    /// 删除选中项；文件夹连同内容一起删除
    @objc
    private func removeSelectedItem() {
        guard let node = selectedNode else { return }

        store.remove(itemID: node.item.id)
    }

    /// 双击文件夹行时进入重命名；App 名不可编辑
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

        updateButtons()
    }
}

// MARK: - Private

extension FolderTreeViewController {
    /// 配置 outline view：单列、无表头、支持树内拖动与从访达拖入
    private func configureOutlineView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.resizingMask = .autoresizingMask

        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        // 展开子层级时不加宽大纲列：加宽后树比滚动区宽，行尾的“不在 Dock 上”会被右缘裁掉
        outlineView.autoresizesOutlineColumn = false

        outlineView.headerView = nil
        outlineView.rowHeight = 26
        outlineView.dataSource = dataSource
        outlineView.delegate = self

        outlineView.target = self
        outlineView.doubleAction = #selector(renameClickedFolder)

        outlineView.registerForDraggedTypes([
            FolderTreeDataSource.itemIDPasteboardType,
            .fileURL,
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

        let newFolderButton = NSButton(
            title: String(
                localized: "folders.newFolder",
                comment: "文件夹区的按钮：新建文件夹"
            ),
            target: self,
            action: #selector(addFolder)
        )

        addAppsButton.target = self
        addAppsButton.action = #selector(addApps)

        addToDockButton.target = self
        addToDockButton.action = #selector(addSelectedFolderToDock)
        addToDockButton.isHidden = dockTileSynchronizer == nil

        removeButton.target = self
        removeButton.action = #selector(removeSelectedItem)

        let buttonRow = NSStackView()
        buttonRow.setViews([newFolderButton, addAppsButton, addToDockButton], in: .leading)
        buttonRow.setViews([removeButton], in: .trailing)

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

    /// 根据选中项更新“添加 App…”“添加到 Dock”与“删除”的可用状态
    private func updateButtons() {
        let hasSelection = selectedNode != nil
        addAppsButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection

        addToDockButton.isEnabled = selectedNode.map { isRemovedFromDock($0) } ?? false
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
