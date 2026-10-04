import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - FolderPanelPlacementTests

/// 面板位置：尾巴尖端必须按实测偏移对准 tile，面板主体整体留在屏幕内；贴边被夹住时移动的是主体，不是尖端
struct FolderPanelPlacementTests {
    /// 面板主体的尺寸（7 项：4 列 2 行）
    private let bodySize = CGSize(width: 546, height: 300)

    /// 底部 Dock：1470 × 956 pt 的屏幕，菜单栏高 33 pt，Dock 自动隐藏
    private let bottomVisibleFrame = CGRect(x: 0, y: 4, width: 1470, height: 919)

    /// 左侧 Dock：Dock 宽 94 pt
    private let leftVisibleFrame = CGRect(x: 94, y: 0, width: 1376, height: 923)

    /// 右侧 Dock：Dock 宽 94 pt
    private let rightVisibleFrame = CGRect(x: 0, y: 0, width: 1376, height: 923)

    /// 底部 Dock 上的 tile：68 × 84 pt，顶边距屏幕底边 89 pt（AX 实测）
    private let bottomTile = CGRect(x: 400, y: 5, width: 68, height: 84)

    /// 尾巴尖端到面板主体的距离
    private let tailHeight = FolderPanelMetrics.tailHeight

    /// 面板主体与屏幕两侧的最小距离
    private let margin = FolderPanelMetrics.screenSideMargin

    /// 底部 Dock：尖端在 tile 中心左侧 5 pt、伸进 tile 顶边 1 pt；主体底边在尖端上方 8 pt，中心在尖端右侧 3 pt
    @Test
    func bottomDockFollowsNativeOffsets() {
        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: bottomTile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame,
            scale: 2
        )

        #expect(placement.tailTip == CGPoint(x: bottomTile.midX - 5, y: bottomTile.maxY - 1))
        #expect(placement.bodyFrame == CGRect(
            x: placement.tailTip.x + 3 - bodySize.width / 2,
            y: placement.tailTip.y + tailHeight,
            width: bodySize.width,
            height: bodySize.height
        ))
    }

    /// 缩放锚点是 tile 图标中心：水平取 tile 中心，竖直在尖端下方 35 pt
    @Test
    func bottomDockAnchorsAtTileIconCenter() {
        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: bottomTile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame,
            scale: 2
        )

        #expect(placement.anchor == CGPoint(x: bottomTile.midX, y: placement.tailTip.y - 35))
    }

    /// tile 靠近屏幕右缘：主体被夹在右边距之内，尖端仍对准 tile
    @Test
    func bottomDockClampsAtRightEdgeKeepingTipOnTile() {
        let tile = CGRect(x: 1300, y: 5, width: 68, height: 84)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame,
            scale: 2
        )

        #expect(placement.bodyFrame.maxX == bottomVisibleFrame.maxX - margin)
        #expect(placement.tailTip.x == tile.midX - 5)
    }

    /// tile 靠近屏幕左缘：主体被夹在左边距之内，尖端仍对准 tile
    @Test
    func bottomDockClampsAtLeftEdgeKeepingTipOnTile() {
        let tile = CGRect(x: 10, y: 5, width: 68, height: 84)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame,
            scale: 2
        )

        #expect(placement.bodyFrame.minX == bottomVisibleFrame.minX + margin)
        #expect(placement.tailTip.x == tile.midX - 5)
    }

    /// 左侧 Dock：主体出现在 tile 右边，尖端伸进 tile 右边 1 pt，锚点在尖端左侧 35 pt
    @Test
    func leftDockPlacesPanelBesideTile() {
        let tile = CGRect(x: 5, y: 400, width: 84, height: 68)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .left,
            visibleFrame: leftVisibleFrame,
            scale: 2
        )

        #expect(placement.tailTip == CGPoint(x: tile.maxX - 1, y: tile.midY - 5))
        #expect(placement.bodyFrame.minX == placement.tailTip.x + tailHeight)
        #expect(placement.bodyFrame.midY == placement.tailTip.y + 3)
        #expect(placement.anchor == CGPoint(x: placement.tailTip.x - 35, y: tile.midY))
    }

    /// 右侧 Dock：主体出现在 tile 左边，尖端伸进 tile 左边 1 pt，锚点在尖端右侧 35 pt
    @Test
    func rightDockPlacesPanelBesideTile() {
        let tile = CGRect(x: 1381, y: 400, width: 84, height: 68)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .right,
            visibleFrame: rightVisibleFrame,
            scale: 2
        )

        #expect(placement.tailTip == CGPoint(x: tile.minX + 1, y: tile.midY - 5))
        #expect(placement.bodyFrame.maxX == placement.tailTip.x - tailHeight)
        #expect(placement.anchor == CGPoint(x: placement.tailTip.x + 35, y: tile.midY))
    }

    /// 左侧 Dock 的 tile 贴近屏幕底部：主体被夹在下边距之内，尖端仍对准 tile
    @Test
    func sideDockClampsVerticallyKeepingTipOnTile() {
        let tile = CGRect(x: 5, y: 10, width: 84, height: 68)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .left,
            visibleFrame: leftVisibleFrame,
            scale: 2
        )

        #expect(placement.bodyFrame.minY == leftVisibleFrame.minY + margin)
        #expect(placement.tailTip.y == tile.midY - 5)
    }

    /// 放大时 tile frame 带小数：尖端按屏幕像素格取整，与理论位置相差不超过半个像素；
    /// 主体随尖端落在像素格上，1 像素的边缘线才不会被分到相邻两个像素而发虚
    @Test(arguments: [
        (scale: CGFloat(2), tipX: CGFloat(986.5)),
        (scale: 1, tipX: 987),
    ])
    func tipSnapsToPixelGrid(scale: CGFloat, tipX: CGFloat) {
        // 中心 991.7、顶边 89.1：理论尖端 (986.7, 88.1)
        let tile = CGRect(x: 954.7, y: 5.1, width: 74, height: 84)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame,
            scale: scale
        )

        let body = placement.bodyFrame

        #expect(placement.tailTip == CGPoint(x: tipX, y: 88))
        #expect((body.minX * scale).rounded() == body.minX * scale)
        #expect((body.minY * scale).rounded() == body.minY * scale)
    }

    /// 可用尺寸：沿 Dock 方向是屏幕减两侧边距；垂直 Dock 方向从主体底边起，到屏幕另一侧留 16 pt 为止
    @Test
    func availableBodySizeLeavesRoomForTailAndMargins() {
        let leftTile = CGRect(x: 5, y: 400, width: 84, height: 68)

        let bottom = FolderPanelPlacement.availableBodySize(
            tileFrame: bottomTile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame
        )

        let left = FolderPanelPlacement.availableBodySize(
            tileFrame: leftTile,
            edge: .left,
            visibleFrame: leftVisibleFrame
        )

        #expect(bottom == CGSize(
            width: bottomVisibleFrame.width - 2 * margin,
            height: bottomVisibleFrame.maxY - 16 - (bottomTile.maxY - 1 + tailHeight)
        ))

        #expect(left == CGSize(
            width: leftVisibleFrame.maxX - 16 - (leftTile.maxX - 1 + tailHeight),
            height: leftVisibleFrame.height - 2 * margin
        ))
    }
}
