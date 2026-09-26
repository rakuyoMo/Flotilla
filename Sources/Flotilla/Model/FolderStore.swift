import Foundation
import os

// MARK: - FolderStore

/// 文件夹树的唯一数据源：负责增删改查与持久化，并在每次变更后发出通知
@MainActor
final class FolderStore {
    /// 文件夹树发生变更后在主线程发出的通知，`object` 为发生变更的 `FolderStore`
    nonisolated static let didChangeNotification = Notification.Name("FolderStore.didChange")

    /// 默认持久化位置：`~/Library/Application Support/Flotilla/folders.json`
    nonisolated static let defaultFileURL = URL.applicationSupportDirectory
        .appending(path: "Flotilla/folders.json")

    /// App 使用的实例，持久化到默认位置
    static let shared = FolderStore(fileURL: defaultFileURL)

    /// 持久化相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "FolderStore"
    )

    /// 根文件夹，每个对应 Dock 上的一个 tile
    private(set) var rootFolders: [Folder]

    /// 持久化文件的位置
    private let fileURL: URL

    /// 以 `[FolderItem]` 的形式读写根层级，让根层级与文件夹内部共用同一套递归操作；根层级只放文件夹
    private var rootItems: [FolderItem] {
        get {
            rootFolders.map { .folder($0) }
        }
        set {
            rootFolders = newValue.compactMap {
                guard case .folder(let folder) = $0 else { return nil }
                return folder
            }
        }
    }

    /// 创建数据源并立即加载持久化文件
    /// - Parameter fileURL: 持久化文件的位置；文件不存在时从空开始，解析失败时把原文件改名保留后从空开始
    init(fileURL: URL) {
        self.fileURL = fileURL
        rootFolders = Self.load(from: fileURL)
    }
}

// MARK: - Query

extension FolderStore {
    /// 在任意层级中查找文件夹
    func folder(id: UUID) -> Folder? {
        guard case .folder(let folder) = Self.findItem(id: id, in: rootItems) else {
            return nil
        }

        return folder
    }

    /// 返回直接包含该项的文件夹；根文件夹或找不到该项时返回 nil
    func parentFolder(of itemID: UUID) -> Folder? {
        Self.findParent(of: itemID, in: rootItems)
    }

    /// 判断能否把一项移入某个文件夹：App 只能放进文件夹，文件夹不能移入自身或自己的子孙
    /// - Parameters:
    ///   - itemID: 要移动的项
    ///   - folderID: 目标文件夹，nil 表示根层级
    func canMove(itemID: UUID, to folderID: UUID?) -> Bool {
        guard let item = Self.findItem(id: itemID, in: rootItems) else { return false }

        // 根层级只放文件夹
        guard let folderID else {
            guard case .folder = item else { return false }
            return true
        }

        // 目标是被移动的文件夹自身或它的子孙时，移动会让文件夹脱离整棵树
        if
            case .folder(let moved) = item,
            moved.id == folderID || Self.findItem(id: folderID, in: moved.items) != nil
        {
            return false
        }

        return folder(id: folderID) != nil
    }
}

// MARK: - Mutation

extension FolderStore {
    /// 在根层级末尾新建文件夹
    func addRootFolder(named name: String) -> Folder {
        let folder = Folder(id: UUID(), name: name, items: [])
        rootFolders.append(folder)
        commit()

        return folder
    }

    /// 在指定文件夹末尾新建子文件夹；找不到父文件夹时返回 nil
    func addSubfolder(named name: String, to parentID: UUID) -> Folder? {
        let folder = Folder(id: UUID(), name: name, items: [])

        var items = rootItems
        let found = Self.modifyFolder(id: parentID, in: &items) {
            $0.items.append(.folder(folder))
        }

        guard found else { return nil }

        rootItems = items
        commit()

        return folder
    }

    /// 把 App 追加到文件夹末尾；该文件夹内已有相同 URL 的 App 时跳过
    func addApps(_ urls: [URL], to folderID: UUID) {
        // App bundle 是目录：统一成带结尾斜杠的标准路径，同一个 App 不会因 URL 写法不同而被重复加入
        let appURLs = urls.map {
            URL(
                filePath: $0.standardizedFileURL.path(percentEncoded: false),
                directoryHint: .isDirectory
            )
        }

        var items = rootItems
        var added = false

        let found = Self.modifyFolder(id: folderID, in: &items) { folder in
            for url in appURLs {
                // 与已有的项以及本次已加入的项比对，同一个 App 在一个文件夹里只出现一次
                let exists = folder.items.contains {
                    guard case .app(let app) = $0 else { return false }
                    return app.url == url
                }
                guard !exists else { continue }

                folder.items.append(.app(AppReference(id: UUID(), url: url)))
                added = true
            }
        }

        guard found, added else { return }

        rootItems = items
        commit()
    }

    /// 重命名文件夹；名称未变化时不产生变更
    func rename(folderID: UUID, to name: String) {
        guard let folder = folder(id: folderID), folder.name != name else { return }

        var items = rootItems
        _ = Self.modifyFolder(id: folderID, in: &items) {
            $0.name = name
        }

        rootItems = items
        commit()
    }

    /// 删除一项；删除文件夹时连同其内容一起删除
    func remove(itemID: UUID) {
        var items = rootItems
        guard Self.removeItem(id: itemID, from: &items) != nil else { return }

        rootItems = items
        commit()
    }

    /// 把一项移动到目标文件夹的指定位置；不满足 `canMove(itemID:to:)` 时不做任何改动
    /// - Parameters:
    ///   - itemID: 要移动的项
    ///   - folderID: 目标文件夹，nil 表示根层级
    ///   - index: 目标位置，按移动前目标层级的下标计算，超出范围时夹到两端
    func move(itemID: UUID, to folderID: UUID?, at index: Int) {
        guard canMove(itemID: itemID, to: folderID) else { return }

        // 记下原位置：在同一层级内向后移动时，先移除自身会让目标位置前移一位
        let sourceParent = parentFolder(of: itemID)
        let siblings = sourceParent?.items ?? rootItems
        let sourceIndex = siblings.firstIndex { $0.id == itemID }

        var items = rootItems
        guard let item = Self.removeItem(id: itemID, from: &items) else { return }

        var targetIndex = index
        if
            sourceParent?.id == folderID,
            let sourceIndex,
            sourceIndex < index
        {
            targetIndex -= 1
        }

        Self.insert(item, into: folderID, at: targetIndex, in: &items)

        rootItems = items
        commit()
    }
}

// MARK: - Persistence

extension FolderStore {
    /// 读取持久化文件；文件不存在时返回空，解析失败时把原文件改名为 `folders.json.broken-<时间戳>` 保留并返回空
    private static func load(from fileURL: URL) -> [Folder] {
        let path = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Folder].self, from: data)
        } catch {
            logger.error("解析文件夹数据失败：\(error.localizedDescription, privacy: .public)")
            preserveBrokenFile(at: fileURL)
            return []
        }
    }

    /// 把无法解析的持久化文件改名保留，避免下一次写入覆盖用户数据
    private static func preserveBrokenFile(at fileURL: URL) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let brokenURL = fileURL.deletingLastPathComponent()
            .appending(path: "\(fileURL.lastPathComponent).broken-\(timestamp)")

        do {
            try FileManager.default.moveItem(at: fileURL, to: brokenURL)
            logger.notice("已将无法解析的文件改名为 \(brokenURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("改名保留无法解析的文件失败：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 持久化并通知观察者；每个变更方法在确实改动了数据后调用
    private func commit() {
        save()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// 以可读的 JSON 原子写入持久化文件
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(rootFolders).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("写入文件夹数据失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Tree Operations

extension FolderStore {
    /// 在 items 及其子孙中查找一项
    private static func findItem(id: UUID, in items: [FolderItem]) -> FolderItem? {
        for item in items {
            if item.id == id {
                return item
            }

            if
                case .folder(let folder) = item,
                let found = findItem(id: id, in: folder.items)
            {
                return found
            }
        }

        return nil
    }

    /// 在 items 的子孙中查找直接包含 itemID 的文件夹；items 这一层自身的项没有父文件夹
    private static func findParent(of itemID: UUID, in items: [FolderItem]) -> Folder? {
        for case .folder(let folder) in items {
            if folder.items.contains(where: { $0.id == itemID }) {
                return folder
            }

            if let found = findParent(of: itemID, in: folder.items) {
                return found
            }
        }

        return nil
    }

    /// 在 items 及其子孙中找到文件夹并原地修改；找到时返回 true
    private static func modifyFolder(
        id: UUID,
        in items: inout [FolderItem],
        _ body: (inout Folder) -> Void
    ) -> Bool {
        for index in items.indices {
            guard case .folder(var folder) = items[index] else { continue }

            // 命中自身或在子孙中命中，都要把修改后的值写回这一层
            if folder.id == id {
                body(&folder)
            } else if !modifyFolder(id: id, in: &folder.items, body) {
                continue
            }

            items[index] = .folder(folder)
            return true
        }

        return false
    }

    /// 从 items 及其子孙中移除一项，返回被移除的项
    private static func removeItem(id: UUID, from items: inout [FolderItem]) -> FolderItem? {
        if let index = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: index)
        }

        for index in items.indices {
            guard case .folder(var folder) = items[index] else { continue }
            guard let removed = removeItem(id: id, from: &folder.items) else { continue }

            items[index] = .folder(folder)
            return removed
        }

        return nil
    }

    /// 把一项插入目标文件夹（nil 表示 items 这一层），下标夹到有效范围内
    private static func insert(
        _ item: FolderItem,
        into folderID: UUID?,
        at index: Int,
        in items: inout [FolderItem]
    ) {
        guard let folderID else {
            items.insert(item, at: min(max(index, 0), items.count))
            return
        }

        _ = modifyFolder(id: folderID, in: &items) {
            $0.items.insert(item, at: min(max(index, 0), $0.items.count))
        }
    }
}
