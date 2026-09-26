import CoreGraphics

// MARK: - FolderPanelPlacement

/// 面板在屏幕上的位置：窗口 frame 与尾巴尖端，均为 AppKit 屏幕坐标
struct FolderPanelPlacement: Equatable {
    #warning("TODO: 待实测 尾巴尖端与 Dock 边缘的距离 tailTipGap、与屏幕边缘的距离 screenMargin，以及放大开启时尖端对准的位置")

    /// 面板窗口的 frame，包含主体与尾巴
    let frame: CGRect

    /// 尾巴尖端：面板被屏幕边缘夹住时仍对准 tile，只有超出窗口时才夹回窗口边缘
    let tailTip: CGPoint

    /// 计算面板位置：主体沿 Dock 方向居中对准 tile，并夹在屏幕可用区域内
    /// - Parameters:
    ///   - bodySize: 面板主体（不含尾巴）的尺寸
    ///   - tileFrame: tile 的 frame
    ///   - edge: Dock 所贴的屏幕边
    ///   - visibleFrame: tile 所在屏幕的 `visibleFrame`
    init(bodySize: CGSize, tileFrame: CGRect, edge: DockEdge, visibleFrame: CGRect) {
        let tip = Self.idealTip(tileFrame: tileFrame, edge: edge)
        let tailHeight = FolderPanelMetrics.tailHeight
        let margin = FolderPanelMetrics.screenMargin

        switch edge {
        // 尾巴朝下：窗口底边就是尖端所在的水平线，水平方向居中后夹在屏幕两侧边距之内
        case .bottom:
            let x = Self.clamped(
                tip.x - bodySize.width / 2,
                lower: visibleFrame.minX + margin,
                upper: visibleFrame.maxX - margin - bodySize.width
            )
            frame = CGRect(x: x, y: tip.y, width: bodySize.width, height: bodySize.height + tailHeight)

        // 尾巴朝左或朝右：竖直方向居中后夹在屏幕上下边距之内，窗口贴着尖端所在的竖直线
        case .left, .right:
            let y = Self.clamped(
                tip.y - bodySize.height / 2,
                lower: visibleFrame.minY + margin,
                upper: visibleFrame.maxY - margin - bodySize.height
            )
            let width = bodySize.width + tailHeight
            let x = edge == .left ? tip.x : tip.x - width

            frame = CGRect(x: x, y: y, width: width, height: bodySize.height)
        }

        tailTip = CGPoint(
            x: Self.clamped(tip.x, lower: frame.minX, upper: frame.maxX),
            y: Self.clamped(tip.y, lower: frame.minY, upper: frame.maxY)
        )
    }

    /// 面板主体在该 tile 旁可用的最大尺寸，用来决定网格的列数上限与是否滚动
    ///
    /// 沿 Dock 方向是屏幕可用区域减去两侧边距；垂直 Dock 方向是从尾巴末端到屏幕另一侧边距为止
    static func availableBodySize(tileFrame: CGRect, edge: DockEdge, visibleFrame: CGRect) -> CGSize {
        let tip = idealTip(tileFrame: tileFrame, edge: edge)
        let tailHeight = FolderPanelMetrics.tailHeight
        let margin = FolderPanelMetrics.screenMargin

        let size =
            switch edge {
            case .bottom:
                CGSize(
                    width: visibleFrame.width - 2 * margin,
                    height: visibleFrame.maxY - margin - (tip.y + tailHeight)
                )

            case .left:
                CGSize(
                    width: visibleFrame.maxX - margin - (tip.x + tailHeight),
                    height: visibleFrame.height - 2 * margin
                )

            case .right:
                CGSize(
                    width: (tip.x - tailHeight) - (visibleFrame.minX + margin),
                    height: visibleFrame.height - 2 * margin
                )
            }

        return CGSize(width: max(size.width, 0), height: max(size.height, 0))
    }
}

// MARK: - Private

extension FolderPanelPlacement {
    /// 尾巴尖端的理想位置：tile 朝向屏幕内侧那条边的中点，再向外让出 `tailTipGap`
    private static func idealTip(tileFrame: CGRect, edge: DockEdge) -> CGPoint {
        let gap = FolderPanelMetrics.tailTipGap

        return switch edge {
        case .bottom:
            CGPoint(x: tileFrame.midX, y: tileFrame.maxY + gap)

        case .left:
            CGPoint(x: tileFrame.maxX + gap, y: tileFrame.midY)

        case .right:
            CGPoint(x: tileFrame.minX - gap, y: tileFrame.midY)
        }
    }

    /// 把 value 夹到 `[lower, upper]`；区间为空（面板比可用区域还大）时取 lower，保证面板的起始边留在屏幕内
    private static func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
