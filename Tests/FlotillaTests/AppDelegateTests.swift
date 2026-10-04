import Foundation
import Testing

@testable import Flotilla

// MARK: - AppDelegateTests

/// 单实例保护：两个 Flotilla 会同时改写 Dock 偏好，启动时发现别的实例就必须退出；
/// 同一 bundle id 的实例列表里总有当前进程自己，它不能被当成“别的实例”，否则 Flotilla 永远起不来
@MainActor
struct AppDelegateTests {
    /// 假定的当前进程号；
    /// 测试参数里的 200 就是当前进程自己
    private let currentProcessIdentifier: pid_t = 200

    /// 只有当前进程在运行：不是重复启动
    @Test
    func aloneIsNotDuplicate() {
        let other = AppDelegate.otherInstance(
            among: [currentProcessIdentifier],
            currentProcessIdentifier: currentProcessIdentifier
        ) { $0 }

        #expect(other == nil)
    }

    /// 另有一个实例在运行，不论它在列表里排在当前进程之前还是之后，都要找出它
    @Test(arguments: [
        [pid_t(100), 200],
        [200, 300],
    ])
    func findsOtherInstance(instances: [pid_t]) {
        let other = AppDelegate.otherInstance(
            among: instances,
            currentProcessIdentifier: currentProcessIdentifier
        ) { $0 }

        #expect(other != nil)
        #expect(other != currentProcessIdentifier)
    }
}
