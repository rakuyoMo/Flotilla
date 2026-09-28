import Foundation

// MARK: - PreferencesFileMonitor

/// 监听一个偏好文件被改写，包括其它进程的写入
///
/// cfprefsd 以替换文件的方式写入，替换后原文件的描述符不再收到事件；因此观察所在目录的写事件，
/// 再比对文件的 inode 与修改时间。实测（macOS 27）其它进程写入偏好后，cfprefsd 在写入返回之前就替换了偏好文件
@MainActor
final class PreferencesFileMonitor {
    /// 被监听的偏好文件
    private let fileURL: URL

    /// 所在目录的写事件源
    private let source: DispatchSourceFileSystemObject

    /// 文件最近一次的 inode 与修改时间；文件不存在时为 nil
    private var lastSignature: [Int]? = nil

    /// 开始监听；打不开所在目录时返回 nil
    /// - Parameters:
    ///   - fileURL: 被监听的偏好文件
    ///   - handler: 文件被改写后在主线程调用
    init?(fileURL: URL, handler: @escaping @MainActor () -> Void) {
        let descriptor = open(
            fileURL.deletingLastPathComponent().path(percentEncoded: false),
            O_EVTONLY
        )

        guard descriptor >= 0 else { return nil }

        self.fileURL = fileURL

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )

        lastSignature = Self.signature(of: fileURL)

        // 目录里任何文件被替换都会触发，只在这个文件变了时通知
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                let signature = Self.signature(of: fileURL)
                guard signature != self.lastSignature else { return }

                self.lastSignature = signature
                handler()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
    }

    /// 停止监听
    deinit {
        source.cancel()
    }

    /// 文件的 inode 与修改时间，用来判断它是否被改写；文件不存在时为 nil
    private static func signature(of fileURL: URL) -> [Int]? {
        var info = stat()
        guard stat(fileURL.path(percentEncoded: false), &info) == 0 else { return nil }

        return [
            Int(info.st_ino),
            info.st_mtimespec.tv_sec,
            info.st_mtimespec.tv_nsec,
        ]
    }
}
