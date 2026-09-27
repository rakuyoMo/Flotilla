import Foundation

// MARK: - DockTileRequest

/// stub 通过 `flotilla://` URL 向 Flotilla 发出的请求
///
/// - 点击 tile：`flotilla://folder/<根文件夹 id>`
/// - 把 App 拖到 tile 上：`flotilla://folder/<根文件夹 id>/apps?path=<路径>&path=<路径>`，每个被拖的项一个 `path`，取值为 POSIX 路径
enum DockTileRequest: Equatable {
    /// 展开或收起根文件夹的面板
    case toggleFolder(UUID)

    /// 把这些 App 加入根文件夹
    case addApps(folderID: UUID, appURLs: [URL])

    /// Flotilla 处理的 URL scheme，与 Info.plist 的 `CFBundleURLTypes` 一致
    static let urlScheme = "flotilla"

    /// 从 URL 中解析请求；scheme、host、路径层级、id 不符合约定，或加入 App 却没有 `path` 时为 nil
    init?(url: URL) {
        guard url.scheme == Self.urlScheme, url.host() == "folder" else { return nil }

        // `pathComponents` 形如 `["/", "<uuid>"]` 或 `["/", "<uuid>", "apps"]`
        let components = url.pathComponents
        guard
            components.count >= 2,
            let folderID = UUID(uuidString: components[1])
        else {
            return nil
        }

        switch components.dropFirst(2) {
        case []:
            self = .toggleFolder(folderID)

        case ["apps"]:
            // 查询项由 stub 用 `URLComponents` 编码，这里同样用它解码，路径里的空格、`&` 与中文都能还原
            let paths = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .filter { $0.name == "path" }
                .compactMap(\.value) ?? []

            guard !paths.isEmpty else { return nil }

            // App bundle 是目录，按目录 URL 给出，与 `FolderStore` 记录的形式一致
            let appURLs = paths.map {
                URL(filePath: $0, directoryHint: .isDirectory)
            }

            self = .addApps(folderID: folderID, appURLs: appURLs)

        default:
            return nil
        }
    }
}
