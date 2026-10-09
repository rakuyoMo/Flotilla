import AppKit
import CoreServices
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
        GroupItem.app(AppReference(
            id: UUID(),
            url: URL(filePath: "/System/Applications/\($0).app"),
            bookmark: nil,
            bundleIdentifier: nil
        ))
    }

    /// 创建指向临时目录的 stub 生成器
    init() {
        builder = DockTileBundleBuilder(
            directory: directory,
            executableURL: URL(filePath: "/usr/bin/true")
        )
    }

    /// 注销本用例生成的 stub，再删除临时目录
    ///
    /// 每次改写 stub 都会向 Launch Services 注册；实测不注销就删除，Launch Services 里会留下指向已删路径的记录
    deinit {
        let groupDirectories = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for groupDirectory in groupDirectories {
            Self.unregisterStubs(in: groupDirectory)
        }

        try? FileManager.default.removeItem(at: directory)
    }

    /// stub 位于 `<目录>/<id>/<组名>.app`，包含 Info.plist、可执行文件、图标与自定义图标，并且签名有效
    @Test
    func writeCreatesSignedBundle() throws {
        let group = makeGroup(name: "工作")
        let changed = try builder.write(group: group, icon: makeIcon(for: group))

        let bundleURL = directory.appending(path: "\(group.id.uuidString)/工作.app")
        let relativePaths = [
            "Contents/Info.plist",
            "Contents/MacOS/FlotillaDockTile",
            "Contents/Resources/Icon.icns",
            "Icon\r",
        ]

        let builtURL = builder.bundleURL(for: group).standardizedFileURL

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

    /// Info.plist 让 stub 成为不出现在 Dock 与切换器里的后台 App，并带上 stub 拼 URL 所需的根组 id
    @Test
    func infoDescribesBackgroundStub() throws {
        let group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        let info = try readInfo(of: group)
        let id = group.id.uuidString

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

    /// Info.plist 声明 stub 能打开 App 与文件：从访达把它们拖到 tile 上时，Dock 才把 tile 当作放置目标；
    /// App 一项排位为 `Alternate`，stub 不会成为 App 的默认打开方式；文件一项排位为 `None`，
    /// `Alternate` 会让 stub 出现在访达的 “打开方式” 里
    @Test
    func infoDeclaresApplicationAndFileDocumentTypes() throws {
        let group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        let info = try readInfo(of: group)
        let documentTypes = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])

        try #require(documentTypes.count == 2)

        let application = documentTypes[0]

        #expect(application["CFBundleTypeName"] as? String == "Application")
        #expect(application["CFBundleTypeRole"] as? String == "Viewer")
        #expect(application["LSHandlerRank"] as? String == "Alternate")

        #expect(
            application["LSItemContentTypes"] as? [String]
                == ["com.apple.application", "com.apple.application-bundle"]
        )

        let file = documentTypes[1]

        #expect(file["CFBundleTypeName"] as? String == "File")
        #expect(file["CFBundleTypeRole"] as? String == "Viewer")
        #expect(file["LSHandlerRank"] as? String == "None")
        #expect(file["LSItemContentTypes"] as? [String] == ["public.data", "com.apple.package"])
    }

    /// 已被 Launch Services 记录的 stub 改写 Info.plist 后重新注册：随即按改写后的文档类型判断，能接收 App 与文件
    ///
    /// 实测不重新注册时，Launch Services 一直按旧记录判断，App 拖不到 tile 上
    @Test
    func rewrittenStubIsReregistered() throws {
        let group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        let stubURL = builder.bundleURL(for: group)
        let chessURL = URL(filePath: "/System/Applications/Chess.app")

        // 让 Launch Services 先记下一份没有文档类型的 Info.plist
        var info = try readInfo(of: group)
        info["CFBundleDocumentTypes"] = nil

        try PropertyListSerialization
            .data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: stubURL.appending(path: "Contents/Info.plist"))

        try CommandRunner.run(
            DockTileBundleBuilder.lsregisterPath,
            arguments: ["-f", stubURL.path(percentEncoded: false)]
        )

        let hostsURL = URL(filePath: "/etc/hosts")

        #expect(try !canAccept(chessURL, stubURL: stubURL))
        #expect(try !canAccept(hostsURL, stubURL: stubURL))

        try builder.write(group: group, icon: makeIcon(for: group))

        #expect(try canAccept(chessURL, stubURL: stubURL))
        #expect(try canAccept(hostsURL, stubURL: stubURL))
    }

    /// 名称与图标都没变时不改写：每次改写都可能触发 Dock 重启
    @Test
    func unchangedGroupIsNotRewritten() throws {
        let group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        #expect(try !builder.write(group: group, icon: makeIcon(for: group)))
    }

    /// 缺少可执行文件或自定义图标的 stub 即使名称与图标没变也要补全，否则 Dock 上的 tile 点不开或图标不对
    @Test(arguments: ["Contents/MacOS/FlotillaDockTile", "Icon\r"])
    func incompleteBundleIsRewritten(missingPath: String) throws {
        let group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        let missingURL = builder.bundleURL(for: group).appending(path: missingPath)
        try FileManager.default.removeItem(at: missingURL)

        #expect(try builder.write(group: group, icon: makeIcon(for: group)))
        #expect(FileManager.default.fileExists(atPath: missingURL.path(percentEncoded: false)))
    }

    /// 重命名后 bundle 在原目录里改名，Info.plist 中的名称随之改写：Dock 按 bundle 的文件名显示 tile 的名称
    @Test
    func renameMovesBundleAndRewritesInfo() throws {
        var group = makeGroup(name: "工作")
        try builder.write(group: group, icon: makeIcon(for: group))

        let originalURL = builder.bundleURL(for: group)

        group.name = "日常"
        let changed = try builder.write(group: group, icon: makeIcon(for: group))

        let info = try readInfo(of: group)
        let renamedURL = builder.bundleURL(for: group)

        #expect(changed)
        #expect(renamedURL.lastPathComponent == "日常.app")
        #expect(builder.existingBundleURL(for: group.id)?.lastPathComponent == "日常.app")
        #expect(!FileManager.default.fileExists(atPath: originalURL.path(percentEncoded: false)))
        #expect(info["CFBundleName"] as? String == "日常")
        #expect(info["CFBundleDisplayName"] as? String == "日常")
    }

    /// 只改大小写的重命名同样生效：卷通常不区分大小写，新旧路径指向同一个文件
    @Test
    func caseOnlyRenameMovesBundle() throws {
        var group = makeGroup(name: "work")
        try builder.write(group: group, icon: makeIcon(for: group))

        group.name = "Work"
        try builder.write(group: group, icon: makeIcon(for: group))

        #expect(builder.existingBundleURL(for: group.id)?.lastPathComponent == "Work.app")
    }

    /// 名称里的 `/` 在文件名里写成 `:`，Launch Services 显示时换回 `/`；空名称用 id 作文件名
    @Test
    func fileNameEscapesSlashAndFallsBackToID() {
        let slashed = makeGroup(name: "工作/学习")
        let unnamed = makeGroup(name: "")
        let unnamedFileName = builder.bundleURL(for: unnamed).lastPathComponent

        #expect(builder.bundleURL(for: slashed).lastPathComponent == "工作:学习.app")
        #expect(unnamedFileName == "\(unnamed.id.uuidString).app")
    }

    /// 预览数量变化让图标变化时，改写图标：Dock 上 tile 显示的就是 stub 的图标
    @Test
    func iconChangeRewritesIcon() throws {
        let group = makeGroup(name: "工作")
        let iconURL = builder.bundleURL(for: group)
            .appending(path: "Contents/Resources/Icon.icns")

        try builder.write(group: group, icon: makeIcon(for: group))
        let original = try Data(contentsOf: iconURL)

        let changed = try builder.write(
            group: group,
            icon: makeIcon(for: group, previewIconCount: 0)
        )

        #expect(changed)
        #expect(try Data(contentsOf: iconURL) != original)
    }

    /// 只列出以根组 id 命名的目录；删除后连同目录一起消失，目录已不存在时再删不报错
    @Test
    func existingGroupIDsTracksWritesAndRemovals() throws {
        let first = makeGroup(name: "工作")
        let second = makeGroup(name: "娱乐")

        try builder.write(group: first, icon: makeIcon(for: first))
        try builder.write(group: second, icon: makeIcon(for: second))

        // 目录里混入无关的文件与目录
        try Data().write(to: directory.appending(path: "notes.txt"))
        try FileManager.default.createDirectory(
            at: directory.appending(path: "Other.app"),
            withIntermediateDirectories: true
        )

        #expect(builder.existingGroupIDs() == [first.id, second.id])

        try builder.remove(groupID: first.id)

        let removedPath = directory
            .appending(path: first.id.uuidString)
            .path(percentEncoded: false)

        #expect(builder.existingGroupIDs() == [second.id])
        #expect(builder.existingBundleURL(for: first.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: removedPath))

        // 同步时删掉 Dock 上残留的 tile 后，会对目录早已不存在的根组再删一次 stub，不能报错
        #expect(throws: Never.self) {
            try builder.remove(groupID: first.id)
        }
    }

    /// AX 给出的 tile URL 以 `/` 结尾：解析出所属根组；不在 stub 目录结构里的 URL 一律不认
    @Test
    func groupIDIsParsedFromBundleURL() {
        let groupID = UUID()
        let tileURL = URL(
            string: "\(directory.absoluteString)\(groupID.uuidString)/%E5%B7%A5%E4%BD%9C.app/"
        )

        let foreignURLs = [
            URL(filePath: "/Applications/Calculator.app"),
            directory.appending(path: "\(groupID.uuidString).app"),
            directory.appending(path: "\(groupID.uuidString)/Icon.icns"),
            directory.appending(path: "notes/工作.app"),
        ]

        #expect(tileURL.flatMap { builder.groupID(forBundleURL: $0) } == groupID)

        for url in foreignURLs {
            #expect(builder.groupID(forBundleURL: url) == nil)
        }
    }

    /// 构造包含两个 App 的根组
    private func makeGroup(name: String) -> Group {
        Group(id: UUID(), name: name, items: apps)
    }

    /// 读取组对应 stub 的 Info.plist
    private func readInfo(of group: Group) throws -> [String: Any] {
        let infoURL = builder.bundleURL(for: group).appending(path: "Contents/Info.plist")

        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoURL),
            format: nil
        )

        return try #require(plist as? [String: Any])
    }

    /// 按需求 2 渲染组图标
    private func makeIcon(for group: Group, previewIconCount: Int = 4) -> NSImage {
        GroupIconRenderer.render(
            group: group,
            previewIconCount: previewIconCount,
            pointSize: 512,
            appearance: .light
        )
    }

    /// Launch Services 是否认为 stub 能打开该项
    private func canAccept(_ itemURL: URL, stubURL: URL) throws -> Bool {
        var accepts = DarwinBoolean(false)

        let status = LSCanURLAcceptURL(
            itemURL as CFURL,
            stubURL as CFURL,
            .all,
            .acceptDefault,
            &accepts
        )

        try #require(status == noErr)

        return accepts.boolValue
    }
}

// MARK: - Web Page Title

extension DockTileBundleBuilderTests {
    /// 网页补上标题不改写 stub：标题不在 Info.plist 里，也不改变图标；不改写，Dock 就不必为它重启
    @Test
    func webPageTitleDoesNotRewriteStub() throws {
        let url = try #require(URL(string: "https://example.com/"))
        let webPageID = UUID()
        var group = makeGroup(name: "工作")

        group.items.append(.webPage(WebPageReference(id: webPageID, url: url, title: nil)))
        try builder.write(group: group, icon: makeIcon(for: group))

        group.items[group.items.count - 1] = .webPage(
            WebPageReference(id: webPageID, url: url, title: "Example Domain")
        )

        #expect(try !builder.write(group: group, icon: makeIcon(for: group)))
    }
}

// MARK: - Private

extension DockTileBundleBuilderTests {
    /// 注销根组目录里的 stub 在 Launch Services 里的注册
    private nonisolated static func unregisterStubs(in groupDirectory: URL) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: groupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []

        for bundleURL in urls where bundleURL.pathExtension == "app" {
            try? CommandRunner.run(
                DockTileBundleBuilder.lsregisterPath,
                arguments: ["-u", bundleURL.path(percentEncoded: false)]
            )
        }
    }
}
