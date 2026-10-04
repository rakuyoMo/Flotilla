import Foundation

// MARK: - DockTileError

/// 生成 Dock tile 的 stub 与图标时的错误
enum DockTileError: Error {
    /// 无法把图标栅格化成指定像素边长的 PNG
    case rasterizationFailed(pixelSide: Int)

    /// 外部命令以非零状态退出：命令路径、退出状态与它写到标准错误的内容
    case commandFailed(path: String, status: Int32, message: String)

    /// 无法为 stub 设置自定义图标
    case customIconFailed(path: String)
}

// MARK: LocalizedError

extension DockTileError: LocalizedError {
    /// 写进日志的错误描述
    var errorDescription: String? {
        switch self {
        case .rasterizationFailed(let pixelSide):
            "无法把图标栅格化为 \(pixelSide)×\(pixelSide) 像素的 PNG"

        case .commandFailed(let path, let status, let message):
            "\(path) 以状态 \(status) 退出：\(message)"

        case .customIconFailed(let path):
            "无法为 \(path) 设置自定义图标"
        }
    }
}
