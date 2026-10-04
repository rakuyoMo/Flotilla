import AppKit

// MARK: - FolderTreeDataSource

/// 设置窗口文件夹树的数据源：把 `FolderStore` 的树转换成行节点，
/// 并处理树内拖动、从访达拖入 App、文件与访达里的文件夹、从浏览器拖入网页
@MainActor
final class FolderTreeDataSource: NSObject {
    /// 树内拖动时写进剪贴板的类型，内容为被拖动项的 id
    static let itemIDPasteboardType = NSPasteboard.PasteboardType(
        "com.rakuyo.flotilla.folder-item-id"
    )

    /// 浏览器拖出网址时，同一个剪贴板项里的网页标题
    static let urlNamePasteboardType = NSPasteboard.PasteboardType("public.url-name")

    /// 根文件夹对应的节点
    private(set) var rootNodes: [FolderTreeNode] = []

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// 创建数据源并按 store 的当前内容建立节点
    /// - Parameter store: 文件夹树的唯一数据源
    init(store: FolderStore) {
        self.store = store
        super.init()

        reloadNodes()
    }

    /// 按 store 的当前内容重建全部节点
    func reloadNodes() {
        rootNodes = store.rootFolders.map {
            FolderTreeNode(item: .folder($0), parent: nil)
        }
    }

    /// 按 id 查找节点；找不到时为 nil
    func node(withID id: UUID) -> FolderTreeNode? {
        var pending = rootNodes

        // 广度优先遍历整棵树
        while !pending.isEmpty {
            let node = pending.removeFirst()

            if node.item.id == id {
                return node
            }

            pending += node.children
        }

        return nil
    }

    /// 计算树内拖动的落点
    /// - Parameters:
    ///   - itemID: 被拖动的项
    ///   - proposedParent: outline view 建议的父节点，nil 表示根层级
    ///   - childIndex: outline view 建议的下标，`NSOutlineViewDropOnItemIndex` 表示落在父节点这一行上
    /// - Returns: 目标文件夹（nil 表示根层级）与目标下标；不允许放在这里时返回 nil
    func moveDestination(
        for itemID: UUID,
        proposedParent: FolderTreeNode?,
        childIndex: Int
    ) -> (folderID: UUID?, index: Int)? {
        // App、文件与网页行不能包含其它项
        if let proposedParent, proposedParent.folder == nil {
            return nil
        }

        let folderID = proposedParent?.folder?.id
        guard store.canMove(itemID: itemID, to: folderID) else { return nil }

        // 落在文件夹这一行上时追加到末尾
        guard childIndex == NSOutlineViewDropOnItemIndex else {
            return (folderID, childIndex)
        }

        return (folderID, proposedParent?.children.count ?? rootNodes.count)
    }
}

// MARK: NSOutlineViewDataSource

extension FolderTreeDataSource: NSOutlineViewDataSource {
    /// 子节点数量；item 为 nil 时是根层级
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    /// 第 index 个子节点；item 为 nil 时是根层级
    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    /// 只有文件夹可以展开
    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FolderTreeNode)?.folder != nil
    }

    /// 树内拖动时把被拖动项的 id 写进剪贴板
    func outlineView(
        _: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> (any NSPasteboardWriting)? {
        guard let node = item as? FolderTreeNode else { return nil }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(node.item.id.uuidString, forType: Self.itemIDPasteboardType)

        return pasteboardItem
    }

    /// 校验落点：树内拖动按移动规则判断；从外部拖入的 App、文件与网页只能落在文件夹上，
    /// 一个能加入的都没有时不接收
    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let proposedParent = item as? FolderTreeNode

        if let itemID = Self.draggedItemID(in: info.draggingPasteboard) {
            let destination = moveDestination(
                for: itemID,
                proposedParent: proposedParent,
                childIndex: index
            )

            return destination == nil ? [] : .move
        }

        guard
            let proposedParent,
            proposedParent.folder != nil,
            !Self.droppedItems(in: info.draggingPasteboard).isEmpty
        else {
            return []
        }

        // 拖入的项总是追加到文件夹末尾，因此高亮整个文件夹行，而不是显示插入线
        outlineView.setDropItem(proposedParent, dropChildIndex: NSOutlineViewDropOnItemIndex)

        return .copy
    }

    /// 执行放下：树内拖动执行移动，从外部拖入的 App、文件与网页加入目标文件夹
    func outlineView(
        _: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let proposedParent = item as? FolderTreeNode

        if let itemID = Self.draggedItemID(in: info.draggingPasteboard) {
            let destination = moveDestination(
                for: itemID,
                proposedParent: proposedParent,
                childIndex: index
            )

            guard let destination else { return false }

            store.move(itemID: itemID, to: destination.folderID, at: destination.index)

            return true
        }

        let items = Self.droppedItems(in: info.draggingPasteboard)
        guard let folder = proposedParent?.folder, !items.isEmpty else { return false }

        store.addItems(items, to: folder.id)

        return true
    }
}

// MARK: - Private

extension FolderTreeDataSource {
    /// 剪贴板里树内拖动的项 id；不是树内拖动时返回 nil
    private static func draggedItemID(in pasteboard: NSPasteboard) -> UUID? {
        pasteboard
            .string(forType: itemIDPasteboardType)
            .flatMap(UUID.init(uuidString:))
    }

    /// 剪贴板里能加入文件夹的项：每个剪贴板项先取文件 URL，没有再取网址；网址带上同一项里的网页标题
    ///
    /// 分类交给 `FolderItem(url:title:)`，已不存在的文件与 `http`、`https` 以外的网址被略过
    private static func droppedItems(in pasteboard: NSPasteboard) -> [FolderItem] {
        (pasteboard.pasteboardItems ?? []).compactMap {
            let urlString = $0.string(forType: .fileURL) ?? $0.string(forType: .URL)

            guard let url = urlString.flatMap(URL.init(string:)) else { return nil }

            return FolderItem(url: url, title: $0.string(forType: urlNamePasteboardType))
        }
    }

    /// item 的子节点；item 为 nil 时是根层级
    private func children(of item: Any?) -> [FolderTreeNode] {
        guard let node = item as? FolderTreeNode else { return rootNodes }

        return node.children
    }
}
