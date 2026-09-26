import AppKit

// MARK: - FolderGridView

/// 一个文件夹的网格：按 `FolderGridLayout` 摆放每一项的单元格，作为滚动视图的文档视图
@MainActor
final class FolderGridView: NSView {
    /// 自上而下排列，与 `FolderGridLayout` 的坐标系一致，滚动视图初始停在顶部
    override var isFlipped: Bool {
        true
    }

    /// 创建网格
    /// - Parameters:
    ///   - items: 文件夹内的项，顺序即展示顺序
    ///   - layout: 按项数算好的布局
    ///   - previewIconCount: 子文件夹图标里叠加的 App 图标数量
    ///   - selectionHandler: 点击某一项后执行
    init(
        items: [FolderItem],
        layout: FolderGridLayout,
        previewIconCount: Int,
        selectionHandler: @escaping (FolderItem) -> Void
    ) {
        super.init(frame: CGRect(origin: .zero, size: layout.gridSize))

        for (item, cellFrame) in zip(items, layout.cellFrames) {
            let content = Self.content(of: item, previewIconCount: previewIconCount)
            let itemView = FolderGridItemView(title: content.title, icon: content.icon) {
                selectionHandler(item)
            }

            itemView.frame = cellFrame
            addSubview(itemView)
        }
    }

    /// 网格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Private

extension FolderGridView {
    /// 一项显示的名称与图标：App 用自己的图标与显示名，子文件夹用渲染出的文件夹图标与文件夹名
    private static func content(of item: FolderItem, previewIconCount: Int) -> (title: String, icon: NSImage) {
        switch item {
        case .app(let app):
            (app.displayName, app.icon)

        case .folder(let folder):
            (
                folder.name,
                FolderIconRenderer.render(
                    folder: folder,
                    previewIconCount: previewIconCount,
                    pointSize: FolderPanelMetrics.iconSize
                )
            )
        }
    }
}
