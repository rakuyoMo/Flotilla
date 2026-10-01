import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridThumbnailTests

/// 访达里的文件夹的层级里，文件按原生叠放显示内容缩略图，一眼看得出是哪份文件，而不是一排相同的通用图标；
/// Flotilla 的文件夹照旧显示图标。缩略图晚到时，不能落到已经离开的层级上
@MainActor
struct FolderGridThumbnailTests {
    /// 假的缩略图生成，由测试决定何时交出什么结果
    private let generator = ThumbnailGeneratorStub()

    /// 访达里的文件夹
    private let finderFolder = FileReference(
        id: UUID(),
        url: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory),
        bookmark: nil
    )

    /// 生成出的缩略图
    private let thumbnail = NSImage(size: CGSize(width: 101, height: 101))

    /// 访达里的文件夹的层级：文件先显示图标，缩略图生成后换上，各自落在发起请求的那一格
    @Test
    func finderFolderFilesShowThumbnails() async {
        let report = makeFile("报告.txt")
        let notes = makeFile("笔记.txt")
        let notesThumbnail = NSImage(size: CGSize(width: 101, height: 101))

        let grid = makeGrid(for: .finderFolder(
            finderFolder,
            items: [.file(report), .file(notes)]
        ))

        let reportIcon = icon(at: 0, in: grid)

        #expect(generator.requestedURLs == [report.url, notes.url])

        // 后请求的先生成出来：只换掉它自己那一格
        generator.complete(notes.url, with: notesThumbnail)
        await settle()

        #expect(icon(at: 0, in: grid) === reportIcon)
        #expect(icon(at: 1, in: grid) === notesThumbnail)

        generator.complete(report.url, with: thumbnail)
        await settle()

        #expect(icon(at: 0, in: grid) === thumbnail)
        #expect(icon(at: 1, in: grid) === notesThumbnail)
    }

    /// Flotilla 的文件夹的层级：同一个文件仍是图标，不请求缩略图
    @Test
    func flotillaFolderFilesKeepIcons() async {
        let report = makeFile("报告.txt")
        let folder = Folder(id: UUID(), name: "工作", items: [.file(report)])

        let grid = makeGrid(for: .folder(folder))
        let reportIcon = icon(at: 0, in: grid)

        generator.complete(report.url, with: thumbnail)
        await settle()

        #expect(generator.requestedURLs.isEmpty)
        #expect(icon(at: 0, in: grid) === reportIcon)
    }

    /// 子目录与生成不出缩略图的文件保持图标；App 不请求缩略图
    @Test
    func itemsWithoutThumbnailsKeepIcons() async {
        let subdirectory = makeFile("资料/")
        let archive = makeFile("归档.zip")

        let app = AppReference(
            id: UUID(),
            url: URL(
                filePath: "/System/Applications/Calculator.app/",
                directoryHint: .isDirectory
            ),
            bookmark: nil
        )

        let grid = makeGrid(for: .finderFolder(
            finderFolder,
            items: [.file(subdirectory), .file(archive), .app(app)]
        ))

        let subdirectoryIcon = icon(at: 0, in: grid)
        let archiveIcon = icon(at: 1, in: grid)

        #expect(generator.requestedURLs == [subdirectory.url, archive.url])

        // QuickLook 对子目录与没有缩略图扩展的类型给不出缩略图
        generator.complete(subdirectory.url, with: nil)
        generator.complete(archive.url, with: nil)
        await settle()

        #expect(icon(at: 0, in: grid) === subdirectoryIcon)
        #expect(icon(at: 1, in: grid) === archiveIcon)
    }

    /// 离开这一层、面板收起时网格离开窗口：还没完成的请求全部取消，之后晚到的结果不换上
    @Test
    func leavingWindowCancelsRequestsAndDropsLateResults() async {
        let report = makeFile("报告.txt")
        let notes = makeFile("笔记.txt")

        let grid = makeGrid(for: .finderFolder(
            finderFolder,
            items: [.file(report), .file(notes)]
        ))

        let window = makeWindow(containing: grid)
        let reportIcon = icon(at: 0, in: grid)
        let notesIcon = icon(at: 1, in: grid)

        #expect(grid.window === window)

        grid.removeFromSuperview()

        #expect(generator.cancelledURLs.count == 2)
        #expect(Set(generator.cancelledURLs) == [report.url, notes.url])

        generator.complete(report.url, with: thumbnail)
        generator.complete(notes.url, with: thumbnail)
        await settle()

        #expect(icon(at: 0, in: grid) === reportIcon)
        #expect(icon(at: 1, in: grid) === notesIcon)
    }
}

// MARK: - Private

extension FolderGridThumbnailTests {
    /// 访达里的文件夹里的一个文件；名称以 `/` 结尾时是子目录
    private func makeFile(_ name: String) -> FileReference {
        let isDirectory = name.hasSuffix("/")

        return FileReference(
            id: UUID(),
            url: URL(
                filePath: "/Users/Shared/" + name,
                directoryHint: isDirectory ? .isDirectory : .notDirectory
            ),
            bookmark: nil
        )
    }

    /// 与面板相同的建法：只有访达里的文件夹的层级有缩略图加载器与“在访达中打开”；
    /// 不在滚动视图里，排版后整个网格都算看得见，单元格全部建出
    private func makeGrid(for content: FolderPanelLevelContent) -> FolderGridView {
        let layout = FolderGridLayout(
            itemCount: content.cellCount,
            availableSize: CGSize(width: 2000, height: 2000)
        )

        let fileThumbnailLoader = content.showsFileThumbnails
            ? generator.makeLoader()
            : nil

        let openInFinderHandler: (() -> Void)? = content.finderFolderURL == nil
            ? nil
            : { }

        let grid = FolderGridView(
            items: content.items,
            layout: layout,
            previewIconCount: 0,
            fileThumbnailLoader: fileThumbnailLoader,
            openInFinderHandler: openInFinderHandler
        ) { _ in }

        grid.layoutSubtreeIfNeeded()

        return grid
    }

    /// 把网格放进一个窗口
    private func makeWindow(containing grid: FolderGridView) -> NSWindow {
        let window = NSWindow(
            contentRect: grid.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )

        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(grid)

        return window
    }

    /// 第 `index` 格（从 0 数）当前显示的图标；各项排在前面，“在访达中打开”在最后
    ///
    /// 每次都从网格里取：网格要一直活到测试结束，缩略图加载器归它所有
    private func icon(at index: Int, in grid: FolderGridView) -> NSImage? {
        let itemViews = grid.subviews
            .compactMap { $0 as? FolderGridItemView }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }

        return itemViews.indices.contains(index) ? itemViews[index].icon : nil
    }

    /// 等主线程处理完排着的任务：缩略图的结果经 `Task { @MainActor in }` 回到主线程
    private func settle() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }
}
