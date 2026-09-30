import AppKit

// MARK: - FileReference

/// 对一个文件的引用：访达里 App 以外的一切，包括文件包、访达里的文件夹与卷
///
/// 带着书签：文件移动或改名后，按书签找到新位置
struct FileReference: Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个文件放进不同文件夹时各有各的 id
    let id: UUID

    /// 文件的 URL；文件包、访达里的文件夹与卷是目录 URL，其余是文件 URL
    let url: URL

    /// 文件的书签，文件移动或改名后据此找到新位置；建不起来时为 nil，只按路径找
    let bookmark: Data?
}

// MARK: - Display

extension FileReference {
    /// 文件在访达中显示的名称
    var displayName: String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// 文件在访达中的图标
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

// MARK: - Location

extension FileReference {
    /// 把本地 URL 规整成记录用的写法：路径标准化，目录为目录 URL，其余为文件 URL；文件不存在时为 nil
    ///
    /// 同一个文件不因 URL 写法不同（结尾斜杠、`..`）而得到不同的 URL，加入时才能去重；
    /// `FolderItem(url:title:)` 为 App 与文件分类、按书签找到新位置时都按这里规整
    static func normalizedURL(_ url: URL) -> URL? {
        // 去掉 `..`、多余的斜杠等不同写法
        let path = url.standardizedFileURL.path(percentEncoded: false)

        // 文件不存在时读不到资源属性
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

    /// 按书签找到文件的当前位置，返回更新后的引用；位置与书签都不用改、或找不到文件时为 nil
    ///
    /// 不弹界面、不挂载卷；文件移进废纸篓时同样跟过去。没有书签的项在文件还在原路径时补建书签
    func relocated() -> FileReference? {
        guard let bookmark else {
            // 文件已不在原路径时建不起书签，这一项保持原样
            guard let newBookmark = try? url.bookmarkData() else { return nil }

            return FileReference(id: id, url: url, bookmark: newBookmark)
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

        // 书签过期时按当前位置重建；重建失败就沿用旧书签，它刚刚仍能解析
        let newBookmark = isStale
            ? (try? newURL.bookmarkData()) ?? bookmark
            : bookmark

        return FileReference(id: id, url: newURL, bookmark: newBookmark)
    }
}

// MARK: - Private

extension FileReference {
    /// 解析符号链接之后的路径，用来判断位置变没变
    ///
    /// 书签解析出的路径与加入时的路径写法可能不同，例如临时目录的 `/private/var` 与 `/var`，不能因此算作移动
    private static func canonicalPath(of url: URL) -> String {
        url
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
    }
}
