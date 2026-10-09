import CoreGraphics

// MARK: - GroupPanelRemoveBoundary

/// 拖出面板时 “移除” 的边界：尾巴那一侧是一条横贯屏幕的线，
/// 其余方向是面板主体的圆角矩形向外扩 `removeBoundaryDistance`，圆角半径同样加这么多
///
/// 鼠标要在边界之外 “移除” 才浮出；轮廓与边界之间不浮出，在这里松开这一项落回原位
struct GroupPanelRemoveBoundary {
    /// 面板主体，与要判定的点同一坐标系
    let bodyFrame: CGRect

    /// Dock 所贴的屏幕边：面板的尾巴长在朝向它的那条边上
    let edge: DockEdge

    /// Dock 所在屏幕的 frame，与要判定的点同一坐标系
    let screenFrame: CGRect

    /// 点是否在边界之内，边上也算
    func contains(_ point: CGPoint) -> Bool {
        isOnDockSide(point) || isNearBody(point)
    }
}

// MARK: - Private

extension GroupPanelRemoveBoundary {
    /// 点是否在尾巴那一侧：从主体朝 Dock 的那条边到屏幕边，横贯整块屏幕
    ///
    /// 与程序坞的边界一样是一条横贯屏幕的线，Dock 上任何地方都不浮出：
    /// 面板贴近 Dock 时，主体向外扩出的范围盖不住 Dock 最外侧的几个点，也盖不住主体两侧的 Dock
    private func isOnDockSide(_ point: CGPoint) -> Bool {
        let isOnScreen = (screenFrame.minX ... screenFrame.maxX).contains(point.x)
            && (screenFrame.minY ... screenFrame.maxY).contains(point.y)

        guard isOnScreen else { return false }

        switch edge {
        case .bottom:
            return point.y <= bodyFrame.minY

        case .left:
            return point.x <= bodyFrame.minX

        case .right:
            return point.x >= bodyFrame.maxX
        }
    }

    /// 点是否在主体的圆角矩形向外扩 `removeBoundaryDistance` 之内，圆角半径同样加这么多
    private func isNearBody(_ point: CGPoint) -> Bool {
        let radius = GroupPanelMetrics.cornerRadius
        let reach = radius + GroupPanelMetrics.removeBoundaryDistance

        // 主体四边各缩进一个圆角半径，得到核心矩形：
        // 扩出的圆角矩形恰好是到核心矩形的距离不超过 “圆角半径 + 扩出距离” 的点
        let core = bodyFrame.insetBy(dx: radius, dy: radius)

        let dx = max(core.minX - point.x, 0, point.x - core.maxX)
        let dy = max(core.minY - point.y, 0, point.y - core.maxY)

        return (dx * dx + dy * dy).squareRoot() <= reach
    }
}
