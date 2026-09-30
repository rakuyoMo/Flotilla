import Foundation

// MARK: - BookmarkedReference

/// 带书签的本地引用：App 与文件共用同一套规则，移动或改名后按书签找到当前位置
protocol BookmarkedReference {
    /// 这一项的唯一标识；跟到新位置后不变
    var id: UUID { get }

    /// 记录的位置
    var url: URL { get }

    /// 书签，移动或改名后据此找到新位置；建不起来时为 nil，只按路径找
    var bookmark: Data? { get }

    /// 用给定的 id、位置与书签建一个引用
    /// - Parameters:
    ///   - id: 这一项的唯一标识
    ///   - url: 记录的位置
    ///   - bookmark: 书签；建不起来时为 nil
    init(id: UUID, url: URL, bookmark: Data?)
}

// MARK: - Location

extension BookmarkedReference {
    /// 把本地 URL 规整成记录用的写法：路径标准化，目录为目录 URL，其余为文件 URL；不存在时为 nil
    ///
    /// 同一个 App 或文件不因 URL 写法不同（结尾斜杠、`..`）而得到不同的 URL，加入时才能去重；
    /// `FolderItem(url:title:)` 为 App 与文件分类、按书签找到新位置时都按这里规整
    static func normalizedURL(_ url: URL) -> URL? {
        // 去掉 `..`、多余的斜杠等不同写法
        let path = url.standardizedFileURL.path(percentEncoded: false)

        // 不存在时读不到资源属性
        guard
            let values = try? URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey])
        else {
            return nil
        }

        let isDirectory = values.isDirectory ?? false

        return URL(
            filePath: path,
            directoryHint: isDirectory ? .isDirectory : .notDirectory
        )
    }

    /// 按书签找到当前位置，返回更新后的引用；位置与书签都不用改、或找不到时为 nil
    ///
    /// 不弹界面、不挂载卷；移进废纸篓时同样跟过去。没有书签的项在原路径上还有东西时补建书签
    func relocated() -> Self? {
        guard let bookmark else {
            // 原路径上已经没有东西时建不起书签，这一项保持原样
            guard let newBookmark = try? url.bookmarkData() else { return nil }

            return Self(id: id, url: url, bookmark: newBookmark)
        }

        var isStale = false

        // 已删除、所在的卷没有挂载时解析失败，这一项保持原样
        guard
            let resolvedURL = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return nil
        }

        let hasMoved = Self.canonicalPath(of: resolvedURL) != Self.canonicalPath(of: url)

        guard hasMoved || isStale else { return nil }

        // 位置变了才换 URL，按加入时的同一规则规整；位置没变时保留原来的写法
        let newURL = hasMoved
            ? Self.normalizedURL(resolvedURL) ?? resolvedURL
            : url

        // 书签过期时按当前位置重建：解析按路径优先，原路径上换成了同名的新项时书签也会过期，
        // 重建后才跟着新项走，而不是之后解析回被换走的旧项。重建失败就沿用旧书签，它刚刚仍能解析
        let newBookmark = isStale
            ? (try? newURL.bookmarkData()) ?? bookmark
            : bookmark

        return Self(id: id, url: newURL, bookmark: newBookmark)
    }
}

// MARK: - Private

extension BookmarkedReference {
    /// 解析符号链接之后的路径，用来判断位置变没变
    ///
    /// 书签解析出的路径与加入时的路径写法可能不同，例如临时目录的 `/private/var` 与 `/var`，不能因此算作移动
    private static func canonicalPath(of url: URL) -> String {
        url
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
    }
}
