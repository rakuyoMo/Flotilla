// MARK: - FolderItemKind

/// `FolderItem` 在 JSON 里的类型标签
enum FolderItemKind: String, Codable {
    /// 对应 `FolderItem.app`
    case app

    /// 对应 `FolderItem.folder`
    case folder
}
