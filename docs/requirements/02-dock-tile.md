# 02 Dock tile

先读 [00 总览](00-overview.md)，并以 01 阶段合入后的代码为基线。本阶段交付需求 2 的 Dock 侧（文件夹图标出现在 Dock 上并随内容实时更新），以及点击 tile 到 Flotilla 收到 URL 的完整信号链路。

## stub 可执行文件

- 新增 SwiftPM executable target `FlotillaDockTile`（`Sources/FlotillaDockTile/`），不依赖 `Flotilla` target。
- 基于 `NSApplication` 运行（`DockTileAppDelegate`），仍是 `LSUIElement` + `LSBackgroundOnly` 的后台 App。
- 行为：读取 `Bundle.main.infoDictionary["FlotillaFolderID"]`，在 `applicationDidFinishLaunching` 里拼出 URL，用 `NSWorkspace.shared.open(_:configuration:completionHandler:)` 打开，配置 `activates = false`
  - 由点击 tile 启动：`flotilla://folder/<id>`
  - 由把 App 拖到 tile 上启动：AppKit 在 `applicationDidFinishLaunching` 之前经 `application(_:open:)` 送来被拖的项；收齐后打开 `flotilla://folder/<id>/apps?path=<路径>&path=<路径>`，每个被拖的项一个 `path` 查询项，取值为它的 POSIX 路径，由 `URLComponents` 编码
    - 实测（macOS 27，探针 stub）：回调顺序为 `applicationWillFinishLaunching` → `application(_:open:)` → `applicationDidFinishLaunching`，后两个在同一毫秒；一次拖放多个 App 时一次 `open` 送齐；`applicationDidFinishLaunching` 之后 1.5 秒内没有迟到的回调；由点击启动时没有 `open`，只有 `applicationShouldOpenUntitledFile`
  - 每次启动只发一个 URL；同一次拖放被系统重复送达时，由 Flotilla 侧 `FolderStore.addApps` 的去重吸收
  - 等到回调（最多 5 秒）后退出
  - 缺少 id 或打开失败时记录日志并以非零状态退出
- 不得激活任何 App：点击或拖放之前的前台 App 必须保持前台。
- `Scripts/bundle.sh`：把 `FlotillaDockTile` 一并拷入 `Flotilla.app/Contents/MacOS/`，然后再签名。
  - Flotilla 通过 `Bundle.main.url(forAuxiliaryExecutable: "FlotillaDockTile")` 找到它。

## stub bundle（`Sources/Flotilla/Dock/DockTileBundleBuilder.swift`）

- 位置：`~/Library/Application Support/Flotilla/DockTiles/<根文件夹 id>/<文件夹名>.app`
  - 实测 stub 启动后，Dock 会把 tile 的名称改成 Launch Services 的显示名，也就是 bundle 的文件名，并写回 Dock 偏好
    - bundle 文件名必须是文件夹名，tile 名称才不会被改掉
  - 每个根文件夹独占一个 `<id>` 目录，同名的根文件夹互不冲突
    - 文件夹名里的 `/` 在文件名里写成 `:`（Launch Services 显示时换回 `/`），名称为空时用 id 作文件名
  - 文件夹改名时 stub 在自己的目录里改名（移动而不是重建）
- 结构：
  - `Contents/Info.plist`
  - `Contents/MacOS/FlotillaDockTile`（从 Flotilla.app 拷贝）
  - `Contents/Resources/Icon.icns`
- `Info.plist` 键：
  - `CFBundleExecutable = FlotillaDockTile`
  - `CFBundleIdentifier = com.rakuyo.flotilla.tile.<id>`
  - `CFBundleName` 与 `CFBundleDisplayName` = 文件夹名
  - `CFBundleIconFile = Icon`
  - `CFBundlePackageType = APPL`
  - `CFBundleInfoDictionaryVersion = 6.0`
  - `LSMinimumSystemVersion = 15.0`
  - `LSUIElement = true`、`LSBackgroundOnly = true`
  - `FlotillaFolderID = <id>`
  - `CFBundleDocumentTypes`，只有一项：`CFBundleTypeName = Application`、`CFBundleTypeRole = Viewer`、`LSHandlerRank = Alternate`、`LSItemContentTypes = [com.apple.application, com.apple.application-bundle]`
    - 取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）：从访达把 App 拖到 tile 上时，tile 高亮为放置目标，松手后 Launch Services 以“打开文档”的方式启动 stub；`Alternate` 让 stub 不成为 App 的默认打开方式
    - 实测（macOS 27，带 `LSBackgroundOnly` 的探针 stub）：拖 App 悬停时 Dock 把 tile 压暗（亮度 229 → 104），松手后以 `odoc` 事件拉起 stub，不会把 App 加成新 tile；拖 `.txt` 时不高亮、不拉起 stub，文件滑回访达；访达的图标视图与列表视图结果一致
    - Dock 上的 tile 之间不能互相拖放：拖动 Dock 图标时整个过程由 Dock 接管，只能排序或拖出
- 每次生成或更新后执行 `/usr/bin/codesign --force --sign - <bundle>`。
- 签名后再用 `NSWorkspace.setIcon(_:forFile:)` 把 `Icon.icns` 设为 bundle 的自定义图标：macOS 26 起，系统把 icns 形式的 App 图标装进灰色圆角底板（macOS 27 实测如此），自定义图标不受影响。
  - 自定义图标文件 `Icon\r` 位于 bundle 根目录，`codesign` 会拒绝为这样的 bundle 签名，因此每次改写前先清除
  - 缺少自定义图标的 stub 视为残缺，重新生成
- 设好自定义图标后执行 `lsregister -f <bundle>`（`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`），让 Launch Services 按改写后的 Info.plist 登记 stub 能打开的文档类型。
  - 实测（macOS 27，`LSCanURLAcceptURL`）：已被 Launch Services 记录过的 stub 改写 Info.plist 后不重新注册，仍按旧记录判断；重新注册后能接收 App，不接收其它文件
- API：`bundleURL(for folder:)`、`folderDirectory(for folderID:)`（stub 独占的 `<id>` 目录）、`existingBundleURL(for folderID:)`、`folderID(forBundleURL:)`、`write(folder:icon:)`、`remove(folderID:)`（先 `lsregister -u` 注销，再连同 `<id>` 目录一起删除）、`existingFolderIDs()`。
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
- 条目字段对照本机 Dock 已有 App 条目：
  - `GUID`（随机 32 位正整数）
  - `tile-data.file-data._CFURLString`（stub 的 `file://` URL，以 `/` 结尾）
  - `tile-data.file-data._CFURLStringType = 15`
  - `tile-data.file-label` = 文件夹名
  - `tile-data.file-type`（对照实测取值）
  - `tile-type = file-tile`
  - 不写 `book`，由 Dock 自行生成
- API：`contains(tileURL:)`、`folderIDs(ofTilesIn:)`（stub 位于给定目录下 `<id>` 子目录的 tile 所属的根文件夹 id）、`add(tileURL:label:)`、`remove(tileDirectory:)`、`update(tileURL:label:isStubRewritten:)`、`restartDock()`。
- 匹配 tile 按标准化后 URL 的所在目录（即 stub 独占的 `<id>` 目录），不按名称：文件夹改名后 stub 的文件名变了，仍要找到原来的 tile。
- 更新已有条目时原地替换，不删除再追加：Dock 里的排序是用户自己拖出来的，重启后必须保持。
  - stub 改名后 `_CFURLString` 换成新位置，并删掉 Dock 按旧位置生成的 `book`，由 Dock 重启后重新生成。
  - stub 改写过时换一个新的 `GUID`：实测（macOS 27）Dock 按 `GUID` 缓存 tile 图标，`GUID` 不变时重启后仍显示旧图标。
- `restartDock()`：终止 `com.apple.dock` 进程，launchd 会自动拉起。

## 同步器（`Sources/Flotilla/Dock/DockTileSynchronizer.swift`）

- `start()` 在 `applicationWillFinishLaunching` 里调用：被 stub 拉起时，URL 事件先于 `applicationDidFinishLaunching` 送达，面板与同步器要在此之前就绪
  - 先做一次对账：每个根文件夹都有 stub，tile 按“添加 tile 的条件”添加；多余的 stub 与 tile 删除
    - tile 按 stub 独占的 `<id>` 目录匹配，stub bundle 已被用户删掉时同样删除条目
    - 多余的 tile 也包括 Dock 偏好里指向 `DockTiles/` 下、目录已不存在的条目
  - 再订阅 `FolderStore.didChangeNotification` 与 `Preferences.didChangeNotification`，并用 KVO 观察 `NSApp.effectiveAppearance`
- 变更后合并处理（防抖 0.5 秒；Dock 重启后的静默期见下）：
  1. 重新渲染每个根文件夹的图标，底板按 `NSApp.effectiveAppearance` 取深浅（见 01），按需更新 stub 的 icns 与 plist
  2. tile 集合或名称有变化：改 Dock 偏好，然后 `restartDock()`
  3. 只有图标变化：实测（macOS 27）Dock 不会自动刷新，`touch` bundle、重新注册 Launch Services、替换自定义图标都无效，因此 tile 换新的 `GUID` 后同样 `restartDock()`
- Dock 重启后的静默期（同步时机的纯逻辑在 `DockSynchronizationSchedule`）：
  - 实测（macOS 27）重启后的 Dock 会把启动时读到的偏好写回一次（`mod-count` 加一），在重启后 4.1–4.2 秒（多次实测），或在此之前被终止时；在这次写回之前写入的改动会被覆盖，随后重启的 Dock 读到的仍是旧条目
    - 终止 Dock 后 10–60 ms 新 Dock 即被拉起；并非每次重启都会写回
  - `restartDock()` 之后 8 秒内不写 Dock 偏好：同步时刻取“变更后 0.5 秒”与“最近一次重启后 8 秒”中较晚的一个，静默期内的变更合并成一次同步
  - 同步重启了 Dock 时，静默期结束再复查一次：重新读取 Dock 偏好对账，把被写回覆盖的改动重新写上；没有差异时不改偏好、不重启 Dock
    - 复查通常也是刚添加的 tile 第一次被“看到”的时机：tile 在 Dock 上就不再待添加，被写回盖掉就再加一次（见下）
    - 复查本身重启了 Dock 时不再安排复查，Dock 写回的条目与写入的始终不一致时也不会被反复重启
- 根文件夹被删除、或被拖成子文件夹：删掉 tile 与 stub；子文件夹被拖成根文件夹：新建 tile 与 stub。
- 添加 tile 的条件（需求 10，纯逻辑在 `DockTileAdditionTracker`）：
  - 用户可以像其它 App 一样把 tile 拖出 Dock，拖出后不再自动加回；tile 不在 Dock 上的根文件夹照常生成与更新 stub，只是不动 Dock 偏好，重新添加时直接引用
  - 只在两种情况下向 Dock 添加 tile：根文件夹是新出现的（上一次同步时还不是根文件夹），或用户在设置窗口点了“添加到 Dock”
    - 同步器创建时的根文件夹都视为已同步过：Flotilla 没运行时不会有新的根文件夹出现，此时缺少 tile 的根文件夹都是被用户拖出去的
  - 添加过 tile 的根文件夹，在同步看到 tile 确实在 Dock 上之前一直待添加；tile 在 Dock 上出现过、之后又不在了，才是被用户拖出去的
    - 待添加的根文件夹被删除或被拖成子文件夹时不再添加
- 查询与请求：`rootFolderIDsRemovedFromDock()` 给出被用户拖出 Dock 的根文件夹（tile 不在 Dock 上、下一次同步也不会添加；Dock 上现有的 tile 取 `DockPreferences.folderIDs(ofTilesIn:)` 对 stub 目录的结果）；`addTile(for:)` 把根文件夹记为待添加并安排一次同步。
- 每次同步结束后发出 `DockTileSynchronizer.didSynchronizeNotification`（`object` 为同步器），设置窗口据此刷新 tile 的状态。
- 系统切换深浅外观：Flotilla 没有固定外观，渲染 stub 图标时读取的 `NSApp.effectiveAppearance` 随系统变化，触发一次同步；底板颜色变了，stub 被改写、tile 换新的 `GUID`，Dock 因此重启一次（Dock 按 `GUID` 缓存 tile 图标，见上文）。

## 信号链路验证

- 点击 tile：stub 被启动，Flotilla 收到 URL，`DockFolderPresenter` 收到对应 id。
- Flotilla 未运行时点击 tile：Flotilla 被拉起并收到 URL。
- 从访达把 App 拖到 tile 上：tile 高亮，stub 以打开文档的方式被启动，Flotilla 收到 `flotilla://folder/<id>/apps?path=…`，由 `DockTileRequest` 解析，只保留 App bundle（`AppReference.isApplicationBundle`）后加入该根文件夹；整个过程不激活 Flotilla，前台 App 保持前台。
- 实测（macOS 27，tile 在左侧 App 区域）：点击 tile 时 Dock 不弹跳、不显示运行指示灯，前台 App 保持前台；图标按渲染结果原样显示，系统没有另套灰色底板。

## 单元测试

- Dock 偏好条目构造（纯函数）
- stub 目录结构与 plist 内容（写到临时目录）
- `.icns` 写入
- 同步时机：防抖、Dock 重启后的静默期与复查（纯逻辑）

## 验收

- 新建根文件夹后 Dock 左侧的 App 区域出现 tile，图标含 App 预览；修改预览数量后图标更新；重命名后 tile 名更新；删除后 tile 消失
- 点击 tile 后 `DockFolderPresenter` 收到对应 id
- 前后导出 Dock 偏好比对，除 Flotilla 的 tile 外没有其它改动
- 测试用的文件夹与 tile 全部清理干净
