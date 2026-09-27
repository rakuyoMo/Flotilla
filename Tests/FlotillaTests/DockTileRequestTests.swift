import Foundation
import Testing

@testable import Flotilla

// MARK: - DockTileRequestTests

/// stub 通过 `flotilla://` URL 发来请求：点击 tile 展开或收起面板，把 App 拖到 tile 上则加入文件夹；
/// 只有约定的两种形式会被执行，路径里的特殊字符要原样还原，否则加入的是另一个 App
struct DockTileRequestTests {
    /// 请求里的根文件夹
    private let folderID = UUID()

    // MARK: 展开或收起

    /// `flotilla://folder/<uuid>`：展开或收起该根文件夹的面板
    @Test
    func parsesToggleFolder() throws {
        let url = try #require(URL(string: "flotilla://folder/\(folderID.uuidString)"))

        #expect(DockTileRequest(url: url) == .toggleFolder(folderID))
    }

    // MARK: 加入 App

    /// `flotilla://folder/<uuid>/apps?path=…`：路径按目录 URL 给出
    @Test
    func parsesAddApps() throws {
        let url = try makeAddAppsURL(paths: ["/System/Applications/Chess.app"])

        let expected = DockTileRequest.addApps(
            folderID: folderID,
            appURLs: [URL(filePath: "/System/Applications/Chess.app", directoryHint: .isDirectory)]
        )

        #expect(DockTileRequest(url: url) == expected)
    }

    /// 路径里的空格、中文与 URL 的保留字符都原样还原
    @Test(arguments: [
        "/Applications/Visual Studio Code.app",
        "/Applications/计算器 工具.app",
        "/Applications/Tom & Jerry=1+2 #3 ?4 100%.app",
    ])
    func decodesSpecialCharactersInPath(path: String) throws {
        let url = try makeAddAppsURL(paths: [path])

        let expected = DockTileRequest.addApps(
            folderID: folderID,
            appURLs: [URL(filePath: path, directoryHint: .isDirectory)]
        )

        #expect(DockTileRequest(url: url) == expected)
    }

    /// 一次拖放多个 App：顺序与查询项一致
    @Test
    func keepsOrderOfMultiplePaths() throws {
        let paths = [
            "/System/Applications/Chess.app",
            "/System/Applications/Calculator.app",
            "/System/Applications/Stickies.app",
        ]

        let url = try makeAddAppsURL(paths: paths)

        let expected = DockTileRequest.addApps(
            folderID: folderID,
            appURLs: paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
        )

        #expect(DockTileRequest(url: url) == expected)
    }

    // MARK: 无法识别

    /// scheme、host、路径层级或 id 不符合约定，或加入 App 却没有 `path` 的 URL 一律忽略
    @Test(arguments: [
        "https://folder/\(UUID().uuidString)",
        "flotilla://tile/\(UUID().uuidString)",
        "flotilla://folder/\(UUID().uuidString)/extra",
        "flotilla://folder/\(UUID().uuidString)/apps/extra?path=/Applications/Chess.app",
        "flotilla://folder/not-a-uuid",
        "flotilla://folder/not-a-uuid/apps?path=/Applications/Chess.app",
        "flotilla://folder/\(UUID().uuidString)/apps",
        "flotilla://folder/\(UUID().uuidString)/apps?app=/Applications/Chess.app",
        "flotilla://folder/",
        "flotilla://folder",
    ])
    func ignoresOtherURLs(string: String) throws {
        let url = try #require(URL(string: string))

        #expect(DockTileRequest(url: url) == nil)
    }
}

// MARK: - Private

extension DockTileRequestTests {
    /// 按 stub 的方式拼出加入 App 的 URL：每个路径一个 `path` 查询项，由 `URLComponents` 编码
    private func makeAddAppsURL(paths: [String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "flotilla"
        components.host = "folder"
        components.path = "/\(folderID.uuidString)/apps"
        components.queryItems = paths.map {
            URLQueryItem(name: "path", value: $0)
        }

        return try #require(components.url)
    }
}
