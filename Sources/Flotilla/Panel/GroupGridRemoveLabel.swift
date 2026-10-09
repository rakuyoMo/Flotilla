import AppKit

// MARK: - GroupGridRemoveLabel

/// “移除” 的气泡：与程序坞拖离图标时浮出的相同，胶囊形的主体底边中点接一个向下的小尖，文字在主体里居中
///
/// macOS 26 起底板是玻璃，此前是单层的半透明底板；形状、底板与文字都在这里，放在哪里、何时浮出由拖动图像与网格决定
@MainActor
final class GroupGridRemoveLabel {
    /// 气泡的视图：大小是主体加小尖的外接矩形，不翻转、原点在左下；没有浮出时完全透明
    let view = NSView()

    /// 文字：照抄程序坞
    let text: String

    /// 主体在 `view` 里的 frame：小尖在它下面，尖端在视图的底边
    let bodyFrame: CGRect

    /// 是否浮出：设为 true 时淡入，设为 false 时淡出；创建时没有浮出
    ///
    /// 读的是模型的不透明度：淡出开始的一刻就算没有浮出
    var isShowing: Bool {
        get {
            view.alphaValue == 1
        }
        set {
            fade(to: newValue ? 1 : 0)
        }
    }

    /// 进行中的淡入淡出的时长；不在淡入淡出中时为 nil
    var fadeDuration: CFTimeInterval? {
        view.layer?.animation(forKey: "opacity")?.duration
    }

    /// 创建气泡，先完全透明
    /// - Parameter scale: 屏幕的倍数：单层的底板按它绘制
    init(scale: CGFloat) {
        text = String(
            localized: "panel.remove",
            comment: "面板里把一项拖出面板一段距离、拖动满一会儿之后，拖动图像的图标上方浮出的标识，此后松开即从组里删除这一项；照抄程序坞"
        )

        let font = NSFont.systemFont(ofSize: GroupPanelMetrics.removeLabelFontSize)

        let textWidth = NSAttributedString(
            string: text,
            attributes: [.font: font]
        ).size().width

        // 主体的宽是文字宽加左右内边距；主体从小尖的高度起，小尖在它下面
        bodyFrame = CGRect(
            x: 0,
            y: GroupPanelMetrics.removeLabelPointerHeight,
            width: ceil(textWidth) + 2 * GroupPanelMetrics.removeLabelHorizontalPadding,
            height: GroupPanelMetrics.removeLabelBodyHeight
        )

        view.frame = CGRect(
            x: 0,
            y: 0,
            width: bodyFrame.width,
            height: bodyFrame.maxY
        )

        // 淡入淡出在图层上做：显式要一个图层，离屏的窗口里子视图默认没有
        view.wantsLayer = true
        view.alphaValue = 0

        view.addSubview(makeBackground(scale: scale))
        view.addSubview(makeTextField(font: font))
    }
}

// MARK: - Private

extension GroupGridRemoveLabel {
    /// 从画面上的当前不透明度淡到给定的值，ease-in-ease-out；已经是这个值时不动
    ///
    /// 淡入途中又淡出时从当时的画面接着变，不跳
    private func fade(to alpha: CGFloat) {
        guard view.alphaValue != alpha else { return }

        let start = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)

        view.alphaValue = alpha

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = start
        animation.toValue = Float(alpha)
        animation.duration = GroupPanelMetrics.removeLabelFadeDuration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        view.layer?.add(animation, forKey: "opacity")
    }

    /// 底板：macOS 26 起是玻璃，此前是单层的半透明底板
    private func makeBackground(scale: CGFloat) -> NSView {
        if #available(macOS 26, *) {
            return makeGlassBackground()
        }

        return makeFlatBackground(scale: scale)
    }

    /// 玻璃的底板：主体与它下面的一个小圆放进同一个容器，两块玻璃融合成带圆头小尖的气泡，外观跟随系统
    ///
    /// 玻璃只有圆角，本身做不出小尖；给它加图层遮罩，玻璃的边就不再画出来
    @available(macOS 26, *)
    private func makeGlassBackground() -> NSView {
        let diameter = GroupPanelMetrics.removeLabelPointerDotDiameter

        let body = Self.makeGlass(frame: bodyFrame)

        // 小圆的下沿就是小尖的尖端，在视图的底边
        let dot = Self.makeGlass(frame: CGRect(
            x: bodyFrame.midX - diameter / 2,
            y: 0,
            width: diameter,
            height: diameter
        ))

        let container = NSGlassEffectContainerView(frame: view.bounds)
        let content = NSView(frame: container.bounds)

        content.addSubview(body)
        content.addSubview(dot)

        // 相距不到这个距离的玻璃融合成一块
        container.spacing = 8
        container.contentView = content

        return container
    }

    /// 单层的半透明底板：胶囊加尖头的三角形小尖，用于没有玻璃的系统
    ///
    /// 颜色按程序坞的 “移除” 在黑、灰、白三种纯色背景上的读数拟合，在五种纯色背景上与程序坞的平均差约 22 级
    private func makeFlatBackground(scale: CGFloat) -> NSView {
        let shape = CAShapeLayer()
        shape.path = Self.flatOutline(bodyFrame: bodyFrame)
        shape.fillColor = NSColor(white: 0.38, alpha: 0.42).cgColor
        shape.contentsScale = scale

        // 托管自己的图层：形状由这里画，AppKit 不改它
        let background = NSView(frame: view.bounds)
        background.layer = shape
        background.wantsLayer = true

        return background
    }

    /// 文字：系统字体常规，白色，关闭字体平滑，在主体里水平、竖直居中
    private func makeTextField(font: NSFont) -> NSTextField {
        let textField = GroupPanelLabel(labelWithString: text)
        textField.font = font
        textField.textColor = NSColor(white: 1, alpha: 0.96)
        textField.alignment = .center

        let size = textField.fittingSize

        textField.frame = CGRect(
            x: bodyFrame.midX - size.width / 2,
            y: bodyFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )

        return textField
    }
}

// MARK: - Helpers

extension GroupGridRemoveLabel {
    /// 一块玻璃：regular 加白色 0.2 的色调，圆角半径是高度的一半
    ///
    /// 这样的玻璃与程序坞的 “移除” 在灰、白、黑、红、蓝五种纯色背景上平均只差约 3 级
    @available(macOS 26, *)
    private static func makeGlass(frame: CGRect) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: frame)
        glass.style = .regular
        glass.tintColor = NSColor(white: 1, alpha: 0.2)
        glass.cornerRadius = frame.height / 2
        glass.contentView = NSView(frame: glass.bounds)

        return glass
    }

    /// 单层底板的轮廓：一条闭合路径，从主体底边左段起，经小尖、右端的半圆、顶边、左端的半圆回到起点
    ///
    /// 主体与小尖合成一条轮廓再填充：分开填充时重叠处的不透明度会叠加
    private static func flatOutline(bodyFrame: CGRect) -> CGPath {
        let radius = bodyFrame.height / 2
        let halfWidth = GroupPanelMetrics.removeLabelPointerWidth / 2

        let tip = CGPoint(
            x: bodyFrame.midX,
            y: bodyFrame.minY - GroupPanelMetrics.removeLabelPointerHeight
        )

        let path = CGMutablePath()
        path.move(to: CGPoint(x: bodyFrame.minX + radius, y: bodyFrame.minY))
        path.addLine(to: CGPoint(x: tip.x - halfWidth, y: bodyFrame.minY))
        path.addLine(to: tip)
        path.addLine(to: CGPoint(x: tip.x + halfWidth, y: bodyFrame.minY))

        // 两端各由两段四分之一圆弧合成半圆
        path.addArc(
            tangent1End: CGPoint(x: bodyFrame.maxX, y: bodyFrame.minY),
            tangent2End: CGPoint(x: bodyFrame.maxX, y: bodyFrame.midY),
            radius: radius
        )

        path.addArc(
            tangent1End: CGPoint(x: bodyFrame.maxX, y: bodyFrame.maxY),
            tangent2End: CGPoint(x: bodyFrame.midX, y: bodyFrame.maxY),
            radius: radius
        )

        path.addArc(
            tangent1End: CGPoint(x: bodyFrame.minX, y: bodyFrame.maxY),
            tangent2End: CGPoint(x: bodyFrame.minX, y: bodyFrame.midY),
            radius: radius
        )

        path.addArc(
            tangent1End: CGPoint(x: bodyFrame.minX, y: bodyFrame.minY),
            tangent2End: CGPoint(x: bodyFrame.midX, y: bodyFrame.minY),
            radius: radius
        )

        path.closeSubpath()

        return path
    }
}
