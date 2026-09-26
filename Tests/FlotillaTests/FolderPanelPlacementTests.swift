import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - FolderPanelPlacementTests

/// 面板位置：尾巴尖端必须对准 tile，面板整体留在屏幕内；贴边被夹住时移动的是面板，不是尖端
struct FolderPanelPlacementTests {
    /// 面板主体的尺寸
    private let bodySize = CGSize(width: 480, height: 300)

    /// 底部 Dock：屏幕 1440×900，Dock 高 80，菜单栏高 30
    private let bottomVisibleFrame = CGRect(x: 0, y: 80, width: 1440, height: 790)

    /// 左侧 Dock：Dock 宽 80
    private let leftVisibleFrame = CGRect(x: 80, y: 0, width: 1360, height: 870)

    /// 右侧 Dock：Dock 宽 80
    private let rightVisibleFrame = CGRect(x: 0, y: 0, width: 1360, height: 870)

    /// 尾巴尖端距 Dock 边缘的距离
    private let gap = FolderPanelMetrics.tailTipGap

    /// 尾巴的高度
    private let tailHeight = FolderPanelMetrics.tailHeight

    /// 与屏幕边缘的最小距离
    private let margin = FolderPanelMetrics.screenMargin

    /// 底部 Dock：面板水平居中对准 tile，窗口底边就是尖端所在的水平线，窗口高度含尾巴
    @Test
    func bottomDockCentersOnTile() {
        let tile = CGRect(x: 700, y: 8, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame
        )

        #expect(placement.tailTip == CGPoint(x: tile.midX, y: tile.maxY + gap))
        #expect(placement.frame == CGRect(
            x: tile.midX - bodySize.width / 2,
            y: tile.maxY + gap,
            width: bodySize.width,
            height: bodySize.height + tailHeight
        ))
    }

    /// tile 靠近屏幕右缘：面板被夹在右边距之内，尖端仍对准 tile
    @Test
    func bottomDockClampsAtRightEdgeKeepingTipOnTile() {
        let tile = CGRect(x: 1360, y: 8, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame
        )

        #expect(placement.frame.maxX == bottomVisibleFrame.maxX - margin)
        #expect(placement.tailTip.x == tile.midX)
    }

    /// tile 靠近屏幕左缘：面板被夹在左边距之内，尖端仍对准 tile
    @Test
    func bottomDockClampsAtLeftEdgeKeepingTipOnTile() {
        let tile = CGRect(x: 0, y: 8, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame
        )

        #expect(placement.frame.minX == bottomVisibleFrame.minX + margin)
        #expect(placement.tailTip.x == tile.midX)
    }

    /// tile 的中心已经落在夹住后的面板之外时，尖端夹回窗口边缘，不画到窗口外
    @Test
    func tipStaysInsideWindowWhenTileIsBeyondPanel() {
        let tile = CGRect(x: 1400, y: 8, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .bottom,
            visibleFrame: bottomVisibleFrame
        )

        #expect(placement.tailTip.x == placement.frame.maxX)
    }

    /// 左侧 Dock：面板出现在 tile 右边，竖直居中，窗口左边就是尖端所在的竖直线
    @Test
    func leftDockPlacesPanelBesideTile() {
        let tile = CGRect(x: 8, y: 400, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .left,
            visibleFrame: leftVisibleFrame
        )

        #expect(placement.tailTip == CGPoint(x: tile.maxX + gap, y: tile.midY))
        #expect(placement.frame == CGRect(
            x: tile.maxX + gap,
            y: tile.midY - bodySize.height / 2,
            width: bodySize.width + tailHeight,
            height: bodySize.height
        ))
    }

    /// 右侧 Dock：面板出现在 tile 左边，窗口右边就是尖端所在的竖直线
    @Test
    func rightDockPlacesPanelBesideTile() {
        let tile = CGRect(x: 1368, y: 400, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .right,
            visibleFrame: rightVisibleFrame
        )

        #expect(placement.tailTip == CGPoint(x: tile.minX - gap, y: tile.midY))
        #expect(placement.frame.maxX == tile.minX - gap)
        #expect(placement.frame.width == bodySize.width + tailHeight)
    }

    /// 左侧 Dock 的 tile 贴近屏幕底部：面板被夹在下边距之内，尖端仍对准 tile
    @Test
    func sideDockClampsVerticallyKeepingTipOnTile() {
        let tile = CGRect(x: 8, y: 20, width: 64, height: 64)

        let placement = FolderPanelPlacement(
            bodySize: bodySize,
            tileFrame: tile,
            edge: .left,
            visibleFrame: leftVisibleFrame
        )

        #expect(placement.frame.minY == leftVisibleFrame.minY + margin)
        #expect(placement.tailTip.y == tile.midY)
    }

    /// 可用尺寸：沿 Dock 方向是屏幕减两侧边距，垂直 Dock 方向是尾巴末端到屏幕另一侧边距
    @Test
    func availableBodySizeLeavesRoomForTailAndMargins() {
        let bottomTile = CGRect(x: 700, y: 8, width: 64, height: 64)
        let leftTile = CGRect(x: 8, y: 400, width: 64, height: 64)

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
            height: bottomVisibleFrame.maxY - margin - (bottomTile.maxY + gap + tailHeight)
        ))
        #expect(left == CGSize(
            width: leftVisibleFrame.maxX - margin - (leftTile.maxX + gap + tailHeight),
            height: leftVisibleFrame.height - 2 * margin
        ))
    }
}
