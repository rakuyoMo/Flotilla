import Foundation
import Testing

@testable import Flotilla

// MARK: - DockPreferencesTests

/// Dock 偏好的条目构造、增删改与备份：Dock 里还有用户自己的 tile，Flotilla 只能动自己的条目
@MainActor
final class DockPreferencesTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)", directoryHint: .isDirectory)

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

    /// 用户自己的“计算器” tile，带有 Dock 补全的字段
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

        stubDirectory = directory.appending(path: "Dock Tiles/\(UUID().uuidString)", directoryHint: .isDirectory)
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
        let expectedURL = "file://\(stubDirectory.path(percentEncoded: true))%E5%B7%A5%E4%BD%9C.app/"

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

        let variant = directory.appending(path: "Dock Tiles/./\(stubDirectory.lastPathComponent)/工作.app/")
        let renamed = stubDirectory.appending(path: "日常.app")

        #expect(preferences.contains(tileURL: tileURL))
        #expect(preferences.contains(tileURL: variant))
        #expect(preferences.contains(tileURL: renamed))
        #expect(!preferences.contains(tileURL: directory.appending(path: "Dock Tiles/Other/工作.app")))
    }

    /// 只改名称时条目原地替换：位置不变，Dock 补全的字段保留
    @Test
    func updateLabelReplacesInPlace() throws {
        try addOwnTileBetweenUserTiles()

        #expect(try preferences.update(tileURL: tileURL, label: "日常"))
        #expect(try !preferences.update(tileURL: tileURL, label: "日常"))

        let updated = storedTiles()
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])

        #expect(updated.count == 3)
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

        #expect(try preferences.update(tileURL: renamed, label: "日常"))
        #expect(try !preferences.update(tileURL: renamed, label: "日常"))

        let updated = storedTiles()
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])
        let fileData = try #require(updatedTileData["file-data"] as? [String: Any])
        let expectedURL = "file://\(stubDirectory.path(percentEncoded: true))%E6%97%A5%E5%B8%B8.app/"

        #expect(updated.count == 3)
        #expect(label(of: updated[1]) == "日常")
        #expect(updatedTileData["book"] == nil)
        #expect(updatedTileData["bundle-identifier"] as? String == "com.rakuyo.flotilla.tile.test")
        #expect(fileData["_CFURLString"] as? String == expectedURL)
    }

    /// 删除只按 URL 匹配：与 Flotilla 的 tile 同名的用户 tile 不受影响
    @Test
    func removeDeletesOnlyMatchingTile() throws {
        var namesake = calculatorTile
        var namesakeData = try #require(namesake["tile-data"] as? [String: Any])
        namesakeData["file-label"] = "工作"
        namesake["tile-data"] = namesakeData
        defaults.set([namesake], forKey: "persistent-apps")

        try preferences.add(tileURL: tileURL, label: "工作")

        #expect(try preferences.remove(tileURL: tileURL))
        #expect(try !preferences.remove(tileURL: tileURL))

        let tiles = storedTiles()

        #expect(tiles.count == 1)
        #expect(try plistData(tiles[0]) == plistData(namesake))
    }

    /// 首次写入前导出改动前的整个域，同一次运行里只备份一次
    @Test
    func firstWriteBacksUpOriginalDomain() throws {
        defaults.set([calculatorTile], forKey: "persistent-apps")
        defaults.set(true, forKey: "autohide")

        try preferences.add(tileURL: tileURL, label: "工作")
        try preferences.update(tileURL: tileURL, label: "日常")

        let backups = try backupFiles()
        let backupURL = try #require(backups.first)
        let backup = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: backupURL),
            format: nil
        )
        let domain = try #require(backup as? [String: Any])
        let tiles = try #require(domain["persistent-apps"] as? [[String: Any]])

        #expect(backups.count == 1)
        #expect(backupURL.lastPathComponent.wholeMatch(of: /com\.apple\.dock-\d{8}-\d{6}\.plist/) != nil)
        #expect(domain["autohide"] as? Bool ?? false)
        #expect(tiles.count == 1)
    }

    /// 备份最多保留 5 份，超出时删掉最旧的
    @Test
    func backupsAreCappedAtFive() throws {
        let backupDirectory = directory.appending(path: "Backups")
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

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

    /// 布置 [用户 tile, 本用例的 tile, 用户 tile]，并模拟 Dock 重启后为本用例的 tile 补全的字段
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
