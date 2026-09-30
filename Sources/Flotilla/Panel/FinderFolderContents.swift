import Foundation

// MARK: - FinderFolderContents

/// 面板里展开访达里的文件夹时读出的内容：跳过隐藏文件，按访达“名称”的顺序排列，App bundle 为 App，其余为文件
///
/// 各项只存在于这一次展开里，不进 `FolderStore`、不建书签。同一个层级里同名的项在一次展开里 id 不变：
/// 返回时父层级是重新读出来的，要按 id 找到缩回的图标、恢复滚动位置
struct FinderFolderContents {
    /// 本次展开里已分配的 id：所在层级的 id → 名称 → 这一项的 id
    ///
    /// 按所在层级与名称而不是完整路径记：最外层的访达里的文件夹按书签跟到新位置后，里面各项的 id 仍然不变
    private var itemIDs: [UUID: [String: UUID]] = [:]

    /// 读出访达里的文件夹里的各项
    /// - Parameter finderFolder: 访达里的文件夹；它的 id 就是展开后那一层的 id
    /// - Returns: 按显示名排好序的各项
    /// - Throws: 读不出内容时抛出：已删除、没有权限、隐私授权被拒
    mutating func items(of finderFolder: FileReference) throws -> [FolderItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: finderFolder.url,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        )

        // 先算好显示名再排序，排序过程中不反复读取
        let namedURLs = urls.map {
            (url: $0, name: FileManager.default.displayName(atPath: $0.path(percentEncoded: false)))
        }

        // `localizedStandardCompare` 让 `a2` 排在 `a10` 前面，与访达“名称”的顺序一致
        let sortedURLs = namedURLs
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map(\.url)

        return sortedURLs.compactMap {
            item(at: $0, in: finderFolder.id)
        }
    }
}

// MARK: - Private

extension FinderFolderContents {
    /// 目录里的一项：App bundle 为 App，其余为文件；读目录之后又被删掉的为 nil
    /// - Parameters:
    ///   - url: 这一项的 URL
    ///   - levelID: 所在层级的 id
    private mutating func item(at url: URL, in levelID: UUID) -> FolderItem? {
        // 按加入文件夹时的同一规则记录 URL：目录为目录 URL，其余为文件 URL
        guard let normalizedURL = FileReference.normalizedURL(url) else { return nil }

        let id = itemID(named: url.lastPathComponent, in: levelID)

        if AppReference.isApplicationBundle(normalizedURL) {
            return .app(AppReference(id: id, url: normalizedURL, bookmark: nil))
        }

        return .file(FileReference(id: id, url: normalizedURL, bookmark: nil))
    }

    /// 某一层里某个名称的 id：第一次遇到时分配，之后沿用
    private mutating func itemID(named name: String, in levelID: UUID) -> UUID {
        if let id = itemIDs[levelID]?[name] {
            return id
        }

        let id = UUID()
        itemIDs[levelID, default: [:]][name] = id

        return id
    }
}
