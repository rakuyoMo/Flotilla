import Foundation

// MARK: - GroupTreeNode

/// 设置窗口组树里的一行：包装一个 `GroupItem`，并记住父节点，用来确定新建、添加与拖放的目标组
///
/// `NSOutlineView` 按对象身份跟踪行的展开与选中，因此用引用类型包装值类型的 `GroupItem`
final class GroupTreeNode {
    /// 这一行对应的项
    let item: GroupItem

    /// 父节点；根组为 nil
    private(set) weak var parent: GroupTreeNode? = nil

    /// 子节点，顺序与 `Group.items` 一致；App、文件与网页没有子节点
    private(set) var children: [GroupTreeNode] = []

    /// 这一行是组时返回该组
    var group: Group? {
        guard case .group(let group) = item else { return nil }
        return group
    }

    /// 这一行所属的组：组的行是自身，App、文件与网页的行是它的父组
    var containingGroupID: UUID? {
        group?.id ?? parent?.group?.id
    }

    /// 以 item 为根递归建立整棵子树
    /// - Parameters:
    ///   - item: 这一行对应的项
    ///   - parent: 父节点；根组传 nil
    init(item: GroupItem, parent: GroupTreeNode?) {
        self.item = item
        self.parent = parent

        guard case .group(let group) = item else { return }
        children = group.items.map { GroupTreeNode(item: $0, parent: self) }
    }
}
