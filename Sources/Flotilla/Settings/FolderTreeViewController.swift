import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeViewController

/// 设置窗口的文件夹区：展示完整的文件夹树，提供新建、添加 App、删除、重命名与拖拽
@MainActor
final class FolderTreeViewController: NSViewController {
    /// 新建文件夹的默认名称
    private static let untitledFolderName = "未命名文件夹"

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// 用户设置，文件夹行的图标按其中的预览图标数渲染
    private let preferences: Preferences

    /// outline view 的数据源，持有全部行节点
    private let dataSource: FolderTreeDataSource

    /// 展示文件夹树
    private let outlineView = NSOutlineView()

    /// “添加 App…”按钮，无选中项时禁用
    private let addAppsButton = NSButton(title: "添加 App…", target: nil, action: nil)

    /// “删除”按钮，无选中项时禁用
    private let removeButton = NSButton(title: "删除", target: nil, action: nil)

    /// 当前选中行的节点
    private var selectedNode: FolderTreeNode? {
        outlineView.item(atRow: outlineView.selectedRow) as? FolderTreeNode
    }

    /// 创建文件夹区
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - preferences: 用户设置，决定文件夹行图标里的预览数量
    init(store: FolderStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences
        dataSource = FolderTreeDataSource(store: store)

        super.init(nibName: nil, bundle: nil)
    }

    /// 文件夹区完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 搭建界面，并在文件夹树或预览数量变化时刷新
    override func loadView() {
        configureOutlineView()
        view = makeContentView()
        updateButtons()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadTree),
            name: FolderStore.didChangeNotification,
            object: store
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadTree),
            name: Preferences.didChangeNotification,
            object: preferences
        )
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
        cell.configure(with: node, previewIconCount: preferences.previewIconCount)
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
    /// 结束编辑文件夹名时写回数据源
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let textField = notification.object as? NSTextField else { return }

        let row = outlineView.row(for: textField)
        let node = outlineView.item(atRow: row) as? FolderTreeNode

        guard let folder = node?.folder else { return }

        store.rename(folderID: folder.id, to: textField.stringValue)
    }
}

// MARK: - Actions

extension FolderTreeViewController {
    /// 新建文件夹：有选中项时建在其所属文件夹内，否则建为根文件夹；建好后立即进入重命名
    @objc
    private func addFolder() {
        let folder: Folder? =
            if let parentID = selectedNode?.containingFolderID {
                store.addSubfolder(named: Self.untitledFolderName, to: parentID)
            } else {
                store.addRootFolder(named: Self.untitledFolderName)
            }

        guard let folder else { return }

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

    /// 按数据源的最新内容重建整棵树，尽量保留展开状态与选中项
    @objc
    private func reloadTree() {
        // 节点会整体重建，先按 id 记下展开的文件夹与选中项
        let expandedIDs = expandedFolderIDs(in: dataSource.rootNodes)
        let selectedID = selectedNode?.item.id

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
        let titleLabel = NSTextField(labelWithString: "文件夹")
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder

        let newFolderButton = NSButton(
            title: "新建文件夹",
            target: self,
            action: #selector(addFolder)
        )

        addAppsButton.target = self
        addAppsButton.action = #selector(addApps)

        removeButton.target = self
        removeButton.action = #selector(removeSelectedItem)

        let buttonRow = NSStackView()
        buttonRow.setViews([newFolderButton, addAppsButton], in: .leading)
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

    /// 根据是否有选中项更新“添加 App…”与“删除”的可用状态
    private func updateButtons() {
        let hasSelection = selectedNode != nil
        addAppsButton.isEnabled = hasSelection
        removeButton.isEnabled = hasSelection
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
