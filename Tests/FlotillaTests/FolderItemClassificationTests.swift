import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderItemClassificationTests

/// `FolderItem(url:title:)` 决定拖进来的东西能否加入文件夹、以什么身份加入：身份错了，点击时就会用错误的方式打开
final class FolderItemClassificationTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 在临时目录里建好普通文件、访达里的文件夹、文件包与 App bundle
    init() throws {
        for name in ["资料", "笔记.rtfd", "Tool.app"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: name),
                withIntermediateDirectories: true
            )
        }

        try Data("报告".utf8).write(to: directory.appending(path: "报告.txt"))
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 本地文件

    /// 普通文件是文件，按文件 URL 记录
    @Test
    func regularFileIsFile() {
        let item = FolderItem(url: directory.appending(path: "报告.txt"), title: nil)

        guard case .file(let file) = item else {
            Issue.record("普通文件应当是文件：\(String(describing: item))")
            return
        }

        #expect(file.url == URL(filePath: path(of: "报告.txt"), directoryHint: .notDirectory))
    }

    /// 文件包在访达里显示成单个文件，是文件，按目录 URL 记录
    @Test
    func packageIsFile() {
        let item = FolderItem(url: URL(filePath: path(of: "笔记.rtfd")), title: nil)

        guard case .file(let file) = item else {
            Issue.record("文件包应当是文件：\(String(describing: item))")
            return
        }

        #expect(file.url == URL(filePath: path(of: "笔记.rtfd"), directoryHint: .isDirectory))
    }

    /// App bundle 是 App，按目录 URL 记录
    @Test
    func applicationBundleIsApp() {
        let item = FolderItem(url: URL(filePath: path(of: "Tool.app")), title: nil)

        guard case .app(let app) = item else {
            Issue.record("App bundle 应当是 App：\(String(describing: item))")
            return
        }

        #expect(app.url == URL(filePath: path(of: "Tool.app"), directoryHint: .isDirectory))
    }

    /// 同一个 App 的不同 URL 写法（结尾斜杠、`..`）得到同一个 URL，加入时才能去重
    @Test
    func differentSpellingsOfSameAppGiveSameURL() {
        let spellings = [
            "/System/Applications/Chess.app",
            "/System/Applications/Utilities/../Chess.app/",
        ]

        let urls: [URL?] = spellings.map {
            let item = FolderItem(url: URL(filePath: $0), title: nil)

            guard case .app(let app) = item else { return nil }

            return app.url
        }

        let chess = URL(filePath: "/System/Applications/Chess.app/")

        #expect(urls == [chess, chess])
    }

    /// 访达里的文件夹是文件，按目录 URL 记录：点击时交给访达打开
    @Test
    func finderFolderIsFile() {
        let item = FolderItem(url: URL(filePath: path(of: "资料")), title: nil)

        guard case .file(let file) = item else {
            Issue.record("访达里的文件夹应当是文件：\(String(describing: item))")
            return
        }

        #expect(file.url == URL(filePath: path(of: "资料"), directoryHint: .isDirectory))
    }

    /// 卷的根目录同样是文件，按目录 URL 记录
    @Test
    func volumeRootIsFile() {
        let item = FolderItem(url: URL(filePath: "/"), title: nil)

        guard case .file(let file) = item else {
            Issue.record("卷的根目录应当是文件：\(String(describing: item))")
            return
        }

        #expect(file.url == URL(filePath: "/", directoryHint: .isDirectory))
    }

    /// 不存在的路径不接收
    @Test
    func missingPathIsRejected() {
        let url = URL(filePath: path(of: "不存在的文件.txt"))

        #expect(FolderItem(url: url, title: nil) == nil)
    }

    /// 新建的文件项带着书签，书签解析回的正是这个文件：文件移动或改名后才能据此找到它
    @Test
    func newFileCarriesBookmarkToItself() throws {
        let item = FolderItem(url: directory.appending(path: "报告.txt"), title: nil)

        guard case .file(let file) = item else {
            Issue.record("普通文件应当是文件：\(String(describing: item))")
            return
        }

        let bookmark = try #require(file.bookmark)
        var isStale = false

        let resolvedURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        // 书签解析出的是 `/private/var` 这类解析过符号链接的写法，按解析后的路径比较
        #expect(
            resolvedURL.resolvingSymlinksInPath().path(percentEncoded: false)
                == file.url.resolvingSymlinksInPath().path(percentEncoded: false)
        )
        #expect(!isStale)
    }

    // MARK: 网址

    /// `http` 与 `https` 网址是网页，带上浏览器给出的标题
    @Test(arguments: [
        "http://example.com/",
        "https://example.com/path?query=1",
    ])
    func httpAndHTTPSAreWebPages(address: String) throws {
        let url = try #require(URL(string: address))
        let item = FolderItem(url: url, title: "Example Domain")

        guard case .webPage(let webPage) = item else {
            Issue.record("网址应当是网页：\(String(describing: item))")
            return
        }

        #expect(webPage.url == url)
        #expect(webPage.title == "Example Domain")
    }

    /// 标题去掉首尾空白；只有空白或空串时视为没有标题
    @Test(arguments: [
        ("  Example Domain\n", "Example Domain"),
        (" \n\t", nil),
        ("", nil),
    ] as [(String, String?)])
    func webPageTitleIsTrimmed(title: String, expected: String?) throws {
        let url = try #require(URL(string: "https://example.com/"))

        guard case .webPage(let webPage) = FolderItem(url: url, title: title) else {
            Issue.record("网址应当是网页")
            return
        }

        #expect(webPage.title == expected)
    }

    /// `http`、`https` 以外的网址不接收
    @Test(arguments: [
        "ftp://example.com/file.txt",
        "mailto:someone@example.com",
    ])
    func otherSchemesAreRejected(address: String) throws {
        let url = try #require(URL(string: address))

        #expect(FolderItem(url: url, title: "标题") == nil)
    }

    /// 临时目录里某一项的 POSIX 路径
    private func path(of name: String) -> String {
        directory.appending(path: name).path(percentEncoded: false)
    }
}
