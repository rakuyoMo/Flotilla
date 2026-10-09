// MARK: - GroupItemKind

/// `GroupItem` 在 JSON 里的类型标签
enum GroupItemKind: String, Codable {
    /// 对应 `GroupItem.app`
    case app

    /// 对应 `GroupItem.group`；
    /// JSON 里的类型标签沿用 `folder`：已保存的数据靠它解码
    case group = "folder"

    /// 对应 `GroupItem.file`
    case file

    /// 对应 `GroupItem.webPage`
    case webPage
}
