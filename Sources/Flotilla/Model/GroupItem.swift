import Foundation

// MARK: - GroupItem

/// 文件夹内的一项：App、子文件夹、文件或网页
enum GroupItem: Hashable, Identifiable {
    /// 一个 App：内容类型符合 `.applicationBundle` 的 App bundle
    case app(AppReference)

    /// 一个子文件夹：Flotilla 管理的分组，可继续嵌套，不对应磁盘目录
    case group(Group)

    /// 一个文件：App 以外的一切，包括文件包、访达里的文件夹与卷
    case file(FileReference)

    /// 一个网页：`http` 或 `https` 网址
    case webPage(WebPageReference)

    /// 所包含项的 id
    var id: UUID {
        switch self {
        case .app(let app):
            app.id

        case .group(let group):
            group.id

        case .file(let file):
            file.id

        case .webPage(let webPage):
            webPage.id
        }
    }
}

// MARK: - Classification

extension GroupItem {
    /// 为要加入文件夹的 URL 建一个新项：App bundle 为 App，其余存在的一切为文件，包括文件包、访达里的文件夹与卷；
    /// `http`、`https` 网址为网页；不存在的文件与其它网址返回 nil
    ///
    /// 设置窗口的拖入、“添加 App…” “添加文件…”、网页提示框（“添加网页…” 与 “编辑…”）与拖到 Dock 上的 tile 都经这里分类；
    /// 同一个 App 或文件不因 URL 写法不同而得到不同的 URL，加入时才能去重
    /// - Parameters:
    ///   - url: 文件 URL 或网址
    ///   - title: 网页的标题，只用于网页：浏览器给出的，或网页提示框里填写的；首尾空白会被去掉，空串视为没有
    init?(url: URL, title: String?) {
        let item = url.isFileURL
            ? Self.localItem(at: url)
            : Self.webPage(at: url, title: title)

        guard let item else { return nil }

        self = item
    }
}

// MARK: Codable

extension GroupItem: Codable {
    /// 先读类型标签，再把同一层级的其余字段交给对应类型解码；
    /// 子文件夹会继续递归解码，因此支持任意嵌套深度；
    /// 类型标签缺失或取值未知、字段解码失败时抛出解码错误
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GroupItemCodingKey.self)

        switch try container.decode(GroupItemKind.self, forKey: .type) {
        case .app:
            self = try .app(AppReference(from: decoder))

        case .group:
            self = try .group(Group(from: decoder))

        case .file:
            self = try .file(FileReference(from: decoder))

        case .webPage:
            self = try .webPage(WebPageReference(from: decoder))
        }
    }

    /// 写出类型标签，再把所包含项的字段平铺到同一层级，让 JSON 保持可读
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: GroupItemCodingKey.self)

        switch self {
        case .app(let app):
            try container.encode(GroupItemKind.app, forKey: .type)
            try app.encode(to: encoder)

        case .group(let group):
            try container.encode(GroupItemKind.group, forKey: .type)
            try group.encode(to: encoder)

        case .file(let file):
            try container.encode(GroupItemKind.file, forKey: .type)
            try file.encode(to: encoder)

        case .webPage(let webPage):
            try container.encode(GroupItemKind.webPage, forKey: .type)
            try webPage.encode(to: encoder)
        }
    }
}

// MARK: - Private

extension GroupItem {
    /// 本地 URL 对应的项：App bundle 为 App，其余存在的一切为文件；不存在的文件为 nil
    private static func localItem(at url: URL) -> GroupItem? {
        // 目录按目录 URL 记录，其余按文件 URL 记录；App bundle 是目录，与 `AppReference` 已有的数据一致
        guard let normalizedURL = FileReference.normalizedURL(url) else { return nil }

        // 书签让 App 与文件移动或改名后仍能找到；建不起来时只按路径找
        let bookmark = try? normalizedURL.bookmarkData()

        // App 另记下 bundle id：更新之后书签找不到装好的那一份时，据此问 Launch Services
        if AppReference.isApplicationBundle(normalizedURL) {
            return .app(AppReference(
                id: UUID(),
                url: normalizedURL,
                bookmark: bookmark,
                bundleIdentifier: AppReference.bundleIdentifier(at: normalizedURL)
            ))
        }

        return .file(FileReference(id: UUID(), url: normalizedURL, bookmark: bookmark))
    }

    /// 网址对应的网页：只接受 `http` 与 `https`，其它网址为 nil
    private static func webPage(at url: URL, title: String?) -> GroupItem? {
        // scheme 不区分大小写
        guard
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme)
        else {
            return nil
        }

        // 浏览器给的与用户填写的标题都可能带首尾空白，也可能是空串
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pageTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 }

        return .webPage(WebPageReference(id: UUID(), url: url, title: pageTitle))
    }
}
