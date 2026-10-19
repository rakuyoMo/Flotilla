import Foundation

@testable import Flotilla

// MARK: - FinderFolderIconUpdateRecorder

/// 记下图标库发出的取图结束通知：测试据此等取图结束，或确认没有发出
@MainActor
final class FinderFolderIconUpdateRecorder: NSObject {
    /// 收到的通知里的文件夹路径，按先后
    private(set) var paths: [String] = []

    /// 开始记下这个图标库的通知；记录器释放时自动停止
    /// - Parameter iconStore: 图标库
    init(of iconStore: FinderFolderIconStore) {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(record(_:)),
            name: FinderFolderIconStore.didUpdateIconNotification,
            object: iconStore
        )
    }

    /// 等到这个文件夹的通知累计收到 count 次，最多等 rounds 轮、每轮至少 20 ms
    ///
    /// 按轮数而不按时钟等：kqueue 的事件、合并间隔到期与取图的结果回到主线程时，排在其它测试已经排着的任务之后，
    /// 整套测试一起跑时会晚到几秒；每一轮也排在它之后，轮数够了它一定已经跑过
    /// - Parameters:
    ///   - path: 文件夹的路径
    ///   - count: 累计的次数
    ///   - rounds: 最多等几轮；默认 100 轮，总共至少 2 s
    /// - Returns: 等到了为 true，轮数用完为 false
    func wait(forUpdatesAt path: String, count: Int = 1, rounds: Int = 100) async -> Bool {
        for _ in 0 ..< rounds {
            guard paths.count(where: { $0 == path }) < count else { return true }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return paths.count(where: { $0 == path }) >= count
    }

    /// 记下一条通知里的路径
    @objc
    private func record(_ notification: Notification) {
        guard
            let path = notification.userInfo?[FinderFolderIconStore.folderPathKey] as? String
        else {
            return
        }

        paths.append(path)
    }
}
