import CoreGraphics

// MARK: - FolderPanelPlacement

/// 面板在屏幕上的位置：面板主体、尾巴尖端与展开收起的缩放锚点，均为 AppKit 屏幕坐标
///
/// 数值在底部 Dock 上实测；Dock 在左右两侧时按同样的数值沿 Dock 方向套用
struct FolderPanelPlacement {
    #warning("TODO: 未能实测 左右两侧 Dock 的尾巴偏移与夹边距离（原生文件夹只能放在底部 Dock 的右侧区域测量）")

    /// 面板主体（不含尾巴）的 frame
    let bodyFrame: CGRect

    /// 尾巴尖端：面板主体被屏幕边缘夹住时仍对准 tile
    let tailTip: CGPoint

    /// 展开、收起时整个面板缩放的锚点：tile 图标中心，位于尾巴尖端向 Dock 内 `anchorDepth` 处
    let anchor: CGPoint

    /// 计算面板位置：主体沿 Dock 方向对准 tile，并夹在屏幕可用区域两侧的边距之内；尾巴尖端对齐到屏幕的像素格
    /// - Parameters:
    ///   - bodySize: 面板主体（不含尾巴）的尺寸
    ///   - tileFrame: tile 的 frame
    ///   - edge: Dock 所贴的屏幕边
    ///   - visibleFrame: tile 所在屏幕的 `visibleFrame`
    ///   - scale: tile 所在屏幕每 pt 的像素数
    init(
        bodySize: CGSize,
        tileFrame: CGRect,
        edge: DockEdge,
        visibleFrame: CGRect,
        scale: CGFloat
    ) {
        // 放大时 AX 给出的 tile frame 带小数；主体尺寸与各项偏移都是整像素，
        // 尖端落在像素格上，轮廓与 1 像素的边缘线才不会被分到相邻两个像素
        let tip = Self.pixelAligned(
            Self.tailTip(tileFrame: tileFrame, edge: edge),
            scale: scale
        )

        let tailHeight = FolderPanelMetrics.tailHeight
        let margin = FolderPanelMetrics.screenSideMargin
        let anchorDepth = FolderPanelMetrics.anchorDepth

        switch edge {
        // 尾巴朝下：主体底边在尖端上方，水平方向按实测偏移对准尖端，再夹在屏幕两侧边距之内
        case .bottom:
            let x = Self.clamped(
                tip.x + FolderPanelMetrics.bodyCenterOffset - bodySize.width / 2,
                lower: visibleFrame.minX + margin,
                upper: visibleFrame.maxX - margin - bodySize.width
            )

            bodyFrame = CGRect(
                origin: CGPoint(x: x, y: tip.y + tailHeight),
                size: bodySize
            )
            anchor = CGPoint(x: tileFrame.midX, y: tip.y - anchorDepth)

        // 尾巴朝左或朝右：主体贴着尖端所在的竖直线，竖直方向对准尖端后夹在屏幕上下边距之内
        case .left, .right:
            let y = Self.clamped(
                tip.y + FolderPanelMetrics.bodyCenterOffset - bodySize.height / 2,
                lower: visibleFrame.minY + margin,
                upper: visibleFrame.maxY - margin - bodySize.height
            )

            let x = edge == .left
                ? tip.x + tailHeight
                : tip.x - tailHeight - bodySize.width
            let anchorX = edge == .left ? tip.x - anchorDepth : tip.x + anchorDepth

            bodyFrame = CGRect(origin: CGPoint(x: x, y: y), size: bodySize)
            anchor = CGPoint(x: anchorX, y: tileFrame.midY)
        }

        tailTip = tip
    }

    /// 面板主体在该 tile 旁可用的最大尺寸，用来决定网格的列数上限与显示的行数
    ///
    /// 沿 Dock 方向是屏幕可用区域减去两侧边距；
    /// 垂直 Dock 方向是从尾巴底边到屏幕另一侧边距为止
    static func availableBodySize(
        tileFrame: CGRect,
        edge: DockEdge,
        visibleFrame: CGRect
    ) -> CGSize {
        #warning("TODO: 未能实测 屏幕较小时按可用尺寸减少列数与显示行数、多显示器下面板保持在 tile 所在屏幕内（本机只有一块 1470 × 956 pt 的屏幕）")

        let tip = tailTip(tileFrame: tileFrame, edge: edge)
        let tailHeight = FolderPanelMetrics.tailHeight
        let sideMargin = FolderPanelMetrics.screenSideMargin
        let farMargin = FolderPanelMetrics.screenFarMargin

        let size =
            switch edge {
            case .bottom:
                CGSize(
                    width: visibleFrame.width - 2 * sideMargin,
                    height: visibleFrame.maxY - farMargin - (tip.y + tailHeight)
                )

            case .left:
                CGSize(
                    width: visibleFrame.maxX - farMargin - (tip.x + tailHeight),
                    height: visibleFrame.height - 2 * sideMargin
                )

            case .right:
                CGSize(
                    width: (tip.x - tailHeight) - (visibleFrame.minX + farMargin),
                    height: visibleFrame.height - 2 * sideMargin
                )
            }

        return CGSize(width: max(size.width, 0), height: max(size.height, 0))
    }
}

// MARK: - Private

extension FolderPanelPlacement {
    /// 尾巴尖端：沿 Dock 方向在 tile frame 中心加上实测偏移，垂直 Dock 方向伸进 tile frame 朝屏幕内侧的边 `tailTipInset`
    private static func tailTip(tileFrame: CGRect, edge: DockEdge) -> CGPoint {
        let offset = FolderPanelMetrics.tailTipOffset
        let inset = FolderPanelMetrics.tailTipInset

        return switch edge {
        case .bottom:
            CGPoint(x: tileFrame.midX + offset, y: tileFrame.maxY - inset)

        case .left:
            CGPoint(x: tileFrame.maxX - inset, y: tileFrame.midY + offset)

        case .right:
            CGPoint(x: tileFrame.minX + inset, y: tileFrame.midY + offset)
        }
    }

    /// 把点按四舍五入对齐到像素格
    private static func pixelAligned(_ point: CGPoint, scale: CGFloat) -> CGPoint {
        CGPoint(
            x: (point.x * scale).rounded() / scale,
            y: (point.y * scale).rounded() / scale
        )
    }

    /// 把 value 夹到 `[lower, upper]`；区间为空（面板比可用区域还大）时取 lower，保证面板的起始边留在屏幕内
    private static func clamped(
        _ value: CGFloat,
        lower: CGFloat,
        upper: CGFloat
    ) -> CGFloat {
        max(lower, min(value, upper))
    }
}
