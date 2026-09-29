// MARK: - FolderItemCodingKey

/// `FolderItem` 在 JSON 里额外写出的键；
/// 其余字段由所包含的 `AppReference`、`Folder`、`FileReference` 或 `WebPageReference` 平铺写出
enum FolderItemCodingKey: String, CodingKey {
    /// 类型标签，取值见 `FolderItemKind`
    case type
}
