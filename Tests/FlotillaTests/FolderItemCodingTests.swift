import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderItemCodingTests

/// 文件夹树的 JSON 编解码：持久化文件要能完整还原任意深度的嵌套结构
struct FolderItemCodingTests {
    /// 三层嵌套、App 与子文件夹混排的结构，编码后再解码必须与原值一致
    @Test
    func nestedTreeRoundTrips() throws {
        let innermost = Folder(
            id: UUID(),
            name: "最内层",
            items: [.app(makeApp("Chess"))]
        )

        let middle = Folder(
            id: UUID(),
            name: "中间层",
            items: [
                .folder(innermost),
                .app(makeApp("Calendar")),
            ]
        )

        let root = Folder(
            id: UUID(),
            name: "根",
            items: [
                .app(makeApp("Calculator")),
                .folder(middle),
            ]
        )

        let data = try JSONEncoder().encode([root])
        let decoded = try JSONDecoder().decode([Folder].self, from: data)

        #expect(decoded == [root])
    }

    /// 文件（有、没有书签）与网页（有、没有标题）编码后再解码必须与原值一致
    @Test
    func filesAndWebPagesRoundTrip() throws {
        let root = Folder(
            id: UUID(),
            name: "根",
            items: [
                makeFile("/Users/Shared/报告.pdf", bookmark: Data("书签".utf8)),
                makeFile("/Users/Shared/笔记.rtfd/", bookmark: nil),
                makeFile("/Users/Shared/资料/", bookmark: Data("书签".utf8)),
                try makeWebPage("https://example.com/", title: "Example Domain"),
                try makeWebPage("https://example.org/", title: nil),
            ]
        )

        let data = try JSONEncoder().encode([root])
        let decoded = try JSONDecoder().decode([Folder].self, from: data)

        #expect(decoded == [root])
    }

    /// 每一项都带显式的类型标签，读者不看代码也能分辨 App、子文件夹、文件与网页
    @Test
    func itemsCarryExplicitTypeTag() throws {
        let items: [FolderItem] = [
            .app(makeApp("Chess")),
            .folder(Folder(id: UUID(), name: "子文件夹", items: [])),
            makeFile("/Users/Shared/报告.pdf", bookmark: nil),
            try makeWebPage("https://example.com/", title: "Example Domain"),
        ]

        let objects = try jsonObjects(encoding: items)

        #expect(objects.map { $0["type"] as? String } == ["app", "folder", "file", "webPage"])
    }

    /// 文件的书签以 base64 写在 `bookmark` 键里；没有书签时不写这个键
    @Test
    func fileWithoutBookmarkOmitsBookmarkKey() throws {
        let bookmark = Data("书签".utf8)

        let items = [
            makeFile("/Users/Shared/报告.pdf", bookmark: bookmark),
            makeFile("/Users/Shared/笔记.rtfd/", bookmark: nil),
        ]

        let objects = try jsonObjects(encoding: items)

        #expect(objects[0]["bookmark"] as? String == bookmark.base64EncodedString())
        #expect(!objects[1].keys.contains("bookmark"))
    }

    /// 没有 `bookmark` 键的文件照常解码，书签为 nil：升级前加入的文件不会丢失
    @Test
    func fileWithoutBookmarkKeyDecodes() throws {
        let fileID = UUID()

        let json = Data(
            #"""
            [
              {
                "type": "file",
                "id": "\#(fileID.uuidString)",
                "url": "file:///Users/Shared/report.pdf"
              }
            ]
            """#.utf8
        )

        let decoded = try JSONDecoder().decode([FolderItem].self, from: json)

        let report = FileReference(
            id: fileID,
            url: URL(filePath: "/Users/Shared/report.pdf"),
            bookmark: nil
        )

        #expect(decoded == [.file(report)])
    }

    /// App 有、没有书签都往返一致；书签以 base64 写在 `bookmark` 键里，没有书签时不写这个键
    @Test
    func appBookmarkRoundTripsAndIsOmittedWhenNil() throws {
        let bookmark = Data("书签".utf8)

        let items: [FolderItem] = [
            .app(AppReference(
                id: UUID(),
                url: URL(filePath: "/System/Applications/Chess.app/"),
                bookmark: bookmark,
                bundleIdentifier: nil
            )),
            .app(makeApp("Calendar")),
        ]

        let data = try JSONEncoder().encode(items)
        let objects = try jsonObjects(encoding: items)

        #expect(try JSONDecoder().decode([FolderItem].self, from: data) == items)
        #expect(objects[0]["bookmark"] as? String == bookmark.base64EncodedString())
        #expect(!objects[1].keys.contains("bookmark"))
    }

    /// App 的 bundle id 往返后保留，写在 `bundleIdentifier` 键里；没有时不写这个键：App 更新之后据此找回装好的那一份
    @Test
    func appBundleIdentifierRoundTripsAndIsOmittedWhenNil() throws {
        let items: [FolderItem] = [
            .app(AppReference(
                id: UUID(),
                url: URL(filePath: "/System/Applications/Chess.app/"),
                bookmark: nil,
                bundleIdentifier: "com.apple.Chess"
            )),
            .app(makeApp("Calendar")),
        ]

        let data = try JSONEncoder().encode(items)
        let objects = try jsonObjects(encoding: items)

        #expect(try JSONDecoder().decode([FolderItem].self, from: data) == items)
        #expect(objects[0]["bundleIdentifier"] as? String == "com.apple.Chess")
        #expect(!objects[1].keys.contains("bundleIdentifier"))
    }

    /// 网页没有标题时 JSON 里不写 `title` 键，有标题时照常写出
    @Test
    func webPageWithoutTitleOmitsTitleKey() throws {
        let items = [
            try makeWebPage("https://example.com/", title: "Example Domain"),
            try makeWebPage("https://example.org/", title: nil),
        ]

        let objects = try jsonObjects(encoding: items)

        #expect(objects[0]["title"] as? String == "Example Domain")
        #expect(!objects[1].keys.contains("title"))
    }

    /// 只有 App 与子文件夹、App 没有书签与 bundle id 的旧数据照常解码，升级后用户的文件夹不会丢失
    @Test
    func legacyDataDecodes() throws {
        let appID = UUID()
        let folderID = UUID()

        let json = Data(
            #"""
            [
              {
                "type": "app",
                "id": "\#(appID.uuidString)",
                "url": "file:///System/Applications/Chess.app/"
              },
              {
                "type": "folder",
                "id": "\#(folderID.uuidString)",
                "name": "子文件夹",
                "items": []
              }
            ]
            """#.utf8
        )

        let decoded = try JSONDecoder().decode([FolderItem].self, from: json)

        let chess = AppReference(
            id: appID,
            url: URL(filePath: "/System/Applications/Chess.app/"),
            bookmark: nil,
            bundleIdentifier: nil
        )

        #expect(decoded == [
            .app(chess),
            .folder(Folder(id: folderID, name: "子文件夹", items: [])),
        ])
    }

    /// 未知的类型标签视为数据损坏，而不是被静默丢弃
    @Test
    func unknownTypeTagFailsToDecode() {
        let json = Data(#"[{"type": "widget", "id": "\#(UUID().uuidString)"}]"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([FolderItem].self, from: json)
        }
    }

    /// 引用 `/System/Applications` 下的系统 App
    private func makeApp(_ name: String) -> AppReference {
        AppReference(
            id: UUID(),
            url: URL(filePath: "/System/Applications/\(name).app"),
            bookmark: nil,
            bundleIdentifier: nil
        )
    }

    /// 按路径新建一个文件项，id 随机、带给定的书签
    private func makeFile(_ path: String, bookmark: Data?) -> FolderItem {
        .file(FileReference(id: UUID(), url: URL(filePath: path), bookmark: bookmark))
    }

    /// 按网址与标题新建一个网页项，id 随机；
    /// 网址解析不出时抛错
    private func makeWebPage(_ address: String, title: String?) throws -> FolderItem {
        let url = try #require(URL(string: address))

        return .webPage(WebPageReference(id: UUID(), url: url, title: title))
    }

    /// 把各项编码成 JSON，再读回成字典，用来检查写出的键
    private func jsonObjects(encoding items: [FolderItem]) throws -> [[String: Any]] {
        let data = try JSONEncoder().encode(items)
        let object = try JSONSerialization.jsonObject(with: data)

        return try #require(object as? [[String: Any]])
    }
}
