import AppKit

// MARK: - FolderIconRenderer

/// 把文件夹渲染成图标（需求 2）：浅色磨砂的圆角方形底板上，按 2×2 网格放前几个 App 的图标
///
/// 底板的位置、大小与圆角和 macOS 26 起系统 App 图标的底板一致，放进 Dock 后与相邻的 App 图标对齐
enum FolderIconRenderer {
    /// 底板在画布四边各留的边距，以画布边长为 1；系统 App 图标的底板同样四边各留 100/1024
    private static let plateInset: CGFloat = 100 / 1024

    /// 底板连续曲率圆角的半径与底板边长之比，按系统 App 图标的轮廓实测拟合
    private static let plateCornerRatio: CGFloat = 0.25

    /// 底板渐变底部的灰度，顶部为白色
    private static let plateBottomWhite: CGFloat = 0.84

    /// 底板的不透明度：半透明，透出 Dock 的背景，形成磨砂感
    private static let plateOpacity: CGFloat = 0.9

    /// 底板边线的不透明度，边线为黑色
    private static let plateEdgeOpacity: CGFloat = 0.12

    /// 底板边线的宽度，以画布边长为 1；边线紧贴轮廓内侧
    private static let plateEdgeWidth: CGFloat = 4.5 / 1024

    /// 预览单元格的边长，以画布边长为 1
    ///
    /// App 图标自带四边各 100/1024 的透明边，单元格按可见底板定几何：
    /// 每个预览的可见底板边长约 0.28、彼此间距约 0.064，四个合起来在画布上居中
    private static let previewCellSide: CGFloat = 0.35

    /// 左上单元格原点的 x、y，以画布边长为 1
    private static let previewGridOrigin: CGFloat = 0.152

    /// 相邻单元格原点之间的距离，以画布边长为 1
    private static let previewCellPitch: CGFloat = 0.346

    /// 预览图标投影的不透明度，投影为黑色
    private static let previewShadowOpacity: CGFloat = 0.3

    /// 预览图标投影的模糊半径，以画布边长为 1
    private static let previewShadowBlur: CGFloat = 14 / 1024

    /// 预览图标投影向下的偏移，以画布边长为 1
    private static let previewShadowOffset: CGFloat = 5 / 1024

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

        // 绘制闭包在每次栅格化时按目标分辨率重新执行；翻转坐标系，让几何按 y 轴自上而下计算
        return NSImage(
            size: NSSize(width: pointSize, height: pointSize),
            flipped: true
        ) { canvas in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            drawPlate(in: canvas, context: context)

            // 没有预览时只留底板
            for (index, icon) in previewIcons.enumerated() {
                let cell = previewCellFrame(at: index, in: canvas)

                drawPreview(
                    icon,
                    in: aspectFitFrame(for: icon.size, in: cell),
                    canvas: canvas,
                    context: context
                )
            }

            return true
        }
    }

    /// 第 index 个预览单元格在画布中的位置，填充顺序为左上、右上、左下、右下
    static func previewCellFrame(at index: Int, in canvas: CGRect) -> CGRect {
        let column = CGFloat(index % 2)
        let row = CGFloat(index / 2)

        // 先在单位画布中定位，再按实际画布缩放平移
        let unitX = previewGridOrigin + column * previewCellPitch
        let unitY = previewGridOrigin + row * previewCellPitch

        return CGRect(
            x: canvas.minX + unitX * canvas.width,
            y: canvas.minY + unitY * canvas.height,
            width: previewCellSide * canvas.width,
            height: previewCellSide * canvas.height
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
}

// MARK: - Private

extension FolderIconRenderer {
    /// 画底板：连续曲率圆角方形，自上而下由白色渐变到浅灰，整体半透明，轮廓内侧一圈淡淡的暗色边线
    private static func drawPlate(in canvas: CGRect, context: CGContext) {
        let inset = canvas.width * plateInset
        let plate = canvas.insetBy(dx: inset, dy: inset)
        let outline = plateOutline(in: plate)

        context.saveGState()
        defer { context.restoreGState() }

        // 渐变与边线都裁在底板之内
        context.addPath(outline)
        context.clip()

        let colors = [
            CGColor(gray: 1, alpha: plateOpacity),
            CGColor(gray: plateBottomWhite, alpha: plateOpacity),
        ]

        // 画布是翻转坐标系，plate.minY 在上方
        if
            let gradient = CGGradient(
                colorsSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
                colors: colors as CFArray,
                locations: [0, 1]
            )
        {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: plate.midX, y: plate.minY),
                end: CGPoint(x: plate.midX, y: plate.maxY),
                options: []
            )
        }

        // 以轮廓为中线描两倍宽的线，外侧一半被裁掉，留下紧贴轮廓内侧的边线
        context.addPath(outline)
        context.setLineWidth(canvas.width * plateEdgeWidth * 2)
        context.setStrokeColor(CGColor(gray: 0, alpha: plateEdgeOpacity))
        context.strokePath()
    }

    /// 画一个预览图标，下方带一层柔和的投影
    private static func drawPreview(
        _ icon: NSImage,
        in frame: CGRect,
        canvas: CGRect,
        context: CGContext
    ) {
        // Core Graphics 的投影参数按设备像素计、不随当前变换缩放，先按画布在设备上的像素边长换算
        let transform = context.userSpaceToDeviceSpaceTransform
        let deviceSide = canvas.width * hypot(transform.a, transform.b)

        context.saveGState()
        defer { context.restoreGState() }

        // 设备空间 y 轴向上，向下偏移取负值
        context.setShadow(
            offset: CGSize(width: 0, height: -deviceSide * previewShadowOffset),
            blur: deviceSide * previewShadowBlur,
            color: CGColor(gray: 0, alpha: previewShadowOpacity)
        )

        // 图标先合成到透明层里，整体只投一层影
        context.beginTransparencyLayer(auxiliaryInfo: nil)

        icon.draw(
            in: frame,
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )

        context.endTransparencyLayer()
    }

    /// 底板轮廓：四个角都是连续曲率圆角的正方形
    private static func plateOutline(in plate: CGRect) -> CGPath {
        let radius = plate.width * plateCornerRatio

        // 从上边右端的圆角起点出发，绕过四个角后闭合回到这里
        let path = CGMutablePath()
        path.move(to: CGPoint(x: plate.maxX - radius * ContinuousCorner.extent, y: plate.minY))

        ContinuousCorner.addCorners(to: path, in: plate, radius: radius)
        path.closeSubpath()

        return path
    }
}
