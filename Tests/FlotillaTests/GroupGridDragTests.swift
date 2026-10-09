import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupGridDragTests

/// 面板里拖动文件夹的项：移动不超过 5 pt 仍是点击，超过即开始拖动、不再算点击；
/// 拖到别的格上其余各格让位，拖出轮廓其余各格补位；在轮廓之内松开落定后保存新的顺序；
/// 开始拖动满 0.5 s、鼠标又在 “移除” 的边界之外时 “移除” 浮出，之后松开才删除这一项，浮出之前在轮廓之外松开这一项飞回原位；
/// 松开的一刻就请面板按鼠标的位置更新点击穿透；
/// 拖动途中层级被重建或面板收起时作废，数据不变，落定途中的保存照常进行；落定途中网格滚动时落点跟着目标格
///
/// 窗口从不上屏：事件直接交给单元格，拖动图像只在面板显示时才排进屏幕
@MainActor
final class GroupGridDragTests {
    /// 6 个网页：3 列、2 行
    private let items: [GroupItem]

    /// 网格所在的离屏窗口；当前层级的轮廓按它的 frame 算，“移除” 的边界在它四周各扩 100 pt
    private let window = NSWindow(
        contentRect: CGRect(x: 200, y: 200, width: 600, height: 500),
        styleMask: .borderless,
        backing: .buffered,
        defer: true
    )

    /// 保存回调收到的项与目标格
    private var moves: [(itemID: UUID, targetIndex: Int)] = []

    /// 删除回调收到的项
    private var removals: [UUID] = []

    /// 点击过的项
    private var selections: [UUID] = []

    /// 松开时的回调被调用的次数
    private var releaseCount = 0

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

    // MARK: 让位与补位

    /// 拖到另一格上：其余各项按 “拖动的项放到目标格” 之后的顺序让位，空位在目标格
    @Test
    func otherCellsMakeRoomForTarget() throws {
        let (_, grid) = makeGrid()

        try drag(item: 1, to: windowPoint(ofCell: 4, in: grid), in: grid)

        #expect(try cellIndices(in: grid) == [0, 4, 1, 2, 3, 5])
    }

    /// 拖到轮廓之外：其余各项按原来的顺序补上空位，最后一格空出来
    @Test
    func otherCellsCloseUpOutsideOutline() throws {
        let (_, grid) = makeGrid()

        try drag(item: 1, to: outsidePoint, in: grid)

        var indices = try cellIndices(in: grid)
        indices.remove(at: 1)

        #expect(indices == [0, 1, 2, 3, 4])
    }

    // MARK: 松开

    /// 在轮廓之内另一格松开：拖动图像按展开动画的时长落进目标格，落定期间网格不响应按下；
    /// 落定之后这一格显示出来，保存回调拿到拖动的项与目标格
    @Test
    func releaseOnAnotherCellSavesAfterLanding() async throws {
        let (_, grid) = makeGrid()
        let target = windowPoint(ofCell: 4, in: grid)
        let itemView = try drag(item: 1, to: target, in: grid)

        try send(.leftMouseUp, to: itemView, at: target)

        let released = ContinuousClock.now
        let image = try #require(grid.dragImage)
        let targetInClipView = try #require(grid.superview).convert(target, from: nil)

        #expect(moves.isEmpty)
        #expect(image.iconCenter == screenIconCenter(ofCell: 4, in: grid))
        #expect(image.landingDuration == GroupPanelMetrics.expandDuration)
        #expect(grid.hitTest(targetInClipView) == nil)

        try await waitUntil { grid.dragImage == nil }

        #expect(ContinuousClock.now - released >= .seconds(GroupPanelMetrics.expandDuration))
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
        #expect(removals.isEmpty)
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
        #expect(removals.isEmpty)
        #expect(selections.isEmpty)
        #expect(releaseCount == 0)
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
        #expect(removals.isEmpty)
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
            height: GroupPanelMetrics.cellSize
        ))

        scrollView.layoutSubtreeIfNeeded()

        let target = windowPoint(ofCell: 2, in: grid)
        let itemView = try drag(item: 0, to: target, in: grid)

        try send(.leftMouseUp, to: itemView, at: target)

        let image = try #require(grid.dragImage)
        let landingPoint = image.iconCenter

        let clipView = scrollView.contentView

        clipView.scroll(to: CGPoint(x: 0, y: GroupPanelMetrics.cellSize))
        scrollView.reflectScrolledClipView(clipView)

        #expect(image.iconCenter != landingPoint)
        #expect(image.iconCenter == screenIconCenter(ofCell: 2, in: grid))

        try await waitUntil { grid.dragImage == nil }

        #expect(moves.map(\.itemID) == [items[0].id])
        #expect(moves.map(\.targetIndex) == [2])
    }
}

// MARK: - Remove Label

extension GroupGridDragTests {
    /// 拖到 “移除” 的边界之外：开始拖动起计时没满时不浮出，满 0.5 s 才浮出；刚甩出面板就松手不该误删
    @Test
    func removeLabelAppearsAfterDelayBeyondBoundary() async throws {
        let (_, grid) = makeGrid()
        let began = ContinuousClock.now

        try drag(item: 1, to: outsidePoint, in: grid)

        let image = try #require(grid.dragImage)

        #expect(!image.removeLabel.isShowing)

        try await waitUntil { image.removeLabel.isShowing }

        #expect(image.removeLabel.isShowing)
        #expect(ContinuousClock.now - began >= .seconds(0.5))
    }

    /// “移除” 浮出之后松开：删除回调只调一次，拿到的是拖动的项，不保存；
    /// 拖动到此结束，拖动图像不飞走，连同 “移除” 在原地按 0.26 s 淡出
    @Test
    func releaseAfterRemoveLabelRemovesItem() async throws {
        let (_, grid) = makeGrid()
        let itemView = try drag(item: 1, to: outsidePoint, in: grid)
        let image = try #require(grid.dragImage)

        try await waitUntil { image.removeLabel.isShowing }

        #expect(image.removeLabel.isShowing)

        let iconCenter = image.iconCenter

        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        #expect(removals == [items[1].id])
        #expect(moves.isEmpty)
        #expect(selections.isEmpty)
        #expect(grid.dragImage == nil)
        #expect(image.iconCenter == iconCenter)
        #expect(image.landingStart == nil)
        #expect(image.fadeOutDuration == 0.26)
    }

    /// 计时已满、鼠标在轮廓与 “移除” 的边界之间：“移除” 不浮出；再拖到边界之外，立即浮出，不重新计时
    @Test
    func removeLabelWaitsForBoundary() async throws {
        let (_, grid) = makeGrid()
        let itemView = try drag(item: 1, to: nearbyPoint, in: grid)
        let image = try #require(grid.dragImage)

        // 等满全部轮数：总时长超过计时，这时计时早已满
        try await waitUntil { image.removeLabel.isShowing }

        #expect(!image.removeLabel.isShowing)

        try send(.leftMouseDragged, to: itemView, at: outsidePoint)

        #expect(image.removeLabel.isShowing)
    }

    /// “移除” 浮出之后退回轮廓与边界之间：“移除” 淡出；在这里松开不删除，这一项飞回原来的格，什么都不保存
    @Test
    func releaseInsideBoundaryReturnsItem() async throws {
        let (_, grid) = makeGrid()
        let itemView = try drag(item: 1, to: outsidePoint, in: grid)
        let image = try #require(grid.dragImage)

        try await waitUntil { image.removeLabel.isShowing }

        #expect(image.removeLabel.isShowing)

        try send(.leftMouseDragged, to: itemView, at: nearbyPoint)

        #expect(!image.removeLabel.isShowing)

        try send(.leftMouseUp, to: itemView, at: nearbyPoint)

        #expect(removals.isEmpty)
        #expect(image.iconCenter == screenIconCenter(ofCell: 1, in: grid))

        try await waitUntil { grid.dragImage == nil }

        #expect(try cellIndices(in: grid) == [0, 1, 2, 3, 4, 5])
        #expect(!itemView.isContentHidden)
        #expect(moves.isEmpty)
        #expect(removals.isEmpty)
    }

    /// “移除” 浮出之后回到面板里：“移除” 淡出，表示此时松开不会删除；
    /// 再拖到边界之外立即浮出，不重新计时，这时松开就删除
    @Test
    func leavingAgainShowsRemoveLabelAtOnce() async throws {
        let (_, grid) = makeGrid()
        let itemView = try drag(item: 1, to: outsidePoint, in: grid)
        let image = try #require(grid.dragImage)

        try await waitUntil { image.removeLabel.isShowing }

        #expect(image.removeLabel.isShowing)

        try send(.leftMouseDragged, to: itemView, at: windowPoint(ofCell: 4, in: grid))

        #expect(!image.removeLabel.isShowing)

        try send(.leftMouseDragged, to: itemView, at: outsidePoint)

        #expect(image.removeLabel.isShowing)

        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        #expect(removals == [items[1].id])
        #expect(moves.isEmpty)
    }

    /// 计时没满就在 “移除” 的边界之外松开：多拖出一点就松手不该误删，这一项飞回原来的格；
    /// 飞回照抄程序坞按 0.32 s 收尾，比落进目标格慢；落定期间网格不响应按下，落定之后各格回到拖动前的位置，
    /// 什么都不保存；松开之后不再浮出 “移除”
    @Test
    func releaseBeforeRemoveLabelReturnsItem() async throws {
        let (_, grid) = makeGrid()

        // 先在另一格上让过位，再拖出面板
        let itemView = try drag(item: 1, to: windowPoint(ofCell: 4, in: grid), in: grid)

        try send(.leftMouseDragged, to: itemView, at: outsidePoint)

        let image = try #require(grid.dragImage)

        #expect(!image.removeLabel.isShowing)

        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        let released = ContinuousClock.now

        let originalCell = try #require(grid.superview).convert(
            windowPoint(ofCell: 1, in: grid),
            from: nil
        )

        #expect(removals.isEmpty)
        #expect(grid.dragImage === image)
        #expect(image.iconCenter == screenIconCenter(ofCell: 1, in: grid))
        #expect(image.landingDuration == 0.32)
        #expect(grid.hitTest(originalCell) == nil)

        try await waitUntil { grid.dragImage == nil }

        #expect(ContinuousClock.now - released >= .seconds(0.32))
        #expect(try cellIndices(in: grid) == [0, 1, 2, 3, 4, 5])
        #expect(!itemView.isContentHidden)
        #expect(moves.isEmpty)
        #expect(removals.isEmpty)
        #expect(selections.isEmpty)

        // 等满全部轮数：总时长超过计时
        try await waitUntil { image.removeLabel.isShowing }

        #expect(!image.removeLabel.isShowing)
    }

    /// 在轮廓与边界之间松开、这一项落回原位：松开的一刻就请面板按鼠标的位置更新点击穿透，落定之后不再请。
    /// 落回原位不重建面板，等鼠标下一次移动才更新的话，鼠标停在轮廓之外直接点击，点击落在面板窗口里，
    /// 既不穿透到下面的窗口，也不收起面板
    @Test
    func releaseOutsideUpdatesPassthroughAtOnce() async throws {
        let (_, grid) = makeGrid()
        let itemView = try drag(item: 1, to: nearbyPoint, in: grid)

        #expect(releaseCount == 0)

        try send(.leftMouseUp, to: itemView, at: nearbyPoint)

        // 还在飞回原来的格，落定之前就已更新
        #expect(grid.dragImage?.landingDuration == GroupPanelMetrics.returnDuration)
        #expect(releaseCount == 1)

        try await waitUntil { grid.dragImage == nil }

        #expect(grid.dragImage == nil)
        #expect(releaseCount == 1)
        #expect(removals.isEmpty)
    }

    /// 计时中拖动作废（面板开始收起，或网格离开窗口）：之后不浮出 “移除”，不调任何回调
    @Test(arguments: [false, true])
    func interruptionKeepsRemoveLabelHidden(leavesWindow: Bool) async throws {
        let (scrollView, grid) = makeGrid()
        let itemView = try drag(item: 1, to: outsidePoint, in: grid)
        let image = try #require(grid.dragImage)

        if leavesWindow {
            scrollView.removeFromSuperview()
        } else {
            grid.cancelDrag()
        }

        // 等满全部轮数：总时长超过计时，作废之前开始的计时若没有停掉，这时已经浮出
        try await waitUntil { image.removeLabel.isShowing }

        #expect(!image.removeLabel.isShowing)

        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        #expect(moves.isEmpty)
        #expect(removals.isEmpty)
        #expect(selections.isEmpty)
        #expect(releaseCount == 0)
    }

    /// 拖动中网格滚动过、原来的格滚出了可见区域：“移除” 浮出之前在轮廓之外松开，
    /// 网格先滚到完整看见原来的格，拖动图像落进这一格滚动之后的屏幕位置，落回原位的过程看得见
    @Test
    func releaseOutsideAfterScrollingRevealsOriginalCell() async throws {
        let (scrollView, grid) = makeGrid()

        // 滚动视图只露出一行，拖动中网格向下滚一行，原来的格所在的第一行滚出可见区域
        scrollView.setFrameSize(CGSize(
            width: layout.gridSize.width,
            height: GroupPanelMetrics.cellSize
        ))

        scrollView.layoutSubtreeIfNeeded()

        let itemView = try drag(item: 0, to: windowPoint(ofCell: 1, in: grid), in: grid)
        let clipView = scrollView.contentView

        clipView.scroll(to: CGPoint(x: 0, y: GroupPanelMetrics.cellSize))
        scrollView.reflectScrolledClipView(clipView)

        #expect(!grid.visibleRect.intersects(layout.cellFrames[0]))

        try send(.leftMouseDragged, to: itemView, at: outsidePoint)
        try send(.leftMouseUp, to: itemView, at: outsidePoint)

        let image = try #require(grid.dragImage)

        #expect(grid.visibleRect.contains(layout.cellFrames[0]))
        #expect(image.iconCenter == screenIconCenter(ofCell: 0, in: grid))

        try await waitUntil { grid.dragImage == nil }

        #expect(removals.isEmpty)
        #expect(moves.isEmpty)
    }
}

// MARK: - Private

extension GroupGridDragTests {
    /// 与网格同一套布局：6 格排成 3 列、2 行
    private var layout: GroupGridLayout {
        GroupGridLayout(
            itemCount: items.count,
            availableSize: CGSize(width: 2000, height: 2000)
        )
    }

    /// 窗口以外的一点，窗口坐标：在当前层级的轮廓与 “移除” 的边界之外
    private var outsidePoint: CGPoint {
        CGPoint(x: -300, y: -300)
    }

    /// 窗口以外的一点，窗口坐标：在当前层级的轮廓之外、“移除” 的边界之内
    private var nearbyPoint: CGPoint {
        CGPoint(x: -50, y: -50)
    }

    /// 放进离屏窗口的网格：网格作为滚动视图的文档视图，单元格在排版时建好
    /// - Parameter isDraggable: 是否像文件夹的层级那样交给网格拖动的动作
    private func makeGrid(
        isDraggable: Bool = true
    ) -> (scrollView: NSScrollView, grid: GroupGridView) {
        let layout = layout
        let outline = window.frame
        let removeBoundary = outline.insetBy(dx: -100, dy: -100)

        let dragActions = GroupGridDragActions(
            containsScreenPoint: { outline.contains($0) },
            removeBoundaryContainsScreenPoint: { removeBoundary.contains($0) },
            releaseHandler: { [weak self] in self?.releaseCount += 1 },
            moveHandler: { [weak self] in self?.moves.append(($0.id, $1)) },
            removeHandler: { [weak self] in self?.removals.append($0.id) }
        )

        let grid = GroupGridView(
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
        in grid: GroupGridView
    ) throws -> GroupGridItemView {
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
        to itemView: GroupGridItemView,
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
        in grid: GroupGridView
    ) throws -> GroupGridItemView {
        let frame = layout.cellFrames[index]

        return try #require(
            grid.subviews
                .compactMap { $0 as? GroupGridItemView }
                .first { $0.frame == frame }
        )
    }

    /// 各项的单元格现在所在的格，按项原来的顺序
    private func cellIndices(in grid: GroupGridView) throws -> [Int] {
        let itemViews = grid.subviews.compactMap { $0 as? GroupGridItemView }

        // 单元格按建的先后加进网格，建的先后就是项原来的顺序
        return try itemViews.map { itemView in
            try #require(layout.cellFrames.firstIndex(of: itemView.frame))
        }
    }

    /// 某一格的中心，窗口坐标
    private func windowPoint(ofCell index: Int, in grid: GroupGridView) -> CGPoint {
        let frame = layout.cellFrames[index]

        return grid.convert(CGPoint(x: frame.midX, y: frame.midY), to: nil)
    }

    /// 某一格的图标中心，AppKit 屏幕坐标
    private func screenIconCenter(ofCell index: Int, in grid: GroupGridView) -> CGPoint {
        let frame = layout.cellFrames[index]

        let center = CGPoint(
            x: frame.midX,
            y: frame.minY + GroupPanelMetrics.iconCenterY
        )

        return window.convertPoint(toScreen: grid.convert(center, to: nil))
    }

    /// 平移一个点
    private func offset(_ point: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: point.x + dx, y: point.y + dy)
    }

    /// 等到条件成立，最多等 100 轮、每轮至少 20 ms：总共至少 2 s，比落定与 “移除” 的计时都长
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
