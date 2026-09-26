import AppKit

// MARK: - DockTileAnchor

/// 面板的定位依据，由 `DockTileLocator` 给出
struct DockTileAnchor {
    /// tile 在 AppKit 屏幕坐标系里的 frame；退化定位时是宽高为 0 的一个点
    let tileFrame: CGRect

    /// Dock 所贴的屏幕边
    let edge: DockEdge

    /// tile 所在的屏幕，面板整体保持在它的 `visibleFrame` 内
    let screen: NSScreen
}
