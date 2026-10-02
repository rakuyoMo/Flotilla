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

    /// 同一项换成给定位置与书签后的引用，id 不变
    /// - Parameters:
    ///   - url: 新的位置
    ///   - bookmark: 新的书签；建不起来时为 nil
    func replacingLocation(with url: URL, bookmark: Data?) -> Self
}

// MARK: - Location

extension BookmarkedReference {
    /// 把本地 URL 规整成记录用的写法：路径标准化，目录为目录 URL，其余为文件 URL；不存在时为 nil
    ///
    /// 同一个 App 或文件不因 URL 写法不同（结尾斜杠、`..`）而得到不同的 URL，加入时才能去重；
    /// `FolderItem(url:title:)` 为 App 与文件分类、按书签找到新位置、面板读出访达里的文件夹的内容时都按这里规整
    static func normalizedURL(_ url: URL) -> URL? {
        // 去掉 `..`、多余的斜杠等不同写法
        let path = url.standardizedFileURL.path(percentEncoded: false)

        // 不存在时读不到资源属性
        guard
            let values = try? URL(filePath: path).resourceValues(forKeys: [.isDirectoryKey])
        else {
            return nil
        }

        return normalizedURL(url, isDirectory: values.isDirectory ?? false)
    }

    /// 已经知道是不是目录时的规整写法，与 `normalizedURL(_:)` 相同，但不读取资源属性
    ///
    /// 面板读访达里的文件夹时，读目录已一次取齐各项是不是目录，逐项再读会让内容很多的目录展开变慢
    /// - Parameters:
    ///   - url: 本地 URL
    ///   - isDirectory: 它是不是目录
    static func normalizedURL(_ url: URL, isDirectory: Bool) -> URL {
        URL(
            filePath: url.standardizedFileURL.path(percentEncoded: false),
            directoryHint: isDirectory ? .isDirectory : .notDirectory
        )
    }

    /// 按书签找到当前位置，返回更新后的引用；位置与书签都不用改、或找不到时为 nil
    ///
    /// 不弹界面、不挂载卷；移进废纸篓时同样跟过去。没有书签的项在原路径上还有东西时补建书签。
    /// 文件按这里跟随；App 要用 `AppReference.relocatedApp(applicationURL:isVolumeMounted:)`，它在这之上不跟进废纸篓、按 bundle id 找回
    func relocated() -> Self? {
        guard let bookmark else {
            // 原路径上已经没有东西时建不起书签，这一项保持原样
            guard let newBookmark = try? url.bookmarkData() else { return nil }

            return replacingLocation(with: url, bookmark: newBookmark)
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

        return replacingLocation(with: newURL, bookmark: newBookmark)
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
