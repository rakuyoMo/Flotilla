import AppKit
import os

// MARK: - DockPreferences

/// 读写 Dock 偏好（`com.apple.dock`）：增删 Flotilla 的 tile，并重启 Dock 让改动生效
///
/// 只动 URL 指向 stub 的条目，其它 tile 与 Dock 的其它偏好一律不碰
@MainActor
final class DockPreferences {
    /// Dock 偏好的域名，同时是 Dock 进程的 bundle identifier
    nonisolated static let dockDomain = "com.apple.dock"

    /// App 使用的备份目录：`~/Library/Application Support/Flotilla/Backups`
    nonisolated static let defaultBackupDirectory = URL.applicationSupportDirectory
        .appending(path: "Flotilla/Backups", directoryHint: .isDirectory)

    /// tile 所在的区域：Dock 左侧的 App 区域
    ///
    /// 实测（macOS 27）这里的 stub 条目在 Dock 重启后保留，显示自定义图标与条目名称，点击即启动 stub
    private static let sectionKey = "persistent-apps"

    /// 备份最多保留的份数
    private static let maximumBackupCount = 5

    /// 备份文件名的前缀，完整文件名为 `com.apple.dock-<yyyyMMdd-HHmmss>.plist`
    private static let backupPrefix = "com.apple.dock-"

    /// Dock 偏好相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockPreferences"
    )

    /// 读写偏好的 `UserDefaults`
    private let defaults: UserDefaults

    /// 偏好所在的域，备份时按它导出全部内容
    private let domainName: String

    /// 存放备份的目录
    private let backupDirectory: URL

    /// 本次运行是否已经备份过：每次运行只在首次写入前备份一次
    private var hasBackedUp = false

    /// 本次运行为每个 tile 写入的最新 GUID，按 stub 所在目录的标准化路径记录
    ///
    /// 实测（macOS 27）Dock 被终止时若带着未写的状态（例如刚接受过一次拖放），会把启动时读到的旧条目写回，
    /// 盖掉 Flotilla 刚换上的新 GUID；重启后的 Dock 读到旧 GUID，仍显示缓存的旧图标
    private var writtenGUIDs: [String: Int] = [:]

    /// 对最近一次被终止的 Dock 进程是否已退出的观察，下一次重启 Dock 时替换
    private var terminationObservations: [NSKeyValueObservation] = []

    /// 创建 Dock 偏好的读写者；域名无法作为 `UserDefaults` 的 suite 时返回 nil
    /// - Parameters:
    ///   - domainName: 偏好所在的域，App 使用 `com.apple.dock`，测试时注入临时文件的绝对路径
    ///   - backupDirectory: 存放备份的目录
    init?(domainName: String, backupDirectory: URL) {
        guard let defaults = UserDefaults(suiteName: domainName) else { return nil }

        self.defaults = defaults
        self.domainName = domainName
        self.backupDirectory = backupDirectory
    }

    /// 构造一个 tile 条目，字段对照 Dock 自己写出的 App 条目；`book` 等其余字段由 Dock 启动后自行补全
    ///
    /// `file-type = 41` 与本机 Dock 为用户添加的 App 写出的取值一致，Dock 重启后原样保留；
    /// 条目缺少 `file-label` 时，Dock 会用 bundle 的文件名（即根文件夹 id）补上，因此名称必须写进条目
    /// - Parameters:
    ///   - tileURL: stub bundle 的文件 URL
    ///   - label: tile 的名称
    ///   - guid: 条目的唯一标识，32 位正整数
    static func tileEntry(tileURL: URL, label: String, guid: Int) -> [String: Any] {
        [
            "GUID": guid,
            "tile-data": [
                "file-data": [
                    "_CFURLString": normalized(tileURL).absoluteString,
                    "_CFURLStringType": 15,
                ],
                "file-label": label,
                "file-type": 41,
            ],
            "tile-type": "file-tile",
        ]
    }
}

// MARK: - Query

extension DockPreferences {
    /// Dock 上是否已有该 stub 所属根文件夹的 tile，按 stub 所在的目录匹配
    func contains(tileURL: URL) -> Bool {
        index(ofDirectory: tileURL.deletingLastPathComponent(), in: tiles) != nil
    }

    /// Dock 上 stub 位于该目录下某个 `<id>` 子目录的 tile 所属的根文件夹 id；子目录名解析不成 UUID 的条目忽略
    ///
    /// 只比对条目里记录的 URL，不访问磁盘：stub 连同它独占的 `<id>` 目录都已不存在时，Dock 上残留的 tile 仍能据此找出
    /// - Parameter stubsDirectory: 存放所有 stub 的目录
    func folderIDs(ofTilesIn stubsDirectory: URL) -> Set<UUID> {
        let target = Self.normalized(stubsDirectory).path(percentEncoded: false)
        var folderIDs: Set<UUID> = []

        for tile in tiles {
            guard
                let tileDirectory = Self.fileURL(of: tile)?.deletingLastPathComponent()
            else {
                continue
            }

            // 条目记录的是 `<stubsDirectory>/<id>/<文件夹名>.app/`：stub 所在目录的上一级必须正好是存放 stub 的目录，
            // 用户自己的 tile 与其它位置的条目一律不认
            let parentPath = tileDirectory
                .deletingLastPathComponent()
                .path(percentEncoded: false)

            guard parentPath == target else { continue }

            // 同一目录下与 Flotilla 无关的子目录，名称解析不成 UUID
            if let folderID = UUID(uuidString: tileDirectory.lastPathComponent) {
                folderIDs.insert(folderID)
            }
        }

        return folderIDs
    }
}

// MARK: - Mutation

extension DockPreferences {
    /// 在区域末尾追加一个 tile
    /// - Parameters:
    ///   - tileURL: stub bundle 的文件 URL
    ///   - label: tile 的名称
    func add(tileURL: URL, label: String) throws {
        let guid = Self.makeGUID()
        let entry = Self.tileEntry(tileURL: tileURL, label: label, guid: guid)

        try save(tiles + [entry])

        writtenGUIDs[Self.directoryKey(of: tileURL)] = guid
    }

    /// 删除根文件夹的 tile：条目记录的 stub 位于该目录即匹配
    ///
    /// 只比对条目里记录的 URL，不访问磁盘：用户在访达里删掉了 stub bundle 时同样能删除
    /// - Parameter tileDirectory: 根文件夹的 stub 独占的目录
    /// - Returns: 是否确实删除了条目
    @discardableResult
    func remove(tileDirectory: URL) throws -> Bool {
        var tiles = tiles
        guard let index = index(ofDirectory: tileDirectory, in: tiles) else { return false }

        tiles.remove(at: index)
        try save(tiles)

        writtenGUIDs[Self.normalized(tileDirectory).path(percentEncoded: false)] = nil

        return true
    }

    /// 让 tile 指向 stub 的当前位置、显示文件夹的当前名称；条目原地替换，Dock 里用户拖出来的顺序保持不变
    ///
    /// 文件夹改名后 stub 随之改名，URL 变化时一并删掉 Dock 按旧位置生成的书签 `book`，由 Dock 重启后按新 URL 重新生成
    ///
    /// 实测（macOS 27）Dock 按条目的 `GUID` 缓存 tile 图标，GUID 不变时重启后仍显示旧图标；stub 改写过就换一个新的 GUID。
    /// 条目的 GUID 不是本次运行写入的值时同样换新：那是 Dock 被终止时写回了旧条目，新图标还没被读取过
    /// - Parameters:
    ///   - tileURL: stub bundle 的当前位置
    ///   - label: tile 的名称
    ///   - isStubRewritten: stub 是否刚被改写
    /// - Returns: 是否确实改动了条目
    @discardableResult
    func update(tileURL: URL, label: String, isStubRewritten: Bool) throws -> Bool {
        var tiles = tiles
        guard
            let index = index(ofDirectory: tileURL.deletingLastPathComponent(), in: tiles),
            var tileData = tiles[index]["tile-data"] as? [String: Any]
        else {
            return false
        }

        // 按路径字符串比较：Swift 的字符串相等按 Unicode 规范等价判断，不受 Dock 写回时的编码形式影响
        let tilePath = Self.normalized(tileURL).path(percentEncoded: false)
        let currentPath = Self.fileURL(of: tiles[index])?.path(percentEncoded: false)
        let isURLChanged = currentPath != tilePath
        let isLabelChanged = tileData["file-label"] as? String != label

        // 本次运行写过 GUID 的 tile，条目里的 GUID 却不是写入的值：被终止的 Dock 把旧条目写回了
        let directoryKey = Self.directoryKey(of: tileURL)
        let isGUIDReverted = writtenGUIDs[directoryKey]
            .map { $0 != tiles[index]["GUID"] as? Int } ?? false

        guard
            isURLChanged
            || isLabelChanged
            || isStubRewritten
            || isGUIDReverted
        else {
            return false
        }

        // 新的 GUID 让 Dock 丢掉按旧 GUID 缓存的图标，重启后从 stub 重新读取
        if isStubRewritten || isGUIDReverted {
            let guid = Self.makeGUID()
            tiles[index]["GUID"] = guid
            writtenGUIDs[directoryKey] = guid
        }

        // 只替换 URL 本身，`file-data` 里 Dock 补全的其它字段保留
        if isURLChanged {
            var fileData = tileData["file-data"] as? [String: Any] ?? [:]
            fileData["_CFURLString"] = Self.normalized(tileURL).absoluteString
            tileData["file-data"] = fileData
            tileData["book"] = nil
        }

        tileData["file-label"] = label
        tiles[index]["tile-data"] = tileData

        try save(tiles)

        return true
    }

    /// 终止 Dock 进程，由 launchd 自动拉起；Dock 只在启动时读取偏好，改动要靠重启生效
    /// - Parameter terminationHandler: 被终止的 Dock 全部退出后在主线程调用。
    ///   Dock 终止时若把旧条目写回，此时已经落地：此刻的偏好就是新拉起的 Dock 读到的内容
    func restartDock(terminationHandler: @escaping @MainActor () -> Void) {
        let docks = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.dockDomain
        )

        // Dock 是 LSUIElement App，NSWorkspace 不为它发退出通知，只能观察 `isTerminated`。
        // 该属性只在主线程的 run loop 里更新，观察回调也在主线程；终止之前就开始观察，不会错过退出
        terminationObservations = docks.map {
            $0.observe(\.isTerminated) { _, _ in
                MainActor.assumeIsolated {
                    guard docks.allSatisfy(\.isTerminated) else { return }

                    terminationHandler()
                }
            }
        }

        for dock in docks {
            kill(dock.processIdentifier, SIGTERM)
        }
    }
}

// MARK: - Private

extension DockPreferences {
    /// 区域内当前的全部条目
    private var tiles: [[String: Any]] {
        defaults.array(forKey: Self.sectionKey) as? [[String: Any]] ?? []
    }

    /// 写回区域内的全部条目；本次运行首次写入前先备份，备份失败时不写
    private func save(_ tiles: [[String: Any]]) throws {
        if !hasBackedUp {
            try backUp()
            hasBackedUp = true
        }

        defaults.set(tiles, forKey: Self.sectionKey)
    }

    /// 把整个偏好域导出到备份目录，并删掉超出保留份数的旧备份
    private func backUp() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let fileName = "\(Self.backupPrefix)\(formatter.string(from: Date())).plist"
        let backupURL = backupDirectory.appending(path: fileName)

        let data = try PropertyListSerialization.data(
            fromPropertyList: defaults.persistentDomain(forName: domainName) ?? [:],
            format: .xml,
            options: 0
        )
        try data.write(to: backupURL, options: .atomic)

        Self.logger.notice("已备份 Dock 偏好到 \(backupURL.path(percentEncoded: false), privacy: .public)")

        try pruneBackups()
    }

    /// 只保留最新的几份备份
    private func pruneBackups() throws {
        let fileManager = FileManager.default

        // 文件名里的时间戳按字典序即按时间先后，排在前面的是旧备份
        let backups = try fileManager
            .contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix(Self.backupPrefix)
                    && $0.pathExtension == "plist"
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for oldBackup in backups.dropLast(Self.maximumBackupCount) {
            try fileManager.removeItem(at: oldBackup)
        }
    }

    /// 在条目中查找 stub 位于该目录的 tile，不按名称匹配
    ///
    /// 每个根文件夹的 stub 独占一个目录，文件夹改名时 stub 在目录里改名，按目录匹配才能找到改名前的 tile
    /// - Parameters:
    ///   - directory: 根文件夹的 stub 独占的目录
    ///   - tiles: 区域内的条目
    private func index(ofDirectory directory: URL, in tiles: [[String: Any]]) -> Int? {
        let target = Self.normalized(directory).path(percentEncoded: false)

        return tiles.firstIndex {
            let tileDirectory = Self.fileURL(of: $0)?
                .deletingLastPathComponent()
                .path(percentEncoded: false)

            return tileDirectory == target
        }
    }
}

// MARK: - Normalization

extension DockPreferences {
    /// stub 所在目录的标准化路径，作为按 tile 记录 GUID 的键
    private static func directoryKey(of tileURL: URL) -> String {
        normalized(tileURL.deletingLastPathComponent()).path(percentEncoded: false)
    }

    /// 把 stub 的 URL 统一成以 `/` 结尾的标准文件 URL，与 Dock 写出的格式一致
    private static func normalized(_ url: URL) -> URL {
        URL(
            filePath: url.standardizedFileURL.path(percentEncoded: false),
            directoryHint: .isDirectory
        )
    }

    /// 条目记录的文件 URL，经过标准化；缺失或不是文件 URL 时为 nil
    private static func fileURL(of tile: [String: Any]) -> URL? {
        let tileData = tile["tile-data"] as? [String: Any]
        let fileData = tileData?["file-data"] as? [String: Any]

        guard
            let urlString = fileData?["_CFURLString"] as? String,
            let url = URL(string: urlString),
            url.isFileURL
        else {
            return nil
        }

        return normalized(url)
    }
}

// MARK: - Helpers

extension DockPreferences {
    /// 生成条目的 `GUID`：随机的 32 位正整数，与 Dock 自己写出的取值范围一致
    private static func makeGUID() -> Int {
        Int.random(in: 1 ... Int(UInt32.max))
    }
}
