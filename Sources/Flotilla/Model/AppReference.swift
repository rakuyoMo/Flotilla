import AppKit
import UniformTypeIdentifiers

// MARK: - AppReference

/// 对一个 App bundle 的引用
///
/// 带着书签与 bundle id：App 移动或改名后按书签找到新位置，App 更新后书签找不到时按 bundle id 找回
struct AppReference: BookmarkedReference, Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个 App 放进不同文件夹时各有各的 id
    let id: UUID

    /// App bundle 的文件 URL
    let url: URL

    /// App 的书签，App 移动或改名后据此找到新位置；建不起来时为 nil，只按路径找
    let bookmark: Data?

    /// App 的 bundle id，书签找不到装好的 App 时据此问 Launch Services；读不到时为 nil
    let bundleIdentifier: String?

    /// 同一个 App 换成给定位置与书签后的引用，id 不变；bundle id 按新位置重读，读不到时沿用原来的
    /// - Parameters:
    ///   - url: 新的位置
    ///   - bookmark: 新的书签；建不起来时为 nil
    func replacingLocation(with url: URL, bookmark: Data?) -> Self {
        Self(
            id: id,
            url: url,
            bookmark: bookmark,
            bundleIdentifier: Self.bundleIdentifier(at: url) ?? bundleIdentifier
        )
    }
}

// MARK: - Display

extension AppReference {
    /// App 在访达中显示的名称
    var displayName: String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// App 的图标
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}

// MARK: - Content Type

extension AppReference {
    /// URL 是否指向 App bundle：内容类型符合 `.applicationBundle`；文件不存在时为否
    ///
    /// `FolderItem(url:title:)` 据此把要加入文件夹的 URL 分成 App 与文件
    static func isApplicationBundle(_ url: URL) -> Bool {
        let contentType = try? url
            .resourceValues(forKeys: [.contentTypeKey])
            .contentType

        return contentType?.conforms(to: .applicationBundle) ?? false
    }

    /// 读出 App bundle 的 bundle id；不存在、没有 `Info.plist` 或其中没有 `CFBundleIdentifier` 时为 nil
    ///
    /// 每次都从磁盘读：`Bundle(url:)` 按路径缓存，App 被原地换成新版本后读到的仍是旧版本的信息
    static func bundleIdentifier(at url: URL) -> String? {
        let infoDictionary = CFBundleCopyInfoDictionaryInDirectory(url as CFURL) as? [String: Any]

        return infoDictionary?[kCFBundleIdentifierKey as String] as? String
    }
}

// MARK: - Location

extension AppReference {
    /// 按书签找到 App 的当前位置，返回更新后的引用；位置、书签与 bundle id 都不用改，或找不到时为 nil
    ///
    /// 在文件的 `relocated()` 之上多两条，让 App 更新之后这一项仍打开装好的那一份：
    /// - 不跟进废纸篓：废纸篓里的 App 启动不了；更新时旧版本移进废纸篓之后，新版本会放回原路径
    /// - 书签找不到 App、或只找到废纸篓里的旧版本时，按 bundle id 问 Launch Services 要装好的那一份；
    ///   书签记录的卷没有挂载时不找，这一项保持原样，卷挂回来照常按书签解析
    /// - Parameters:
    ///   - applicationURL: 按 bundle id 找 App 的位置，默认问 Launch Services；测试里换成假实现
    ///   - isVolumeMounted: 书签记录的卷当前是否挂载着，默认按 `isVolumeMounted(recordedIn:)` 判断；测试里换成假实现
    func relocatedApp(
        applicationURL: (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        isVolumeMounted: (Data) -> Bool = AppReference.isVolumeMounted(recordedIn:)
    ) -> AppReference? {
        // 先与文件一样按书签跟随；跟到废纸篓里的不算，位置与书签都保持原样
        if let followed = relocated(), !Self.isInTrash(followed.url) {
            return followed
        }

        // 原路径上还有东西：书签解析按路径优先，说明位置与书签都不用改；旧数据趁这时补上 bundle id
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return withBundleIdentifierFilled()
        }

        // 书签记录的卷没有挂载：App 仍在那个卷上，不去找别处的同一个 App，这一项保持原样，等卷挂回来照常解析
        if let bookmark, !isVolumeMounted(bookmark) {
            return nil
        }

        // 原路径上没有东西：书签解析失败，或只找到废纸篓里的旧版本
        return recovered(applicationURL: applicationURL)
    }
}

// MARK: - Volume

extension AppReference {
    /// 书签记录的卷当前是否挂载着：书签里记着卷的 UUID，在已挂载的卷里找同一个 UUID
    ///
    /// 按 UUID 认卷，与书签解析一致：同一个卷挂到别的位置照样解析得到，同名的另一个卷挂在原位置时解析不到。
    /// 书签里读不到卷的 UUID 时确认不了，按没挂载处理
    /// - Parameter bookmark: App 的书签
    static func isVolumeMounted(recordedIn bookmark: Data) -> Bool {
        #warning("TODO: 未能实测 网络卷上的书签是否记着卷的 UUID")

        // 卷没挂载时，书签里记着的卷信息照样读得出来
        guard
            let volumeUUID = URL.resourceValues(
                forKeys: [.volumeUUIDStringKey],
                fromBookmarkData: bookmark
            )?.volumeUUIDString
        else {
            return false
        }

        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey],
            options: []
        ) ?? []

        let mountedVolumeUUIDs = mountedVolumes.compactMap {
            try? $0
                .resourceValues(forKeys: [.volumeUUIDStringKey])
                .volumeUUIDString
        }

        return mountedVolumeUUIDs.contains(volumeUUID)
    }
}

// MARK: - Private

extension AppReference {
    /// 没有 bundle id 的旧数据，按原路径上的 App 补上；已有 bundle id、或读不到时为 nil
    private func withBundleIdentifierFilled() -> AppReference? {
        guard
            bundleIdentifier == nil,
            let newBundleIdentifier = Self.bundleIdentifier(at: url)
        else {
            return nil
        }

        return AppReference(
            id: id,
            url: url,
            bookmark: bookmark,
            bundleIdentifier: newBundleIdentifier
        )
    }

    /// 按 bundle id 找回装好的 App：跟到 Launch Services 给出的位置，按新位置建书签；
    /// 没有 bundle id、Launch Services 给不出、给出的已不存在或在废纸篓里时为 nil
    /// - Parameter applicationURL: 按 bundle id 找 App 的位置
    private func recovered(applicationURL: (String) -> URL?) -> AppReference? {
        guard
            let bundleIdentifier,
            let foundURL = applicationURL(bundleIdentifier),
            !Self.isInTrash(foundURL),
            let newURL = Self.normalizedURL(foundURL)
        else {
            return nil
        }

        // 与按书签跟随相同：按加入时的同一规则规整，书签建不起来时沿用旧书签
        let newBookmark = (try? newURL.bookmarkData()) ?? bookmark

        return replacingLocation(with: newURL, bookmark: newBookmark)
    }
}

// MARK: - Helpers

extension AppReference {
    /// 位置是否在废纸篓里：用户的 `~/.Trash`，或其它卷上的 `.Trashes`
    ///
    /// 域传空：只传 `.userDomainMask` 时认不出其它卷上的 `.Trashes`。
    /// 不在废纸篓里的其它卷上的位置会抛错，与不存在的位置一样按不在废纸篓里处理
    private static func isInTrash(_ url: URL) -> Bool {
        var relationship = FileManager.URLRelationship.other

        try? FileManager.default.getRelationship(
            &relationship,
            of: .trashDirectory,
            in: [],
            toItemAt: url
        )

        return relationship == .contains
    }
}
