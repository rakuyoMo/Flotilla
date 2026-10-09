import AppKit
import os

// MARK: - DockTileAppDelegate

/// stub 的 App delegate：
/// 启动完成后以不激活任何 App 的方式打开一个 `flotilla://` URL，等到结果后退出
///
/// - 由点击 tile 启动：打开 `flotilla://folder/<id>`
/// - 由把 App 或文件拖到 tile 上启动：打开 `flotilla://folder/<id>/items?path=<路径>&path=<路径>`，
///   每个被拖的项一个 `path`
@MainActor
final class DockTileAppDelegate: NSObject {
    /// 等待打开结果的最长时间（秒）
    private static let openTimeout: TimeInterval = 5

    /// stub 的日志
    private nonisolated static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockTile"
    )

    /// 被拖到 tile 上的项，按送达顺序；由点击启动时为空
    private var droppedURLs: [URL] = []
}

// MARK: NSApplicationDelegate

extension DockTileAppDelegate: NSApplicationDelegate {
    /// 收下被拖到 tile 上的项
    ///
    /// 实测（macOS 27）由拖放启动时，AppKit 在 `applicationDidFinishLaunching` 之前送来，一次拖放的多个项一次送齐；
    /// URL 在启动完成时发出，之后才送达的项不再发出
    func application(_: NSApplication, open urls: [URL]) {
        droppedURLs += urls
    }

    /// 拼出 URL 并打开；缺少根文件夹 id 时以非零状态退出
    func applicationDidFinishLaunching(_: Notification) {
        // 根文件夹 id 由 Flotilla 生成 stub 时写进 Info.plist；
        // 键名沿用 `FlotillaFolderID`：Flotilla 写进 Info.plist 的就是它
        guard
            let groupID = Bundle.main.infoDictionary?["FlotillaFolderID"] as? String,
            let url = makeURL(groupID: groupID)
        else {
            Self.logger.error("Info.plist 缺少有效的 FlotillaFolderID")
            exit(EXIT_FAILURE)
        }

        open(url)
    }
}

// MARK: - Private

extension DockTileAppDelegate {
    /// 以不激活 URL 处理者的方式打开 URL，等到回调（最多 `openTimeout` 秒）后退出
    ///
    /// 实测（macOS 27）stub 是 `LSBackgroundOnly` 的后台 App，点击 tile 时 Dock 不弹跳、不显示运行指示灯
    private func open(_ url: URL) {
        // 点击或拖放之前的前台 App 保持前台
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false

        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            guard let error else {
                exit(EXIT_SUCCESS)
            }

            Self.logger.error(
                "打开 \(url.absoluteString, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)"
            )
            exit(EXIT_FAILURE)
        }

        // 回调迟迟不来时按失败退出，stub 不能常驻
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openTimeout) {
            Self.logger.error("等待打开 \(url.absoluteString, privacy: .public) 超时")
            exit(EXIT_FAILURE)
        }
    }

    /// 发给 Flotilla 的 URL：有被拖的项时带上它们的 POSIX 路径，由 `URLComponents` 编码
    private func makeURL(groupID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "flotilla"

        // host 沿用 `folder`：Flotilla 只认它，Dock 上已有的 stub 发的也是它
        components.host = "folder"
        components.path = "/\(groupID)"

        guard !droppedURLs.isEmpty else { return components.url }

        components.path += "/items"
        components.queryItems = droppedURLs.map {
            URLQueryItem(name: "path", value: $0.path(percentEncoded: false))
        }

        return components.url
    }
}
