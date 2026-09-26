import CoreGraphics
import Foundation

// MARK: - FolderPanelMetrics

/// 面板的几何、网格与动画参数；对照原生弹窗的数值集中在这里，按实测结果替换
enum FolderPanelMetrics {
    // MARK: 外观

    /// 面板主体的圆角半径
    static let cornerRadius: CGFloat = 20

    /// 尾巴底边的宽度
    static let tailWidth: CGFloat = 24

    /// 尾巴从底边到尖端的高度
    static let tailHeight: CGFloat = 12

    /// 尾巴尖端与 Dock 边缘的距离
    static let tailTipGap: CGFloat = 4

    /// 面板主体到内容的内边距
    static let contentInset: CGFloat = 16

    /// 面板与屏幕 `visibleFrame` 边缘保持的最小距离
    static let screenMargin: CGFloat = 16

    // MARK: 网格

    /// 单元格尺寸
    static let cellSize = CGSize(width: 112, height: 100)

    /// 单元格内图标的边长
    static let iconSize: CGFloat = 64

    /// 图标与名称之间的间距
    static let iconTitleSpacing: CGFloat = 4

    /// 名称的字号
    static let titleFontSize: CGFloat = 12

    /// 名称最多显示的行数
    static let titleMaximumLines = 2

    /// 悬停、按下高亮的圆角半径
    static let highlightCornerRadius: CGFloat = 8

    /// 列数规则里的最少列数：项数不少于它时，至少排这么多列
    static let minimumColumnCount = 4

    /// 列数规则里的系数：列数随 `ceil(sqrt(项数 × 系数))` 增长
    static let columnGrowthFactor = 1.5

    // MARK: 导航头

    /// 导航头的高度
    static let headerHeight: CGFloat = 32

    /// 导航头标题的字号
    static let headerTitleFontSize: CGFloat = 13

    /// 返回按钮的边长
    static let backButtonSize: CGFloat = 24

    // MARK: 动画

    /// 展开动画的时长（秒）
    static let expandDuration: CFTimeInterval = 0.2

    /// 收起动画的时长（秒）
    static let collapseDuration: CFTimeInterval = 0.15

    /// 展开动画开始时、收起动画结束时面板的缩放比例
    static let collapsedScale: CGFloat = 0.2

    /// 进入、返回子文件夹时转场与面板尺寸变化的时长（秒）
    static let navigationDuration: CFTimeInterval = 0.2

    /// 进入子文件夹时新内容的起始缩放比例；返回时取它的倒数
    static let navigationScale: CGFloat = 0.9

    // MARK: 点击

    /// 在 tile 上按下后，移动超过这个距离即视为拖动
    static let dragThreshold: CGFloat = 4
}
