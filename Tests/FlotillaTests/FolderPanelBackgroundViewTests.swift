import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - FolderPanelBackgroundViewTests

/// 面板轮廓：尾巴必须长在面向 Dock 的边上，尖端落在给定位置，即使尖端偏到圆角附近也不能丢失
@MainActor
struct FolderPanelBackgroundViewTests {
    /// 主体区域
    private let body = CGRect(x: 12, y: 12, width: 400, height: 300)

    /// 轮廓的外接矩形恰好是主体加上尖端，尖端附近的尾巴内部属于面板
    @Test(arguments: [
        (DockEdge.bottom, CGPoint(x: 212, y: 0)),
        (DockEdge.left, CGPoint(x: 0, y: 162)),
        (DockEdge.right, CGPoint(x: 424, y: 162)),
    ])
    func tailGrowsTowardDock(edge: DockEdge, tip: CGPoint) {
        let path = FolderPanelBackgroundView.outlinePath(bodyRect: body, tailTip: tip, edge: edge)

        #expect(isClose(path.boundingBoxOfPath, body.union(CGRect(origin: tip, size: .zero))))
        #expect(path.contains(Self.point(from: tip, towards: CGPoint(x: body.midX, y: body.midY), distance: 2)))
    }

    /// 尖端偏到主体一角之外：尾巴变斜，尖端仍在轮廓上
    @Test
    func skewedTailKeepsTipOnTile() {
        let tip = CGPoint(x: body.minX + 2, y: 0)

        let path = FolderPanelBackgroundView.outlinePath(bodyRect: body, tailTip: tip, edge: .bottom)

        #expect(isClose(path.boundingBoxOfPath, body.union(CGRect(origin: tip, size: .zero))))
    }
}

// MARK: - Helpers

extension FolderPanelBackgroundViewTests {
    /// 从 start 朝 target 走 distance 后的点
    private static func point(from start: CGPoint, towards target: CGPoint, distance: CGFloat) -> CGPoint {
        let length = hypot(target.x - start.x, target.y - start.y)

        return CGPoint(
            x: start.x + (target.x - start.x) / length * distance,
            y: start.y + (target.y - start.y) / length * distance
        )
    }

    /// 两个矩形在浮点误差内相等：圆弧的端点由三角函数算出，会有末位误差
    private func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = 1e-9

        return abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }
}
