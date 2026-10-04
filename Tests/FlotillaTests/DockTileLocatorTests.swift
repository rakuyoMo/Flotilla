import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - DockTileLocatorTests

/// 定位的纯计算：AX 坐标以主屏左上角为原点、y 向下，AppKit 以主屏左下角为原点、y 向上，换算错了面板就会出现在屏幕另一头
@MainActor
struct DockTileLocatorTests {
    /// 假定的主屏高度：AX 与 AppKit 的 y 坐标以它为基准互换；
    /// 各用例的期望值按 900 算
    private let primaryScreenHeight: CGFloat = 900

    /// 主屏底部的 tile：AX 的 y 是 tile 顶边到主屏顶边的距离，换算后是 tile 底边到主屏底边的距离
    @Test
    func convertsTileNearBottomOfPrimaryScreen() {
        let axFrame = CGRect(x: 100, y: 800, width: 64, height: 64)

        let frame = DockTileLocator.appKitRect(
            fromTopLeftRect: axFrame,
            primaryScreenHeight: primaryScreenHeight
        )

        #expect(frame == CGRect(x: 100, y: 36, width: 64, height: 64))
    }

    /// 主屏上方的副屏：AX 的 y 为负，换算后高于主屏
    @Test
    func convertsRectOnScreenAbovePrimary() {
        let axFrame = CGRect(x: 0, y: -1000, width: 100, height: 100)

        let frame = DockTileLocator.appKitRect(
            fromTopLeftRect: axFrame,
            primaryScreenHeight: primaryScreenHeight
        )

        #expect(frame == CGRect(x: 0, y: 1800, width: 100, height: 100))
    }

    /// 命中测试用的点：AppKit 的点换算成 AX 的点，再按矩形换算回来，回到原处
    @Test
    func pointConversionRoundTrips() {
        let mouseLocation = CGPoint(x: 732, y: 40)

        let axPoint = DockTileLocator.topLeftPoint(
            fromAppKitPoint: mouseLocation,
            primaryScreenHeight: primaryScreenHeight
        )

        let roundTrip = DockTileLocator.appKitRect(
            fromTopLeftRect: CGRect(origin: axPoint, size: .zero),
            primaryScreenHeight: primaryScreenHeight
        )

        #expect(axPoint == CGPoint(x: 732, y: 860))
        #expect(roundTrip.origin == mouseLocation)
    }

    /// 退化锚点落在 Dock 朝向屏幕内侧的那条边上，沿 Dock 方向保留鼠标的位置
    @Test
    func projectsMouseOntoInnerEdgeOfDock() {
        let bottom = DockTileLocator.projection(
            of: CGPoint(x: 500, y: 30),
            onto: CGRect(x: 0, y: 0, width: 1440, height: 80),
            edge: .bottom
        )

        let left = DockTileLocator.projection(
            of: CGPoint(x: 40, y: 300),
            onto: CGRect(x: 0, y: 0, width: 80, height: 900),
            edge: .left
        )

        let right = DockTileLocator.projection(
            of: CGPoint(x: 1400, y: 300),
            onto: CGRect(x: 1360, y: 0, width: 80, height: 900),
            edge: .right
        )

        #expect(bottom == CGPoint(x: 500, y: 80))
        #expect(left == CGPoint(x: 80, y: 300))
        #expect(right == CGPoint(x: 1360, y: 300))
    }

    /// 估算的 Dock 区域贴着 Dock 所在的屏幕边；tile 尺寸为 64 时与 AX 实测的 Dock 列表外缘（距屏幕边 94 pt）一致
    @Test
    func dockAreaHugsDockEdge() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

        let bottom = DockTileLocator.dockArea(in: screenFrame, edge: .bottom, tileSize: 64)
        let left = DockTileLocator.dockArea(in: screenFrame, edge: .left, tileSize: 64)
        let right = DockTileLocator.dockArea(in: screenFrame, edge: .right, tileSize: 64)

        #expect(bottom == CGRect(x: 0, y: 0, width: 1470, height: 94))
        #expect(left == CGRect(x: 0, y: 0, width: 94, height: 956))
        #expect(right == CGRect(x: 1376, y: 0, width: 94, height: 956))
    }

    /// Dock 偏好 `orientation` 缺省或无法识别时按底部处理
    @Test(arguments: [
        ("left", DockEdge.left),
        ("right", DockEdge.right),
        ("bottom", DockEdge.bottom),
        ("unknown", DockEdge.bottom),
        (nil, DockEdge.bottom),
    ] as [(String?, DockEdge)])
    func dockEdgeFollowsOrientationPreference(orientation: String?, edge: DockEdge) {
        #expect(DockEdge(orientation: orientation) == edge)
    }
}
