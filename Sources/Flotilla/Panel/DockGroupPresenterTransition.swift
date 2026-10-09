import Foundation

// MARK: - DockGroupPresenterTransition

/// `DockGroupPresenterState` 处理一个信号后的结论，由 `DockGroupPresenter` 落实到面板上
enum DockGroupPresenterTransition: Equatable {
    /// 面板保持原样：信号被合并、被忽略，或不影响展开状态
    case unchanged

    /// 展开该根文件夹的根层级；已有面板时旧面板立即消失
    case expand(UUID)

    /// 按收起动画收起面板；只在面板展开时给出
    case collapse
}
