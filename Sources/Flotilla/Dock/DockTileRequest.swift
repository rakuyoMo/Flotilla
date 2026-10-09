import Foundation

// MARK: - DockTileRequest

/// stub 通过 `flotilla://` URL 向 Flotilla 发出的请求
///
/// - 点击 tile：`flotilla://folder/<根组 id>`
/// - 把 App 或文件拖到 tile 上：`flotilla://folder/<根组 id>/items?path=<路径>&path=<路径>`，
///   每个被拖的项一个 `path`，取值为 POSIX 路径
enum DockTileRequest: Equatable {
    /// 展开或收起根组的面板
    case toggleGroup(UUID)

    /// 把拖到 tile 上的这些项加入根组，是否接收由 `GroupItem(url:title:)` 分类决定
    case addItems(groupID: UUID, fileURLs: [URL])

    /// Flotilla 处理的 URL scheme，与 Info.plist 的 `CFBundleURLTypes` 一致
    static let urlScheme = "flotilla"

    /// 从 URL 中解析请求；scheme、host、路径层级、id 不符合约定，或加入项却没有 `path` 时为 nil
    init?(url: URL) {
        // host 沿用 `folder`：Dock 上已有的 stub 发来的就是它
        guard url.scheme == Self.urlScheme, url.host() == "folder" else { return nil }

        // `pathComponents` 形如 `["/", "<uuid>"]` 或 `["/", "<uuid>", "items"]`
        let components = url.pathComponents
        guard
            components.count >= 2,
            let groupID = UUID(uuidString: components[1])
        else {
            return nil
        }

        switch components.dropFirst(2) {
        case []:
            self = .toggleGroup(groupID)

        // 查询项由 stub 用 `URLComponents` 编码，这里同样用它解码，路径里的空格、`&` 与中文都能还原
        case ["items"]:
            let paths = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .filter { $0.name == "path" }
                .compactMap(\.value) ?? []

            guard !paths.isEmpty else { return nil }

            // stub 送来的目录路径以 `/` 结尾，按路径推断即可；分类时还会再规整
            let fileURLs = paths.map {
                URL(filePath: $0)
            }

            self = .addItems(groupID: groupID, fileURLs: fileURLs)

        default:
            return nil
        }
    }
}
