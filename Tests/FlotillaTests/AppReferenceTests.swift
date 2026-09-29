import Foundation
import Testing

@testable import Flotilla

// MARK: - AppReferenceTests

/// 要加入文件夹的 URL 据此分出 App：只有 App bundle 是 App
struct AppReferenceTests {
    /// App bundle 被识别为 App
    @Test
    func applicationBundleIsRecognized() {
        let url = URL(filePath: "/System/Applications/Chess.app", directoryHint: .isDirectory)

        #expect(AppReference.isApplicationBundle(url))
    }

    /// 普通文件、命令行工具、目录与不存在的路径都不是 App
    @Test(arguments: [
        "/etc/hosts",
        "/usr/bin/true",
        "/System/Applications",
        "/Applications/不存在的应用.app",
    ])
    func otherItemsAreRejected(path: String) {
        #expect(!AppReference.isApplicationBundle(URL(filePath: path)))
    }
}
