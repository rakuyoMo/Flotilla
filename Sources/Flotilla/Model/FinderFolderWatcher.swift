import Foundation

// MARK: - FinderFolderWatcher

/// 监听一个访达文件夹的属性变化（kqueue 的 `.attrib`）：标签、emoji 与符号都写在它的扩展属性里，改了就收到
///
/// 释放即停止监听，描述符随之关掉。同一卷内改名后旧的描述符照样收到事件；
/// `.attrib` 也会因权限、时间戳等其它属性的变化而来，收到后要重新读外观才知道变没变
final class FinderFolderWatcher {
    /// 文件夹的 kqueue 事件源，在主队列上回调
    private let source: any DispatchSourceFileSystemObject

    /// 打开文件夹并开始监听
    /// - Parameters:
    ///   - path: 文件夹的路径
    ///   - handler: 文件夹的属性变化时在主线程执行；改一次标签可能连着来几次
    /// - Returns: 文件夹打不开（已删除、没有权限）时为 nil
    init?(path: String, handler: @escaping @MainActor () -> Void) {
        // 只为收事件打开，不占着卷，卷照常可以推出
        let descriptor = open(path, O_EVTONLY)

        guard descriptor >= 0 else { return nil }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .attrib,
            queue: .main
        )

        // 事件源建在主队列上，回调就在主线程
        source.setEventHandler {
            MainActor.assumeIsolated {
                handler()
            }
        }

        // 取消后才关描述符：事件源取消之前一直用着它
        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
    }

    /// 停止监听，关掉描述符
    deinit {
        source.cancel()
    }
}
