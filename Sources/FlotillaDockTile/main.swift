import AppKit
import os

// Dock tile 的 stub：被 Dock 启动后，以不激活任何 App 的方式打开 `flotilla://folder/<id>`，随即退出

/// stub 的日志
let logger = Logger(subsystem: "com.rakuyo.flotilla", category: "DockTile")

/// 等待打开结果的最长时间（秒）
let openTimeout: TimeInterval = 5

// 根文件夹 id 由 Flotilla 生成 stub 时写进 Info.plist
guard
    let folderID = Bundle.main.infoDictionary?["FlotillaFolderID"] as? String,
    let url = URL(string: "flotilla://folder/\(folderID)")
else {
    logger.error("Info.plist 缺少有效的 FlotillaFolderID")
    exit(EXIT_FAILURE)
}

/// 打开 URL 的配置：不激活 URL 的处理者，点击 tile 前的前台 App 保持前台
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false

NSWorkspace.shared.open(url, configuration: configuration) { _, error in
    guard let error else {
        exit(EXIT_SUCCESS)
    }

    logger.error("打开 \(url.absoluteString, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)")
    exit(EXIT_FAILURE)
}

// 回调迟迟不来时按失败退出，stub 不能常驻
DispatchQueue.main.asyncAfter(deadline: .now() + openTimeout) {
    logger.error("等待打开 \(url.absoluteString, privacy: .public) 超时")
    exit(EXIT_FAILURE)
}

dispatchMain()
