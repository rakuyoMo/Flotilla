import AppKit

// MARK: - FolderIconRenderer

/// 把文件夹渲染成图标（需求 2）：系统文件夹图标作底图，正面按 2×2 网格叠加前几个 App 的图标
enum FolderIconRenderer {
    /// 预览网格的外框，以画布边长为 1、y 轴自上而下
    private static let previewGridFrame = CGRect(x: 0.25, y: 0.36, width: 0.5, height: 0.5)

    /// 预览网格单元格之间的间距，以画布边长为 1
    private static let previewGridSpacing: CGFloat = 0.04

    /// 渲染文件夹图标
    /// - Parameters:
    ///   - folder: 要渲染的文件夹
    ///   - previewIconCount: 叠加的 App 图标数量上限，超出 `0...Preferences.maximumPreviewIconCount` 时夹取
    ///   - pointSize: 输出图像的边长（点）
    /// - Returns: 用绘制闭包构造的图像，与分辨率无关，调用方可按任意像素尺寸栅格化
    static func render(
        folder: Folder,
        previewIconCount: Int,
        pointSize: CGFloat
    ) -> NSImage {
        let count = min(max(previewIconCount, 0), Preferences.maximumPreviewIconCount)

        // 按顺序取前几个 App，跳过子文件夹
        let previewIcons = folder.items
            .compactMap { item -> AppReference? in
                guard case .app(let app) = item else { return nil }
                return app
            }
            .prefix(count)
            .map(\.icon)

        let baseIcon = NSWorkspace.shared.icon(for: .folder)

        // 绘制闭包在每次栅格化时按目标分辨率重新执行；翻转坐标系，让预览网格按 y 轴自上而下计算
        return NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: true
        ) { canvas in
            draw(baseIcon, in: canvas)

            for (index, icon) in previewIcons.enumerated() {
                let cell = previewCellFrame(at: index, in: canvas)
                draw(icon, in: aspectFitFrame(for: icon.size, in: cell))
            }

            return true
        }
    }

    /// 第 index 个预览单元格在画布中的位置，填充顺序为左上、右上、左下、右下
    static func previewCellFrame(at index: Int, in canvas: CGRect) -> CGRect {
        let cellSide = (previewGridFrame.width - previewGridSpacing) / 2
        let column = CGFloat(index % 2)
        let row = CGFloat(index / 2)

        // 先在单位画布中定位，再按实际画布缩放平移
        let unitX = previewGridFrame.minX + column * (cellSide + previewGridSpacing)
        let unitY = previewGridFrame.minY + row * (cellSide + previewGridSpacing)

        return CGRect(
            x: canvas.minX + unitX * canvas.width,
            y: canvas.minY + unitY * canvas.height,
            width: cellSide * canvas.width,
            height: cellSide * canvas.height
        )
    }

    /// 把尺寸为 size 的内容等比缩放后居中放进 frame
    static func aspectFitFrame(for size: CGSize, in frame: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return frame }

        let scale = min(frame.width / size.width, frame.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)

        return CGRect(
            x: frame.midX - fitted.width / 2,
            y: frame.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// 在翻转坐标系里正向绘制图像
    private static func draw(_ image: NSImage, in frame: CGRect) {
        image.draw(
            in: frame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
    }
}
