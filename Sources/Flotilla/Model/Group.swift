import Foundation

// MARK: - Group

/// Flotilla 管理的分组，收纳 App、文件与网页，可嵌套；数据由 `GroupStore` 保存，不对应磁盘目录
struct Group: Codable, Hashable, Identifiable {
    /// 文件夹的唯一标识，根文件夹的 Dock tile 与 `flotilla://` URL 都靠它关联
    let id: UUID

    /// 文件夹名称：设置窗口的树、面板与根文件夹的 Dock tile 都显示它
    var name: String

    /// 文件夹内的项，顺序即展示顺序
    var items: [GroupItem]
}
