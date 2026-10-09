import Foundation

// MARK: - ExpectedDockTile

/// 一个根组的 tile 在 Dock 偏好里应有的样子：同步时算出，写入偏好后在 Dock 重启时据此核对
struct ExpectedDockTile {
    /// stub bundle 的当前位置
    let tileURL: URL

    /// tile 的名称，即组名
    let label: String

    /// tile 不在 Dock 上时是否添加；不添加时只在 tile 已在 Dock 上时更新它
    let canAdd: Bool
}
