import Foundation

// MARK: - FinderFolderContents

/// 面板里展开访达里的文件夹时读出的内容：按设置跳过或显示隐藏文件，按访达“名称”的顺序排列，App bundle 为 App，其余为文件
///
/// 各项只存在于这一次展开里，不进 `FolderStore`、不建书签。同一个层级里同名的项在一次展开里 id 不变：
/// 返回时父层级是重新读出来的，要按 id 找到缩回的图标、恢复滚动位置
struct FinderFolderContents {
    /// 显示隐藏文件时仍不显示的文件名，与访达的 ⌘⇧. 相同（macOS 27 实测）
    private static let alwaysHiddenNames: Set<String> = [".DS_Store", ".localized"]

    /// 本次展开里已分配的 id：所在层级的 id → 名称 → 这一项的 id
    ///
    /// 按所在层级与名称而不是完整路径记：最外层的访达里的文件夹按书签跟到新位置后，里面各项的 id 仍然不变
    private var itemIDs: [UUID: [String: UUID]] = [:]

    /// 本次展开里读出的隐藏项的 id，面板把它们画成半透明；以每一项最近一次读到的属性为准
    private(set) var hiddenItemIDs: Set<UUID> = []

    /// 读出访达里的文件夹里的各项，并按这次读到的属性更新 `hiddenItemIDs`
    /// - Parameters:
    ///   - finderFolder: 访达里的文件夹；它的 id 就是展开后那一层的 id
    ///   - includingHiddenFiles: 是否显示隐藏文件；显示时 `.DS_Store` 与 `.localized` 仍不显示
    /// - Returns: 按显示名排好序的各项
    /// - Throws: 读不出内容时抛出：已删除、没有权限、隐私授权被拒
    mutating func items(
        of finderFolder: FileReference,
        includingHiddenFiles: Bool
    ) throws -> [FolderItem] {
        // 读目录时一并取齐排序、分类与是否隐藏要用的属性，之后各项只读这份缓存，不再逐项访问磁盘
        let urls = try FileManager.default.contentsOfDirectory(
            at: finderFolder.url,
            includingPropertiesForKeys: [
                .localizedNameKey,
                .isDirectoryKey,
                .contentTypeKey,
                .isHiddenKey,
            ],
            options: includingHiddenFiles ? [] : [.skipsHiddenFiles]
        )

        // 访达显示隐藏文件时，这两个名称的文件仍不显示
        let shownURLs = urls.filter {
            !Self.alwaysHiddenNames.contains($0.lastPathComponent)
        }

        // 先取出显示名再排序，排序过程中不反复读取；预取的显示名与 `FileManager.displayName(atPath:)` 相同，
        // 取不到时同样退回文件名
        let namedURLs = shownURLs.map { url in
            let name = try? url
                .resourceValues(forKeys: [.localizedNameKey])
                .localizedName

            return (url: url, name: name ?? url.lastPathComponent)
        }

        // `localizedStandardCompare` 让 `a2` 排在 `a10` 前面，与访达“名称”的顺序一致；
        // 隐藏的项与其它项混在一起按显示名排，开头的 `.` 也参与比较，与访达显示隐藏文件时相同
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
    /// 目录里的一项：App bundle 为 App，其余为文件，隐藏的另记进 `hiddenItemIDs`；读目录时已取不到属性（刚被删掉）的为 nil
    /// - Parameters:
    ///   - url: 这一项的 URL
    ///   - levelID: 所在层级的 id
    private mutating func item(at url: URL, in levelID: UUID) -> FolderItem? {
        // 是否目录、是否隐藏与内容类型都取自读目录时的预取，不再访问磁盘
        guard
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
        else {
            return nil
        }

        // 按加入文件夹时的同一规则记录 URL：目录为目录 URL，其余为文件 URL
        let normalizedURL = FileReference.normalizedURL(
            url,
            isDirectory: values.isDirectory ?? false
        )

        let id = itemID(named: url.lastPathComponent, in: levelID)

        // 以 `.` 开头、带 `hidden` 标志的都算隐藏；同一项再读时按这次读到的属性改记
        if values.isHidden ?? false {
            hiddenItemIDs.insert(id)
        } else {
            hiddenItemIDs.remove(id)
        }

        // 这些项只在这一次展开里，不跟随移动，书签与 bundle id 都用不上
        if AppReference.isApplicationBundle(url) {
            return .app(AppReference(
                id: id,
                url: normalizedURL,
                bookmark: nil,
                bundleIdentifier: nil
            ))
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
