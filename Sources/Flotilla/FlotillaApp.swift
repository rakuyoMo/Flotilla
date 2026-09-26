import AppKit

// MARK: - FlotillaApp

/// Flotilla 应用入口
@main
enum FlotillaApp {
    /// 启动 AppKit 主循环
    @MainActor
    static func main() {
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
