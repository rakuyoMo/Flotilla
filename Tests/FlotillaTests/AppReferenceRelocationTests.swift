import Foundation
import Testing

@testable import Flotilla

// MARK: - AppReferenceRelocationTests

/// App 更新之后，组里的这一项仍要打开装好的那一份：刷新恰好落在 “旧版本已挪走、新版本还没放进来” 的空档里时，
/// 这一项不能跟进废纸篓，也不能停在之后被删掉的旧版本上；文件仍跟进废纸篓，用户还能从那里打开它
///
/// Launch Services 的查询换成假实现：临时目录里的 bundle 不一定登记得上。
/// 废纸篓用真的：临时目录里自造的废纸篓不被认作废纸篓，用例结束时删掉自己放进去的项
final class AppReferenceRelocationTests {
    /// 假 App 的 bundle id
    static let bundleIdentifier = "com.example.FlotillaTests.Tool"

    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例移进废纸篓的项，用例结束时删除
    private var trashedURLs: [URL] = []

    /// 建好临时目录
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 删除本用例的临时目录与移进废纸篓的项
    deinit {
        for url in trashedURLs {
            try? FileManager.default.removeItem(at: url)
        }

        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 更新的空档

    /// 刷新落在空档里、旧版本在废纸篓：这一项不跟进去；新版本放回原路径后记录的仍是原路径，
    /// 书签按新版本重建，之后新版本再移动，跟着新版本走
    @Test
    func staysOffTrashedOldVersion() throws {
        let original = try addApp()

        try moveToTrash("Tool.app")

        #expect(original.relocatedApp { _ in nil } == nil)

        try writeBundle("Tool.app")

        let updated = try #require(original.relocatedApp { _ in nil })

        #expect(updated.id == original.id)
        #expect(updated.url == original.url)
        #expect(updated.bookmark != original.bookmark)

        try move("Tool.app", to: "Tool 2.app")

        #expect(updated.relocatedApp { _ in nil }?.url == directoryURL(of: "Tool 2.app"))
    }

    /// 刷新落在空档里、旧版本挪到临时目录：先跟过去；旧版本删掉后，按 bundle id 跟回装好的新版本，
    /// 书签按新版本建，之后新版本再移动，跟着新版本走
    @Test
    func recoversNewVersionAfterStagedOldVersionIsDeleted() throws {
        let original = try addApp()

        // 更新器先把旧版本挪进暂存目录
        try createDirectory("暂存")
        try move("Tool.app", to: "暂存/Tool.app")

        let staged = try #require(original.relocatedApp { _ in nil })

        #expect(staged.url == directoryURL(of: "暂存/Tool.app"))

        // 新版本装回原路径，暂存的旧版本随即删掉
        try writeBundle("Tool.app")
        try FileManager.default.removeItem(at: directory.appending(path: "暂存/Tool.app"))

        let recovered = try #require(
            staged.relocatedApp(applicationURL: installedApp(at: "Tool.app"))
        )

        #expect(recovered.id == original.id)
        #expect(recovered.url == original.url)

        try move("Tool.app", to: "Tool 2.app")

        #expect(recovered.relocatedApp { _ in nil }?.url == directoryURL(of: "Tool 2.app"))
    }

    /// Flotilla 没运行期间 App 先被原地更新、又被移动，旧版本还在废纸篓：书签只找得到旧版本，按 bundle id 找到新版本的新位置
    @Test
    func findsMovedNewVersionWhileOldVersionIsInTrash() throws {
        let original = try addApp()

        try moveToTrash("Tool.app")
        try writeBundle("Tool.app")
        try createDirectory("应用程序")
        try move("Tool.app", to: "应用程序/Tool.app")

        let relocated = try #require(
            original.relocatedApp(applicationURL: installedApp(at: "应用程序/Tool.app"))
        )

        #expect(relocated.id == original.id)
        #expect(relocated.url == directoryURL(of: "应用程序/Tool.app"))
    }

    /// Launch Services 给不出、给出的在废纸篓里或已不存在：这一项保持原样，不提交
    @Test
    func staysUnchangedWithoutUsableInstalledApp() throws {
        let original = try addApp()
        let trashedURL = try moveToTrash("Tool.app")
        let missingURL = directoryURL(of: "不存在.app")

        #expect(original.relocatedApp { _ in nil } == nil)
        #expect(original.relocatedApp { _ in trashedURL } == nil)
        #expect(original.relocatedApp { _ in missingURL } == nil)
    }

    /// App 还在原处时什么都不改，也不问 Launch Services：每次刷新都会走到这里
    @Test
    func unchangedAppDoesNotAskLaunchServices() throws {
        let original = try addApp()

        let relocated = original.relocatedApp { (_: String) -> URL? in
            Issue.record("App 还在原处时不该问 Launch Services")
            return nil
        }

        #expect(relocated == nil)
    }

    // MARK: 卷

    /// App 所在的卷没挂载时，别处装着同一个 bundle id 的另一份也不跟过去：这一项保持原样，
    /// 卷挂回来后照常按书签解析到原路径
    ///
    /// 临时目录里卸不下卷：删掉 App 让书签解析失败、原路径上没有东西，卷没挂载由假的判断给出
    @Test
    func staysOnAppOfUnmountedVolume() throws {
        let original = try addApp()

        try createDirectory("应用程序")
        try writeBundle("应用程序/Tool.app")
        try FileManager.default.removeItem(at: directory.appending(path: "Tool.app"))

        let unmounted = original.relocatedApp(
            applicationURL: installedApp(at: "应用程序/Tool.app"),
            isVolumeMounted: { _ in false }
        )

        #expect(unmounted == nil)

        // 卷挂回来：原路径上又有了这个 App
        try writeBundle("Tool.app")

        // 真的卷挂回来时是同一个 App，记录不变（返回 nil）；这里放回的是新的 bundle，书签按它重建，位置仍是原路径
        let remounted = original.relocatedApp { (_: String) -> URL? in
            Issue.record("书签解析得到 App 时不该问 Launch Services")
            return nil
        } ?? original

        #expect(remounted.id == original.id)
        #expect(remounted.url == original.url)
    }

    /// 卷挂着、原路径上的 App 被删掉：按 bundle id 找回别处装着的那一份；卷是否挂载用真的判断，
    /// 临时目录所在的启动卷必须判为挂载着，否则启动卷上的 App 都找不回
    @Test
    func recoversDeletedAppOnMountedVolume() throws {
        let original = try addApp()
        let bookmark = try #require(original.bookmark)

        try createDirectory("应用程序")
        try writeBundle("应用程序/Tool.app")
        try FileManager.default.removeItem(at: directory.appending(path: "Tool.app"))

        #expect(AppReference.isVolumeMounted(recordedIn: bookmark))

        let recovered = try #require(
            original.relocatedApp(applicationURL: installedApp(at: "应用程序/Tool.app"))
        )

        #expect(recovered.id == original.id)
        #expect(recovered.url == directoryURL(of: "应用程序/Tool.app"))
    }

    // MARK: bundle id

    /// 没有 bundle id 的旧数据，App 还在原处时补上，位置与书签不变；补上之后再刷新什么都不改
    @Test
    func legacyAppGainsBundleIdentifier() throws {
        let added = try addApp()

        let legacy = AppReference(
            id: added.id,
            url: added.url,
            bookmark: added.bookmark,
            bundleIdentifier: nil
        )

        let filled = try #require(legacy.relocatedApp { _ in nil })

        #expect(filled.url == legacy.url)
        #expect(filled.bookmark == legacy.bookmark)
        #expect(filled.bundleIdentifier == Self.bundleIdentifier)
        #expect(filled.relocatedApp { _ in nil } == nil)
    }

    /// 没有书签也没有东西在原路径上的旧数据，有 bundle id 时同样按 bundle id 找回，并按新位置建书签
    @Test
    func legacyAppWithoutBookmarkRecoversByBundleIdentifier() throws {
        try createDirectory("应用程序")
        try writeBundle("应用程序/Tool.app")

        let legacy = AppReference(
            id: UUID(),
            url: directoryURL(of: "Tool.app"),
            bookmark: nil,
            bundleIdentifier: Self.bundleIdentifier
        )

        let recovered = try #require(
            legacy.relocatedApp(applicationURL: installedApp(at: "应用程序/Tool.app"))
        )

        #expect(recovered.id == legacy.id)
        #expect(recovered.url == directoryURL(of: "应用程序/Tool.app"))
        #expect(recovered.bookmark != nil)
    }

    /// 跟到新位置时按新位置重读 bundle id；新位置上读不到时沿用原来的
    @Test
    func followingRereadsBundleIdentifier() throws {
        let original = try addApp()

        try move("Tool.app", to: "Tool 2.app")
        try writeBundle("Tool 2.app", bundleIdentifier: "com.example.FlotillaTests.Tool2")

        let renamed = try #require(original.relocatedApp { _ in nil })

        #expect(renamed.bundleIdentifier == "com.example.FlotillaTests.Tool2")

        try move("Tool 2.app", to: "Tool 3.app")
        try FileManager.default.removeItem(
            at: directory.appending(path: "Tool 3.app/Contents/Info.plist")
        )

        let unreadable = try #require(renamed.relocatedApp { _ in nil })

        #expect(unreadable.url == directoryURL(of: "Tool 3.app"))
        #expect(unreadable.bundleIdentifier == "com.example.FlotillaTests.Tool2")
    }

    // MARK: 文件

    /// 文件移进废纸篓仍跟过去：用户还能从废纸篓里打开它
    @Test
    func fileFollowsIntoTrash() throws {
        try Data("报告".utf8).write(to: directory.appending(path: "报告.txt"))

        let item = try #require(GroupItem(url: directory.appending(path: "报告.txt"), title: nil))

        guard case .file(let file) = item else {
            Issue.record("应当是文件：\(item)")
            return
        }

        let trashedURL = try moveToTrash("报告.txt")
        let relocated = try #require(file.relocated())

        #expect(
            relocated.url.resolvingSymlinksInPath().path(percentEncoded: false)
                == trashedURL.resolvingSymlinksInPath().path(percentEncoded: false)
        )
    }
}

// MARK: - Bundles

extension AppReferenceRelocationTests {
    /// 在 `url` 处写出一个最小的 App bundle：`Contents/Info.plist` 里带着 bundle id
    /// - Parameters:
    ///   - url: bundle 的位置，已存在时只改写 `Info.plist`
    ///   - bundleIdentifier: 写进 `CFBundleIdentifier` 的值
    static func writeBundle(at url: URL, bundleIdentifier: String) throws {
        let contents = url.appending(path: "Contents", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        let infoDictionary: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundlePackageType": "APPL",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: infoDictionary,
            format: .xml,
            options: 0
        )

        try data.write(to: contents.appending(path: "Info.plist"))
    }
}

// MARK: - Private

extension AppReferenceRelocationTests {
    /// 项是 App 时返回它的引用
    private static func appReference(of item: GroupItem) -> AppReference? {
        guard case .app(let app) = item else { return nil }

        return app
    }

    /// 在临时目录里写出 Tool.app，经分类后作为 App 加入，返回加入的 App 项
    private func addApp() throws -> AppReference {
        try writeBundle("Tool.app")

        let item = try #require(GroupItem(url: directory.appending(path: "Tool.app"), title: nil))

        return try #require(Self.appReference(of: item), "应当是 App")
    }

    /// 在临时目录里写出 App bundle
    /// - Parameters:
    ///   - name: bundle 在临时目录里的相对路径
    ///   - bundleIdentifier: 写进 `CFBundleIdentifier` 的值，默认是本用例的 bundle id
    private func writeBundle(
        _ name: String,
        bundleIdentifier: String = AppReferenceRelocationTests.bundleIdentifier
    ) throws {
        try Self.writeBundle(
            at: directory.appending(path: name, directoryHint: .isDirectory),
            bundleIdentifier: bundleIdentifier
        )
    }

    /// 假的 Launch Services：问本用例的 bundle id 时给出临时目录里的 `name`，问别的给不出
    private func installedApp(at name: String) -> (String) -> URL? {
        let url = directoryURL(of: name)

        return { $0 == Self.bundleIdentifier ? url : nil }
    }

    /// 把临时目录里的一项移进废纸篓，返回它在废纸篓里的位置
    @discardableResult
    private func moveToTrash(_ name: String) throws -> URL {
        // `trashItem` 只按 `NSURL` 交回在废纸篓里的位置
        // swiftlint:disable:next legacy_objc_type
        var resultingURL: NSURL?

        try FileManager.default.trashItem(
            at: directory.appending(path: name),
            resultingItemURL: &resultingURL
        )

        let trashedURL = try #require(resultingURL as URL?)
        trashedURLs.append(trashedURL)

        return trashedURL
    }

    /// 在临时目录里新建目录
    private func createDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: directory.appending(path: name),
            withIntermediateDirectories: true
        )
    }

    /// 在临时目录里移动或改名
    private func move(_ source: String, to destination: String) throws {
        try FileManager.default.moveItem(
            at: directory.appending(path: source),
            to: directory.appending(path: destination)
        )
    }

    /// 临时目录里某个目录的目录 URL，与分类后记录的写法一致
    private func directoryURL(of name: String) -> URL {
        URL(
            filePath: directory.appending(path: name).path(percentEncoded: false),
            directoryHint: .isDirectory
        )
    }
}
