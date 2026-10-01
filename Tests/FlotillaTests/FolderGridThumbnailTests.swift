import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridThumbnailTests

/// 访达里的文件夹的层级里，文件按原生叠放显示内容缩略图，一眼看得出是哪份文件，而不是一排相同的通用图标；
/// Flotilla 的文件夹照旧显示图标。缩略图晚到时，不能落到已经离开的层级上；
/// 请求只为看得见附近的格保留，快速滚过上千项后，看得见的格不必排在滚过的格后面等
@MainActor
struct FolderGridThumbnailTests {
    /// 假的缩略图生成，由测试决定何时交出什么结果
    private let generator = ThumbnailGeneratorStub()

    /// 滚动用的 100 个文件：加上“在访达中打开”共 7 列、15 行，面板显示 5 行
    private let manyFiles = (0 ..< 100).map {
        FileReference(
            id: UUID(),
            url: URL(filePath: "/Users/Shared/文件\($0).txt"),
            bookmark: nil
        )
    }

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
            bookmark: nil,
            bundleIdentifier: nil
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

    /// 请求还没完成的格滚出看得见附近：请求取消，QuickLook 不再为它排队；之后晚到的结果不换上
    @Test
    func scrollingAwayCancelsPendingRequests() async {
        let (scrollView, grid) = makeScrolledGrid()

        scrollView.layoutSubtreeIfNeeded()

        let firstIcon = icon(at: 0, in: grid)

        #expect(generator.pendingURLs == urls(inRows: 0 ... 5))

        // 停在第 8 行：看得见附近是第 7–13 行，按格的先后请求
        scroll(scrollView, toRow: 8)

        #expect(Set(generator.cancelledURLs) == Set(urls(inRows: 0 ... 5)))
        #expect(generator.cancelledURLs.count == urls(inRows: 0 ... 5).count)
        #expect(generator.pendingURLs == urls(inRows: 7 ... 13))

        generator.complete(manyFiles[0].url, with: thumbnail)
        await settle()

        #expect(icon(at: 0, in: grid) === firstIcon)
    }

    /// 还没换上缩略图的格滚回看得见附近：重新请求，结果落到这一格
    @Test
    func scrollingBackRequestsAgain() async {
        let (scrollView, grid) = makeScrolledGrid()
        let firstURL = manyFiles[0].url

        scrollView.layoutSubtreeIfNeeded()
        scroll(scrollView, toRow: 8)
        scroll(scrollView, toRow: 0)

        #expect(generator.pendingURLs == urls(inRows: 0 ... 5))
        #expect(generator.requestedURLs.filter { $0 == firstURL }.count == 2)

        // 被取消的第一次请求也收到结果：只有重新发出的请求落到这一格
        generator.complete(firstURL, with: thumbnail)
        await settle()

        #expect(icon(at: 0, in: grid) === thumbnail)
    }

    /// 已经换上缩略图的格滚出再滚回：保持缩略图，不再请求
    @Test
    func thumbnailedCellsAreNotRequestedAgain() async {
        let (scrollView, grid) = makeScrolledGrid()
        let firstURL = manyFiles[0].url

        scrollView.layoutSubtreeIfNeeded()

        generator.complete(firstURL, with: thumbnail)
        await settle()

        scroll(scrollView, toRow: 8)
        scroll(scrollView, toRow: 0)

        #expect(generator.requestedURLs.filter { $0 == firstURL }.count == 1)
        #expect(!generator.cancelledURLs.contains(firstURL))
        #expect(!generator.pendingURLs.contains(firstURL))
        #expect(icon(at: 0, in: grid) === thumbnail)
    }

    /// 快速滚到底：滚过的格的请求都已取消，还没完成的只剩看得见附近的格
    @Test
    func fastScrollKeepsOnlyNearbyRequests() {
        let (scrollView, _) = makeScrolledGrid()

        scrollView.layoutSubtreeIfNeeded()

        // 每步滚过 3 行，直到最底部：最后停在第 10 行，看得见附近是第 9–14 行
        for row in stride(from: 3, through: 15, by: 3) {
            scroll(scrollView, toRow: row)
        }

        #expect(generator.pendingURLs == urls(inRows: 9 ... 14))
    }

    /// 预绘区域提前建的格先只建格，滚进看得见附近才请求
    @Test
    func preparedCellsRequestOnlyWhenNearVisible() {
        let (scrollView, grid) = makeScrolledGrid()
        let cell = FolderPanelMetrics.cellSize

        scrollView.layoutSubtreeIfNeeded()

        // 第 10、11 两行：建出第 9–12 行
        grid.prepareContent(in: CGRect(
            x: 0,
            y: 10 * cell,
            width: grid.bounds.width,
            height: 2 * cell
        ))

        let builtCellCount = urls(inRows: 0 ... 5).count + urls(inRows: 9 ... 12).count

        #expect(grid.subviews.count == builtCellCount)
        #expect(generator.requestedURLs == urls(inRows: 0 ... 5))

        scroll(scrollView, toRow: 8)

        #expect(generator.pendingURLs == urls(inRows: 7 ... 13))
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

    /// 不在滚动视图里的网格：排版后整个网格都算看得见，单元格全部建出
    private func makeGrid(for content: FolderPanelLevelContent) -> FolderGridView {
        let grid = makeGridView(for: content)

        grid.layoutSubtreeIfNeeded()

        return grid
    }

    /// 与面板相同的摆法：100 个文件的访达里的文件夹，网格作为滚动视图的文档视图，滚动视图高度正好是显示的行数
    private func makeScrolledGrid() -> (scrollView: NSScrollView, grid: FolderGridView) {
        let grid = makeGridView(for: .finderFolder(
            finderFolder,
            items: manyFiles.map { .file($0) }
        ))

        let scrollView = NSScrollView(frame: CGRect(
            x: 0,
            y: 0,
            width: grid.bounds.width,
            height: CGFloat(FolderPanelMetrics.maximumVisibleRowCount) * FolderPanelMetrics.cellSize
        ))

        scrollView.documentView = grid

        return (scrollView, grid)
    }

    /// 与面板相同的建法：只有访达里的文件夹的层级有缩略图加载器与“在访达中打开”；还没排版，一格也没建
    private func makeGridView(for content: FolderPanelLevelContent) -> FolderGridView {
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

        return FolderGridView(
            items: content.items,
            layout: layout,
            previewIconCount: 0,
            hiddenItemIDs: [],
            fileThumbnailLoader: fileThumbnailLoader,
            openInFinderHandler: openInFinderHandler
        ) { _ in }
    }

    /// 让第 `row` 行（从 0 数）停在可见区域顶部，滚动视图允许的范围之外时停在最底部
    private func scroll(_ scrollView: NSScrollView, toRow row: Int) {
        let clipView = scrollView.contentView

        let proposedBounds = CGRect(
            origin: CGPoint(x: 0, y: CGFloat(row) * FolderPanelMetrics.cellSize),
            size: clipView.bounds.size
        )

        clipView.scroll(to: clipView.constrainBoundsRect(proposedBounds).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// 滚动用的文件里，落在这些行（从 0 数）的文件的 URL，按格的先后
    private func urls(inRows rows: ClosedRange<Int>) -> [URL] {
        let columnCount = FolderPanelMetrics.overflowColumnCount

        return manyFiles.indices
            .filter { rows.contains($0 / columnCount) }
            .map { manyFiles[$0].url }
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
