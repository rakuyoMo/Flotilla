import Foundation
import Testing

@testable import Flotilla

// MARK: - FinderFolderContentsTests

/// 访达里的文件夹在面板里展开时读出的内容：顺序与访达“名称”一致，隐藏文件按设置跳过或标为隐藏，
/// 每一项的身份决定点击后是启动、继续进入还是打开；同一次展开里 id 不变，返回时才找得到缩回的图标
final class FinderFolderContentsTests {
    /// 本用例独占的临时目录，作为被展开的访达里的文件夹
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 建好临时目录
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 默认不显示隐藏文件：以 `.` 开头的文件与目录、带 `hidden` 标志的文件都被跳过
    @Test
    func skipsHiddenFiles() throws {
        try writeHiddenEntries()
        try writeFile("报告.txt")

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder(), includingHiddenFiles: false)

        #expect(names(of: items) == ["报告.txt"])
        #expect(contents.hiddenItemIDs.isEmpty)
    }

    /// 显示隐藏文件时与访达的 ⌘⇧. 一致：以 `.` 开头的文件与目录、带 `hidden` 标志的文件都读出来并标为隐藏，
    /// 面板据此把它们画成半透明；`.DS_Store` 与 `.localized` 仍不显示。关掉之后再读，又被跳过
    @Test
    func showsHiddenFilesWhenAsked() throws {
        try writeHiddenEntries()
        try writeFile("报告.txt")

        let folder = try finderFolder()
        var contents = FinderFolderContents()

        let items = try contents.items(of: folder, includingHiddenFiles: true)
        let hiddenItems = items.filter { contents.hiddenItemIDs.contains($0.id) }

        #expect(Set(names(of: items)) == [".隐藏.txt", ".隐藏目录", "标志.txt", "报告.txt"])
        #expect(Set(names(of: hiddenItems)) == [".隐藏.txt", ".隐藏目录", "标志.txt"])

        let skipped = try contents.items(of: folder, includingHiddenFiles: false)

        #expect(names(of: skipped) == ["报告.txt"])
    }

    /// 按显示名以 `localizedStandardCompare` 排序：`a2` 在 `a10` 前，不区分大小写
    @Test
    func sortsLikeFinderName() throws {
        for name in ["B.txt", "a10.txt", "a2.txt"] {
            try writeFile(name)
        }

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder(), includingHiddenFiles: false)

        #expect(names(of: items) == ["a2.txt", "a10.txt", "B.txt"])
    }

    /// App bundle 是 App；访达里的文件夹、文件包、普通文件与指向目录的符号链接都是文件，只有访达里的文件夹能继续进入
    @Test
    func classifiesEachEntry() throws {
        // 每种身份各布置一个：App、访达里的文件夹、文件包、普通文件、指向目录的符号链接
        for name in ["Tool.app", "资料", "笔记.rtfd"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: name),
                withIntermediateDirectories: true
            )
        }

        try writeFile("报告.txt")

        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "链接"),
            withDestinationURL: directory.appending(path: "资料")
        )

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder(), includingHiddenFiles: false)

        // 分别挑出 App 与能继续进入的访达里的文件夹
        let apps = items.compactMap { item -> String? in
            guard case .app(let app) = item else { return nil }

            return app.url.lastPathComponent
        }

        let finderFolders = items.compactMap { item -> String? in
            guard case .file(let file) = item, file.isFinderFolder else { return nil }

            return file.url.lastPathComponent
        }

        #expect(apps == ["Tool.app"])
        #expect(finderFolders == ["资料"])
        #expect(Set(names(of: items)) == ["资料", "笔记.rtfd", "报告.txt", "链接"])
    }

    /// 读目录时一次取齐的属性与逐项单独读取的结果一致：顺序按 `FileManager.displayName(atPath:)`，
    /// URL 按 `normalizedURL(_:)` 规整，App 的判断相同
    ///
    /// “Tool.app”与“Tool 2.app”按文件名排序与按显示名（“Tool”“Tool 2”）排序正好相反；
    /// 隐藏了扩展名的文件、名称里的“:”（访达里显示为“/”）的显示名也都不同于文件名
    @Test
    func matchesPerEntryLookups() throws {
        for name in ["Tool.app", "Tool 2.app", "资料", "笔记.rtfd"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: name),
                withIntermediateDirectories: true
            )
        }

        for name in ["报告.txt", "a:1.txt", "隐藏扩展名.txt", "noext"] {
            try writeFile(name)
        }

        var hiddenExtension = URLResourceValues()
        hiddenExtension.hasHiddenExtension = true

        var hiddenExtensionURL = directory.appending(path: "隐藏扩展名.txt")
        try hiddenExtensionURL.setResourceValues(hiddenExtension)

        try FileManager.default.createSymbolicLink(
            at: directory.appending(path: "链接"),
            withDestinationURL: directory.appending(path: "资料")
        )

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder(), includingHiddenFiles: false)

        // 逐项单独读取：各自读显示名、规整 URL、判断是不是 App
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let expected = try urls
            .map { url -> (name: String, url: URL, isApp: Bool) in
                let normalizedURL = try #require(FileReference.normalizedURL(url))

                return (
                    name: FileManager.default.displayName(atPath: url.path(percentEncoded: false)),
                    url: normalizedURL,
                    isApp: AppReference.isApplicationBundle(normalizedURL)
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        #expect(items.compactMap(url(of:)) == expected.map(\.url))
        #expect(items.map(isApp(_:)) == expected.map(\.isApp))
    }

    /// 同一次展开里再读同一个目录，各项的 id 不变；另一次展开重新分配
    @Test
    func keepsItemIDsWithinOneExpansion() throws {
        try writeFile("报告.txt")

        let folder = try finderFolder()

        var contents = FinderFolderContents()
        let first = try contents.items(of: folder, includingHiddenFiles: false).map(\.id)
        let second = try contents.items(of: folder, includingHiddenFiles: false).map(\.id)

        var nextExpansion = FinderFolderContents()
        let third = try nextExpansion.items(of: folder, includingHiddenFiles: false).map(\.id)

        #expect(first == second)
        #expect(first != third)
    }

    /// 目录已删除时读不出内容：抛出错误，面板据此交给访达打开并收起
    @Test
    func deletedDirectoryThrows() throws {
        let folder = try finderFolder()

        try FileManager.default.removeItem(at: directory)

        var contents = FinderFolderContents()

        #expect(throws: (any Error).self) {
            try contents.items(of: folder, includingHiddenFiles: false)
        }
    }
}

// MARK: - Private

extension FinderFolderContentsTests {
    /// 临时目录本身经分类后成为的文件项
    private func finderFolder() throws -> FileReference {
        let item = FolderItem(url: directory, title: nil)
        let file: FileReference? = if case .file(let file) = item { file } else { nil }

        return try #require(file, "访达里的文件夹应当是文件：\(String(describing: item))")
    }

    /// 在临时目录里写一个文件
    private func writeFile(_ name: String) throws {
        try Data(name.utf8).write(to: directory.appending(path: name))
    }

    /// 在临时目录里写出各种隐藏项：以 `.` 开头的文件与目录、带 `hidden` 标志的文件，
    /// 以及访达显示隐藏文件时仍不显示的 `.DS_Store` 与 `.localized`
    private func writeHiddenEntries() throws {
        for name in [".隐藏.txt", ".DS_Store", ".localized", "标志.txt"] {
            try writeFile(name)
        }

        try FileManager.default.createDirectory(
            at: directory.appending(path: ".隐藏目录"),
            withIntermediateDirectories: true
        )

        // 名称普通、只带 `hidden` 标志的文件
        var flaggedURL = directory.appending(path: "标志.txt")
        var values = URLResourceValues()
        values.isHidden = true

        try flaggedURL.setResourceValues(values)
    }

    /// 一项的 URL；目录里读出的只有 App 与文件
    private func url(of item: FolderItem) -> URL? {
        switch item {
        case .app(let app):
            app.url

        case .file(let file):
            file.url

        case .folder, .webPage:
            nil
        }
    }

    /// 一项是不是 App
    private func isApp(_ item: FolderItem) -> Bool {
        guard case .app = item else { return false }

        return true
    }

    /// 各文件项的文件名，App 不算
    private func names(of items: [FolderItem]) -> [String] {
        items.compactMap {
            guard case .file(let file) = $0 else { return nil }

            return file.url.lastPathComponent
        }
    }
}
