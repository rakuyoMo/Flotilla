import AppKit

// MARK: - StatusBarIcon

/// 状态栏图标（需求 7）：App 图标里那艘方帆船的剪影，按矢量绘制成 template 图
///
/// 画布 16×16 pt，船从桅顶到船底占满画布高度，放进 22 pt 见方的状态栏按钮后四周各留 3 pt。
/// 桅杆、甲板、船尾与船底都落在整点上，1x 屏幕上这些边缘不发虚。
/// SF Symbols 的 `sailboat` 是三角帆小艇，与 App 图标的方帆船不像，因此在这里自己画
enum StatusBarIcon {
    /// 生成状态栏图标
    /// - Returns: template 图，由系统按菜单栏的深浅着色；无障碍描述为“Flotilla”
    static func makeImage() -> NSImage {
        let image = NSImage(
            size: NSSize(width: 16, height: 16),
            flipped: true
        ) { _ in
            // template 图只取不透明度，颜色取什么都一样
            NSColor.black.set()

            // 先画桅杆，帆与船身盖在它上面；桅杆露在上帆之上、帆间的缝里，以及下帆与甲板之间
            drawMastAndFlag()
            drawSails()
            drawHull()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "Flotilla"

        return image
    }
}

// MARK: - Private

extension StatusBarIcon {
    /// 桅杆与桅顶的小旗
    ///
    /// 坐标取自母版剪影：把船从桅顶到船底缩到 16 pt 高，桅杆落在船身左起约四成处
    private static func drawMastAndFlag() {
        // 桅杆宽 1 pt，占满 x 6–7 这一列整点，从画布顶端一直插到甲板（y = 13）
        NSBezierPath.fill(NSRect(x: 6, y: 0, width: 1, height: 13))

        // 小旗贴着桅顶挂在桅杆右侧，是一面向右飘的三角旗，
        // 高 1.8 pt，下缘与上帆之间留出空隙，缩小后两者不粘连
        let flag = NSBezierPath()
        flag.move(to: NSPoint(x: 7, y: 0))
        flag.line(to: NSPoint(x: 10.4, y: 0.9))
        flag.line(to: NSPoint(x: 7, y: 1.8))
        flag.close()
        flag.fill()
    }

    /// 三面上下叠放的横帆
    ///
    /// 与母版一样，帆桁左高右低、越往下越宽；相邻两面之间留 1.1 pt 的斜缝，
    /// 桅杆从缝里露出来。四个角按母版剪影量得，再缩到 16 pt 高
    private static func drawSails() {
        // 上帆：最窄，帆桁在桅杆处比小旗下缘低约 0.8 pt
        sail(
            topLeft: NSPoint(x: 4, y: 2.2),
            topRight: NSPoint(x: 8.5, y: 3),
            bottomRight: NSPoint(x: 9.3, y: 5.1),
            bottomLeft: NSPoint(x: 2.9, y: 4)
        )
        .fill()

        // 中帆：上缘与上帆下缘平行，整体向右下展宽
        sail(
            topLeft: NSPoint(x: 2.9, y: 5.1),
            topRight: NSPoint(x: 9.4, y: 6.2),
            bottomRight: NSPoint(x: 10.7, y: 8.8),
            bottomLeft: NSPoint(x: 2.1, y: 7.4)
        )
        .fill()

        // 下帆：最宽，帆脚水平，与甲板之间留 1.2 pt，露出一段桅杆
        sail(
            topLeft: NSPoint(x: 2.2, y: 8.5),
            topRight: NSPoint(x: 10.7, y: 9.9),
            bottomRight: NSPoint(x: 11.4, y: 11.8),
            bottomLeft: NSPoint(x: 2.5, y: 11.8)
        )
        .fill()
    }

    /// 船身与船首斜桅
    ///
    /// 船尾在左、高起一截，甲板水平，船首在右、向上翘成尖，船底是一段平直的龙骨接两头的弧线
    private static func drawHull() {
        let hull = NSBezierPath()

        // 船尾楼：左上角从 (1, 12) 起，高出甲板 1 pt、宽 1 pt，边缘都在整点上
        hull.move(to: NSPoint(x: 1, y: 12))
        hull.line(to: NSPoint(x: 2, y: 12))
        hull.line(to: NSPoint(x: 2, y: 13))

        // 甲板：y = 13 的整点水平线，一直走到船首根部，再斜着翘到船首尖
        hull.line(to: NSPoint(x: 11.6, y: 13))
        hull.line(to: NSPoint(x: 12.7, y: 12.3))

        // 船首下缘：从船首尖弧形收到龙骨右端
        hull.curve(
            to: NSPoint(x: 9.2, y: 16),
            controlPoint1: NSPoint(x: 12.3, y: 14.4),
            controlPoint2: NSPoint(x: 11, y: 15.8)
        )

        // 龙骨：贴着画布底边（y = 16）的水平线
        hull.line(to: NSPoint(x: 3.8, y: 16))

        // 船尾下缘：从龙骨左端弧形收到船尾竖直的外缘（x = 1），再回到起点
        hull.curve(
            to: NSPoint(x: 1, y: 14),
            controlPoint1: NSPoint(x: 2.3, y: 16),
            controlPoint2: NSPoint(x: 1.1, y: 15.1)
        )
        hull.close()
        hull.fill()

        // 船首斜桅：从船首根部向右上伸出，右端连同线宽到 x ≈ 15，与左侧船尾（x = 1）对称，整幅图水平居中
        let bowsprit = NSBezierPath()
        bowsprit.lineWidth = 0.75
        bowsprit.move(to: NSPoint(x: 12, y: 12.8))
        bowsprit.line(to: NSPoint(x: 14.8, y: 11))
        bowsprit.stroke()
    }

    /// 一面横帆的轮廓
    ///
    /// 上缘是帆桁、下缘是帆脚，都是直线；两侧向外鼓，右侧鼓 0.7 pt 表现兜满了风，左侧鼓 0.3 pt
    /// - Parameters:
    ///   - topLeft: 帆桁左端
    ///   - topRight: 帆桁右端
    ///   - bottomRight: 帆脚右端
    ///   - bottomLeft: 帆脚左端
    /// - Returns: 闭合的帆面路径
    private static func sail(
        topLeft: NSPoint,
        topRight: NSPoint,
        bottomRight: NSPoint,
        bottomLeft: NSPoint
    ) -> NSBezierPath {
        let rightHeight = bottomRight.y - topRight.y
        let leftHeight = bottomLeft.y - topLeft.y

        let path = NSBezierPath()
        path.move(to: topLeft)
        path.line(to: topRight)

        // 右缘：两个控制点在上下三成处向右推出，上段鼓得多、下段收回，像被风兜起的帆面
        path.curve(
            to: bottomRight,
            controlPoint1: NSPoint(x: topRight.x + 0.7, y: topRight.y + rightHeight * 0.3),
            controlPoint2: NSPoint(x: bottomRight.x + 0.42, y: bottomRight.y - rightHeight * 0.3)
        )

        path.line(to: bottomLeft)

        // 左缘：两个控制点在上下三成处向左推出 0.3 pt，只微微外鼓
        path.curve(
            to: topLeft,
            controlPoint1: NSPoint(x: bottomLeft.x - 0.3, y: bottomLeft.y - leftHeight * 0.3),
            controlPoint2: NSPoint(x: topLeft.x - 0.3, y: topLeft.y + leftHeight * 0.3)
        )

        path.close()

        return path
    }
}
