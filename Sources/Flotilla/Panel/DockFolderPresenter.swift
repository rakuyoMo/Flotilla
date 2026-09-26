import Foundation
import os

// MARK: - DockFolderPresenter

/// 面板的展开、收起与切换，是 `flotilla://folder/<id>` URL 事件的最终接收者
@MainActor
final class DockFolderPresenter {
    /// App 唯一的面板调度者
    static let shared = DockFolderPresenter()

    /// 面板相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockFolderPresenter"
    )

    /// 切换根文件夹面板的展开状态
    /// - Parameter folderID: 被点击的 Dock tile 所对应的根文件夹
    func toggle(folderID: UUID) {
        #warning("TODO: 面板由 03 阶段实现")
        Self.logger.notice("收到切换请求：\(folderID.uuidString, privacy: .public)")
    }
}
