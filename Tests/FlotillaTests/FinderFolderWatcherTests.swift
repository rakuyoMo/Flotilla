import Foundation
import Testing

@testable import Flotilla

// MARK: - FinderFolderWatcherTests

/// 监听器释放之后不再回调、描述符随之关掉：图标库把访达文件夹移出组树时，靠释放监听器停止监听，
/// 每个访达文件夹常驻的描述符不能留着；文件夹被删除、改名或挪走也要回调，图标库才会去核对原路径上换没换文件夹
@MainActor
final class FinderFolderWatcherTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 监听器回调的次数
    private var eventCount = 0

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 改扩展属性时回调；释放之后再改，不再回调
    @Test
    func releasedWatcherStopsCallingBack() async throws {
        let folder = try makeFolder()
        var watcher = makeWatcher(of: folder)

        try #require(watcher != nil)

        try FinderFolderAttributes.setTags(["红色\n6"], of: folder)

        try #require(await wait { eventCount > 0 })

        watcher = nil

        let count = eventCount

        try FinderFolderAttributes.setTags(["绿色\n2"], of: folder)

        // 30 轮至少 0.6 s：事件 1 ms 内就到，没停的话这时一定已经回调过
        #expect(await !wait(rounds: 30) { eventCount > count })
    }

    /// 释放之后，打开着这个文件夹的描述符随之关掉
    @Test
    func releasedWatcherClosesDescriptor() async throws {
        let folder = try makeFolder()
        var watcher = makeWatcher(of: folder)

        try #require(watcher != nil)

        #expect(openDescriptorCount(of: folder) == 1)

        watcher = nil

        // 取消之后，描述符在主队列上关掉
        #expect(await wait { openDescriptorCount(of: folder) == 0 })
    }

    /// 文件夹被删除：回调
    @Test
    func deletionCallsBack() async throws {
        let folder = try makeFolder()
        let watcher = try #require(makeWatcher(of: folder))

        try FileManager.default.removeItem(at: folder)

        #expect(await wait { eventCount > 0 })

        withExtendedLifetime(watcher) { }
    }

    /// 文件夹改名：回调
    @Test
    func renamingCallsBack() async throws {
        let folder = try makeFolder()
        let watcher = try #require(makeWatcher(of: folder))

        try FileManager.default.moveItem(
            at: folder,
            to: directory.appending(path: "改名", directoryHint: .isDirectory)
        )

        #expect(await wait { eventCount > 0 })

        withExtendedLifetime(watcher) { }
    }
}

// MARK: - Private

extension FinderFolderWatcherTests {
    /// 在临时目录里新建一个文件夹
    private func makeFolder() throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return folder
    }

    /// 监听这个文件夹，每次回调把 `eventCount` 加 1
    /// - Parameter folder: 文件夹的 URL
    private func makeWatcher(of folder: URL) -> FinderFolderWatcher? {
        FinderFolderWatcher(path: folder.path(percentEncoded: false)) { [weak self] in
            self?.eventCount += 1
        }
    }

    /// 进程里打开着这个文件夹的描述符有几个：逐个问描述符指向的路径
    ///
    /// 按文件夹名比较：它是本用例独有的 UUID，临时目录的路径写法（`/var` 与 `/private/var`）不影响
    /// - Parameter folder: 文件夹的 URL
    private func openDescriptorCount(of folder: URL) -> Int {
        let suffix = "/" + folder.lastPathComponent
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))

        return (0 ..< getdtablesize()).count {
            guard fcntl($0, F_GETPATH, &buffer) != -1 else { return false }

            return String(cString: buffer).hasSuffix(suffix)
        }
    }

    /// 等到条件成立，最多等 rounds 轮、每轮至少 20 ms
    ///
    /// 按轮数而不按时钟等，理由同 `FinderFolderIconUpdateRecorder`
    /// - Parameters:
    ///   - rounds: 最多等几轮；默认 100 轮，总共至少 2 s
    ///   - condition: 要等的条件
    /// - Returns: 等到了为 true，轮数用完为 false
    private func wait(rounds: Int = 100, until condition: () -> Bool) async -> Bool {
        for _ in 0 ..< rounds {
            guard !condition() else { return true }

            try? await Task.sleep(for: .milliseconds(20))
        }

        return condition()
    }
}
