import AppKit

// MARK: - FolderPanelAppearance

/// 面板跟随系统外观时随之变化的取值：颜色、不透明度与返回按钮的几个尺寸，深色、浅色各一组
///
/// 数值来自对原生 Dock 文件夹弹窗的实测（macOS 27、tilesize 64），边缘线的读数都取灰度 128 的背景；
/// 与外观无关的几何与动画参数见 `FolderPanelMetrics`
enum FolderPanelAppearance {
    /// 深色外观
    case dark

    /// 浅色外观
    case light

    /// 标题与名称使用的动态颜色：随视图的实际外观取值，外观变化时文字自动换色
    static let dynamicTextColor = NSColor(name: nil) {
        Self($0).textColor
    }

    /// 文字颜色
    ///
    /// 深色原生文字在四种底色上都等于白色以不透明度 0.95 叠在材质上；
    /// 浅色原生文字在四种底色上都等于材质 × 0.15，即黑色、不透明度 0.85
    var textColor: NSColor {
        switch self {
        case .dark:
            NSColor(white: 1, alpha: 0.95)

        case .light:
            NSColor(white: 0, alpha: 0.85)
        }
    }

    /// 阴影的不透明度：浅色原生阴影在边缘处约为深色的 0.64 倍，形状相同
    var shadowOpacity: Float {
        switch self {
        case .dark:
            0.17

        case .light:
            0.11
        }
    }

    /// 轮廓外侧暗线的不透明度，竖直边上最强：深色读数约 50，浅色约 59（紧邻的底色 121）
    var edgeShadeOpacity: CGFloat {
        switch self {
        case .dark:
            0.57

        case .light:
            0.51
        }
    }

    /// 水平边外侧暗线的不透明度：浅色读数上 104、下 99（紧邻的底色 124、118）；深色没有这道线
    var horizontalEdgeShadeOpacity: CGFloat {
        switch self {
        case .dark:
            0

        case .light:
            0.16
        }
    }

    /// 轮廓内侧自外向内每道 1 像素亮线的不透明度，集中在水平边
    ///
    /// 深色读数约 157、139，浅色约 233、220、208（材质 205）
    var edgeHighlightOpacities: [CGFloat] {
        switch self {
        case .dark:
            [0.3, 0.17, 0]

        case .light:
            [0.56, 0.3, 0.06]
        }
    }

    /// 返回按钮底色可见部分相对 21 × 22 pt 按钮 frame 的内缩
    ///
    /// 深色底色 21 × 21 pt，贴 frame 顶边，frame 最下面 1 pt 不画；浅色连边线 20 × 20 pt，比深色四周各小 0.5 pt，下方留给投影
    var backButtonBezelInsets: NSEdgeInsets {
        switch self {
        case .dark:
            NSEdgeInsets(top: 0, left: 0, bottom: 1, right: 0)

        case .light:
            NSEdgeInsets(top: 0.5, left: 0.5, bottom: 1.5, right: 0.5)
        }
    }

    /// 返回按钮底色可见部分的圆角半径，连续曲率
    ///
    /// 浅色可见部分比深色四周各小 0.5 pt，圆角同心，半径也小 0.5 pt
    var backButtonCornerRadius: CGFloat {
        switch self {
        case .dark:
            4

        case .light:
            3.5
        }
    }

    /// 返回按钮底色外一圈 1 像素暗线的不透明度；深色没有这圈线
    ///
    /// 浅色原生读数按 “黑色叠在材质上” 折算，灰、黑两种底色一致：上 0.16、左右 0.18
    var backButtonBorderOpacity: CGFloat {
        switch self {
        case .dark:
            0

        case .light:
            0.16
        }
    }

    /// 返回按钮下方的投影；深色没有投影
    ///
    /// 浅色原生下边线折算 0.26，其外两像素 0.12、0.04，左右与上方外侧约 0.03；按这组参数画出的读数与原生相差不超过 6 / 255
    var backButtonShadow: NSShadow? {
        switch self {
        case .dark:
            return nil

        case .light:
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.13)
            shadow.shadowOffset = CGSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 0.75

            return shadow
        }
    }

    /// 返回按钮 chevron 的颜色：浅色与文字相同
    var backButtonChevronColor: NSColor {
        switch self {
        case .dark:
            .white

        case .light:
            NSColor(white: 0, alpha: 0.85)
        }
    }

    /// 返回按钮 chevron 的线宽
    ///
    /// 两种外观下原生 chevron 的位置与长度相同，截图上深色的线更粗：按 8 位读数线性叠加拟合，深色 1.13 pt、浅色 0.95 pt
    var backButtonChevronLineWidth: CGFloat {
        switch self {
        case .dark:
            1.13

        case .light:
            0.95
        }
    }

    /// “在访达中打开” 的图标与面板材质的合成方式，取 Core Animation 的合成滤镜名
    ///
    /// 黑、灰、白、红四种底色上，原生图标处每个通道都与材质相差同样的量：
    /// 深色是叠加（plus-lighter），比材质高；浅色是叠暗（plus-darker），比材质低
    var openInFinderCompositingFilter: String {
        switch self {
        case .dark:
            "plusL"

        case .light:
            "plusD"
        }
    }

    /// 与视图的实际外观最接近的一种；高对比度等变体归入对应的深色或浅色
    /// - Parameter appearance: 视图的 `effectiveAppearance`
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }

    /// “在访达中打开” 图标的颜色，按 `openInFinderCompositingFilter` 与材质合成
    ///
    /// 叠加时加上的量就是颜色本身；叠暗时减去的量是 1 减去颜色。取 sRGB 灰：屏上读数与 sRGB 的数值一致
    ///
    /// 原生实测：深色平时加 124 / 255、按下加 50 / 255；浅色平时减 127 / 255、按下减 194 / 255
    /// - Parameter isPressed: 是否处于按下状态
    func openInFinderIconColor(isPressed: Bool) -> NSColor {
        let white: CGFloat =
            switch (self, isPressed) {
            // 叠加：颜色就是加上的量
            case (.dark, false):
                124 / 255

            case (.dark, true):
                50 / 255

            // 叠暗：颜色是 1 减去减掉的量，按下时减得更多
            case (.light, false):
                1 - 127 / 255

            case (.light, true):
                1 - 194 / 255
            }

        return NSColor(
            srgbRed: white,
            green: white,
            blue: white,
            alpha: 1
        )
    }

    /// 返回按钮的底色，悬停不变
    ///
    /// 深色是半透明白色，按下时更白；浅色是不透明的白色，按下时变为 240 灰
    /// - Parameter isPressed: 是否处于按下状态
    func backButtonFillColor(isPressed: Bool) -> NSColor {
        switch self {
        case .dark:
            NSColor(white: 1, alpha: isPressed ? 0.61 : 0.42)

        case .light:
            NSColor(white: isPressed ? 240 / 255 : 1, alpha: 1)
        }
    }
}
