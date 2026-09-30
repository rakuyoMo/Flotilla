import AppKit

// MARK: - FolderGridView

/// 一个层级的网格：按 `FolderGridLayout` 摆放每一项的单元格，作为滚动视图的文档视图；
/// 访达里的文件夹的层级在末尾另有一格“在访达中打开”
///
/// 只为与可见区域相交的行（上下各多一行）建单元格，滚动时按需补建，建过的不删：
/// 访达里的文件夹可能有上千项，一次建齐会让展开明显卡顿
@MainActor
final class FolderGridView: NSView {
    /// 这一层的项，顺序即展示顺序
    private let items: [FolderItem]

    /// 每一格的 frame：各项依次在前，“在访达中打开”在最后
    private let cellFrames: [CGRect]

    /// 子文件夹图标里叠加的预览图标数量
    private let previewIconCount: Int

    /// 点击“在访达中打开”后执行；为 nil 时没有这一格
    private let openInFinderHandler: (() -> Void)?

    /// 点击某一项后执行
    private let selectionHandler: (FolderItem) -> Void

    /// 已建好单元格的格序号，与 `cellFrames` 的下标一致
    private var builtCellIndices = IndexSet()

    /// 已建的子文件夹与它的单元格：系统外观变化时，按新外观重新渲染这些单元格的图标
    private var folderItemViews: [(folder: Folder, itemView: FolderGridItemView)] = []

    /// “在访达中打开”的单元格，它那一行露出之前为 nil；
    /// 它的图标按外观的文字颜色着色，系统外观变化时重新着色
    private var openInFinderItemView: FolderGridItemView? = nil

    /// 自上而下排列，与 `FolderGridLayout` 的坐标系一致，滚动视图初始停在顶部
    override var isFlipped: Bool {
        true
    }

    /// 创建网格；单元格等到排版或滚动时才按可见区域建
    /// - Parameters:
    ///   - items: 这一层的项，顺序即展示顺序
    ///   - layout: 按格数算好的布局
    ///   - previewIconCount: 子文件夹图标里叠加的预览图标数量
    ///   - openInFinderHandler: 点击“在访达中打开”后执行；为 nil 时没有这一格
    ///   - selectionHandler: 点击某一项后执行
    init(
        items: [FolderItem],
        layout: FolderGridLayout,
        previewIconCount: Int,
        openInFinderHandler: (() -> Void)?,
        selectionHandler: @escaping (FolderItem) -> Void
    ) {
        self.items = items
        self.previewIconCount = previewIconCount
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

    /// 排版时为可见的行建单元格：第一次显示之前，滚动位置已经恢复，建的正是那里的行
    override func layout() {
        super.layout()

        buildCells(near: visibleRect)
    }

    /// AppKit 提前准备可见区域以外的内容时（滚动时的预绘区域），一并建好那里的单元格
    override func prepareContent(in rect: NSRect) {
        super.prepareContent(in: rect)

        buildCells(near: rect)
    }

    /// 系统外观变化时，已建的子文件夹图标换成对应外观的底板，“在访达中打开”的图标换成对应外观的颜色；
    /// 之后才建的单元格按建的时候的外观渲染
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        for (folder, itemView) in folderItemViews {
            itemView.icon = folderIcon(of: folder)
        }

        openInFinderItemView?.icon = openInFinderIcon()
    }
}

// MARK: - Private

extension FolderGridView {
    /// 滚动视图的可见区域变了：在画出来之前补建新露出的行
    @objc
    private func clipViewBoundsDidChange(_: Notification) {
        buildCells(near: visibleRect)
    }

    /// 为与给定区域相交的行建单元格，上下各多一行；已建的跳过
    private func buildCells(near rect: CGRect) {
        // 上下各多一行：慢慢滚动时，下一行在露出之前就已建好
        let area = rect
            .insetBy(dx: 0, dy: -FolderPanelMetrics.cellSize)
            .intersection(bounds)

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

        // 记下子文件夹的单元格：外观变化时只有文件夹图标需要重新渲染
        if case .folder(let folder) = item {
            folderItemViews.append((folder, itemView))
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

        let itemView = FolderGridItemView(
            title: title,
            icon: openInFinderIcon(),
            clickHandler: openInFinderHandler
        )

        itemView.frame = frame
        addSubview(itemView)
        openInFinderItemView = itemView
    }

    /// “在访达中打开”的图标：Dock 自己的箭头图，按网格当前外观的文字颜色着色，铺满图标画布
    private func openInFinderIcon() -> NSImage {
        #warning("TODO: 按原生实测校准“在访达中打开”一格的外观")

        let source = Self.openInFinderSourceIcon
        let color = FolderPanelAppearance(effectiveAppearance).textColor
        let side = FolderPanelMetrics.iconSize

        // 先铺满颜色，再只留下原图不透明的部分，得到按文字颜色着色的箭头
        return NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            rect.fill()

            source.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)

            return true
        }
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
