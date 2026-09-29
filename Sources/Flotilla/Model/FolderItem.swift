import Foundation

// MARK: - FolderItem

/// 文件夹内的一项：App、子文件夹、文件或网页
enum FolderItem: Hashable, Identifiable {
    /// 一个 App
    case app(AppReference)

    /// 一个子文件夹
    case folder(Folder)

    /// 一个文件：App 以外的文件，包括文件包
    case file(FileReference)

    /// 一个网页
    case webPage(WebPageReference)

    /// 所包含项的 id
    var id: UUID {
        switch self {
        case .app(let app):
            app.id

        case .folder(let folder):
            folder.id

        case .file(let file):
            file.id

        case .webPage(let webPage):
            webPage.id
        }
    }
}

// MARK: - Classification

extension FolderItem {
    /// 为要加入文件夹的 URL 建一个新项：App bundle 为 App，其余文件与文件包为文件，`http`、`https` 网址为网页；
    /// 普通文件夹（包括卷）、不存在的文件与其它网址返回 nil
    ///
    /// 设置窗口的拖入、“添加 App…”与拖到 Dock 上的 tile 都经这里分类；
    /// 同一个 App 或文件不因 URL 写法不同而得到不同的 URL，加入时才能去重
    /// - Parameters:
    ///   - url: 文件 URL 或网址
    ///   - title: 浏览器给出的网页标题，只用于网页；首尾空白会被去掉，空串视为没有
    init?(url: URL, title: String?) {
        let item = url.isFileURL
            ? Self.localItem(at: url)
            : Self.webPage(at: url, title: title)

        guard let item else { return nil }

        self = item
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

        case .file:
            self = try .file(FileReference(from: decoder))

        case .webPage:
            self = try .webPage(WebPageReference(from: decoder))
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

        case .file(let file):
            try container.encode(FolderItemKind.file, forKey: .type)
            try file.encode(to: encoder)

        case .webPage(let webPage):
            try container.encode(FolderItemKind.webPage, forKey: .type)
            try webPage.encode(to: encoder)
        }
    }
}

// MARK: - Private

extension FolderItem {
    /// 本地 URL 对应的项：App bundle 为 App，文件与文件包为文件；普通文件夹与不存在的文件为 nil
    private static func localItem(at url: URL) -> FolderItem? {
        // 统一成标准路径：去掉 `..`、多余的斜杠等不同写法，同一个文件只对应一个 URL
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let standardizedURL = URL(filePath: path)

        // 文件不存在时读不到资源属性
        guard
            let values = try? standardizedURL.resourceValues(
                forKeys: [.isDirectoryKey, .isPackageKey]
            )
        else {
            return nil
        }

        let isDirectory = values.isDirectory ?? false
        let isPackage = values.isPackage ?? false

        // App bundle 是目录，按目录 URL 记录，与 `AppReference` 已有的数据一致
        if AppReference.isApplicationBundle(standardizedURL) {
            let appURL = URL(filePath: path, directoryHint: .isDirectory)

            return .app(AppReference(id: UUID(), url: appURL))
        }

        // 访达里显示成文件夹的目录不接收
        guard !isDirectory || isPackage else { return nil }

        let fileURL = URL(
            filePath: path,
            directoryHint: isPackage ? .isDirectory : .notDirectory
        )

        return .file(FileReference(id: UUID(), url: fileURL))
    }

    /// 网址对应的网页：只接受 `http` 与 `https`，其它网址为 nil
    private static func webPage(at url: URL, title: String?) -> FolderItem? {
        // scheme 不区分大小写
        guard
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        // 浏览器给的标题可能带首尾空白，也可能是空串
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 }

        return .webPage(WebPageReference(id: UUID(), url: url, title: pageTitle))
    }
}
