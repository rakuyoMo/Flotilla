import Foundation

// MARK: - FileIdentity

/// 一个路径上的文件在文件系统里的身份：所在设备的编号与 inode
///
/// 同一路径上的文件被换掉（拷贝同名文件夹时选了 “替换”、删掉后在原处新建同名的），身份就变了。
/// 每次都从 `stat` 现读，不用 `URL` 的资源值：资源值会被缓存，换掉之后仍可能给旧的
struct FileIdentity: Equatable {
    /// 所在设备的编号
    let device: dev_t

    /// 在这个设备上的 inode
    let inode: ino_t

    /// 读出路径上现在那个文件的身份；符号链接按它指向的文件读，与打开它监听时相同
    /// - Parameter path: 文件的路径
    /// - Returns: 路径上没有东西、读不到时为 nil
    init?(path: String) {
        var info = stat()

        guard stat(path, &info) == 0 else { return nil }

        device = info.st_dev
        inode = info.st_ino
    }
}
