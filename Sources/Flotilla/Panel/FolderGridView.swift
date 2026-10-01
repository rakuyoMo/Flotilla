import AppKit

// MARK: - FolderGridView

/// 一个层级的网格：按 `FolderGridLayout` 摆放每一项的单元格，作为滚动视图的文档视图；
/// 访达里的文件夹的层级在末尾另有一格“在访达中打开”，其中的文件换上内容缩略图
///
/// 只为与可见区域相交的行（上下各多一行）建单元格，滚动时按需补建，建过的不删：
/// 访达里的文件夹可能有上千项，一次建齐会让展开明显卡顿。缩略图请求也只为这个范围里的格保留，
/// 快速滚过上千项后，看得见的格不必排在滚过的格后面等 QuickLook
@MainActor
final class FolderGridView: NSView {
    /// 这一层的项，顺序即展示顺序
    private let items: [FolderItem]

    /// 每一格的 frame：各项依次在前，“在访达中打开”在最后
    private let cellFrames: [CGRect]

    /// 子文件夹图标里叠加的预览图标数量
    private let previewIconCount: Int

    /// 隐藏的项的 id：访达里的文件夹显示隐藏文件时，这些项半透明
    private let hiddenItemIDs: Set<UUID>

    /// 为文件请求内容缩略图；只有访达里的文件夹的层级有，为 nil 时文件显示图标
    private let fileThumbnailLoader: FileThumbnailLoader?

    /// 点击“在访达中打开”后执行；为 nil 时没有这一格
    private let openInFinderHandler: (() -> Void)?

    /// 点击某一项后执行
    private let selectionHandler: (FolderItem) -> Void

    /// 已建好单元格的格序号，与 `cellFrames` 的下标一致
    private var builtCellIndices = IndexSet()

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
    ///   - openInFinderHandler: 点击“在访达中打开”后执行；为 nil 时没有这一格
    ///   - selectionHandler: 点击某一项后执行
    init(
        items: [FolderItem],
        layout: FolderGridLayout,
        previewIconCount: Int,
        hiddenItemIDs: Set<UUID>,
        fileThumbnailLoader: FileThumbnailLoader?,
        openInFinderHandler: (() -> Void)?,
        selectionHandler: @escaping (FolderItem) -> Void
    ) {
        self.items = items
        self.previewIconCount = previewIconCount
        self.hiddenItemIDs = hiddenItemIDs
        self.fileThumbnailLoader = fileThumbnailLoader
        self.openInFinderHandler = openInFinderHandler
        self.selectionHandler = selectionHandler

        // 各项之后，布局里还有一格时才放“在访达中打开”
        let cellCount = openInFinderHandler == nil ? items.count : items.count + 1
        cellFrames = Array(layout.cellFrames.prefix(cellCount))

        super.init(frame: CGRect(origin: .zero, size: layout.gridSize))
    }

    /// 网格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

        let frame = cellFrames[index]

        return CGPoint(
            x: frame.midX,
            y: frame.minY + FolderPanelMetrics.iconCenterY
        )
    }

    /// 放进滚动视图后跟随滚动：每次滚动都同步补建新露出的行
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()

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

    /// 离开窗口（离开这一层、面板收起）时，取消还没完成的缩略图请求，晚到的结果不再换上
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window == nil else { return }

        fileThumbnailLoader?.cancelAll()
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

// MARK: - Private

extension FolderGridView {
    /// 滚动视图的可见区域变了：在画出来之前补建新露出的行，缩略图请求跟着换到新的范围
    @objc
    private func clipViewBoundsDidChange(_: Notification) {
        buildCells(near: visibleRect)
        updateThumbnailRequests()
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

    /// 建一格：各项的单元格，或排在最后的“在访达中打开”
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

    /// 加上“在访达中打开”的单元格；没有这一格时什么也不做
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
    /// “在访达中打开”的原图，只加载一次
    private static let openInFinderSourceIcon = makeOpenInFinderSourceIcon()

    /// 读取 Dock 自己给“在访达中打开”用的 `openinfinder.png`（透明底上的黑色箭头，含 2 倍图）；
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
