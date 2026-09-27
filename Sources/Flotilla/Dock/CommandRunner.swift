import Foundation

// MARK: - CommandRunner

/// 同步运行系统自带的命令行工具（`iconutil`、`codesign`、`lsregister`）
enum CommandRunner {
    /// 运行命令并等待其退出
    /// - Parameters:
    ///   - executablePath: 命令的绝对路径
    ///   - arguments: 命令参数
    /// - Throws: 命令无法启动时抛出启动错误；以非零状态退出时抛出 `DockTileError.commandFailed`，附带标准错误的内容
    static func run(_ executablePath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: executablePath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()

        // 先读完标准错误再等待退出：输出塞满管道缓冲区时，子进程会阻塞在写入上而永远不退出
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw DockTileError.commandFailed(
                path: executablePath,
                status: process.terminationStatus,
                message: String(decoding: errorData, as: UTF8.self)
            )
        }
    }
}
