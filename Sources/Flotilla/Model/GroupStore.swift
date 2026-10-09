import Foundation
import os

// MARK: - GroupStore

/// 文件夹树的唯一数据源：负责增删改查与持久化，并在每次变更后发出通知
@MainActor
final class GroupStore {
    /// 文件夹树发生变更后在主线程发出的通知，`object` 为发生变更的 `GroupStore`
    nonisolated static let didChangeNotification = Notification.Name("GroupStore.didChange")

    /// 默认持久化位置：`~/Library/Application Support/Flotilla/folders.json`；
    /// 文件名沿用 `folders.json`：已保存的数据就在这个文件里
    nonisolated static let defaultFileURL = URL.applicationSupportDirectory
        .appending(path: "Flotilla/folders.json")

    /// App 使用的实例，持久化到默认位置
    static let shared = GroupStore(fileURL: defaultFileURL)

    /// 持久化相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "GroupStore"
    )

    /// 根文件夹，每个对应一个 Dock tile
    private(set) var rootGroups: [Group]

    /// 持久化文件的位置
    private let fileURL: URL

    /// 以 `[GroupItem]` 的形式读写根层级，让根层级与文件夹内部共用同一套递归操作；根层级只放文件夹
    private var rootItems: [GroupItem] {
        get {
            rootGroups.map { .group($0) }
        }
        set {
            rootGroups = newValue.compactMap {
                guard case .group(let group) = $0 else { return nil }
                return group
            }
        }
    }

    /// 创建数据源并立即加载持久化文件
    /// - Parameter fileURL: 持久化文件的位置；文件不存在时从空开始，解析失败时把原文件改名保留后从空开始
    init(fileURL: URL) {
        self.fileURL = fileURL
        rootGroups = Self.load(from: fileURL)
    }
}

// MARK: - Query

extension GroupStore {
    /// 在任意层级中查找文件夹；找不到时为 nil
    func group(id: UUID) -> Group? {
        guard case .group(let group) = Self.findItem(id: id, in: rootItems) else {
            return nil
        }

        return group
    }

    /// 返回直接包含该项的文件夹；根文件夹或找不到该项时返回 nil
    func parentGroup(of itemID: UUID) -> Group? {
        Self.findParent(of: itemID, in: rootItems)
    }

    /// 判断能否把一项移入某个文件夹：App、文件与网页只能放进文件夹，文件夹不能移入自身或自己的子孙
    /// - Parameters:
    ///   - itemID: 要移动的项
    ///   - groupID: 目标文件夹，nil 表示根层级
    func canMove(itemID: UUID, to groupID: UUID?) -> Bool {
        guard let item = Self.findItem(id: itemID, in: rootItems) else { return false }

        // 根层级只放文件夹
        guard let groupID else {
            guard case .group = item else { return false }
            return true
        }

        // 目标是被移动的文件夹自身或它的子孙时，移动会让文件夹脱离整棵树
        if
            case .group(let moved) = item,
            moved.id == groupID || Self.findItem(id: groupID, in: moved.items) != nil
        {
            return false
        }

        return group(id: groupID) != nil
    }
}

// MARK: - Mutation

extension GroupStore {
    /// 在根层级末尾新建文件夹，返回新建的文件夹
    func addRootGroup(named name: String) -> Group {
        let group = Group(id: UUID(), name: name, items: [])
        rootGroups.append(group)
        commit()

        return group
    }

    /// 在指定文件夹末尾新建子文件夹；找不到父文件夹时返回 nil
    func addSubgroup(named name: String, to parentID: UUID) -> Group? {
        let group = Group(id: UUID(), name: name, items: [])

        var items = rootItems
        let found = Self.modifyGroup(id: parentID, in: &items) {
            $0.items.append(.group(group))
        }

        guard found else { return nil }

        rootItems = items
        commit()

        return group
    }

    /// 把 App、文件与网页追加到文件夹末尾，一次提交、只发一次变更通知
    ///
    /// 与该文件夹已有的项、以及本批已加入的项同类且 URL 相同时跳过；子文件夹不经这里添加，传进来就忽略。
    /// 比对之前先按书签把该文件夹里的 App 与文件跟到新位置，与加入合成一次提交
    /// - Parameters:
    ///   - items: 由 `GroupItem(url:title:)` 新建的项，id 不与树里已有的项重复
    ///   - groupID: 目标文件夹
    func addItems(_ items: [GroupItem], to groupID: UUID) {
        var tree = rootItems
        var added = false
        var relocated = false

        let found = Self.modifyGroup(id: groupID, in: &tree) { group in
            // App 或文件改名后再把它拖进同一个文件夹时，已有的那一项先换成新路径，下面才认得出是同一个
            relocated = Self.updateItemLocations(in: &group.items)

            for item in items {
                // 子文件夹只由 `addSubgroup(named:to:)` 新建
                if case .group = item {
                    continue
                }

                // 与已有的项以及本批已加入的项比对，同一个 App、文件或网页在一个文件夹里只出现一次
                let exists = group.items.contains {
                    Self.isDuplicate($0, of: item)
                }

                guard !exists else { continue }

                group.items.append(item)
                added = true
            }
        }

        guard found, added || relocated else { return }

        rootItems = tree
        commit()
    }

    /// 给不带标题加入或保存的网页补上取到的标题，位置与 id 不变
    ///
    /// 只在这一项仍在、是网页、网址仍是取标题时那个、标题仍为 nil 时才改：
    /// 保存之后网址又被改掉时，旧网址晚到的标题不属于它，不补。
    /// 改了就提交并发一次变更通知；其余情况什么都不做
    /// - Parameters:
    ///   - title: 网页的标题，已去掉首尾空白，不为空
    ///   - webPage: 不带标题交出的那一份网页：按它的 id 找这一项，核对它的网址，即取标题的网址
    func fillTitle(_ title: String, of webPage: WebPageReference) {
        guard
            case .webPage(let current) = Self.findItem(id: webPage.id, in: rootItems),
            current.url == webPage.url,
            current.title == nil
        else {
            return
        }

        updateWebPage(WebPageReference(id: webPage.id, url: webPage.url, title: title))
    }

    /// 把网页换成给定的网址与标题，位置与 id 不变
    ///
    /// 按 id 找到这一项；它已不在、不是网页、网址与标题都没变时什么都不做，改了就提交并发一次变更通知。
    /// 不按网址去重：去重只在加入时进行，改成与同一文件夹里另一个网页相同的网址时两项都保留
    /// - Parameter webPage: 改好的网页，id 与要改的那一项相同
    func updateWebPage(_ webPage: WebPageReference) {
        guard
            case .webPage(let current) = Self.findItem(id: webPage.id, in: rootItems),
            current != webPage,
            let parent = parentGroup(of: webPage.id)
        else {
            return
        }

        // 网页只放在文件夹里：在所在的文件夹里原地换成新的那一份
        var tree = rootItems

        _ = Self.modifyGroup(id: parent.id, in: &tree) { group in
            guard let index = group.items.firstIndex(where: { $0.id == webPage.id }) else { return }

            group.items[index] = .webPage(webPage)
        }

        rootItems = tree
        commit()
    }

    /// 按书签把 App 项与文件项跟到当前位置：移动或改名后换成新位置，id 不变；
    /// App 更新之后书签找不到装好的那一份时，按 bundle id 找回
    ///
    /// 有变化时一次提交；没有变化时不提交、不发通知。找不到的 App 与文件保持原样
    /// - Parameter groupID: 只更新这个文件夹及其子孙；nil 表示整棵树
    func updateItemLocations(in groupID: UUID? = nil) {
        var tree = rootItems
        var changed = false

        // 限定文件夹时只遍历它的子树；找不到这个文件夹时什么都不变
        if let groupID {
            _ = Self.modifyGroup(id: groupID, in: &tree) {
                changed = Self.updateItemLocations(in: &$0.items)
            }
        } else {
            changed = Self.updateItemLocations(in: &tree)
        }

        guard changed else { return }

        rootItems = tree
        commit()
    }

    /// 重命名文件夹；名称未变化时不产生变更
    func rename(groupID: UUID, to name: String) {
        guard let group = group(id: groupID), group.name != name else { return }

        var items = rootItems
        _ = Self.modifyGroup(id: groupID, in: &items) {
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
    ///   - groupID: 目标文件夹，nil 表示根层级
    ///   - index: 目标位置，按移动前目标层级的下标计算，超出范围时夹到两端
    func move(itemID: UUID, to groupID: UUID?, at index: Int) {
        guard canMove(itemID: itemID, to: groupID) else { return }

        // 记下原位置：在同一层级内向后移动时，先移除自身会让目标位置前移一位
        let sourceParent = parentGroup(of: itemID)
        let siblings = sourceParent?.items ?? rootItems
        let sourceIndex = siblings.firstIndex { $0.id == itemID }

        var items = rootItems
        guard let item = Self.removeItem(id: itemID, from: &items) else { return }

        var targetIndex = index
        if
            sourceParent?.id == groupID,
            let sourceIndex,
            sourceIndex < index
        {
            targetIndex -= 1
        }

        Self.insert(item, into: groupID, at: targetIndex, in: &items)

        rootItems = items
        commit()
    }
}

// MARK: - Persistence

extension GroupStore {
    /// 读取持久化文件；文件不存在时返回空，解析失败时把原文件改名为 `folders.json.broken-<时间戳>` 保留并返回空
    private static func load(from fileURL: URL) -> [Group] {
        let path = fileURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([Group].self, from: data)
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
            try encoder.encode(rootGroups).write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("写入文件夹数据失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Tree Operations

extension GroupStore {
    /// 在 items 及其子孙中查找一项；找不到时为 nil
    private static func findItem(id: UUID, in items: [GroupItem]) -> GroupItem? {
        for item in items {
            if item.id == id {
                return item
            }

            if
                case .group(let group) = item,
                let found = findItem(id: id, in: group.items)
            {
                return found
            }
        }

        return nil
    }

    /// 在 items 的子孙中查找直接包含 itemID 的文件夹；items 这一层自身的项没有父文件夹
    private static func findParent(of itemID: UUID, in items: [GroupItem]) -> Group? {
        for case .group(let group) in items {
            if group.items.contains(where: { $0.id == itemID }) {
                return group
            }

            if let found = findParent(of: itemID, in: group.items) {
                return found
            }
        }

        return nil
    }

    /// 在 items 及其子孙中找到文件夹并原地修改；找到时返回 true
    private static func modifyGroup(
        id: UUID,
        in items: inout [GroupItem],
        _ body: (inout Group) -> Void
    ) -> Bool {
        for index in items.indices {
            guard case .group(var group) = items[index] else { continue }

            // 命中自身或在子孙中命中，都要把修改后的值写回这一层
            if group.id == id {
                body(&group)
            } else if !modifyGroup(id: id, in: &group.items, body) {
                continue
            }

            items[index] = .group(group)
            return true
        }

        return false
    }

    /// 从 items 及其子孙中移除一项，返回被移除的项；找不到时为 nil
    private static func removeItem(id: UUID, from items: inout [GroupItem]) -> GroupItem? {
        if let index = items.firstIndex(where: { $0.id == id }) {
            return items.remove(at: index)
        }

        for index in items.indices {
            guard case .group(var group) = items[index] else { continue }
            guard let removed = removeItem(id: id, from: &group.items) else { continue }

            items[index] = .group(group)
            return removed
        }

        return nil
    }

    /// 把一项插入目标文件夹（nil 表示 items 这一层），下标夹到有效范围内
    private static func insert(
        _ item: GroupItem,
        into groupID: UUID?,
        at index: Int,
        in items: inout [GroupItem]
    ) {
        guard let groupID else {
            items.insert(item, at: min(max(index, 0), items.count))
            return
        }

        _ = modifyGroup(id: groupID, in: &items) {
            $0.items.insert(item, at: min(max(index, 0), $0.items.count))
        }
    }

    /// 按书签更新 items 及其子孙里的 App 项与文件项；有任何一项变化时返回 true
    private static func updateItemLocations(in items: inout [GroupItem]) -> Bool {
        var changed = false

        for index in items.indices {
            switch items[index] {
            // App 不跟进废纸篓，书签找不到时按 bundle id 找回装好的那一份
            case .app(let app):
                guard let relocated = app.relocatedApp() else { continue }

                items[index] = .app(relocated)
                changed = true

            case .file(let file):
                guard let relocated = file.relocated() else { continue }

                items[index] = .file(relocated)
                changed = true

            // 子文件夹里有变化时，把修改后的子文件夹写回这一层
            case .group(var group):
                guard updateItemLocations(in: &group.items) else { continue }

                items[index] = .group(group)
                changed = true

            // 网页不涉及位置
            case .webPage:
                continue
            }
        }

        return changed
    }

    /// 两项是否同类且 URL 相同；子文件夹之间不算重复
    private static func isDuplicate(_ lhs: GroupItem, of rhs: GroupItem) -> Bool {
        switch (lhs, rhs) {
        case (.app(let lhs), .app(let rhs)):
            lhs.url == rhs.url

        case (.file(let lhs), .file(let rhs)):
            lhs.url == rhs.url

        case (.webPage(let lhs), .webPage(let rhs)):
            lhs.url == rhs.url

        default:
            false
        }
    }
}
