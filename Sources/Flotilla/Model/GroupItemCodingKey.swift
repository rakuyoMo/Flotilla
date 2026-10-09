// MARK: - GroupItemCodingKey

/// `GroupItem` 在 JSON 里额外写出的键；
/// 其余字段由所包含的 `AppReference`、`Group`、`FileReference` 或 `WebPageReference` 平铺写出
enum GroupItemCodingKey: String, CodingKey {
    /// 类型标签，取值见 `GroupItemKind`
    case type
}
