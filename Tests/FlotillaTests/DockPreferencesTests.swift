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

    /// 本用例的 stub 位置，路径里带空格，检验 URL 编码与标准化
    private let tileURL: URL

    /// 用户自己的“下载”文件夹 tile，带有 Dock 补全的字段
    private let downloadsTile: [String: Any] = [
        "GUID": 685_773_939,
        "tile-data": [
            "arrangement": 2,
            "book": Data([1, 2, 3]),
            "file-data": [
                "_CFURLString": "file:///Users/test/Downloads/",
                "_CFURLStringType": 15,
            ],
            "file-label": "下载",
            "file-type": 2,
        ],
        "tile-type": "directory-tile",
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

        tileURL = directory.appending(path: "Dock Tiles/\(UUID().uuidString).app")
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
        let expectedURL = "file://\(directory.path(percentEncoded: true))Dock%20Tiles/\(tileURL.lastPathComponent)/"

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
        defaults.set([downloadsTile], forKey: "persistent-others")

        try preferences.add(tileURL: tileURL, label: "工作")

        let tiles = storedTiles()
        let guid = try #require(tiles.last?["GUID"] as? Int)

        #expect(tiles.count == 2)
        #expect(try plistData(tiles[0]) == plistData(downloadsTile))
        #expect((1 ... Int(UInt32.max)).contains(guid))
        #expect(label(of: tiles[1]) == "工作")
    }

    /// 按标准化后的 URL 匹配：有无结尾斜杠、路径里多余的 `.` 都视为同一个 stub
    @Test
    func containsMatchesNormalizedURL() throws {
        try preferences.add(tileURL: tileURL, label: "工作")

        let variant = directory.appending(path: "Dock Tiles/./\(tileURL.lastPathComponent)/")

        #expect(preferences.contains(tileURL: tileURL))
        #expect(preferences.contains(tileURL: variant))
        #expect(!preferences.contains(tileURL: directory.appending(path: "Other.app")))
    }

    /// 改名时条目原地替换：位置不变，Dock 补全的字段保留
    @Test
    func updateLabelReplacesInPlace() throws {
        defaults.set([downloadsTile], forKey: "persistent-others")
        try preferences.add(tileURL: tileURL, label: "工作")

        // 模拟 Dock 重启后补全字段，并在我们的 tile 后面还有用户的 tile
        var tiles = storedTiles()
        var ownTileData = try #require(tiles[1]["tile-data"] as? [String: Any])
        ownTileData["book"] = Data([9, 9])
        tiles[1]["tile-data"] = ownTileData
        tiles.append(downloadsTile)
        defaults.set(tiles, forKey: "persistent-others")

        #expect(try preferences.updateLabel(tileURL: tileURL, label: "日常"))
        #expect(try !preferences.updateLabel(tileURL: tileURL, label: "日常"))

        let updated = storedTiles()
        let updatedTileData = try #require(updated[1]["tile-data"] as? [String: Any])

        #expect(updated.count == 3)
        #expect(label(of: updated[1]) == "日常")
        #expect(updatedTileData["book"] as? Data == Data([9, 9]))
        #expect(label(of: updated[0]) == "下载")
        #expect(label(of: updated[2]) == "下载")
    }

    /// 删除只按 URL 匹配：与 Flotilla 的 tile 同名的用户 tile 不受影响
    @Test
    func removeDeletesOnlyMatchingTile() throws {
        var namesake = downloadsTile
        var namesakeData = try #require(namesake["tile-data"] as? [String: Any])
        namesakeData["file-label"] = "工作"
        namesake["tile-data"] = namesakeData
        defaults.set([namesake], forKey: "persistent-others")

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
        defaults.set([downloadsTile], forKey: "persistent-others")
        defaults.set(true, forKey: "autohide")

        try preferences.add(tileURL: tileURL, label: "工作")
        try preferences.updateLabel(tileURL: tileURL, label: "日常")

        let backups = try backupFiles()
        let backupURL = try #require(backups.first)
        let backup = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: backupURL),
            format: nil
        )
        let domain = try #require(backup as? [String: Any])
        let tiles = try #require(domain["persistent-others"] as? [[String: Any]])

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

    /// 读出测试域里的全部条目
    private func storedTiles() -> [[String: Any]] {
        defaults.array(forKey: "persistent-others") as? [[String: Any]] ?? []
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
