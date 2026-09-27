import Foundation

// MARK: - FolderItem

/// 文件夹内的一项：App 或子文件夹
enum FolderItem: Hashable, Identifiable {
    /// 一个 App
    case app(AppReference)

    /// 一个子文件夹
    case folder(Folder)

    /// 所包含项的 id
    var id: UUID {
        switch self {
        case .app(let app):
            app.id

        case .folder(let folder):
            folder.id
        }
    }
}

// MARK: Codable

extension FolderItem: Codable {
    /// 先读类型标签，再把同一层级的其余字段交给对应类型解码；子文件夹会继续递归解码，因此支持任意嵌套深度
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: FolderItemCodingKey.self)

        switch try container.decode(FolderItemKind.self, forKey: .type) {
        case .app:
            self = try .app(AppReference(from: decoder))

        case .folder:
            self = try .folder(Folder(from: decoder))
        }
    }

    /// 写出类型标签，再把所包含项的字段平铺到同一层级，让 JSON 保持可读
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: FolderItemCodingKey.self)

        switch self {
        case .app(let app):
            try container.encode(FolderItemKind.app, forKey: .type)
            try app.encode(to: encoder)

        case .folder(let folder):
            try container.encode(FolderItemKind.folder, forKey: .type)
            try folder.encode(to: encoder)
        }
    }
}
