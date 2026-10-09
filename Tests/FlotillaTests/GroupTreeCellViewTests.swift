import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupTreeCellViewTests

/// 设置窗口里访达文件夹与组的图标相同，只靠名称后的位置文字区分：
/// 只有访达文件夹这一行显示，行视图复用后其余各行不能残留；宽度不够时先让出位置、在中间省略，名称尽量完整
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
        cell.configure(with: GroupTreeNode(item: .file(deleted), parent: nil))

        #expect(cell.locationText == nil)
    }

    /// 组不显示位置；复用刚显示过位置的行视图时不残留
    @Test
    func flotillaGroupShowsNoLocationAfterReuse() throws {
        let cell = try configuredCell(with: directory.appending(path: "资料"))
        let group = Group(id: UUID(), name: "工作", items: [])

        cell.configure(with: GroupTreeNode(item: .group(group), parent: nil))

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

// MARK: - Private

extension GroupTreeCellViewTests {
    /// 把本地 URL 经分类后放进一行
    private func configuredCell(with url: URL) throws -> GroupTreeCellView {
        let item = try #require(GroupItem(url: url, title: nil))

        let cell = GroupTreeCellView()
        cell.configure(with: GroupTreeNode(item: item, parent: nil))

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
}
