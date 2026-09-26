import Foundation

// MARK: - FolderTreeNode

/// 设置窗口文件夹树里的一行：包装一个文件夹项，并记住父节点，用来确定新建、添加与拖放的目标文件夹
///
/// `NSOutlineView` 按对象身份跟踪行的展开与选中，因此用引用类型包装值类型的 `FolderItem`
final class FolderTreeNode {
    /// 这一行对应的项
    let item: FolderItem

    /// 父节点；根文件夹为 nil
    private(set) weak var parent: FolderTreeNode? = nil

    /// 子节点，顺序与 `Folder.items` 一致；App 没有子节点
    private(set) var children: [FolderTreeNode] = []

    /// 这一行是文件夹时返回该文件夹
    var folder: Folder? {
        guard case .folder(let folder) = item else { return nil }
        return folder
    }

    /// 这一行所属的文件夹：文件夹行是自身，App 行是它的父文件夹
    var containingFolderID: UUID? {
        folder?.id ?? parent?.folder?.id
    }

    /// 以 item 为根递归建立整棵子树
    /// - Parameters:
    ///   - item: 这一行对应的项
    ///   - parent: 父节点；根文件夹传 nil
    init(item: FolderItem, parent: FolderTreeNode?) {
        self.item = item
        self.parent = parent

        guard case .folder(let folder) = item else { return }
        children = folder.items.map { FolderTreeNode(item: $0, parent: self) }
    }
}
