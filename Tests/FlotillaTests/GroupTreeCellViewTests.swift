import AppKit
import Testing
import UniformTypeIdentifiers

@testable import Flotilla

// MARK: - GroupTreeCellViewTests

/// 名称后的灰色小字：访达文件夹靠它标出位置，带标题的网页靠它标出网址。
/// 只有这两种行显示，行视图复用后其余各行不能残留；宽度不够时先让出它、在中间省略，名称尽量完整
///
/// 行首图标：组是黄色文件夹，与系统给的蓝色访达文件夹区分开
@MainActor
final class GroupTreeCellViewTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 在临时目录里建好访达文件夹、文件包与普通文件
    init() throws {
        for name in ["资料", "笔记.rtfd"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: name),
                withIntermediateDirectories: true
            )
        }

        try Data("报告".utf8).write(to: directory.appending(path: "报告.txt"))
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 家目录之内的访达文件夹：位置是父目录，家目录写成 `~`
    @Test
    func finderFolderInHomeShowsTildeLocation() throws {
        let caches = URL.homeDirectory.appending(path: "Library/Caches")
        let cell = try configuredCell(with: caches)

        #expect(cell.locationText == "~/Library")
    }

    /// 家目录以外的访达文件夹：位置是父目录的完整路径
    @Test
    func finderFolderOutsideHomeShowsFullLocation() throws {
        let cell = try configuredCell(with: directory.appending(path: "资料"))

        #expect(cell.locationText == directory.path(percentEncoded: false))
    }

    /// `/` 没有父目录，不显示位置
    @Test
    func volumeRootShowsNoLocation() throws {
        let cell = try configuredCell(with: URL(filePath: "/"))

        #expect(cell.locationText == nil)
    }

    /// 文件与文件包不显示位置
    @Test(arguments: ["报告.txt", "笔记.rtfd"])
    func filesShowNoLocation(name: String) throws {
        let cell = try configuredCell(with: directory.appending(path: name))

        #expect(cell.locationText == nil)
    }

    /// 已删除的访达文件夹读不到属性，不显示位置
    @Test
    func deletedFinderFolderShowsNoLocation() {
        let deleted = FileReference(
            id: UUID(),
            url: directory.appending(path: "已删除", directoryHint: .isDirectory),
            bookmark: nil
        )

        let cell = GroupTreeCellView()
        cell.configure(
            with: GroupTreeNode(item: .file(deleted), parent: nil),
            finderFolderIcons: .unstarted()
        )

        #expect(cell.locationText == nil)
    }

    /// 组不显示位置；复用刚显示过位置的行视图时不残留
    @Test
    func flotillaGroupShowsNoLocationAfterReuse() throws {
        let cell = try configuredCell(with: directory.appending(path: "资料"))
        let group = Group(id: UUID(), name: "工作", items: [])

        cell.configure(
            with: GroupTreeNode(item: .group(group), parent: nil),
            finderFolderIcons: .unstarted()
        )

        #expect(cell.locationText == nil)
    }

    /// 宽度不够时先截断位置，名称保持完整
    @Test
    func locationTruncatesBeforeName() throws {
        let deepPath = String(repeating: "很长的目录名/", count: 8) + "资料"

        try FileManager.default.createDirectory(
            at: directory.appending(path: deepPath),
            withIntermediateDirectories: true
        )

        let cell = try configuredCell(with: directory.appending(path: deepPath))
        cell.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
        cell.layoutSubtreeIfNeeded()

        let nameField = try #require(cell.textField)
        let location = try #require(locationField(in: cell))

        #expect(nameField.frame.width >= nameField.intrinsicContentSize.width)
        #expect(location.frame.width < location.intrinsicContentSize.width)
    }

    /// 位置截断时在中间省略：开头的 `~/` 与离它最近的那一级目录都留着，仍能看出它在哪
    @Test
    func locationTruncatesInMiddle() throws {
        let cell = try configuredCell(with: directory.appending(path: "资料"))
        let location = try #require(locationField(in: cell))

        #expect(location.lineBreakMode == .byTruncatingMiddle)
    }
}

// MARK: - Web Page Address

extension GroupTreeCellViewTests {
    /// 带标题的网页名称是标题，看不出网址：名称后标出网址，与 “编辑…” 提示框里填的一致
    @Test
    func titledWebPageShowsAddress() throws {
        let cell = try configuredCell(with: #require(URL(string: Self.macAddress)), title: "Mac")

        #expect(cell.textField?.stringValue == "Mac")
        #expect(cell.locationText == Self.macAddress)
    }

    /// 没有标题时名称就是网址，标题恰好就是网址时同样：名称后不再重复一遍
    @Test(arguments: [nil, GroupTreeCellViewTests.macAddress])
    func webPageNamedByAddressShowsNoAddress(title: String?) throws {
        let cell = try configuredCell(with: #require(URL(string: Self.macAddress)), title: title)

        #expect(cell.textField?.stringValue == Self.macAddress)
        #expect(cell.locationText == nil)
    }

    /// 网址里的中文按还原后的文字标出，与 “编辑…” 提示框里填的一致
    @Test
    func titledWebPageShowsDecodedAddress() throws {
        let cell = try configuredCell(with: #require(URL(string: Self.wikiAddress)), title: "归帆")

        #expect(cell.textField?.stringValue == "归帆")
        #expect(cell.locationText == Self.decodedWikiAddress)
    }

    /// 没有标题时名称就是还原后的网址，标题恰好是它时同样：只显示一次
    @Test(arguments: [nil, GroupTreeCellViewTests.decodedWikiAddress])
    func webPageNamedByDecodedAddressShowsItOnce(title: String?) throws {
        let cell = try configuredCell(with: #require(URL(string: Self.wikiAddress)), title: title)

        #expect(cell.textField?.stringValue == Self.decodedWikiAddress)
        #expect(cell.locationText == nil)
    }

    /// 复用刚显示过网址的行视图去显示 App 或组时，网址不残留
    @Test
    func addressDoesNotRemainAfterReuse() throws {
        let chess = try #require(
            GroupItem(url: URL(filePath: "/System/Applications/Chess.app"), title: nil)
        )

        let group = GroupItem.group(Group(id: UUID(), name: "工作", items: []))

        for item in [chess, group] {
            let cell = try configuredCell(with: #require(URL(string: Self.macAddress)), title: "Mac")

            try #require(cell.locationText != nil)

            cell.configure(
                with: GroupTreeNode(item: item, parent: nil),
                finderFolderIcons: .unstarted()
            )

            #expect(cell.locationText == nil)
        }
    }

    /// 宽度不够时先截断网址，名称保持完整
    @Test
    func addressTruncatesBeforeName() throws {
        let longPath = String(repeating: "very-long-path/", count: 12)
        let address = try #require(URL(string: "https://www.apple.com/\(longPath)mac/"))

        let cell = try configuredCell(with: address, title: "Mac")
        cell.frame = CGRect(x: 0, y: 0, width: 240, height: 24)
        cell.layoutSubtreeIfNeeded()

        let nameField = try #require(cell.textField)
        let addressField = try #require(locationField(in: cell))

        #expect(nameField.frame.width >= nameField.intrinsicContentSize.width)
        #expect(addressField.frame.width < addressField.intrinsicContentSize.width)
    }
}

// MARK: - Icon

extension GroupTreeCellViewTests {
    /// 组这一行是黄色文件夹：文件夹正面中央的红、绿明显高于蓝，色相落在黄色
    @Test(arguments: [1, 2] as [CGFloat])
    func groupRowIconIsYellow(scale: CGFloat) throws {
        let pixels = try pixels(of: #require(groupCell().imageView?.image), scale: scale)
        let side = Int(Self.iconSide * scale)

        // 图标中心落在文件夹正面上
        let base = (side / 2 * side + side / 2) * 4

        let red = Double(pixels[base])
        let green = Double(pixels[base + 1])
        let blue = Double(pixels[base + 2])

        #expect(red - blue > 128)
        #expect(green - blue > 128)

        // 红最大、蓝最小时色相是 60° × (绿 − 蓝) / (红 − 蓝)：0° 是红，60° 是黄
        try #require(red >= green && green >= blue)

        #expect((40 ... 60).contains(60 * (green - blue) / (red - blue)))
    }

    /// 着色只换颜色：透明度与系统的通用文件夹图标逐像素相同，形状不变，1 倍、2 倍屏上都不经缩放；
    /// 完全不透明的像素颜色都换了，文件夹下方黑色的阴影仍是黑色，与系统的黄色文件夹一样
    @Test(arguments: [1, 2] as [CGFloat])
    func groupRowIconKeepsFolderShape(scale: CGFloat) throws {
        let yellow = try pixels(of: #require(groupCell().imageView?.image), scale: scale)
        let folder = try pixels(of: NSWorkspace.shared.icon(for: .folder), scale: scale)

        let alphaIndices = stride(from: 3, to: folder.count, by: 4)

        #expect(alphaIndices.allSatisfy { yellow[$0] == folder[$0] })

        let opaqueBases = stride(from: 0, to: folder.count, by: 4)
            .filter { folder[$0 + 3] == 255 }

        try #require(!opaqueBases.isEmpty)

        #expect(opaqueBases.allSatisfy { yellow[$0 ..< $0 + 3] != folder[$0 ..< $0 + 3] })

        // 阴影：半透明、颜色是黑色的像素
        let shadowBases = stride(from: 0, to: folder.count, by: 4)
            .filter { folder[$0 + 3] > 0 && folder[$0 + 3] < 255 }
            .filter { folder[$0 ..< $0 + 3].allSatisfy { $0 == 0 } }

        try #require(!shadowBases.isEmpty)

        #expect(shadowBases.allSatisfy { yellow[$0 ..< $0 + 3].allSatisfy { $0 == 0 } })
    }

    /// 打了红色标签的访达文件夹：这一行是系统画好的红色文件夹，与访达里看到的一样，不是蓝色
    @Test(arguments: [1, 2] as [CGFloat])
    func redTaggedFinderFolderRowIsRed(scale: CGFloat) async throws {
        let url = directory.appending(path: "红色", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FinderFolderAttributes.setTags(["红色\n6"], of: url)

        let item = try #require(GroupItem(url: url, title: nil))

        guard case .file(let finderFolder) = item else {
            Issue.record("访达文件夹没有分类成文件")
            return
        }

        // 图标库跟着的组树里要有这个访达文件夹，才会监听、取图
        let store = GroupStore(fileURL: directory.appending(path: "folders.json"))

        store.addItems([item], to: store.addRootGroup(named: "资料").id)

        let iconStore = FinderFolderIconStore(store: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: FinderFolderIconStore.folderPath(of: finderFolder)))

        let cell = GroupTreeCellView()

        cell.configure(
            with: GroupTreeNode(item: item, parent: nil),
            finderFolderIcons: iconStore
        )

        let color = try IconPixels.centerColor(
            of: #require(cell.imageView?.image),
            side: Self.iconSide,
            scale: scale
        )

        #expect(color.red - color.green > 100)
        #expect(color.red - color.blue > 100)
    }

    /// 访达文件夹这一行仍是系统给的蓝色文件夹，与组这一行的黄色文件夹区分开
    @Test
    func finderFolderRowKeepsSystemIcon() throws {
        let cell = try configuredCell(with: directory.appending(path: "资料"))
        let finderFolder = try pixels(of: #require(cell.imageView?.image), scale: 2)

        #expect(try finderFolder == pixels(of: NSWorkspace.shared.icon(for: .folder), scale: 2))
        #expect(try finderFolder != pixels(of: #require(groupCell().imageView?.image), scale: 2))
    }
}

// MARK: - Private

extension GroupTreeCellViewTests {
    /// 行首图标的边长（pt），与 `GroupTreeCellView` 的相同
    private nonisolated static let iconSide: CGFloat = 20

    /// 网页测试用的网址
    private nonisolated static let macAddress = "https://www.apple.com/mac/"

    /// 网页测试用的、路径里有中文的网址：`url.absoluteString` 是百分号编码
    private nonisolated static let wikiAddress = "https://zh.wikipedia.org/wiki/%E5%BD%92%E5%B8%86"

    /// `wikiAddress` 里的中文还原后的网址
    private nonisolated static let decodedWikiAddress = "https://zh.wikipedia.org/wiki/归帆"

    /// 把 URL 经分类后放进一行；网页带上 title 作标题
    private func configuredCell(with url: URL, title: String? = nil) throws -> GroupTreeCellView {
        let item = try #require(GroupItem(url: url, title: title))

        let cell = GroupTreeCellView()
        cell.configure(
            with: GroupTreeNode(item: item, parent: nil),
            finderFolderIcons: .unstarted()
        )

        return cell
    }

    /// 行里显示位置文字的文本框；这一行不显示位置时为 nil
    private func locationField(in cell: GroupTreeCellView) -> NSTextField? {
        textFields(in: cell).first {
            $0 !== cell.textField && $0.stringValue == cell.locationText
        }
    }

    /// 视图及其子孙里的全部文本框
    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap {
            ($0 as? NSTextField).map { [$0] } ?? textFields(in: $0)
        }
    }

    /// 显示一个空组的行
    private func groupCell() -> GroupTreeCellView {
        let group = Group(id: UUID(), name: "工作", items: [])

        let cell = GroupTreeCellView()
        cell.configure(
            with: GroupTreeNode(item: .group(group), parent: nil),
            finderFolderIcons: .unstarted()
        )

        return cell
    }

    /// 把图像按行首图标的边长、scale 倍画进位图，读出全部字节，见 `IconPixels.pixels(of:side:scale:)`
    private func pixels(of image: NSImage, scale: CGFloat) throws -> [UInt8] {
        try IconPixels.pixels(of: image, side: Self.iconSide, scale: scale)
    }
}
