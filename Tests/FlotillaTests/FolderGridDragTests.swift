import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridDragTests

/// 面板里拖动文件夹的项：移动不超过 5 pt 仍是点击，超过即开始拖动、不再算点击；
/// 拖到别的格上其余各格让位；松开落定后保存新的顺序；
/// 拖动途中层级被重建或面板收起时作废，数据不变，落定途中的保存照常进行；落定途中网格滚动时落点跟着目标格
///
/// 窗口从不上屏：事件直接交给单元格，拖动图像只在面板显示时才排进屏幕
@MainActor
final class FolderGridDragTests {
    /// 6 个网页：3 列、2 行
    private let items: [FolderItem]

    /// 网格所在的离屏窗口；当前层级的轮廓按它的 frame 算
    private let window = NSWindow(
        contentRect: CGRect(x: 200, y: 200, width: 600, height: 500),
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )

    /// 保存回调收到的项与目标格
    private var moves: [(itemID: UUID, targetIndex: Int)] = []

    /// 点击过的项
    private var selections: [UUID] = []

    /// 准备 6 个网址各不相同的网页
    init() throws {
        items = try (0 ..< 6).map {
            .webPage(WebPageReference(
                id: UUID(),
                url: try #require(URL(string: "https://example.com/\($0)")),
                title: "网页\($0)"
            ))
        }
    }

    // MARK: 点击与开始拖动

    /// 移动不超过 5 pt（正好 5 pt）再抬起：照旧是一次点击，不开始拖动
    @Test
    func smallMoveStillClicks() throws {
        let (_, grid) = makeGrid()
        let itemView = try cellView(ofItem: 0, in: grid)
        let center = windowPoint(ofCell: 0, in: grid)

        try send(.leftMouseDown, to: itemView, at: center)
        try send(.leftMouseDragged, to: itemView, at: offset(center, 3, 4))

        #expect(grid.dragImage == nil)

        try send(.leftMouseUp, to: itemView, at: offset(center, 3, 4))

        #expect(selections == [items[0].id])
    }

    /// 超过 5 pt：开始拖动，这一格的图标与名称隐藏；拖动图像跟随鼠标，鼠标在图标上的位置与按下时相同
    @Test
    func dragBeyondThresholdStartsDragging() throws {
        let (_, grid) = makeGrid()
        let itemView = try cellView(ofItem: 0, in: grid)
        let center = windowPoint(ofCell: 0, in: grid)
        let iconCenter = screenIconCenter(ofCell: 0, in: grid)

        try send(.leftMouseDown, to: itemView, at: center)
        try send(.leftMouseDragged, to: itemView, at: offset(center, 6, 0))

        let image = try #require(grid.dragImage)

        #expect(itemView.isContentHidden)
        #expect(image.iconCenter == offset(iconCenter, 6, 0))

        try send(.leftMouseDragged, to: itemView, at: offset(center, 40, -30))

        #expect(image.iconCenter == offset(iconCenter, 40, -30))
    }

    /// 开始拖动之后，回到原来的格里抬起也不算点击
    @Test
    func releaseAfterDragDoesNotClick() throws {
        let (_, grid) = makeGrid()
        let itemView = try cellView(ofItem: 0, in: grid)
        let center = windowPoint(ofCell: 0, in: grid)

        try send(.leftMouseDown, to: itemView, at: center)
        try send(.leftMouseDragged, to: itemView, at: offset(center, 20, 0))
        try send(.leftMouseUp, to: itemView, at: center)

        #expect(selections.isEmpty)
    }

    /// 访达里的文件夹的层级（没有拖动的动作）：移动超过 5 pt 不开始拖动，在格里抬起照旧是点击
    @Test
    func gridWithoutDragActionsDoesNotDrag() throws {
        let (_, grid) = makeGrid(isDraggable: false)
        let itemView = try cellView(ofItem: 0, in: grid)
        let center = windowPoint(ofCell: 0, in: grid)

        try send(.leftMouseDown, to: itemView, at: center)
        try send(.leftMouseDragged, to: itemView, at: offset(center, 30, 0))

        #expect(grid.dragImage == nil)
        #expect(!itemView.isContentHidden)

        try send(.leftMouseUp, to: itemView, at: offset(center, 30, 0))

        #expect(selections == [items[0].id])
    }

    // MARK: 让位

    /// 拖到另一格上：其余各项按 “拖动的项放到目标格” 之后的顺序让位，空位在目标格
    @Test
    func otherCellsMakeRoomForTarget() throws {
        let (_, grid) = makeGrid()

        try drag(item: 1, to: windowPoint(ofCell: 4, in: grid), in: grid)

        #expect(try cellIndices(in: grid) == [0, 4, 1, 2, 3, 5])
    }

    // MARK: 松开

    /// 在另一格松开：拖动图像落进目标格，落定期间网格不响应按下；
    /// 落定之后这一格显示出来，保存回调拿到拖动的项与目标格
    @Test
    func releaseOnAnotherCellSavesAfterLanding() async throws {
        let (_, grid) = makeGrid()
        let target = windowPoint(ofCell: 4, in: grid)
        let itemView = try drag(item: 1, to: target, in: grid)

        try send(.leftMouseUp, to: itemView, at: target)

        let image = try #require(grid.dragImage)
        let targetInClipView = try #require(grid.superview).convert(target, from: nil)

        #expect(moves.isEmpty)
        #expect(image.iconCenter == screenIconCenter(ofCell: 4, in: grid))
        #expect(grid.hitTest(targetInClipView) == nil)

        try await waitUntil { grid.dragImage == nil }

        #expect(moves.map(\.itemID) == [items[1].id])
        #expect(moves.map(\.targetIndex) == [4])
        #expect(!itemView.isContentHidden)
        #expect(itemView.frame == layout.cellFrames[4])
    }

    /// 在原来的格里松开：落定之后什么都不保存
    @Test
    func releaseInPlaceDoesNotSave() async throws {
        let (_, grid) = makeGrid()
        let nearby = offset(windowPoint(ofCell: 1, in: grid), 20, 10)
        let itemView = try drag(item: 1, to: nearby, in: grid)

        try send(.leftMouseUp, to: itemView, at: nearby)

        try await waitUntil { grid.dragImage == nil }

        #expect(grid.dragImage == nil)
        #expect(moves.isEmpty)
        #expect(selections.isEmpty)
        #expect(!itemView.isContentHidden)
    }

    // MARK: 中断

    /// 拖动中网格离开窗口（层级被重建）：拖动作废、图像消失、不调任何回调；这次按下之后的拖动与抬起什么都不触发
    @Test
    func leavingWindowDuringDragCancels() throws {
        let (scrollView, grid) = makeGrid()
        let itemView = try drag(item: 1, to: windowPoint(ofCell: 4, in: grid), in: grid)

        scrollView.removeFromSuperview()

        #expect(grid.dragImage == nil)
        #expect(!itemView.isContentHidden)

        try send(.leftMouseDragged, to: itemView, at: outsidePoint)
        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        #expect(moves.isEmpty)
        #expect(selections.isEmpty)
    }

    /// 拖动中面板开始收起：网格恢复原来的样子，图像消失；之后在另一格抬起也不落定、不保存
    @Test
    func cancelDuringDragRestoresGrid() throws {
        let (_, grid) = makeGrid()
        let target = windowPoint(ofCell: 4, in: grid)
        let itemView = try drag(item: 1, to: target, in: grid)

        grid.cancelDrag()

        #expect(grid.dragImage == nil)
        #expect(!itemView.isContentHidden)
        #expect(try cellIndices(in: grid) == [0, 1, 2, 3, 4, 5])

        try send(.leftMouseUp, to: itemView, at: target)

        #expect(grid.dragImage == nil)
        #expect(moves.isEmpty)
        #expect(selections.isEmpty)
    }

    /// 落定途中网格离开窗口：拖动图像立即消失，保存仍按松开时的结果进行一次
    @Test
    func leavingWindowDuringLandingStillSaves() async throws {
        let (scrollView, grid) = makeGrid()
        let target = windowPoint(ofCell: 4, in: grid)
        let itemView = try drag(item: 1, to: target, in: grid)

        try send(.leftMouseUp, to: itemView, at: target)
        scrollView.removeFromSuperview()

        #expect(grid.dragImage == nil)

        try await waitUntil { !moves.isEmpty }

        #expect(moves.map(\.itemID) == [items[1].id])
        #expect(moves.map(\.targetIndex) == [4])
    }

    // MARK: 滚动

    /// 落定途中网格滚动（例如松开时还有惯性滚动）：拖动图像的落点跟着目标格滚动之后的位置，
    /// 不落到旧位置；落定之后保存的仍是松开时的目标格
    @Test
    func scrollDuringLandingMovesLandingPoint() async throws {
        let (scrollView, grid) = makeGrid()

        // 滚动视图只露出第一行，网格还能向下滚一行
        scrollView.setFrameSize(CGSize(
            width: layout.gridSize.width,
            height: FolderPanelMetrics.cellSize
        ))

        scrollView.layoutSubtreeIfNeeded()

        let target = windowPoint(ofCell: 2, in: grid)
        let itemView = try drag(item: 0, to: target, in: grid)

        try send(.leftMouseUp, to: itemView, at: target)

        let image = try #require(grid.dragImage)
        let landingPoint = image.iconCenter

        let clipView = scrollView.contentView

        clipView.scroll(to: CGPoint(x: 0, y: FolderPanelMetrics.cellSize))
        scrollView.reflectScrolledClipView(clipView)

        #expect(image.iconCenter != landingPoint)
        #expect(image.iconCenter == screenIconCenter(ofCell: 2, in: grid))

        try await waitUntil { grid.dragImage == nil }

        #expect(moves.map(\.itemID) == [items[0].id])
        #expect(moves.map(\.targetIndex) == [2])
    }
}

// MARK: - Private

extension FolderGridDragTests {
    /// 与网格同一套布局：6 格排成 3 列、2 行
    private var layout: FolderGridLayout {
        FolderGridLayout(
            itemCount: items.count,
            availableSize: CGSize(width: 2000, height: 2000)
        )
    }

    /// 窗口以外的一点，窗口坐标：在当前层级的轮廓之外
    private var outsidePoint: CGPoint {
        CGPoint(x: -100, y: -100)
    }

    /// 放进离屏窗口的网格：网格作为滚动视图的文档视图，单元格在排版时建好
    /// - Parameter isDraggable: 是否像文件夹的层级那样交给网格拖动的动作
    private func makeGrid(
        isDraggable: Bool = true
    ) -> (scrollView: NSScrollView, grid: FolderGridView) {
        let layout = layout
        let outline = window.frame

        let dragActions = FolderGridDragActions(
            containsScreenPoint: { outline.contains($0) },
            moveHandler: { [weak self] in self?.moves.append(($0.id, $1)) }
        )

        let grid = FolderGridView(
            items: items,
            layout: layout,
            previewIconCount: 0,
            hiddenItemIDs: [],
            fileThumbnailLoader: nil,
            openInFinderHandler: nil,
            dragActions: isDraggable ? dragActions : nil
        ) { [weak self] in
            self?.selections.append($0.id)
        }

        let scrollView = NSScrollView(frame: CGRect(
            origin: CGPoint(x: 50, y: 50),
            size: layout.gridSize
        ))

        scrollView.documentView = grid

        window.contentView?.addSubview(scrollView)
        scrollView.layoutSubtreeIfNeeded()

        return (scrollView, grid)
    }

    /// 按下某一项并拖到给定位置，返回它的单元格
    @discardableResult
    private func drag(
        item index: Int,
        to location: CGPoint,
        in grid: FolderGridView
    ) throws -> FolderGridItemView {
        let itemView = try cellView(ofItem: index, in: grid)
        let center = windowPoint(ofCell: index, in: grid)

        try send(.leftMouseDown, to: itemView, at: center)
        try send(.leftMouseDragged, to: itemView, at: offset(center, 10, 0))
        try send(.leftMouseDragged, to: itemView, at: location)

        return itemView
    }

    /// 把窗口里某一点的按下、拖动或抬起直接交给单元格
    private func send(
        _ type: NSEvent.EventType,
        to itemView: FolderGridItemView,
        at location: CGPoint
    ) throws {
        let event = try #require(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        switch type {
        case .leftMouseDown:
            itemView.mouseDown(with: event)

        case .leftMouseDragged:
            itemView.mouseDragged(with: event)

        default:
            itemView.mouseUp(with: event)
        }
    }

    /// 某一项的单元格：按它原来的格找
    private func cellView(
        ofItem index: Int,
        in grid: FolderGridView
    ) throws -> FolderGridItemView {
        let frame = layout.cellFrames[index]

        return try #require(
            grid.subviews
                .compactMap { $0 as? FolderGridItemView }
                .first { $0.frame == frame }
        )
    }

    /// 各项的单元格现在所在的格，按项原来的顺序
    private func cellIndices(in grid: FolderGridView) throws -> [Int] {
        let itemViews = grid.subviews.compactMap { $0 as? FolderGridItemView }

        // 单元格按建的先后加进网格，建的先后就是项原来的顺序
        return try itemViews.map { itemView in
            try #require(layout.cellFrames.firstIndex(of: itemView.frame))
        }
    }

    /// 某一格的中心，窗口坐标
    private func windowPoint(ofCell index: Int, in grid: FolderGridView) -> CGPoint {
        let frame = layout.cellFrames[index]

        return grid.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
    }

    /// 某一格的图标中心，AppKit 屏幕坐标
    private func screenIconCenter(ofCell index: Int, in grid: FolderGridView) -> CGPoint {
        let frame = layout.cellFrames[index]

        let center = CGPoint(
            x: frame.midX,
            y: frame.minY + FolderPanelMetrics.iconCenterY
        )

        return window.convertPoint(toScreen: grid.convert(center, to: nil))
    }

    /// 平移一个点
    private func offset(_ point: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: point.x + dx, y: point.y + dy)
    }

    /// 等到条件成立，最多等 100 轮、每轮至少 20 ms
    ///
    /// 按轮数而不按时钟等：落定的收尾回到主线程时排在其它测试已经排着的任务之后，整套测试一起跑时会晚到几十秒；
    /// 每一轮也排在它之后，轮数够了它一定已经跑过
    private func waitUntil(_ condition: () -> Bool) async throws {
        var round = 0

        while !condition(), round < 100 {
            try await Task.sleep(for: .milliseconds(20))
            round += 1
        }
    }
}
