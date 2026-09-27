import AppKit

// MARK: - FlotillaApp

/// Flotilla 应用入口
@main
enum FlotillaApp {
    /// 创建应用、挂上 `AppDelegate` 并启动 AppKit 主循环
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        // `NSApplication.delegate` 是弱引用，主循环运行期间由这里持有 delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
