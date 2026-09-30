import Foundation
import Testing

@testable import Flotilla

// MARK: - FinderFolderContentsTests

/// 访达里的文件夹在面板里展开时读出的内容：顺序与访达“名称”一致，隐藏文件不出现，
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

    /// 以 `.` 开头的隐藏文件被跳过
    @Test
    func skipsHiddenFiles() throws {
        try writeFile(".DS_Store")
        try writeFile("报告.txt")

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder())

        #expect(names(of: items) == ["报告.txt"])
    }

    /// 按显示名以 `localizedStandardCompare` 排序：`a2` 在 `a10` 前，不区分大小写
    @Test
    func sortsLikeFinderName() throws {
        for name in ["B.txt", "a10.txt", "a2.txt"] {
            try writeFile(name)
        }

        var contents = FinderFolderContents()
        let items = try contents.items(of: finderFolder())

        #expect(names(of: items) == ["a2.txt", "a10.txt", "B.txt"])
    }

    /// App bundle 是 App；访达里的文件夹、文件包、普通文件与指向目录的符号链接都是文件，只有访达里的文件夹能继续进入
    @Test
    func classifiesEachEntry() throws {
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
        let items = try contents.items(of: finderFolder())

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
        let items = try contents.items(of: finderFolder())

        // 逐项单独读取：各自读显示名、规整 URL、判断是不是 App
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        let expected = try urls
            .map { url in
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
        let first = try contents.items(of: folder).map(\.id)
        let second = try contents.items(of: folder).map(\.id)

        var nextExpansion = FinderFolderContents()
        let third = try nextExpansion.items(of: folder).map(\.id)

        #expect(first == second)
        #expect(first != third)
    }

    /// 目录已删除时读不出内容
    @Test
    func deletedDirectoryThrows() throws {
        let folder = try finderFolder()

        try FileManager.default.removeItem(at: directory)

        var contents = FinderFolderContents()

        #expect(throws: (any Error).self) {
            try contents.items(of: folder)
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
