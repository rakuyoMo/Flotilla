import CoreGraphics
import Foundation

// MARK: - FolderPanelMetrics

/// 面板的几何、网格与动画参数，数值来自对原生 Dock 文件夹弹窗的实测（macOS 27、深色外观、tilesize 64）
enum FolderPanelMetrics {
    // MARK: 外观

    /// 面板主体的圆角半径，连续曲率
    static let cornerRadius: CGFloat = 25

    /// 尾巴两条 45° 斜边与面板边的两个交点之间的距离
    static let tailBaseWidth: CGFloat = 19.5

    /// 尾巴尖端倒圆的半径
    static let tailTipRadius: CGFloat = 4

    /// 尾巴斜边与面板边相接处内凹圆角的半径
    static let tailFilletRadius: CGFloat = 4

    /// 面板主体面向 Dock 的边到尾巴尖端的距离
    static let tailHeight: CGFloat = 8

    /// 尾巴尖端沿 Dock 方向相对 tile frame 中心的偏移
    ///
    /// 左侧 App 区域的 tile 图标同样居中于 tile frame，尖端因此与原生一样落在图标视觉中心左侧 5 pt
    static let tailTipOffset: CGFloat = -5

    /// 尾巴尖端伸进 tile frame 的深度
    static let tailTipInset: CGFloat = 1

    /// 面板主体中心沿 Dock 方向相对尾巴尖端的偏移：原生面板并不以尾巴为中线
    static let bodyCenterOffset: CGFloat = 3

    /// 面板主体与屏幕两侧边缘的最小距离
    static let screenSideMargin: CGFloat = 32

    /// 面板主体与屏幕可用区域远离 Dock 那一侧边缘的最小距离
    static let screenFarMargin: CGFloat = 16

    /// 展开、收起的缩放锚点（tile 图标中心）从尾巴尖端向 Dock 内的距离
    static let anchorDepth: CGFloat = 35

    /// 阴影的模糊半径：原生阴影拟合为 σ ≈ 18 pt 的高斯模糊，屏上实测 `shadowRadius` 约等于 σ
    static let shadowRadius: CGFloat = 18

    /// 阴影向屏幕下方的偏移
    static let shadowOffset: CGFloat = 8.5

    /// 窗口在面板轮廓之外为阴影留出的距离
    static let shadowMargin: CGFloat = 60

    // MARK: 网格

    /// 标题区的高度，根层级与子层级都有
    static let headerHeight: CGFloat = 32

    /// 网格与面板主体左右边的距离
    static let gridSideInset: CGFloat = 17

    /// 网格与面板主体底边的距离
    static let gridBottomInset: CGFloat = 12

    /// 单元格的边长，单元格彼此紧贴
    static let cellSize: CGFloat = 128

    /// 图标画布的边长：图标主体约 81 pt，macOS 26 起 App 图标主体占画布的 80%
    static let iconSize: CGFloat = 101

    /// 文件内容缩略图的画布边长：QuickLook 在这个画布里画出长边 88 pt 的页面或图片，带圆角、亮边与投影
    ///
    /// 原生叠放的缩略图与按这个边长生成的逐项相同：外接框、中心与投影剖面（macOS 27、tilesize 64 实测）；
    /// 画布居中放进图标画布，中心与图标相同
    static let fileThumbnailSize: CGFloat = 100

    /// 图标中心与单元格顶边的距离
    static let iconCenterY: CGFloat = 56

    /// 名称的字号
    static let titleFontSize: CGFloat = 13

    /// 名称的最大宽度，超出时在中间省略
    static let titleMaximumWidth: CGFloat = 120

    /// 名称基线与单元格顶边的距离
    static let titleBaselineY: CGFloat = 119

    /// 按下时图标的亮度（RGB 乘以这个系数）
    static let pressedIconBrightness: CGFloat = 0.475

    /// “在访达中打开”图标的边长：Dock 的 128 pt 原图按这个边长画，中心与其它格的图标相同，圆圈外径 64 pt、线宽 2.3 pt
    static let openInFinderIconSize: CGFloat = 100

    /// 最多显示的行数，超出时网格滚动
    static let maximumVisibleRowCount = 5

    /// 行数超过 `maximumVisibleRowCount` 时改用的列数
    static let overflowColumnCount = 7

    /// 滚动条右缘与面板主体右边的距离
    static let scrollerTrailingInset: CGFloat = 3

    // MARK: 标题区

    /// 标题的字号
    static let headerTitleFontSize: CGFloat = 14

    /// 标题基线与面板主体顶边的距离：原生根层级与子层级渲染出的基线都在 23 pt
    static let headerTitleBaselineY: CGFloat = 23

    /// 原生标题框比文字宽（向上取整到点）多出的宽度
    ///
    /// 原生标题框宽为文字宽向上取整再加这个值，框的左边是居中位置向下取整到点，文字在框里居中
    static let headerTitleFrameExtraWidth: CGFloat = 1

    /// 返回按钮在面板主体里的位置与尺寸，原点在主体左上角、y 向下
    static let backButtonFrame = CGRect(x: 15, y: 7, width: 21, height: 22)

    /// 返回按钮里 chevron 的高度：两个端点之间的竖直距离，不含线宽
    ///
    /// 两条边与水平方向成 45°，宽度是高度的一半；深色、浅色原生的几何相同
    static let backChevronHeight: CGFloat = 10.1

    /// chevron 外接框（不含线宽）的水平中心相对底色中心的偏移，负值向左
    ///
    /// 原生 chevron 并不水平居中：顶点距按钮 frame 左边 7.225 pt，外接框中心比 21 pt 宽的底色中心偏左 0.75 pt
    static let backChevronOffsetX: CGFloat = -0.75

    // MARK: 动画

    /// 展开时的起始缩放比例
    static let expandInitialScale: CGFloat = 0.1

    /// 展开时缩放的时长（秒）
    static let expandDuration: CFTimeInterval = 0.23

    /// 展开时缩放的时间曲线控制点（ease-out cubic）
    static let expandTimingControlPoints: [Float] = [0.33, 1, 0.68, 1]

    /// 展开时淡入的时长（秒）
    static let expandFadeDuration: CFTimeInterval = 0.15

    /// 收起时缩放的时长（秒），缩放到 0
    static let collapseDuration: CFTimeInterval = 0.23

    /// 收起时缩放的时间曲线控制点
    static let collapseTimingControlPoints: [Float] = [0.25, 0.1, 0.25, 1]

    /// 收起时淡出的时长（秒），早于缩放结束，收起约 0.15 秒时已看不见
    static let collapseFadeDuration: CFTimeInterval = 0.15

    /// 进入子文件夹时旧层级原地淡出的时长（秒）
    static let enterFadeOutDuration: CFTimeInterval = 0.08

    /// 返回上一层时父层级原地淡入的时长（秒）
    static let backFadeInDuration: CFTimeInterval = 0.07

    // MARK: 点击

    /// 在 tile 上按下后，移动超过这个距离即视为拖动：与 Dock 一致，移动不超过 5 pt 时 Dock 仍按点击启动 stub
    static let dragThreshold: CGFloat = 5

    /// 按住 tile 超过这个时长（秒）抬起不算点击
    ///
    /// Dock 按住约 0.5 秒即判为长按、弹出 App 菜单，之后抬起不再启动 stub；
    /// 取略小的值，落在两者之间的抬起由随后到达的 URL 按点击处理，Dock 弹出菜单时面板不会展开
    static let longPressDuration: TimeInterval = 0.45
}
