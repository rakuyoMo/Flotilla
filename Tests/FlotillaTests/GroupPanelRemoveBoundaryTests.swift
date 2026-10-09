import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - GroupPanelRemoveBoundaryTests

/// “移除” 的边界：拖到面板主体四周 94 pt 以外 “移除” 才浮出，与程序坞的距离相同；在这之内松开不删除。
/// 角上按圆弧算，不按外接矩形：斜着拖出面板时，浮出的距离与正对着边拖出时相同。
/// 尾巴那一侧与程序坞一样是一条横贯屏幕的线：拖到 Dock 上任何地方都不浮出，面板离 Dock 多近都一样
struct GroupPanelRemoveBoundaryTests {
    /// Dock 所在的屏幕：1920 × 1080 pt
    private let screenFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    /// 400 × 300 pt 的主体，左下角在 (100, 200)，圆角半径 25 pt
    private let bodyFrame = CGRect(x: 100, y: 200, width: 400, height: 300)

    /// 尾巴之外的三条边：离主体 94 pt 以内（含 94 pt）在边界之内，再远 1 pt 就在边界之外
    @Test(arguments: [DockEdge.bottom, .left, .right])
    func otherEdgesAreNinetyFourPointsOut(dockEdge: DockEdge) {
        let boundary = makeBoundary(dockEdge: dockEdge)

        // 正对四条边各一对点：离主体 94 pt 与 95 pt
        let probes: [(side: CGRectEdge, inside: CGPoint, outside: CGPoint)] = [
            (
                side: .minXEdge,
                inside: CGPoint(x: 6, y: 350),
                outside: CGPoint(x: 5, y: 350)
            ),
            (
                side: .maxXEdge,
                inside: CGPoint(x: 594, y: 350),
                outside: CGPoint(x: 595, y: 350)
            ),
            (
                side: .minYEdge,
                inside: CGPoint(x: 300, y: 106),
                outside: CGPoint(x: 300, y: 105)
            ),
            (
                side: .maxYEdge,
                inside: CGPoint(x: 300, y: 594),
                outside: CGPoint(x: 300, y: 595)
            ),
        ]

        for probe in probes where probe.side != dockEdge.rectEdge {
            #expect(boundary.contains(probe.inside))
            #expect(!boundary.contains(probe.outside))
        }
    }

    /// 角上是半径 25 + 94 = 119 pt 的圆弧，圆心就是主体圆角的圆心：沿 45° 方向离圆心 118 pt 在之内、120 pt 在之外；
    /// 扩出的外接矩形的角落不在之内
    @Test
    func cornersAreRounded() {
        let boundary = makeBoundary(dockEdge: .bottom)

        // 左上角圆角的圆心
        let center = CGPoint(x: 125, y: 475)
        let diagonal = 0.5.squareRoot()

        #expect(boundary.contains(CGPoint(
            x: center.x - 118 * diagonal,
            y: center.y + 118 * diagonal
        )))

        #expect(!boundary.contains(CGPoint(
            x: center.x - 120 * diagonal,
            y: center.y + 120 * diagonal
        )))

        // 外接矩形的左上角是 (6, 594)：往里 1 pt 仍在矩形之内，却在圆弧之外
        #expect(!boundary.contains(CGPoint(x: 7, y: 593)))
    }

    /// 尾巴那一侧是主体朝 Dock 的那条边所在的线，横贯整块屏幕：离主体远的地方，线上与线外直到屏幕的角都在边界之内，
    /// 往面板那一侧多 1 pt 就在边界之外；越过屏幕边到了别的屏幕上不再算。Dock 在下、左、右都一样
    @Test
    func dockSideIsLineAcrossScreen() {
        let cases: [(
            dockEdge: DockEdge,
            onLine: CGPoint,
            inward: CGPoint,
            screenCorner: CGPoint,
            offScreen: CGPoint
        )] = [
            (
                dockEdge: .bottom,
                onLine: CGPoint(x: 1800, y: 200),
                inward: CGPoint(x: 1800, y: 201),
                screenCorner: CGPoint(x: 1920, y: 0),
                offScreen: CGPoint(x: 1800, y: -1)
            ),
            (
                dockEdge: .left,
                onLine: CGPoint(x: 100, y: 1000),
                inward: CGPoint(x: 101, y: 1000),
                screenCorner: CGPoint(x: 0, y: 1080),
                offScreen: CGPoint(x: -1, y: 1000)
            ),
            (
                dockEdge: .right,
                onLine: CGPoint(x: 500, y: 1000),
                inward: CGPoint(x: 499, y: 1000),
                screenCorner: CGPoint(x: 1920, y: 1080),
                offScreen: CGPoint(x: 1921, y: 1000)
            ),
        ]

        for testCase in cases {
            let boundary = makeBoundary(dockEdge: testCase.dockEdge)

            #expect(boundary.contains(testCase.onLine))
            #expect(!boundary.contains(testCase.inward))
            #expect(boundary.contains(testCase.screenCorner))
            #expect(!boundary.contains(testCase.offScreen))
        }
    }

    /// 面板贴近底部的 Dock（tilesize 64，面板下沿离 Dock 上沿 13 pt）：主体底边在 y 102，Dock 上沿在 y 89。
    /// 主体向外扩 94 pt 只到 y 8：Dock 最下面几 pt、主体左下方与右下方的 Dock 上，都要靠横贯屏幕的那条线才不浮出
    @Test
    func dockNearPanelIsInside() {
        let boundary = GroupPanelRemoveBoundary(
            bodyFrame: CGRect(x: 1107.5, y: 102, width: 418, height: 300),
            edge: .bottom,
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        // 主体正下方，Dock 最下面的几 pt
        for y in [0, 1, 4, 7] as [CGFloat] {
            #expect(boundary.contains(CGPoint(x: 1188.5, y: y)))
        }

        // 主体左下方与右下方的 Dock 上，以及同高处的屏幕两端
        #expect(boundary.contains(CGPoint(x: 1030, y: 30)))
        #expect(boundary.contains(CGPoint(x: 1610, y: 30)))
        #expect(boundary.contains(CGPoint(x: 200, y: 45)))
        #expect(boundary.contains(CGPoint(x: 1900, y: 45)))
    }
}

// MARK: - Private

extension GroupPanelRemoveBoundaryTests {
    /// 主体与屏幕都取上面的值、Dock 贴在给定屏幕边上时的边界
    private func makeBoundary(dockEdge: DockEdge) -> GroupPanelRemoveBoundary {
        GroupPanelRemoveBoundary(
            bodyFrame: bodyFrame,
            edge: dockEdge,
            screenFrame: screenFrame
        )
    }
}
