import AppKit

// MARK: - FolderNavigationBackButton

/// 导航头里的返回按钮：面板不是 key window 时，第一次点击也直接生效
@MainActor
final class FolderNavigationBackButton: NSButton {
    /// 面板从不激活 Flotilla，第一次点击不能只用来激活窗口
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }
}
