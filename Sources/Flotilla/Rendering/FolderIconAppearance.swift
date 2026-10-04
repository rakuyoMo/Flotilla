import AppKit

// MARK: - FolderIconAppearance

/// 文件夹图标跟随系统外观时随之变化的取值：底板的颜色与不透明度，深色、浅色各一组
///
/// 两种外观的底板形状、边线宽度与预览网格完全相同，只有颜色不同；与外观无关的取值见 `FolderIconRenderer`。
/// 灰度都在 generic gray gamma 2.2 色彩空间里取值。
///
/// 深色取自 wjvalue/macos-dock-folders 的 `glass-dark` 样式，换算到这里的绘制结构：
/// 它的渐变两端是同一灰度色彩空间里的 0.20、0.08，不透明度同为 0.96，
/// 分别作为渐变两端的灰度与底板整体的不透明度；边线的白色、不透明度 0.16 照搬
enum FolderIconAppearance {
    #warning("TODO: 深色底板未与系统深色图标实测对照")

    /// 深色外观
    case dark

    /// 浅色外观
    case light

    /// 底板渐变顶部的灰度
    var plateTopWhite: CGFloat {
        switch self {
        case .dark:
            0.2

        case .light:
            1
        }
    }

    /// 底板渐变底部的灰度
    var plateBottomWhite: CGFloat {
        switch self {
        case .dark:
            0.08

        case .light:
            0.84
        }
    }

    /// 底板的不透明度：半透明，透出 Dock 的背景，形成磨砂感
    var plateOpacity: CGFloat {
        switch self {
        case .dark:
            0.96

        case .light:
            0.9
        }
    }

    /// 底板边线的灰度：深色底板上是白色亮线，浅色底板上是黑色暗线
    var plateEdgeWhite: CGFloat {
        switch self {
        case .dark:
            1

        case .light:
            0
        }
    }

    /// 底板边线的不透明度
    var plateEdgeOpacity: CGFloat {
        switch self {
        case .dark:
            0.16

        case .light:
            0.12
        }
    }

    /// 与给定外观最接近的一种；高对比度等变体归入对应的深色或浅色
    /// - Parameter appearance: 视图的 `effectiveAppearance`，或渲染 stub 图标时 App 的 `effectiveAppearance`
    init(_ appearance: NSAppearance) {
        self = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .dark
            : .light
    }
}
