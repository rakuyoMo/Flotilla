import AppKit

// MARK: - FolderPanelLevel

/// 面板里的一个层级：一个文件夹的背景、标题区与网格，以及它在屏幕上占据的位置
@MainActor
struct FolderPanelLevel {
    /// 这一层展示的文件夹
    let folderID: UUID

    /// 这一层的视图，背景、标题区与网格作为一个整体缩放与淡入淡出
    let view: FolderPanelBackgroundView

    /// 视图在屏幕上的 frame（AppKit 屏幕坐标），包含轮廓与阴影留白
    let screenFrame: CGRect

    /// 网格所在的滚动视图；空文件夹没有
    let scrollView: NSScrollView?

    /// 网格；空文件夹没有
    let gridView: FolderGridView?

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

    /// 屏幕上的点换算到这一层视图自身的坐标系，也是视图图层的坐标系
    func localPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenFrame.minX, y: point.y - screenFrame.minY)
    }
}
