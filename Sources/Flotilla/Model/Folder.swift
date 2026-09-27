import Foundation

// MARK: - Folder

/// Flotilla 管理的 App 分组，可嵌套；数据由 `FolderStore` 保存，不对应磁盘目录
struct Folder: Codable, Hashable, Identifiable {
    /// 文件夹的唯一标识，根文件夹的 Dock tile 与 `flotilla://` URL 都靠它关联
    let id: UUID

    /// 文件夹名称
    var name: String

    /// 文件夹内的项，顺序即展示顺序
    var items: [FolderItem]
}
