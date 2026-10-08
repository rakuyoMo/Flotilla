import AppKit

// MARK: - FolderGridView

/// 一个层级的网格：按 `FolderGridLayout` 摆放每一项的单元格，作为滚动视图的文档视图；
/// 访达里的文件夹的层级在末尾另有一格 “在访达中打开”，其中的文件换上内容缩略图
///
/// 只为与可见区域相交的行（上下各多一行）建单元格，滚动时按需补建，建过的不删：
/// 访达里的文件夹可能有上千项，一次建齐会让展开明显卡顿。缩略图请求也只为这个范围里的格保留，
/// 快速滚过上千项后，看得见的格不必排在滚过的格后面等 QuickLook
///
/// 文件夹的层级里各项可以拖动：其余各格让位或补位，在轮廓之内松开保存新的顺序，在轮廓之外松开删除这一项
@MainActor
final class FolderGridView: NSView {
    /// 这一层的项，顺序即展示顺序
    private let items: [FolderItem]

    /// 每一格的 frame：各项依次在前，“在访达中打开” 在最后
    private let cellFrames: [CGRect]

    /// 列数：拖动时按它算鼠标所在的格
    private let columnCount: Int

    /// 子文件夹图标里叠加的预览图标数量
    private let previewIconCount: Int

    /// 隐藏的项的 id：访达里的文件夹显示隐藏文件时，这些项半透明
    private let hiddenItemIDs: Set<UUID>

    /// 为文件请求内容缩略图；只有访达里的文件夹的层级有，为 nil 时文件显示图标
    private let fileThumbnailLoader: FileThumbnailLoader?

    /// 点击 “在访达中打开” 后执行；为 nil 时没有这一格
    private let openInFinderHandler: (() -> Void)?

    /// 点击某一项后执行
    private let selectionHandler: (FolderItem) -> Void

    /// 拖动各项时的判定与动作；只有文件夹的层级有，为 nil 时各项不能拖动
    private let dragActions: FolderGridDragActions?

    /// 已建好单元格的格序号，与 `cellFrames` 的下标一致
    private var builtCellIndices = IndexSet()

    /// 已建的各项单元格，按项的下标：拖动时据此移动单元格
    private var itemViews: [Int: FolderGridItemView] = [:]

    /// 进行中的拖动，含落定的那段时间；没有时为 nil
    private var dragSession: FolderGridDragSession?

    /// 拖动图像：拖动与落定期间有，消失后为 nil
    var dragImage: FolderGridDragImage? {
        dragSession?.image
    }

    /// 已建的子文件夹与它的单元格：系统外观变化时，按新外观重新渲染这些单元格的图标
    private var folderItemViews: [(folder: Folder, itemView: FolderGridItemView)] = []

    /// 已建、还没换上缩略图的文件格，按格序号；只在有缩略图加载器时记，格在看得见附近时为它请求缩略图
    private var cellsAwaitingThumbnails: [Int: FolderGridItemView] = [:]

    /// 在看得见附近为文件格发出的缩略图请求，按格序号记请求编号：拿到缩略图时移除，格滚出看得见附近时取消并移除
    ///
    /// 生成不出缩略图的请求同样留到格滚出：留在看得见附近时，不在每一步滚动里重复请求
    private var thumbnailRequestIDs: [Int: UUID] = [:]

    /// 自上而下排列，与 `FolderGridLayout` 的坐标系一致，滚动视图初始停在顶部
    override var isFlipped: Bool {
        true
    }

    /// 创建网格；单元格等到排版或滚动时才按可见区域建
    /// - Parameters:
    ///   - items: 这一层的项，顺序即展示顺序
    ///   - layout: 按格数算好的布局
    ///   - previewIconCount: 子文件夹图标里叠加的预览图标数量
    ///   - hiddenItemIDs: 隐藏的项的 id，这些项半透明
    ///   - fileThumbnailLoader: 为文件请求内容缩略图；只有访达里的文件夹的层级传入，为 nil 时文件显示图标
    ///   - openInFinderHandler: 点击 “在访达中打开” 后执行；为 nil 时没有这一格
    ///   - dragActions: 拖动各项时的判定与动作；只有文件夹的层级传入，为 nil 时各项不能拖动
    ///   - selectionHandler: 点击某一项后执行
    init(
        items: [FolderItem],
        layout: FolderGridLayout,
        previewIconCount: Int,
        hiddenItemIDs: Set<UUID>,
        fileThumbnailLoader: FileThumbnailLoader?,
        openInFinderHandler: (() -> Void)?,
        dragActions: FolderGridDragActions? = nil,
        selectionHandler: @escaping (FolderItem) -> Void
    ) {
        self.items = items
        self.previewIconCount = previewIconCount
        self.hiddenItemIDs = hiddenItemIDs
        self.fileThumbnailLoader = fileThumbnailLoader
        self.openInFinderHandler = openInFinderHandler
        self.dragActions = dragActions
        self.selectionHandler = selectionHandler

        // 有 “在访达中打开” 时，它占布局里各项之后的那一格
        let cellCount = openInFinderHandler == nil ? items.count : items.count + 1
        cellFrames = Array(layout.cellFrames.prefix(cellCount))
        columnCount = layout.columnCount

        super.init(frame: CGRect(origin: .zero, size: layout.gridSize))
    }

    /// 网格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("不支持从归档解码")
    }

    /// 某一项的图标中心，自身坐标系；没有这一项时为 nil
    ///
    /// 按布局计算，不依赖单元格是否已建：返回时父层级刚重建、还没排版，缩回的目标格可能还没建
    func iconCenter(of itemID: UUID) -> CGPoint? {
        guard
            let index = items.firstIndex(where: { $0.id == itemID }),
            cellFrames.indices.contains(index)
        else {
            return nil
        }

        return iconCenter(inCell: index)
    }

    /// 放进滚动视图后跟随滚动：每次滚动都同步补建新露出的行
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()

        // 父视图换了：先停掉对上一个 clip view 的监听
        NotificationCenter.default.removeObserver(
            self,
            name: NSView.boundsDidChangeNotification,
            object: nil
        )

        guard let clipView = superview as? NSClipView else { return }

        clipView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
    }

    /// 离开窗口（离开这一层、面板收起、文件夹树变化重建）时，取消还没完成的缩略图请求，晚到的结果不再换上；
    /// 进行中的拖动随之作废
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window == nil else { return }

        fileThumbnailLoader?.cancelAll()
        cancelDrag()
    }

    /// 落定期间不响应新的按下，免得在新旧顺序之间又开始一次拖动
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard dragSession?.isLanding != true else { return nil }

        return super.hitTest(point)
    }

    /// 排版时为可见的行建单元格，并为其中的文件请求缩略图：第一次显示之前，滚动位置已经恢复，建的正是那里的行
    override func layout() {
        super.layout()

        buildCells(near: visibleRect)
        updateThumbnailRequests()
    }

    /// AppKit 提前准备可见区域以外的内容时（滚动时的预绘区域），一并建好那里的单元格；
    /// 这些格先不请求缩略图，滚进看得见附近时才请求
    override func prepareContent(in rect: NSRect) {
        super.prepareContent(in: rect)

        buildCells(near: rect)
    }

    /// 系统外观变化时，已建的子文件夹图标换成对应外观的底板；之后才建的单元格按建的时候的外观渲染
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        for (folder, itemView) in folderItemViews {
            itemView.icon = folderIcon(of: folder)
        }
    }
}

// MARK: - Dragging

extension FolderGridView {
    /// 单元格按下后移动超过阈值：开始拖动这一项
    ///
    /// 这一格的图标与名称隐藏，原处留出空位；拖动图像从原来的图标处起跟随鼠标
    /// - Parameters:
    ///   - itemView: 按下的单元格
    ///   - pressLocation: 按下的位置，窗口坐标
    ///   - event: 越过阈值的这次拖动
    /// - Returns: 开始了拖动时为 true；已有拖动、不在窗口里、或不是网格里某一项的单元格时为 false
    func beginDrag(
        of itemView: FolderGridItemView,
        pressedAt pressLocation: CGPoint,
        with event: NSEvent
    ) -> Bool {
        guard
            dragSession == nil,
            let window,
            let itemIndex = itemViews.first(where: { $0.value === itemView })?.key
        else {
            return false
        }

        // 让位只移动已有的单元格：懒建是为访达里上千项的目录，文件夹的层级一般不多，一次建齐
        buildCells(near: bounds)

        // 图标中心与按下的位置之差保持到拖动结束：鼠标在图标上的位置与按下时相同
        let iconCenter = screenPoint(ofIconInCell: itemIndex, in: window)
        let pressPoint = window.convertPoint(toScreen: pressLocation)

        let image = FolderGridDragImage(
            icon: itemView.icon,
            iconCenter: iconCenter,
            screenFrames: NSScreen.screens.map(\.frame),
            scale: window.backingScaleFactor
        )

        image.show(over: window)
        itemView.isContentHidden = true

        dragSession = FolderGridDragSession(
            itemIndex: itemIndex,
            itemView: itemView,
            iconOffset: CGVector(
                dx: iconCenter.x - pressPoint.x,
                dy: iconCenter.y - pressPoint.y
            ),
            image: image,
            location: event.locationInWindow,
            arrangement: FolderGridDragArrangement(
                itemCount: items.count,
                draggedIndex: itemIndex,
                targetIndex: itemIndex
            )
        )

        updateDrag()

        return true
    }

    /// 拖动中：图像跟随鼠标，各格按鼠标的位置让位或补位；
    /// 鼠标在轮廓之内、在网格可见区域的上方或下方时，网格随之滚动
    func continueDrag(with event: NSEvent) {
        guard isDragging else { return }

        dragSession?.location = event.locationInWindow

        autoscrollIfNeeded(with: event)
        updateDrag()
    }

    /// 松开：在轮廓之内落进目标格，落定之后保存新的顺序；在轮廓之外，图像立即消失，这一项从文件夹里删除
    func endDrag(with event: NSEvent) {
        guard isDragging else { return }

        dragSession?.location = event.locationInWindow
        updateDrag()

        guard let session = dragSession else { return }

        guard let targetIndex = session.arrangement.targetIndex else {
            remove(session)
            return
        }

        land(session, at: targetIndex)
    }

    /// 作废进行中的拖动：面板开始收起时由面板调用，网格离开窗口（层级被重建、面板隐藏）时自己调用
    ///
    /// 拖动图像立即消失，这一格显示出来；拖动中的各格恢复原来的样子，数据不变；
    /// 落定中的各格已在新的顺序上，保存仍按松开时的结果进行
    func cancelDrag() {
        guard let session = dragSession else { return }

        dragSession = nil
        session.image.close()
        session.itemView.isContentHidden = false

        guard !session.isLanding else { return }

        // 各格回到原来的格，不加动画
        for (index, itemView) in itemViews {
            itemView.layer?.removeAnimation(forKey: "position")
            itemView.frame = cellFrames[index]
        }
    }
}

// MARK: - Private

extension FolderGridView {
    /// 是否正在拖动：有进行中的拖动，且还没松开
    private var isDragging: Bool {
        guard let dragSession else { return false }

        return !dragSession.isLanding
    }

    /// 滚动视图的可见区域变了：在画出来之前补建新露出的行，缩略图请求跟着换到新的范围；
    /// 拖动中按鼠标当前的位置重新判定目标格，落定途中拖动图像的落点跟着目标格
    @objc
    private func clipViewBoundsDidChange(_: Notification) {
        buildCells(near: visibleRect)
        updateThumbnailRequests()
        updateDrag()
        updateLanding()
    }

    /// 为与给定区域相交的行建单元格，上下各多一行；已建的跳过
    private func buildCells(near rect: CGRect) {
        let area = nearbyArea(of: rect)

        guard !area.isEmpty else { return }

        let indices = cellFrames.indices.filter {
            !builtCellIndices.contains($0) && cellFrames[$0].intersects(area)
        }

        for index in indices {
            buildCell(at: index)
        }
    }

    /// 建一格：各项的单元格，或排在最后的 “在访达中打开”
    private func buildCell(at index: Int) {
        builtCellIndices.insert(index)

        guard items.indices.contains(index) else {
            addOpenInFinderItem(frame: cellFrames[index])
            return
        }

        let item = items[index]
        let (title, icon) = content(of: item)

        // 只捕获点击后的动作，不捕获网格自身：单元格是网格的子视图
        let itemView = FolderGridItemView(title: title, icon: icon) { [selectionHandler] in
            selectionHandler(item)
        }

        itemView.frame = cellFrames[index]
        addSubview(itemView)

        itemViews[index] = itemView

        // 文件夹的层级里，单元格把拖动转交给网格
        if dragActions != nil {
            itemView.dragTarget = self
        }

        // 隐藏的项与访达显示隐藏文件时一样，图标与名称都半透明；换上的缩略图同样半透明，按下照样压暗
        if hiddenItemIDs.contains(item.id) {
            itemView.alphaValue = FolderPanelMetrics.hiddenItemOpacity
        }

        // 记下子文件夹的单元格：外观变化时只有文件夹图标需要重新渲染
        if case .folder(let folder) = item {
            folderItemViews.append((folder, itemView))
        }

        // 访达里的文件夹的层级里，文件先显示图标；缩略图由 `updateThumbnailRequests()` 在格处于看得见附近时请求
        if case .file = item, fileThumbnailLoader != nil {
            cellsAwaitingThumbnails[index] = itemView
        }
    }

    /// 只为看得见附近（可见区域上下各多一行，与建格相同）的文件格保留缩略图请求
    ///
    /// QuickLook 按请求的先后生成：滚过的格的请求要取消，快速滚过上千项后，看得见的格才不必排在它们后面等上几秒
    private func updateThumbnailRequests() {
        guard let fileThumbnailLoader else { return }

        let area = nearbyArea(of: visibleRect)

        // 滚出这个范围的格：取消还没完成的请求；这些格还没换上缩略图，回来时再请求
        for (index, id) in thumbnailRequestIDs where !cellFrames[index].intersects(area) {
            fileThumbnailLoader.cancel(id)
            thumbnailRequestIDs[index] = nil
        }

        // 在这个范围里、还没换上缩略图、也没在请求的格：按格的先后请求，QuickLook 先生成上面的格
        let indices = cellsAwaitingThumbnails.keys
            .filter {
                thumbnailRequestIDs[$0] == nil
                    && cellFrames[$0].intersects(area)
            }
            .sorted()

        for index in indices {
            requestThumbnail(at: index, with: fileThumbnailLoader)
        }
    }

    /// 为一个文件格请求缩略图；生成后换上，这一格不再请求
    /// - Parameters:
    ///   - index: 格序号
    ///   - loader: 缩略图加载器
    private func requestThumbnail(at index: Int, with loader: FileThumbnailLoader) {
        guard case .file(let file) = items[index] else { return }

        // 网格持有加载器，加载器持有回调：回调弱引用网格，不形成循环
        thumbnailRequestIDs[index] = loader.loadThumbnail(of: file.url) { [weak self] thumbnail in
            guard let self else { return }

            thumbnailRequestIDs[index] = nil

            // 结果只落到发起请求的这一格；换上之后不再等缩略图
            cellsAwaitingThumbnails.removeValue(forKey: index)?.icon = thumbnail
        }
    }

    /// 一项显示的名称与图标：App、文件与网页用各自的图标与显示名，子文件夹用渲染出的文件夹图标与文件夹名
    private func content(of item: FolderItem) -> (title: String, icon: NSImage) {
        switch item {
        case .app(let app):
            (app.displayName, app.icon)

        case .folder(let folder):
            (folder.name, folderIcon(of: folder))

        case .file(let file):
            (file.displayName, file.icon)

        case .webPage(let webPage):
            (webPage.displayName, webPage.icon)
        }
    }

    /// 子文件夹的图标，底板按网格当前的外观取色
    private func folderIcon(of folder: Folder) -> NSImage {
        FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: FolderPanelMetrics.iconSize,
            appearance: FolderIconAppearance(effectiveAppearance)
        )
    }

    /// 加上 “在访达中打开” 的单元格；没有这一格时什么也不做
    /// - Parameter frame: 单元格的 frame
    private func addOpenInFinderItem(frame: CGRect) {
        guard let openInFinderHandler else { return }

        let title = String(
            localized: "panel.openInFinder",
            comment: "访达里的文件夹在面板里展开后，网格末尾那一格的名称"
        )

        // 图标只给原图的形状，颜色与合成方式由单元格按外观决定
        let itemView = FolderGridItemView(
            title: title,
            icon: Self.openInFinderSourceIcon,
            style: .openInFinder,
            clickHandler: openInFinderHandler
        )

        itemView.frame = frame
        addSubview(itemView)
    }

    /// 按鼠标最近的位置更新拖动：图像跟随鼠标；鼠标在轮廓之内时其余各项为目标格让位，在轮廓之外时依次补位
    private func updateDrag() {
        guard
            isDragging,
            let session = dragSession,
            let window,
            let dragActions
        else {
            return
        }

        let mouse = window.convertPoint(toScreen: session.location)

        session.image.move(to: CGPoint(
            x: mouse.x + session.iconOffset.dx,
            y: mouse.y + session.iconOffset.dy
        ))

        // 轮廓之外没有目标格，拖动的项不占格，即删除之后的样子
        let targetIndex: Int? = dragActions.containsScreenPoint(mouse)
            ? FolderGridDragArrangement.targetIndex(
                at: convert(session.location, from: nil),
                visibleRect: visibleRect,
                itemCount: items.count,
                columnCount: columnCount
            )
            : nil

        let arrangement = FolderGridDragArrangement(
            itemCount: items.count,
            draggedIndex: session.itemIndex,
            targetIndex: targetIndex
        )

        guard arrangement != session.arrangement else { return }

        dragSession?.arrangement = arrangement
        arrange(arrangement, draggedIndex: session.itemIndex)
    }

    /// 落定途中网格滚动（例如松开时还有惯性滚动）：拖动图像的落点跟着目标格现在的屏幕位置
    ///
    /// 目标格不变，落定按松开时的时长收尾，收尾时图像正好在这一格上，落定之后显示出来的格不跳
    private func updateLanding() {
        guard
            let session = dragSession,
            session.isLanding,
            let targetIndex = session.arrangement.targetIndex,
            let window
        else {
            return
        }

        session.image.moveLandingPoint(to: screenPoint(ofIconInCell: targetIndex, in: window))
    }

    /// 各格移到排列给出的格：其余各项从当前画面移过去，带动画；拖动的项看不见，直接放到目标格
    private func arrange(_ arrangement: FolderGridDragArrangement, draggedIndex: Int) {
        for (index, cellIndex) in arrangement.cellIndices.enumerated() {
            guard
                let itemView = itemViews[index],
                let cellIndex
            else {
                continue
            }

            if index == draggedIndex {
                itemView.frame = cellFrames[cellIndex]
            } else {
                move(itemView, to: cellFrames[cellIndex])
            }
        }
    }

    /// 单元格从当前画面上的位置移到新的格，带动画；动画途中又移动时从当时的画面接着移动
    private func move(_ itemView: FolderGridItemView, to frame: CGRect) {
        guard itemView.frame != frame else { return }

        let start = itemView.layer.map { $0.presentation()?.position ?? $0.position }

        itemView.frame = frame

        // 不在屏幕上的网格（离屏的测试窗口）里单元格还没有图层，只改位置
        guard
            let layer = itemView.layer,
            let start
        else {
            return
        }

        FolderGridDragAnimation.movePosition(of: layer, from: start)
    }

    /// 鼠标在轮廓之内、在网格可见区域的上方（标题区）或下方（底部留白、尾巴）时，网格随拖动滚动；轮廓之外不滚动
    ///
    /// 滚动之后 `clipViewBoundsDidChange(_:)` 按鼠标当前的位置重新判定目标格
    private func autoscrollIfNeeded(with event: NSEvent) {
        guard
            let window,
            let dragActions
        else {
            return
        }

        let mouse = window.convertPoint(toScreen: event.locationInWindow)
        let location = convert(event.locationInWindow, from: nil)
        let isAboveOrBelow = !(visibleRect.minY ... visibleRect.maxY).contains(location.y)

        guard
            dragActions.containsScreenPoint(mouse),
            isAboveOrBelow
        else {
            return
        }

        _ = autoscroll(with: event)
    }

    /// 在轮廓之外松开：图像立即消失，这一项从文件夹里删除
    ///
    /// 删除引起文件夹树变化，面板随即按剩下的项重建网格、重算尺寸
    private func remove(_ session: FolderGridDragSession) {
        dragSession = nil
        session.image.close()

        dragActions?.removeHandler(items[session.itemIndex])
    }

    /// 在轮廓之内松开：拖动图像落进目标格的图标位置，落定之后这一格显示出来，目标格变了才保存新的顺序
    ///
    /// 保存在落定之后：保存引起的重建与落定后的画面一致，不跳
    private func land(_ session: FolderGridDragSession, at targetIndex: Int) {
        guard
            let window,
            let moveHandler = dragActions?.moveHandler
        else {
            return
        }

        dragSession?.isLanding = true
        session.image.land(at: screenPoint(ofIconInCell: targetIndex, in: window))

        let image = session.image
        let item = items[session.itemIndex]
        let isMoved = targetIndex != session.itemIndex

        // 按时长收尾，不等 Core Animation 的完成回调：锁屏、显示器休眠时回调可能一直不来。
        // 回调与要保存的数据由这里持有、不靠网格：落定途中面板收起、这一层被重建，仍按松开时的结果保存
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(FolderPanelMetrics.expandDuration))

            self?.finishLanding(of: image)

            guard isMoved else { return }

            moveHandler(item, targetIndex)
        }
    }

    /// 落定：这一格显示出来，拖动图像消失；落定之前已经作废的什么都不做
    private func finishLanding(of image: FolderGridDragImage) {
        guard
            let session = dragSession,
            session.image === image
        else {
            return
        }

        dragSession = nil
        image.close()
        session.itemView.isContentHidden = false
    }

    /// 某一格的图标中心，网格坐标；不依赖单元格是否已建
    private func iconCenter(inCell index: Int) -> CGPoint {
        let frame = cellFrames[index]

        return CGPoint(
            x: frame.midX,
            y: frame.minY + FolderPanelMetrics.iconCenterY
        )
    }

    /// 某一格的图标中心，AppKit 屏幕坐标
    private func screenPoint(ofIconInCell index: Int, in window: NSWindow) -> CGPoint {
        window.convertPoint(toScreen: convert(iconCenter(inCell: index), to: nil))
    }

    /// 给定区域上下各多一行、限在网格之内：建格与保留缩略图请求都按这个范围
    ///
    /// 上下各多一行：慢慢滚动时，下一行在露出之前就已建好、已在请求缩略图
    private func nearbyArea(of rect: CGRect) -> CGRect {
        rect
            .insetBy(dx: 0, dy: -FolderPanelMetrics.cellSize)
            .intersection(bounds)
    }
}

// MARK: - Helpers

extension FolderGridView {
    /// “在访达中打开” 的原图，只加载一次
    private static let openInFinderSourceIcon = makeOpenInFinderSourceIcon()

    /// 读取 Dock 自己给 “在访达中打开” 用的 `openinfinder.png`（透明底上的黑色箭头，含 2 倍图）；
    /// 读不到时退回同样造型的系统符号
    private static func makeOpenInFinderSourceIcon() -> NSImage {
        let dock = Bundle(path: "/System/Library/CoreServices/Dock.app")

        if let icon = dock?.image(forResource: "openinfinder") {
            return icon
        }

        let symbol = NSImage(
            systemSymbolName: "arrowshape.turn.up.right.circle",
            accessibilityDescription: nil
        )

        return symbol ?? NSImage(size: CGSize(width: 1, height: 1))
    }
}
