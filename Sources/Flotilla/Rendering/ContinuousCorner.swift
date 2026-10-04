import CoreGraphics

// MARK: - ContinuousCorner

/// 连续曲率圆角：每个角由三段三次贝塞尔曲线组成，曲率从直边上的 0 逐渐增大，直边与圆角相接处没有折痕
enum ContinuousCorner {
    /// 圆角沿每条边占用的长度与半径之比
    static let extent: CGFloat = 1.528_664_83

    /// 三段三次贝塞尔曲线：每段是（终点、控制点 1、控制点 2），
    /// 每个点写成（沿来路往回的距离，沿去路的距离），单位为半径
    private static let curves: [(CGVector, CGVector, CGVector)] = [
        (
            CGVector(dx: 0.669_934_27, dy: 0.065_496),
            CGVector(dx: 1.088_493_23, dy: 0),
            CGVector(dx: 0.868_406_89, dy: 0)
        ),
        (
            CGVector(dx: 0.065_495_69, dy: 0.669_934_93),
            CGVector(dx: 0.372_824_16, dy: 0.193_830_71),
            CGVector(dx: 0.193_831_2, dy: 0.372_823_59)
        ),
        (
            CGVector(dx: 0, dy: 1.528_664_71),
            CGVector(dx: 0, dy: 0.868_407_11),
            CGVector(dx: 0, dy: 1.088_493_23)
        ),
    ]

    /// 依次绕过 rect 的 (maxX, minY)、(maxX, maxY)、(minX, maxY)、(minX, minY) 四个角，角与角之间连直边
    ///
    /// 调用前当前点须位于 minY 边上距右端 `extent × radius` 处；结束于同一条边上距左端同样距离处，由调用方闭合
    /// - Parameters:
    ///   - path: 要追加曲线的路径
    ///   - rect: 圆角矩形的外框
    ///   - radius: 圆角半径
    static func addCorners(
        to path: CGMutablePath,
        in rect: CGRect,
        radius: CGFloat
    ) {
        let cornerLength = radius * extent

        // 每个角是（角点、来路方向、去路方向）
        let corners = [
            (CGPoint(x: rect.maxX, y: rect.minY), CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGVector(dx: 0, dy: 1), CGVector(dx: -1, dy: 0)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)),
            (CGPoint(x: rect.minX, y: rect.minY), CGVector(dx: 0, dy: -1), CGVector(dx: 1, dy: 0)),
        ]

        for (index, (corner, incoming, outgoing)) in corners.enumerated() {
            addCorner(
                to: path,
                at: corner,
                incoming: incoming,
                outgoing: outgoing,
                radius: radius
            )

            // 每个角之后沿下一条边走到下一个角的起点；
            // 最后一个角之后由调用方闭合
            guard index < corners.count - 1 else { break }

            let next = corners[index + 1]
            path.addLine(to: CGPoint(
                x: next.0.x - next.1.dx * cornerLength,
                y: next.0.y - next.1.dy * cornerLength
            ))
        }
    }

    /// 添加一个角：当前点位于 corner 沿来路往回 `extent × radius` 处，结束于沿去路同样距离处
    private static func addCorner(
        to path: CGMutablePath,
        at corner: CGPoint,
        incoming: CGVector,
        outgoing: CGVector,
        radius: CGFloat
    ) {
        let point = { (vector: CGVector) in
            CGPoint(
                x: corner.x - incoming.dx * vector.dx * radius + outgoing.dx * vector.dy * radius,
                y: corner.y - incoming.dy * vector.dx * radius + outgoing.dy * vector.dy * radius
            )
        }

        for (end, control1, control2) in curves {
            path.addCurve(
                to: point(end),
                control1: point(control1),
                control2: point(control2)
            )
        }
    }
}
