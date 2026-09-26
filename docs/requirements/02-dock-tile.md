# 02 Dock tile

先读 [00 总览](00-overview.md)，并以 01 阶段合入后的代码为基线。本阶段交付需求 2 的 Dock 侧（文件夹图标出现在 Dock 上并随内容实时更新），以及点击 tile 到 Flotilla 收到 URL 的完整信号链路。

## stub 可执行文件

- 新增 SwiftPM executable target `FlotillaDockTile`（`Sources/FlotillaDockTile/main.swift`），不依赖 `Flotilla` target。
- 行为：读取 `Bundle.main.infoDictionary["FlotillaFolderID"]`，拼出 `flotilla://folder/<id>`，用 `NSWorkspace.shared.open(_:configuration:completionHandler:)` 打开，配置 `activates = false`；等到回调（最多 5 秒）后退出。缺少 id 或打开失败时记录日志并以非零状态退出。
- 不得激活任何 App：点击 tile 前的前台 App 必须保持前台。
- `Scripts/bundle.sh`：把 `FlotillaDockTile` 一并拷入 `Flotilla.app/Contents/MacOS/`，然后再签名。Flotilla 通过 `Bundle.main.url(forAuxiliaryExecutable: "FlotillaDockTile")` 找到它。

## stub bundle（`Sources/Flotilla/Dock/DockTileBundleBuilder.swift`）

- 位置：`~/Library/Application Support/Flotilla/DockTiles/<根文件夹 id>.app`
- 结构：
  - `Contents/Info.plist`
  - `Contents/MacOS/FlotillaDockTile`（从 Flotilla.app 拷贝）
  - `Contents/Resources/Icon.icns`
- `Info.plist` 键：`CFBundleExecutable = FlotillaDockTile`、`CFBundleIdentifier = com.rakuyo.flotilla.tile.<id>`、`CFBundleName` 与 `CFBundleDisplayName` = 文件夹名、`CFBundleIconFile = Icon`、`CFBundlePackageType = APPL`、`CFBundleInfoDictionaryVersion = 6.0`、`LSMinimumSystemVersion = 15.0`、`LSUIElement = true`、`LSBackgroundOnly = true`、`FlotillaFolderID = <id>`
- 每次生成或更新后执行 `/usr/bin/codesign --force --sign - <bundle>`。
- 签名后再用 `NSWorkspace.setIcon(_:forFile:)` 把 `Icon.icns` 设为 bundle 的自定义图标：macOS 26 起，系统把 icns 形式的 App 图标装进灰色圆角底板（macOS 27 实测如此），自定义图标不受影响。自定义图标文件 `Icon\r` 位于 bundle 根目录，`codesign` 会拒绝为这样的 bundle 签名，因此每次改写前先清除；缺少自定义图标的 stub 视为残缺，重新生成。
- API：`bundleURL(for folderID:)`、`write(folder:icon:)`、`remove(folderID:)`、`existingFolderIDs()`。
- 只在内容确有变化时重写文件（名称比对 plist，图标比对渲染结果）。

## `.icns` 写入（`Sources/Flotilla/Dock/IconFileWriter.swift`）

- `static func write(_ image: NSImage, to url: URL) throws`
- 输出 16、32、128、256、512 五档及各自 @2x，共 10 张 PNG，从 `FolderIconRenderer` 返回的图按目标像素尺寸栅格化，按 `icon_<边长>x<边长>[@2x].png` 命名放进临时 `.iconset` 目录。
- 用 `/usr/bin/iconutil -c icns` 把 `.iconset` 转成 `.icns`（`iconutil` 随 macOS 自带，不依赖 Xcode）。
- 单元测试：写到临时目录后能被 `NSImage(contentsOf:)` 读回，且包含多个尺寸的表示。

## Dock 偏好（`Sources/Flotilla/Dock/DockPreferences.swift`）

- 读写域 `com.apple.dock`（`UserDefaults(suiteName:)`），条目字段沿用 Dock 自己写出的结构。
- 备份：首次写入前把当前全部内容导出到 `~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`，最多保留 5 份。
- 放置区域：`persistent-apps`，即 Dock 左侧的 App 区域（`tile-type = file-tile`）；新 tile 追加在该区域末尾。
- 条目字段对照本机 Dock 已有 App 条目：`GUID`（随机 32 位正整数）、`tile-data.file-data._CFURLString`（stub 的 `file://` URL，以 `/` 结尾）、`tile-data.file-data._CFURLStringType = 15`、`tile-data.file-label` = 文件夹名、`tile-data.file-type`（对照实测取值）、`tile-type = file-tile`。不写 `book`，由 Dock 自行生成。
- API：`contains(tileURL:)`、`add(tileURL:label:)`、`remove(tileURL:)`、`updateLabel(tileURL:label:)`、`restartDock()`。
- 匹配 tile 只按标准化后的 URL，不按名称。
- 更新已有条目时原地替换，不删除再追加：Dock 里的排序是用户自己拖出来的，重启后必须保持。
- `restartDock()`：终止 `com.apple.dock` 进程，launchd 会自动拉起。

## 同步器（`Sources/Flotilla/Dock/DockTileSynchronizer.swift`）

- `start()` 在 `applicationDidFinishLaunching` 里调用：先做一次对账（每个根文件夹都有 stub 与 tile；多余的 stub 与 tile 删除），再订阅 `FolderStore.didChangeNotification` 与 `Preferences.didChangeNotification`。
- 变更后合并处理（防抖 0.5 秒）：
  1. 重新渲染每个根文件夹的图标，按需更新 stub 的 icns 与 plist
  2. tile 集合或名称有变化：改 Dock 偏好，然后 `restartDock()`
  3. 只有图标变化：实测 Dock 会不会自动刷新（先试 `touch` bundle 与重新签名）；不刷新就 `restartDock()`。结论写成一句注释
- 根文件夹被删除、或被拖成子文件夹：删掉 tile 与 stub；子文件夹被拖成根文件夹：新建 tile 与 stub。

## 信号链路验证

- 点击 tile：stub 被启动，Flotilla 收到 URL，`DockFolderPresenter.toggle` 的日志里出现对应 id。
- Flotilla 未运行时点击 tile：Flotilla 被拉起并收到 URL。
- 观察并记录：点击 tile 时 Dock 有没有弹跳动画、前台 App 有没有失去激活。若有，尝试 stub 的 `Info.plist` 键组合消除；无法消除时用 `#warning` 标记并汇报。

## 单元测试

- Dock 偏好条目构造（纯函数）
- stub 目录结构与 plist 内容（写到临时目录）
- `.icns` 写入

## 验收

- 新建根文件夹后 Dock 左侧的 App 区域出现 tile，图标含 App 预览；修改预览数量后图标更新；重命名后 tile 名更新；删除后 tile 消失
- 点击 tile 后 Flotilla 日志出现对应 id
- 前后导出 Dock 偏好比对，除 Flotilla 的 tile 外没有其它改动
- 测试用的文件夹与 tile 全部清理干净
