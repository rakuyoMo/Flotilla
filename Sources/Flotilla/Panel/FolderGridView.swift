import AppKit

// MARK: - FolderGridView

/// 一个层级的网格：按 `FolderGridLayout` 摆放每一项的单元格，作为滚动视图的文档视图；
/// 访达里的文件夹的层级在末尾另有一格“在访达中打开”
@MainActor
final class FolderGridView: NSView {
    /// 每一项的单元格，按项的 id 查找
    private var itemViews: [UUID: FolderGridItemView] = [:]

    /// 子文件夹与它的单元格：系统外观变化时，按新外观重新渲染这些单元格的图标
    private var folderItemViews: [(folder: Folder, itemView: FolderGridItemView)] = []

    /// “在访达中打开”的单元格；它的图标按外观的文字颜色着色，系统外观变化时重新着色
    private var openInFinderItemView: FolderGridItemView? = nil

    /// 子文件夹图标里叠加的预览图标数量
    private let previewIconCount: Int

    /// 自上而下排列，与 `FolderGridLayout` 的坐标系一致，滚动视图初始停在顶部
    override var isFlipped: Bool {
        true
    }

    /// 创建网格
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
        self.previewIconCount = previewIconCount

        super.init(frame: CGRect(origin: .zero, size: layout.gridSize))

        for (item, cellFrame) in zip(items, layout.cellFrames) {
            let (title, icon) = content(of: item)
            let itemView = FolderGridItemView(title: title, icon: icon) {
                selectionHandler(item)
            }

            itemView.frame = cellFrame
            addSubview(itemView)
            itemViews[item.id] = itemView

            // 记下子文件夹的单元格：外观变化时只有文件夹图标需要重新渲染
            if case .folder(let folder) = item {
                folderItemViews.append((folder, itemView))
            }
        }

        // “在访达中打开”排在所有项之后，占布局里的最后一格
        if let openInFinderHandler, layout.cellFrames.indices.contains(items.count) {
            addOpenInFinderItem(
                frame: layout.cellFrames[items.count],
                clickHandler: openInFinderHandler
            )
        }
    }

    /// 网格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 某一项的图标中心，自身坐标系；没有这一项时为 nil
    func iconCenter(of itemID: UUID) -> CGPoint? {
        guard let itemView = itemViews[itemID] else { return nil }

        return itemView.convert(itemView.iconCenter, to: self)
    }

    /// 系统外观变化时，子文件夹的图标换成对应外观的底板，“在访达中打开”的图标换成对应外观的颜色
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

    /// 加上“在访达中打开”的单元格
    /// - Parameters:
    ///   - frame: 单元格的 frame
    ///   - clickHandler: 点击后执行
    private func addOpenInFinderItem(frame: CGRect, clickHandler: @escaping () -> Void) {
        let title = String(
            localized: "panel.openInFinder",
            comment: "访达里的文件夹在面板里展开后，网格末尾那一格的名称"
        )

        let itemView = FolderGridItemView(
            title: title,
            icon: openInFinderIcon(),
            clickHandler: clickHandler
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
