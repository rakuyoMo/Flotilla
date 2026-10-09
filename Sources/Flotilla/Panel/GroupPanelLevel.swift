import AppKit

// MARK: - GroupPanelLevel

/// 面板里的一个层级：Flotilla 的文件夹或访达里的文件夹的背景、标题区与网格，以及它在屏幕上占据的位置
@MainActor
struct GroupPanelLevel {
    /// 这一层的 id，即 `GroupPanelLevelContent.id`
    let id: UUID

    /// 这一层的视图，背景、标题区与网格作为一个整体缩放与淡入淡出
    let view: GroupPanelBackgroundView

    /// 视图在屏幕上的 frame（AppKit 屏幕坐标），包含轮廓与阴影留白
    let screenFrame: CGRect

    /// Dock 所贴的屏幕边：尾巴长在主体朝向它的那条边上
    let dockEdge: DockEdge

    /// Dock 所在屏幕的 frame（AppKit 屏幕坐标）：“移除” 的边界在尾巴那一侧横贯这块屏幕
    let dockScreenFrame: CGRect

    /// 网格所在的滚动视图；空的 Flotilla 文件夹没有
    let scrollView: NSScrollView?

    /// 网格；空的 Flotilla 文件夹没有
    let gridView: GroupGridView?

    /// 某一项的图标中心，AppKit 屏幕坐标；没有这一项时为 nil
    func iconCenterOnScreen(of itemID: UUID) -> CGPoint? {
        guard
            let gridView,
            let window = gridView.window,
            let center = gridView.iconCenter(of: itemID)
        else {
            return nil
        }

        return window.convertPoint(toScreen: gridView.convert(center, to: nil))
    }

    /// 屏幕上的点是否落在这一层的轮廓之内
    func contains(screenPoint: CGPoint) -> Bool {
        view.contains(localPoint(fromScreen: screenPoint))
    }

    /// 屏幕上的点是否落在这一层 “移除” 的边界之内：
    /// 尾巴那一侧是横贯屏幕的一条线，其余方向是面板主体向外扩出的圆角矩形
    func removeBoundaryContains(screenPoint: CGPoint) -> Bool {
        // 主体放在材质视图的内容里：先换算到这一层视图自身的坐标系，再平移到屏幕坐标
        let bodyFrame = view
            .convert(view.bodyView.bounds, from: view.bodyView)
            .offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)

        let boundary = GroupPanelRemoveBoundary(
            bodyFrame: bodyFrame,
            edge: dockEdge,
            screenFrame: dockScreenFrame
        )

        return boundary.contains(screenPoint)
    }

    /// 屏幕上的点换算到这一层视图自身的坐标系，也是视图图层的坐标系
    func localPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }
}
