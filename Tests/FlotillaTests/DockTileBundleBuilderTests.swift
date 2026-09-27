import AppKit
import Testing

@testable import Flotilla

// MARK: - DockTileBundleBuilderTests

/// stub bundle 的目录结构、Info.plist 内容与按需改写：Dock 与 Launch Services 按这些约定识别并启动 stub
///
/// 放在主线程串行执行：并发栅格化同一个 App 图标时，偶尔会画出不同的像素
@MainActor
final class DockTileBundleBuilderTests {
    /// 本用例独占的临时目录，充当 stub 目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(
            path: "FlotillaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

    /// 以系统自带的 `true` 代替 stub 可执行文件：它是可以重新签名的真实 Mach-O
    private let builder: DockTileBundleBuilder

    /// 用作图标预览的系统 App
    private let apps = ["Calculator", "Chess"].map {
        FolderItem.app(AppReference(
            id: UUID(),
            url: URL(filePath: "/System/Applications/\($0).app")
        ))
    }

    /// 创建指向临时目录的 stub 生成器
    init() {
        builder = DockTileBundleBuilder(
            directory: directory,
            executableURL: URL(filePath: "/usr/bin/true")
        )
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// stub 位于 `<目录>/<id>/<文件夹名>.app`，包含 Info.plist、可执行文件、图标与自定义图标，并且签名有效
    @Test
    func writeCreatesSignedBundle() throws {
        let folder = makeFolder(name: "工作")
        let changed = try builder.write(folder: folder, icon: makeIcon(for: folder))

        let bundleURL = directory.appending(path: "\(folder.id.uuidString)/工作.app")
        let relativePaths = [
            "Contents/Info.plist",
            "Contents/MacOS/FlotillaDockTile",
            "Contents/Resources/Icon.icns",
            "Icon\r",
        ]

        let builtURL = builder.bundleURL(for: folder).standardizedFileURL

        #expect(changed)
        #expect(builtURL == bundleURL.standardizedFileURL)

        for relativePath in relativePaths {
            let fileURL = bundleURL.appending(path: relativePath)

            #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        }

        // 自定义图标位于 bundle 根目录，只能通过不带 `--strict` 的校验
        try CommandRunner.run(
            "/usr/bin/codesign",
            arguments: ["--verify", bundleURL.path(percentEncoded: false)]
        )
    }

    /// Info.plist 让 stub 成为不出现在 Dock 与切换器里的后台 App，并带上 stub 拼 URL 所需的根文件夹 id
    @Test
    func infoDescribesBackgroundStub() throws {
        let folder = makeFolder(name: "工作")
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        let info = try readInfo(of: folder)
        let id = folder.id.uuidString

        #expect(info["CFBundleExecutable"] as? String == "FlotillaDockTile")
        #expect(info["CFBundleIdentifier"] as? String == "com.rakuyo.flotilla.tile.\(id)")
        #expect(info["CFBundleName"] as? String == "工作")
        #expect(info["CFBundleDisplayName"] as? String == "工作")
        #expect(info["CFBundleIconFile"] as? String == "Icon")
        #expect(info["CFBundlePackageType"] as? String == "APPL")
        #expect(info["CFBundleInfoDictionaryVersion"] as? String == "6.0")
        #expect(info["LSMinimumSystemVersion"] as? String == "15.0")
        #expect(info["LSUIElement"] as? Bool ?? false)
        #expect(info["LSBackgroundOnly"] as? Bool ?? false)
        #expect(info["FlotillaFolderID"] as? String == id)
    }

    /// 名称与图标都没变时不改写：每次改写都可能触发 Dock 重启
    @Test
    func unchangedFolderIsNotRewritten() throws {
        let folder = makeFolder(name: "工作")
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        #expect(try !builder.write(folder: folder, icon: makeIcon(for: folder)))
    }

    /// 缺少可执行文件或自定义图标的 stub 即使名称与图标没变也要补全，否则 Dock 上的 tile 点不开或图标不对
    @Test(arguments: ["Contents/MacOS/FlotillaDockTile", "Icon\r"])
    func incompleteBundleIsRewritten(missingPath: String) throws {
        let folder = makeFolder(name: "工作")
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        let missingURL = builder.bundleURL(for: folder).appending(path: missingPath)
        try FileManager.default.removeItem(at: missingURL)

        #expect(try builder.write(folder: folder, icon: makeIcon(for: folder)))
        #expect(FileManager.default.fileExists(atPath: missingURL.path(percentEncoded: false)))
    }

    /// 重命名后 bundle 在原目录里改名，Info.plist 中的名称随之改写：Dock 按 bundle 的文件名显示 tile 的名称
    @Test
    func renameMovesBundleAndRewritesInfo() throws {
        var folder = makeFolder(name: "工作")
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        let originalURL = builder.bundleURL(for: folder)

        folder.name = "日常"
        let changed = try builder.write(folder: folder, icon: makeIcon(for: folder))

        let info = try readInfo(of: folder)
        let renamedURL = builder.bundleURL(for: folder)

        #expect(changed)
        #expect(renamedURL.lastPathComponent == "日常.app")
        #expect(builder.existingBundleURL(for: folder.id)?.lastPathComponent == "日常.app")
        #expect(!FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
        #expect(info["CFBundleName"] as? String == "日常")
        #expect(info["CFBundleDisplayName"] as? String == "日常")
    }

    /// 只改大小写的重命名同样生效：卷宗通常不区分大小写，新旧路径指向同一个文件
    @Test
    func caseOnlyRenameMovesBundle() throws {
        var folder = makeFolder(name: "work")
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        folder.name = "Work"
        try builder.write(folder: folder, icon: makeIcon(for: folder))

        #expect(builder.existingBundleURL(for: folder.id)?.lastPathComponent == "Work.app")
    }

    /// 名称里的 `/` 在文件名里写成 `:`，Launch Services 显示时换回 `/`；空名称用 id 作文件名
    @Test
    func fileNameEscapesSlashAndFallsBackToID() {
        let slashed = makeFolder(name: "工作/学习")
        let unnamed = makeFolder(name: "")
        let unnamedFileName = builder.bundleURL(for: unnamed).lastPathComponent

        #expect(builder.bundleURL(for: slashed).lastPathComponent == "工作:学习.app")
        #expect(unnamedFileName == "\(unnamed.id.uuidString).app")
    }

    /// 预览数量变化让图标变化时，改写图标
    @Test
    func iconChangeRewritesIcon() throws {
        let folder = makeFolder(name: "工作")
        let iconURL = builder.bundleURL(for: folder)
            .appending(path: "Contents/Resources/Icon.icns")

        try builder.write(folder: folder, icon: makeIcon(for: folder))
        let original = try Data(contentsOf: iconURL)

        let changed = try builder.write(
            folder: folder,
            icon: makeIcon(for: folder, previewIconCount: 0)
        )

        #expect(changed)
        #expect(try Data(contentsOf: iconURL) != original)
    }

    /// 只列出以根文件夹 id 命名的目录；删除后连同目录一起消失，目录已不存在时再删不报错
    @Test
    func existingFolderIDsTracksWritesAndRemovals() throws {
        let first = makeFolder(name: "工作")
        let second = makeFolder(name: "娱乐")

        try builder.write(folder: first, icon: makeIcon(for: first))
        try builder.write(folder: second, icon: makeIcon(for: second))

        // 目录里混入无关的文件与目录
        try Data().write(to: directory.appending(path: "notes.txt"))
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Other.app"),
            withIntermediateDirectories: true
        )

        #expect(builder.existingFolderIDs() == [first.id, second.id])

        try builder.remove(folderID: first.id)

        let removedPath = directory
            .appending(path: first.id.uuidString)
            .path(percentEncoded: false)

        #expect(builder.existingFolderIDs() == [second.id])
        #expect(builder.existingBundleURL(for: first.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: removedPath))

        // 对账删掉 Dock 上残留的 tile 后，会对目录早已不存在的根文件夹再删一次 stub，不能报错
        #expect(throws: Never.self) {
            try builder.remove(folderID: first.id)
        }
    }

    /// AX 给出的 tile URL 以 `/` 结尾：解析出所属根文件夹；不在 stub 目录结构里的 URL 一律不认
    @Test
    func folderIDIsParsedFromBundleURL() {
        let folderID = UUID()
        let tileURL = URL(
            string: "\(directory.absoluteString)\(folderID.uuidString)/%E5%B7%A5%E4%BD%9C.app/"
        )

        let foreignURLs = [
            URL(filePath: "/Applications/Calculator.app"),
            directory.appending(path: "\(folderID.uuidString).app"),
            directory.appending(path: "\(folderID.uuidString)/Icon.icns"),
            directory.appending(path: "notes/工作.app"),
        ]

        #expect(tileURL.flatMap { builder.folderID(forBundleURL: $0) } == folderID)

        for url in foreignURLs {
            #expect(builder.folderID(forBundleURL: url) == nil)
        }
    }

    /// 构造包含两个 App 的根文件夹
    private func makeFolder(name: String) -> Folder {
        Folder(id: UUID(), name: name, items: apps)
    }

    /// 读取文件夹对应 stub 的 Info.plist
    private func readInfo(of folder: Folder) throws -> [String: Any] {
        let infoURL = builder.bundleURL(for: folder).appending(path: "Contents/Info.plist")

        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoURL),
            format: nil
        )

        return try #require(plist as? [String: Any])
    }

    /// 按需求 2 渲染文件夹图标
    private func makeIcon(for folder: Folder, previewIconCount: Int = 4) -> NSImage {
        FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: 512,
            appearance: .light
        )
    }
}
