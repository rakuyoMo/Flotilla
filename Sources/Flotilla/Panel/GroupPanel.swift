import AppKit

// MARK: - GroupPanel

/// 展开组时的悬浮面板：层级高于 Dock，可以成为 key window 接收 Esc，但从不激活 Flotilla（需求 6）
///
/// 全局只有一个实例，由 `GroupPanelController` 持有并复用
@MainActor
final class GroupPanel: NSPanel {
    /// 按下 Esc 时的回调
    var cancelHandler: (() -> Void)?

    /// 允许成为 key window，才能收到 Esc；`nonactivatingPanel` 保证成为 key 时不激活 Flotilla
    override var canBecomeKey: Bool {
        true
    }

    /// 创建无边框、透明、不激活 App 的面板；外观跟随系统
    init() {
        let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        super.init(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: true)

        isOpaque = false
        backgroundColor = .clear

        // 系统阴影边缘更深、衰减更快，与原生不符，阴影由每个层级自己画
        hasShadow = false

        // 鼠标在面板上移动时要判断是否仍在轮廓之内，决定点击是否穿透到下面
        acceptsMouseMovedEvents = true

        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
        hidesOnDeactivate = false
        isFloatingPanel = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        // 设置 isFloatingPanel 会把层级改回 floating，层级必须在它之后设置
        level = .popUpMenu
    }

    /// Esc 经响应链到达窗口时收起面板
    override func cancelOperation(_: Any?) {
        cancelHandler?()
    }
}
