import Foundation

// MARK: - Group

/// Flotilla 管理的分组，收纳 App、文件与网页，可嵌套；数据由 `GroupStore` 保存，不对应磁盘目录
struct Group: Codable, Hashable, Identifiable {
    /// 组的唯一标识，根组的 Dock tile 与 `flotilla://` URL 都靠它关联
    let id: UUID

    /// 组名：设置窗口的树、面板与根组的 Dock tile 都显示它
    var name: String

    /// 组内的项，顺序即展示顺序
    var items: [GroupItem]
}
