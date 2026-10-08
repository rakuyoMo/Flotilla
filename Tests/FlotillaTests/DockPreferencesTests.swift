import Foundation
import Testing

@testable import Flotilla

// MARK: - DockPreferencesTests

/// Dock 偏好的条目构造、增删改与备份：Dock 里还有用户自己的 tile，Flotilla 只能动自己的条目
@MainActor
final class DockPreferencesTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(
            path: "FlotillaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

    /// 以临时目录下的绝对路径充当 Dock 偏好的域
    private let domainName: String

    /// 直接读写该域，用于布置初始条目与检查结果
    private let defaults: UserDefaults

    /// 被测对象
    private let preferences: DockPreferences

    /// 本用例的 stub 所在的目录，每个根文件夹独占一个
    private let stubDirectory: URL

    /// 本用例的 stub 位置，路径里带空格，检验 URL 编码与标准化
    private let tileURL: URL

    /// 用户自己的 “计算器” tile，带有 Dock 补全的字段
    private let calculatorTile: [String: Any] = [
        "GUID": 685_773_939,
        "tile-data": [
            "book": Data([1, 2, 3]),
            "bundle-identifier": "com.apple.calculator",
            "file-data": [
                "_CFURLString": "file:///System/Applications/Calculator.app/",
                "_CFURLStringType": 15,
            ],
            "file-label": "计算器",
            "file-type": 41,
        ],
        "tile-type": "file-tile",
    ]

    /// 创建指向临时域与临时备份目录的被测对象
    init() throws {
        domainName = directory.appending(path: "dock").path(percentEncoded: false)
        defaults = try #require(UserDefaults(suiteName: domainName))

        preferences = try #require(
            DockPreferences(
                domainName: domainName,
                backupDirectory: directory.appending(path: "Backups")
            )
        )

        stubDirectory = directory.appending(
            path: "Dock Tiles/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        tileURL = stubDirectory.appending(path: "工作.app")
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 条目字段与 Dock 为 App 写出的结构一致：URL 以 `/` 结尾且经过百分号编码，不带 `book`
    @Test
    func tileEntryMatchesDockFormat() throws {
        let entry = DockPreferences.tileEntry(tileURL: tileURL, label: "工作", guid: 42)

        let tileData = try #require(entry["tile-data"] as? [String: Any])
        let fileData = try #require(tileData["file-data"] as? [String: Any])

        let stubPath = stubDirectory.path(percentEncoded: true)
        let expectedURL = "file://\(stubPath)%E5%B7%A5%E4%BD%9C.app/"

        #expect(entry["GUID"] as? Int == 42)
        #expect(entry["tile-type"] as? String == "file-tile")
        #expect(tileData["file-label"] as? String == "工作")
        #expect(tileData["file-type"] as? Int == 41)
        #expect(tileData["book"] == nil)
        #expect(fileData["_CFURLString"] as? String == expectedURL)
        #expect(fileData["_CFURLStringType"] as? Int == 15)
    }

    /// 新 tile 追加在末尾，已有的 tile 原样保留；GUID 是 32 位正整数
    @Test
    func addAppendsAfterExistingTiles() throws {
        defaults.set([calculatorTile], forKey: "persistent-apps")

        try preferences.add(tileURL: tileURL, label: "工作")

        let tiles = storedTiles()
        let guid = try #require(tiles.last?["GUID"] as? Int)

        #expect(tiles.count == 2)
        #expect(try plistData(tiles[0]) == plistData(calculatorTile))
        #expect((1 ... Int(UInt32.max)).contains(guid))
        #expect(label(of: tiles[1]) == "工作")
    }

    /// 按标准化后 URL 的所在目录匹配：有无结尾斜杠、路径里多余的 `.` 都视为同一个 stub；改名后的 stub 仍能找到原来的 tile
    @Test
    func containsMatchesStubDirectory() throws {
        try preferences.add(tileURL: tileURL, label: "工作")

        let variant = directory.appending(
            path: "Dock Tiles/./\(stubDirectory.lastPathComponent)/工作.app/"
        )
        let renamed = stubDirectory.appending(path: "日常.app")
        let other = directory.appending(path: "Dock Tiles/Other/工作.app")

        #expect(preferences.contains(tileURL: tileURL))
        #expect(preferences.contains(tileURL: variant))
        #expect(preferences.contains(tileURL: renamed))
        #expect(!preferences.contains(tileURL: other))
    }

    /// 只改名称时条目原地替换：位置与 GUID 不变，Dock 补全的字段保留
    @Test
    func updateLabelReplacesInPlace() throws {
        try addOwnTileBetweenUserTiles()

        let originalGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        #expect(try preferences.update(tileURL: tileURL, label: "日常", isStubRewritten: false))
        #expect(try !preferences.update(tileURL: tileURL, label: "日常", isStubRewritten: false))

        let updated = storedTiles()
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])

        #expect(updated.count == 3)
        #expect(updated[1]["GUID"] as? Int == originalGUID)
        #expect(label(of: updated[1]) == "日常")
        #expect(updatedTileData["book"] as? Data == Data([9, 9]))
        #expect(label(of: updated[0]) == "计算器")
        #expect(label(of: updated[2]) == "计算器")
    }

    /// stub 改名后条目原地指向新位置，并删掉指向旧位置的书签，其余字段保留
    @Test
    func updateURLReplacesInPlaceAndDropsBookmark() throws {
        try addOwnTileBetweenUserTiles()

        let renamed = stubDirectory.appending(path: "日常.app")

        #expect(try preferences.update(tileURL: renamed, label: "日常", isStubRewritten: false))
        #expect(try !preferences.update(tileURL: renamed, label: "日常", isStubRewritten: false))

        let updated = storedTiles()
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])
        let fileData = try #require(updatedTileData["file-data"] as? [String: Any])

        let stubPath = stubDirectory.path(percentEncoded: true)
        let expectedURL = "file://\(stubPath)%E6%97%A5%E5%B8%B8.app/"

        #expect(updated.count == 3)
        #expect(label(of: updated[1]) == "日常")
        #expect(updatedTileData["book"] == nil)
        #expect(updatedTileData["bundle-identifier"] as? String == "com.rakuyo.flotilla.tile.test")
        #expect(fileData["_CFURLString"] as? String == expectedURL)
    }

    /// stub 改写过时条目原地换一个新的 GUID：Dock 按 GUID 缓存 tile 图标，GUID 不变就一直显示旧图标
    @Test
    func updateRenewsGUIDAfterStubRewrite() throws {
        try addOwnTileBetweenUserTiles()

        let originalGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        #expect(try preferences.update(tileURL: tileURL, label: "工作", isStubRewritten: true))

        let updated = storedTiles()
        let renewedGUID = try #require(updated[1]["GUID"] as? Int)
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])

        #expect(updated.count == 3)
        #expect(renewedGUID != originalGUID)
        #expect((1 ... Int(UInt32.max)).contains(renewedGUID))
        #expect(label(of: updated[1]) == "工作")
        #expect(updatedTileData["book"] as? Data == Data([9, 9]))

        // 用户的 tile 一个字段都不变
        #expect(try plistData(updated[0]) == plistData(calculatorTile))
        #expect(try plistData(updated[2]) == plistData(calculatorTile))
    }

    /// Dock 被终止时把旧 GUID 写回、盖掉刚换上的新 GUID：下一次更新发现条目的 GUID 不是自己写入的值，再换一个新的并要求重启 Dock；
    /// 之后 GUID 没有再被改动时不再改条目
    @Test
    func updateRenewsGUIDAgainAfterDockRevertsIt() throws {
        try addOwnTileBetweenUserTiles()

        let originalGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        try preferences.update(tileURL: tileURL, label: "工作", isStubRewritten: true)
        let renewedGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        // 模拟被终止的 Dock 写回启动时读到的旧条目
        var tiles = storedTiles()
        tiles[1]["GUID"] = originalGUID
        defaults.set(tiles, forKey: "persistent-apps")

        #expect(try preferences.update(tileURL: tileURL, label: "工作", isStubRewritten: false))

        let latestGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        #expect(latestGUID != originalGUID)
        #expect(latestGUID != renewedGUID)
        #expect(try !preferences.update(tileURL: tileURL, label: "工作", isStubRewritten: false))
    }

    /// 本次运行没有写过 GUID 的 tile（上次运行留下的）：条目里的 GUID 是什么都不算被写回，不动条目
    @Test
    func updateLeavesUnknownGUIDAlone() throws {
        defaults.set(
            [DockPreferences.tileEntry(tileURL: tileURL, label: "工作", guid: 7)],
            forKey: "persistent-apps"
        )

        #expect(try !preferences.update(tileURL: tileURL, label: "工作", isStubRewritten: false))
        #expect(storedTiles()[0]["GUID"] as? Int == 7)
    }

    /// 删除只按 stub 所在的目录匹配：与 Flotilla 的 tile 同名的用户 tile 不受影响
    @Test
    func removeDeletesOnlyMatchingTile() throws {
        var namesake = calculatorTile
        var namesakeData = try #require(namesake["tile-data"] as? [String: Any])
        namesakeData["file-label"] = "工作"
        namesake["tile-data"] = namesakeData

        defaults.set([namesake], forKey: "persistent-apps")

        try preferences.add(tileURL: tileURL, label: "工作")

        #expect(try preferences.remove(tileDirectory: stubDirectory))
        #expect(try !preferences.remove(tileDirectory: stubDirectory))

        let tiles = storedTiles()

        #expect(tiles.count == 1)
        #expect(try plistData(tiles[0]) == plistData(namesake))
    }

    /// 用户在访达里删掉了 stub bundle、只剩下它的目录：按目录仍能删掉 Dock 上失效的条目，用户的 tile 一个字段都不变
    @Test
    func removeByDirectoryWithoutStubBundle() throws {
        try addOwnTileBetweenUserTiles()

        try FileManager.default.createDirectory(
            at: stubDirectory,
            withIntermediateDirectories: true
        )

        let stubPath = tileURL.path(percentEncoded: false)

        #expect(!FileManager.default.fileExists(atPath: stubPath))
        #expect(try preferences.remove(tileDirectory: stubDirectory))

        let tiles = storedTiles()

        #expect(tiles.count == 2)
        #expect(try plistData(tiles[0]) == plistData(calculatorTile))
        #expect(try plistData(tiles[1]) == plistData(calculatorTile))
    }

    /// 只列出 stub 位于存放 stub 的目录下 `<id>` 子目录的 tile，stub 连同目录都不在磁盘上时照样列出；
    /// 同步时据此删掉残留的 tile，用户的 tile 与位置不符的条目一律不能列出
    @Test
    func folderIDsListsOnlyTilesInStubsDirectory() throws {
        let stubsDirectory = directory.appending(path: "Dock Tiles")
        let ownID = try #require(UUID(uuidString: stubDirectory.lastPathComponent))
        let orphanID = UUID()

        let ownURLs = [
            tileURL,
            stubsDirectory.appending(path: "\(orphanID.uuidString)/日常.app"),
        ]

        // 子目录名不是 UUID、层级不对、目录名只是前缀相同或位于其它目录的条目
        let foreignURLs = [
            stubsDirectory.appending(path: "Other/工作.app"),
            stubsDirectory.appending(path: "工作.app"),
            stubsDirectory.appending(path: "\(UUID().uuidString)/Nested/工作.app"),
            directory.appending(path: "Dock Tiles 2/\(UUID().uuidString)/工作.app"),
            directory.appending(path: "Elsewhere/\(UUID().uuidString)/工作.app"),
        ]

        let entries = (ownURLs + foreignURLs).map {
            DockPreferences.tileEntry(tileURL: $0, label: "工作", guid: 42)
        }

        defaults.set([calculatorTile] + entries, forKey: "persistent-apps")

        let stubsPath = stubsDirectory.path(percentEncoded: false)

        #expect(!FileManager.default.fileExists(atPath: stubsPath))
        #expect(preferences.folderIDs(ofTilesIn: stubsDirectory) == [ownID, orphanID])
    }

    /// 首次写入前导出改动前的整个域，同一次运行里只备份一次
    @Test
    func firstWriteBacksUpOriginalDomain() throws {
        defaults.set([calculatorTile], forKey: "persistent-apps")
        defaults.set(true, forKey: "autohide")

        try preferences.add(tileURL: tileURL, label: "工作")
        try preferences.update(tileURL: tileURL, label: "日常", isStubRewritten: false)

        let backups = try backupFiles()
        let backupURL = try #require(backups.first)
        let backup = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: backupURL),
            format: nil
        )

        let domain = try #require(backup as? [String: Any])
        let tiles = try #require(domain["persistent-apps"] as? [[String: Any]])
        let backupName = backupURL.lastPathComponent

        #expect(backups.count == 1)
        #expect(backupName.wholeMatch(of: /com\.apple\.dock-\d{8}-\d{6}\.plist/) != nil)
        #expect(domain["autohide"] as? Bool ?? false)
        #expect(tiles.count == 1)
    }

    /// 备份最多保留 5 份，超出时删掉最旧的
    @Test
    func backupsAreCappedAtFive() throws {
        let backupDirectory = directory.appending(path: "Backups")

        try FileManager.default.createDirectory(
            at: backupDirectory,
            withIntermediateDirectories: true
        )

        // 先放 6 份更早的备份
        let oldNames = (1 ... 6).map { "com.apple.dock-2020010\($0)-000000.plist" }

        for name in oldNames {
            try Data().write(to: backupDirectory.appending(path: name))
        }

        try preferences.add(tileURL: tileURL, label: "工作")

        let names = try backupFiles().map(\.lastPathComponent)
        let newest = try #require(names.last)

        #expect(names.count == 5)
        #expect(Array(names.prefix(4)) == Array(oldNames.suffix(4)))
        #expect(!newest.hasPrefix("com.apple.dock-2020"))
    }
}

// MARK: - Apply

extension DockPreferencesTests {
    /// 被终止的 Dock 把启动时读到的旧条目写回，盖掉了刚写入的改名、换新的 GUID、新增与删除：
    /// 按同一份期望再应用一次，要把它们全部改回来，并报告偏好有改动（据此判断新 Dock 是否读到）；
    /// 之后再应用不再改动，Dock 不会被反复重启
    @Test
    func applyRestoresExpectationAfterDockWritesBackOldEntries() throws {
        try addOwnTileBetweenUserTiles()

        let staleDirectory = directory.appending(
            path: "Dock Tiles/\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

        try preferences.add(tileURL: staleDirectory.appending(path: "旧.app"), label: "旧")

        let launchTiles = storedTiles()
        let launchGUID = try #require(launchTiles[1]["GUID"] as? Int)

        let renamed = stubDirectory.appending(path: "日常.app")
        let newTileURL = directory.appending(path: "Dock Tiles/\(UUID().uuidString)/新.app")

        let expectedTiles = [
            ExpectedDockTile(tileURL: renamed, label: "日常", canAdd: true),
            ExpectedDockTile(tileURL: newTileURL, label: "新", canAdd: true),
        ]

        let isWritten = try preferences.apply(
            expectedTiles,
            rewrittenTileURLs: [renamed],
            removingTilesIn: [staleDirectory]
        )

        let writtenGUID = try #require(storedTiles()[1]["GUID"] as? Int)

        // 模拟被终止的 Dock 写回启动时读到的全部条目
        defaults.set(launchTiles, forKey: "persistent-apps")

        let isRewritten = try preferences.apply(
            expectedTiles,
            rewrittenTileURLs: [],
            removingTilesIn: [staleDirectory]
        )

        let tiles = storedTiles()
        let restoredGUID = try #require(tiles[1]["GUID"] as? Int)

        #expect(isWritten)
        #expect(isRewritten)
        #expect(tiles.map { label(of: $0) } == ["计算器", "日常", "计算器", "新"])
        #expect(preferences.contains(tileURL: renamed))
        #expect(!preferences.contains(tileURL: staleDirectory.appending(path: "旧.app")))
        #expect(restoredGUID != launchGUID)
        #expect(restoredGUID != writtenGUID)
        #expect(try plistData(tiles[0]) == plistData(calculatorTile))

        #expect(
            try !preferences.apply(
                expectedTiles,
                rewrittenTileURLs: [],
                removingTilesIn: [staleDirectory]
            )
        )
    }

    /// Dock 没有写回时再应用同一份期望不改动偏好：重启 Dock 后的核对不会凭空补写、再重启一次
    @Test
    func applyWithoutWriteBackChangesNothing() throws {
        try addOwnTileBetweenUserTiles()

        let expectedTiles = [ExpectedDockTile(tileURL: tileURL, label: "日常", canAdd: true)]

        let isWritten = try preferences.apply(
            expectedTiles,
            rewrittenTileURLs: [tileURL],
            removingTilesIn: []
        )

        let written = try plistData(storedTiles()[1])

        let isRewritten = try preferences.apply(
            expectedTiles,
            rewrittenTileURLs: [],
            removingTilesIn: []
        )

        #expect(isWritten)
        #expect(!isRewritten)
        #expect(try plistData(storedTiles()[1]) == written)
    }

    /// 不在 Dock 上、又不能添加的 tile 是被用户拖出去的：不加回，偏好不改动
    @Test
    func applyDoesNotAddTileThatCannotBeAdded() throws {
        defaults.set([calculatorTile], forKey: "persistent-apps")

        let isChanged = try preferences.apply(
            [ExpectedDockTile(tileURL: tileURL, label: "工作", canAdd: false)],
            rewrittenTileURLs: [tileURL],
            removingTilesIn: []
        )

        #expect(!isChanged)
        #expect(storedTiles().count == 1)
    }
}

// MARK: - Relaunched Dock

extension DockPreferencesTests {
    /// 补写完成时新 Dock 还没启动，或完成得早于它启动后 `relaunchReadDelay`：
    /// 新 Dock 一定读到补写，不必再重启
    @Test
    func rewriteBeforeRelaunchedDockReadsIsRead() {
        let launch = Date()
        let readDelay = DockPreferences.relaunchReadDelay

        let isReadWithoutDock = DockPreferences.isReadByRelaunchedDock(
            writtenAt: launch,
            dockLaunchedAt: nil
        )

        let isReadBeforeLaunch = DockPreferences.isReadByRelaunchedDock(
            writtenAt: launch.addingTimeInterval(-0.01),
            dockLaunchedAt: launch
        )

        let isReadWithinDelay = DockPreferences.isReadByRelaunchedDock(
            writtenAt: launch.addingTimeInterval(readDelay / 2),
            dockLaunchedAt: launch
        )

        #expect(isReadWithoutDock)
        #expect(isReadBeforeLaunch)
        #expect(isReadWithinDelay)
    }

    /// 补写完成得不早于新 Dock 启动后 `relaunchReadDelay`：
    /// 新 Dock 可能已读到被写回的旧条目，要再重启一次
    @Test
    func rewriteAfterReadDelayIsNotRead() {
        let launch = Date()
        let readDelay = DockPreferences.relaunchReadDelay

        let isReadAtDelay = DockPreferences.isReadByRelaunchedDock(
            writtenAt: launch.addingTimeInterval(readDelay),
            dockLaunchedAt: launch
        )

        let isReadLater = DockPreferences.isReadByRelaunchedDock(
            writtenAt: launch.addingTimeInterval(readDelay + 1),
            dockLaunchedAt: launch
        )

        #expect(!isReadAtDelay)
        #expect(!isReadLater)
    }
}

// MARK: - Private

extension DockPreferencesTests {
    /// 布置三个条目：用户 tile、本用例的 tile、用户 tile，
    /// 并模拟 Dock 重启后为本用例的 tile 补全的字段
    private func addOwnTileBetweenUserTiles() throws {
        defaults.set([calculatorTile], forKey: "persistent-apps")

        try preferences.add(tileURL: tileURL, label: "工作")

        var tiles = storedTiles()
        var ownTileData = try #require(tiles[1]["tile-data"] as? [String: Any])
        ownTileData["book"] = Data([9, 9])
        ownTileData["bundle-identifier"] = "com.rakuyo.flotilla.tile.test"

        tiles[1]["tile-data"] = ownTileData
        tiles.append(calculatorTile)

        defaults.set(tiles, forKey: "persistent-apps")
    }

    /// 读出测试域里的全部条目
    private func storedTiles() -> [[String: Any]] {
        defaults.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
    }

    /// 条目的名称
    private func label(of tile: [String: Any]) -> String? {
        (tile["tile-data"] as? [String: Any])?["file-label"] as? String
    }

    /// 把条目序列化成 XML 属性列表，用于比较两个条目的全部字段
    private func plistData(_ tile: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: tile, format: .xml, options: 0)
    }

    /// 备份目录里的文件，按文件名排序
    private func backupFiles() throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(
                at: directory.appending(path: "Backups"),
                includingPropertiesForKeys: nil
            )
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
