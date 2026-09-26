import Foundation

// MARK: - DockFolderPresenterTransition

/// `DockFolderPresenterState` 处理一个信号后的结论，由 `DockFolderPresenter` 落实到面板上
enum DockFolderPresenterTransition: Equatable {
    /// 面板保持原样
    case unchanged

    /// 展开该根文件夹的根层级；已有面板时旧面板立即消失
    case expand(UUID)

    /// 收起面板
    case collapse
}
