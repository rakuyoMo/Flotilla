import Foundation
import Testing

@testable import Flotilla

// MARK: - DockTileRequestTests

/// stub 通过 `flotilla://` URL 发来请求：点击 tile 展开或收起面板，把 App 或文件拖到 tile 上则加入文件夹；
/// 只有约定的两种形式会被执行，路径里的特殊字符要原样还原，否则加入的是另一个文件
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

    // MARK: 加入项

    /// `flotilla://folder/<uuid>/items?path=…`：路径还原成文件 URL
    @Test
    func parsesAddItems() throws {
        let url = try makeAddItemsURL(paths: ["/Users/Shared/报告.pdf"])

        let expected = DockTileRequest.addItems(
            folderID: folderID,
            fileURLs: [URL(filePath: "/Users/Shared/报告.pdf")]
        )

        #expect(DockTileRequest(url: url) == expected)
    }

    /// 路径里的空格、中文与 URL 的保留字符都原样还原；stub 送来的文件包、App 路径以 `/` 结尾，还原成目录 URL
    @Test(arguments: [
        "/Users/Shared/年度 报告.pdf",
        "/Users/Shared/笔记 草稿.rtfd/",
        "/Applications/Visual Studio Code.app/",
        "/Users/Shared/Tom & Jerry=1+2 #3 ?4 100%.txt",
    ])
    func decodesSpecialCharactersInPath(path: String) throws {
        let url = try makeAddItemsURL(paths: [path])

        guard case .addItems(let parsedID, let fileURLs) = DockTileRequest(url: url) else {
            Issue.record("应当解析为加入项：\(url.absoluteString)")
            return
        }

        #expect(parsedID == folderID)
        #expect(fileURLs.map { $0.path(percentEncoded: false) } == [path])
        #expect(fileURLs.first?.hasDirectoryPath == path.hasSuffix("/"))
    }

    /// 一次拖放多个项：顺序与查询项一致
    @Test
    func keepsOrderOfMultiplePaths() throws {
        let paths = [
            "/System/Applications/Chess.app/",
            "/Users/Shared/报告.pdf",
            "/Users/Shared/笔记.rtfd/",
        ]

        let url = try makeAddItemsURL(paths: paths)

        let expected = DockTileRequest.addItems(
            folderID: folderID,
            fileURLs: paths.map { URL(filePath: $0) }
        )

        #expect(DockTileRequest(url: url) == expected)
    }

    // MARK: 无法识别

    /// scheme、host、路径层级或 id 不符合约定、加入项却没有 `path`，一律忽略
    @Test(arguments: [
        "https://folder/\(UUID().uuidString)",
        "flotilla://tile/\(UUID().uuidString)",
        "flotilla://folder/\(UUID().uuidString)/extra",
        "flotilla://folder/\(UUID().uuidString)/items/extra?path=/Users/Shared/报告.pdf",
        "flotilla://folder/not-a-uuid",
        "flotilla://folder/not-a-uuid/items?path=/Users/Shared/报告.pdf",
        "flotilla://folder/\(UUID().uuidString)/items",
        "flotilla://folder/\(UUID().uuidString)/items?file=/Users/Shared/报告.pdf",
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
    /// 按 stub 的方式拼出加入项的 URL：每个路径一个 `path` 查询项，由 `URLComponents` 编码
    private func makeAddItemsURL(paths: [String]) throws -> URL {
        var components = URLComponents()
        components.scheme = "flotilla"
        components.host = "folder"
        components.path = "/\(folderID.uuidString)/items"
        components.queryItems = paths.map {
            URLQueryItem(name: "path", value: $0)
        }

        return try #require(components.url)
    }
}
