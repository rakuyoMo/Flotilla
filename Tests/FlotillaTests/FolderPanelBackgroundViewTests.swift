import CoreGraphics
import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderPanelBackgroundViewTests

/// 面板轮廓：尾巴必须长在面向 Dock 的边上、尖端落在给定位置，即使尖端偏到圆角附近也不能丢失；
/// 轮廓同时决定点击是否穿透，阴影留白与尾巴两侧不能挡住下面的 tile
@MainActor
struct FolderPanelBackgroundViewTests {
    /// 面板主体在背景视图里的矩形：7 项（4 列 2 行）时的主体尺寸
    private let body = CGRect(x: 60, y: 68, width: 546, height: 300)

    /// 尖端到主体的距离
    private let tailHeight = FolderPanelMetrics.tailHeight

    /// 轮廓的外接矩形是主体加上尖端，尖端附近的尾巴内部属于面板
    @Test(arguments: [DockEdge.bottom, .left, .right])
    func tailGrowsTowardDock(edge: DockEdge) {
        let tip = tip(facing: edge)

        let path = FolderPanelBackgroundView.outlinePath(
            bodyRect: body,
            tailTip: tip,
            edge: edge
        )

        let insideTip = Self.point(
            from: tip,
            towards: CGPoint(x: body.midX, y: body.midY),
            distance: 1
        )

        let expectedBox = body.union(CGRect(origin: tip, size: .zero))

        #expect(isClose(path.boundingBoxOfPath, expectedBox))
        #expect(path.contains(insideTip))
    }

    /// 尖端偏向主体一角（面板被屏幕边缘夹住）：尾巴变斜，尖端仍落在给定位置，主体不被挖缺
    @Test
    func skewedTailKeepsTipOnTile() {
        let tip = CGPoint(x: body.minX + 50, y: body.minY - tailHeight)

        let path = FolderPanelBackgroundView.outlinePath(
            bodyRect: body,
            tailTip: tip,
            edge: .bottom
        )

        let expectedBox = body.union(CGRect(origin: tip, size: .zero))

        #expect(isClose(path.boundingBoxOfPath, expectedBox))
        #expect(path.contains(CGPoint(x: tip.x, y: tip.y + 1)))
        #expect(path.contains(CGPoint(x: tip.x, y: body.minY + 1)))
    }

    /// 尖端偏到尾巴斜不过去的位置（贴近屏幕边缘的 tile）：尾巴停在极限处，轮廓不折回，主体不被挖缺
    @Test
    func tailStopsAtSkewLimitNearCorner() {
        let tip = CGPoint(x: body.minX + 10, y: body.minY - tailHeight)

        let path = FolderPanelBackgroundView.outlinePath(
            bodyRect: body,
            tailTip: tip,
            edge: .bottom
        )

        let box = path.boundingBoxOfPath

        // 斜到极限的尾巴尖角更尖，倒圆后比给定尖端略浅，但仍伸向 tile
        #expect(abs(box.minY - tip.y) < 1)
        #expect(box.minX == body.minX)
        #expect(!path.contains(CGPoint(x: tip.x, y: tip.y + 1)))

        // 主体沿面向 Dock 的边完整，尾巴根部附近没有被挖掉的缺口
        for x in stride(from: body.minX + 40, through: body.minX + 80, by: 2) {
            #expect(path.contains(CGPoint(x: x, y: body.minY + 0.5)))
        }
    }

    /// 点击穿透的判定：主体与尾巴之内接收点击；尾巴两侧、阴影留白、圆角之外都穿透
    @Test
    func containsOnlyPointsInsideOutline() {
        let tip = tip(facing: .bottom)
        let view = FolderPanelBackgroundView(
            frame: CGRect(x: 0, y: 0, width: 666, height: 428),
            bodyRect: body,
            tailTip: tip,
            edge: .bottom
        )

        #expect(view.contains(CGPoint(x: body.midX, y: body.midY)))
        #expect(view.contains(CGPoint(x: tip.x, y: tip.y + 2)))

        #expect(!view.contains(CGPoint(x: tip.x + 15, y: tip.y + 2)))
        #expect(!view.contains(CGPoint(x: body.midX, y: body.maxY + 10)))
        #expect(!view.contains(CGPoint(x: body.minX + 1, y: body.maxY - 1)))
    }

    /// 层级按屏幕坐标判定：屏幕上的点先换算到层级视图里，再与轮廓比较；
    /// “移除” 的边界同样按主体在屏幕上的位置算，正对主体上边 94 pt 以内在边界之内；
    /// 尾巴那一侧按 Dock 所在的屏幕横贯，主体右下方远处的 Dock 上也在边界之内
    @Test
    func levelConvertsScreenPointsBeforeHitTesting() {
        let tip = tip(facing: .bottom)
        let screenFrame = CGRect(x: 100, y: 20, width: 666, height: 428)
        let level = FolderPanelLevel(
            id: UUID(),
            view: FolderPanelBackgroundView(
                frame: CGRect(origin: .zero, size: screenFrame.size),
                bodyRect: body,
                tailTip: tip,
                edge: .bottom
            ),
            screenFrame: screenFrame,
            dockEdge: .bottom,
            dockScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            scrollView: nil,
            gridView: nil
        )

        let bodyCenterOnScreen = CGPoint(
            x: screenFrame.minX + body.midX,
            y: screenFrame.minY + body.midY
        )

        #expect(level.contains(screenPoint: bodyCenterOnScreen))

        // 这个点在视图自身坐标系里落在主体左缘之内，换算到屏幕上的层级后已在主体左侧之外
        #expect(!level.contains(screenPoint: CGPoint(x: body.minX + 5, y: body.midY)))

        let bodyTopOnScreen = screenFrame.minY + body.maxY

        #expect(level.removeBoundaryContains(screenPoint: CGPoint(
            x: bodyCenterOnScreen.x,
            y: bodyTopOnScreen + 94
        )))

        #expect(!level.removeBoundaryContains(screenPoint: CGPoint(
            x: bodyCenterOnScreen.x,
            y: bodyTopOnScreen + 95
        )))

        #expect(level.removeBoundaryContains(screenPoint: CGPoint(
            x: 1500,
            y: screenFrame.minY + body.minY - 10
        )))
    }
}

// MARK: - Helpers

extension FolderPanelBackgroundViewTests {
    /// 从 `start` 朝 `target` 走 `distance` 后的点
    private static func point(
        from start: CGPoint,
        towards target: CGPoint,
        distance: CGFloat
    ) -> CGPoint {
        let length = hypot(target.x - start.x, target.y - start.y)

        return CGPoint(
            x: start.x + (target.x - start.x) / length * distance,
            y: start.y + (target.y - start.y) / length * distance
        )
    }

    /// 面向 Dock 的边中点外侧 `tailHeight` 处的尖端
    private func tip(facing edge: DockEdge) -> CGPoint {
        switch edge {
        case .bottom:
            CGPoint(x: body.midX, y: body.minY - tailHeight)

        case .left:
            CGPoint(x: body.minX - tailHeight, y: body.midY)

        case .right:
            CGPoint(x: body.maxX + tailHeight, y: body.midY)
        }
    }

    /// 两个矩形相差不到半个像素（2 倍屏）：尖端倒圆后的最低点按 90° 尖角估算，尾巴不是正好 90° 时与给定尖端略有出入
    private func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = 0.25

        return abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }
}
