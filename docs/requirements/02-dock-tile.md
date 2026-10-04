# 02 Dock tile

先读 [00 总览](00-overview.md)，并以 01 阶段合入后的代码为基线。本阶段交付需求 2 的 Dock 侧（文件夹图标出现在 Dock 上并随内容实时更新），以及点击 tile 到 Flotilla 收到 URL 的完整信号链路。

## stub 可执行文件

- 新增 SwiftPM executable target `FlotillaDockTile`（`Sources/FlotillaDockTile/`），不依赖 `Flotilla` target。
- 基于 `NSApplication` 运行（`DockTileAppDelegate`），仍是 `LSUIElement` + `LSBackgroundOnly` 的后台 App。
- 行为：读取 `Bundle.main.infoDictionary["FlotillaFolderID"]`，在 `applicationDidFinishLaunching` 里拼出 URL，用 `NSWorkspace.shared.open(_:configuration:completionHandler:)` 打开，配置 `activates = false`
  - 由点击 tile 启动：`flotilla://folder/<id>`
  - 由把 App 或文件拖到 tile 上启动：AppKit 在 `applicationDidFinishLaunching` 之前经 `application(_:open:)` 送来被拖的项；收齐后打开 `flotilla://folder/<id>/items?path=<路径>&path=<路径>`，每个被拖的项一个 `path` 查询项，取值为它的 POSIX 路径，由 `URLComponents` 编码
    - 实测（macOS 27，探针 stub）：
      - 回调顺序为 `applicationWillFinishLaunching` → `application(_:open:)` → `applicationDidFinishLaunching`，后两个在同一毫秒
      - 一次拖放多个 App 时一次 `open` 送齐
      - `applicationDidFinishLaunching` 之后 1.5 秒内没有迟到的回调
      - 由点击启动时没有 `open`，只有 `applicationShouldOpenUntitledFile`
    - 实测（macOS 27，探针 stub）：拖放以 `aevt/odoc` 事件送达，收到的都是文件 URL，文件包、App 与文件夹的以 `/` 结尾
  - 每次启动只发一个 URL；同一次拖放被系统重复送达时，由 Flotilla 侧 `FolderStore.addItems` 的去重吸收
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
  - `CFBundleDocumentTypes`，两项：
    - App：`CFBundleTypeName = Application`、`CFBundleTypeRole = Viewer`、`LSHandlerRank = Alternate`、`LSItemContentTypes = [com.apple.application, com.apple.application-bundle]`
      - 取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）：从访达把 App 拖到 tile 上时，tile 高亮为放置目标，松手后 Launch Services 以“打开文档”的方式启动 stub；`Alternate` 让 stub 不成为 App 的默认打开方式
      - 实测（macOS 27，带 `LSBackgroundOnly` 的探针 stub）：拖 App 悬停时 Dock 把 tile 压暗（亮度 229 → 104），松手后以 `odoc` 事件拉起 stub，不会把 App 加成新 tile；访达的图标视图与列表视图结果一致
    - 文件（需求 14，见 06）：`CFBundleTypeName = File`、`CFBundleTypeRole = Viewer`、`LSHandlerRank = None`、`LSItemContentTypes = [public.data, com.apple.package]`
      - `LSHandlerRank` 必须是 `None`：实测（macOS 27）`Alternate` 会让 stub 出现在访达的“打开方式”里
      - 实测（macOS 27）：从访达拖 `.txt`、`.pdf`、`.rtfd`、`.webloc` 与未知扩展名的文件，tile 压暗为放置目标，松手后以 `odoc` 拉起 stub；stub 不出现在“打开方式”里，各类文件的默认打开 App 不变
      - 实测（macOS 27）：声明了 `public.data` 或 `com.apple.package`，Dock 对访达里的文件夹也高亮并拉起 stub，它作为文件加入（见 07）
    - Dock 只在 stub 提供服务（`NSServices`）时接收网址的拖放，那会在“系统设置 › 键盘 › 键盘快捷键 › 服务”里给每个根文件夹加一项
    - Dock 上的 tile 之间不能互相拖放：拖动 Dock 图标时整个过程由 Dock 接管，只能排序或拖出
- 每次生成或更新后执行 `/usr/bin/codesign --force --sign - <bundle>`。
- 签名后再用 `NSWorkspace.setIcon(_:forFile:)` 把 `Icon.icns` 设为 bundle 的自定义图标：macOS 26 起，系统把 icns 形式的 App 图标装进灰色圆角底板（macOS 27 实测如此），自定义图标不受影响。
  - 自定义图标文件 `Icon\r` 位于 bundle 根目录，`codesign` 会拒绝为这样的 bundle 签名，因此每次改写前先清除
  - 缺少自定义图标的 stub 视为残缺，重新生成
- 设好自定义图标后执行 `lsregister -f <bundle>`（`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`），让 Launch Services 按改写后的 Info.plist 登记 stub 能打开的文档类型。
  - 实测（macOS 27，`LSCanURLAcceptURL`）：已被 Launch Services 记录过的 stub 改写 Info.plist 后不重新注册，仍按旧记录判断；重新注册后能接收 App，不接收其它文件
- API：
  - `bundleURL(for folder:)`
  - `folderDirectory(for folderID:)`（stub 独占的 `<id>` 目录）
  - `existingBundleURL(for folderID:)`
  - `folderID(forBundleURL:)`
  - `write(folder:icon:)`
  - `remove(folderID:)`（先 `lsregister -u` 注销，再连同 `<id>` 目录一起删除）
  - `existingFolderIDs()`
- 只在内容确有变化时重写文件：Info.plist 与图标都与按当前文件夹新生成的结果逐字节比对。

## `.icns` 写入（`Sources/Flotilla/Dock/IconFileWriter.swift`）

- `static func write(_ image: NSImage, to url: URL) throws`
- 输出 16、32、128、256、512 五档及各自 @2x，共 10 张 PNG，从 `FolderIconRenderer` 返回的图按目标像素尺寸栅格化，按 `icon_<边长>x<边长>[@2x].png` 命名放进临时 `.iconset` 目录。
- 用 `/usr/bin/iconutil -c icns` 把 `.iconset` 转成 `.icns`（`iconutil` 随 macOS 自带，不依赖 Xcode）。
- 单元测试：写到临时目录后能被 `NSImage(contentsOf:)` 读回，且包含多个尺寸的表示。

## Dock 偏好（`Sources/Flotilla/Dock/DockPreferences.swift`）

- 读写域 `com.apple.dock`（`UserDefaults` 的子类 `DockDefaults`，见 `observeTiles(_:)`），条目字段沿用 Dock 自己写出的结构。
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
- API：
  - `contains(tileURL:)`
  - `folderIDs(ofTilesIn:)`（stub 位于给定目录下 `<id>` 子目录的 tile 所属的根文件夹 id）
  - `add(tileURL:label:)`
  - `remove(tileDirectory:)`
  - `update(tileURL:label:isStubRewritten:)`
  - `apply(_:rewrittenTileURLs:removingTilesIn:)`
  - `observeTiles(_:)`
  - `restartDock(terminationHandler:)`
  - `relaunchedDockLaunchDate()`
  - `isReadByRelaunchedDock(writtenAt:dockLaunchedAt:)`
- 每次写入后调用 `synchronize()`，等写入交给 cfprefsd 之后再返回：重启 Dock 之后的补写要据此判断是否赶在新 Dock 读取之前。
- 匹配 tile 按标准化后 URL 的所在目录（即 stub 独占的 `<id>` 目录），不按名称：文件夹改名后 stub 的文件名变了，仍要找到原来的 tile。
- 更新已有条目时原地替换，不删除再追加：Dock 里的排序是用户自己拖出来的，重启后必须保持。
  - stub 改名后 `_CFURLString` 换成新位置，并删掉 Dock 按旧位置生成的 `book`，由 Dock 重启后重新生成。
  - stub 改写过时换一个新的 `GUID`：实测（macOS 27）Dock 按 `GUID` 缓存 tile 图标，`GUID` 不变时重启后仍显示旧图标。
  - 条目的 `GUID` 不是本次运行写入的值时同样换新：实测（macOS 27）Dock 被终止时若带着未写的状态（例如松手约 2 秒内刚接受过一次拖放），会在终止时把启动时读到的旧条目写回，盖掉刚换上的 `GUID`，重启后的 Dock 仍显示旧图标；旧 Dock 退出后的核对据此再换一个新的 `GUID`（见“Dock 重启后的核对”）。
- `apply(_:rewrittenTileURLs:removingTilesIn:)`：让 Flotilla 的 tile 与一份期望状态一致，返回是否改动了偏好；同步时的第一次写入与旧 Dock 退出后的核对共用这一步
  - 期望状态是每个根文件夹一个 `ExpectedDockTile`：stub 的位置、tile 的名称、tile 不在 Dock 上时能否添加
  - 已在 Dock 上的按 `update` 原地更新，`rewrittenTileURLs` 里的 stub 刚被改写，换新的 `GUID`；不在 Dock 上且能添加的按 `add` 追加；`removingTilesIn` 给出的 stub 目录按 `remove` 删除
- `observeTiles(_:)`：`persistent-apps` 变化时在主线程回调，Dock 自己的写入与 Flotilla 的写入都会通知
  - 读写偏好用 `UserDefaults` 的子类 `DockDefaults`：键名带连字符，写不成 KeyPath，借 KVO 的依赖键（`keyPathsForValuesAffectingTiles`）让属性 `tiles` 随 `persistent-apps` 一起通知
  - 实测（macOS 27）以域名创建的 `UserDefaults(suiteName:)` 能收到其它进程写入的 KVO 通知，写入后随即送达；偏好文件要等 cfprefsd 落盘，Dock 自己的写入有时晚 5 秒以上才出现在 `com.apple.dock.plist` 里，监听文件赶不上
- `restartDock(terminationHandler:)`：终止本用户的 Dock 进程，launchd 会自动拉起；被终止的 Dock 全部退出后在主线程调用 `terminationHandler`，没有在运行的 Dock 时立即调用。
  - Dock 进程按进程名在内核里找（`proc_listpids` + `proc_pidinfo` 的 `PROC_PIDTBSDINFO`），退出用 kqueue（`DispatchSource.makeProcessSource`，`.exit`）监听，终止之前就开始监听
  - 不用 `NSRunningApplication`：
    - 核对不通过时要终止的是刚拉起的新 Dock，实测（macOS 27）它启动约 45 ms（37–66 ms，23 次）后才出现在 `NSRunningApplication` 里，`launchDate` 为空
    - `isTerminated` 的 KVO 也比 kqueue 的退出事件晚 1–16 ms（中位 3.7 ms）
    - NSWorkspace 不为 LSUIElement 的 Dock 发 `didTerminateApplicationNotification`
  - Dock 终止时若把旧条目写回，退出时已经落地（实测退出事件到达时读到的偏好已是写回之后的内容）
- `relaunchedDockLaunchDate()`：最近一次重启后新拉起的 Dock 的内核启动时刻，排除被终止的进程与僵尸进程；新 Dock 还没启动时为 nil
  - 实测（macOS 27）：旧 Dock 的退出事件之后 0.4 ms 之内新进程就被创建（23 次）；它先以 xpcproxy 运行，约 7–10 ms 后才 exec 成 Dock（3 次），在此之前按进程名找不到它，它也还没开始执行 Dock 的代码
- `isReadByRelaunchedDock(writtenAt:dockLaunchedAt:)`：重启 Dock 之后的补写是否一定会被新 Dock 读到：补写完成时新 Dock 还没启动，或补写完成得早于新 Dock 启动后 `relaunchReadDelay`
  - 实测（macOS 27，23 次，在新 Dock 启动后不同时刻改测试 tile 的名称，看它显示哪个）：新 Dock 在启动后约 70–85 ms 读取 `persistent-apps`，70 ms 之前写完的改动都被读到，73 ms 起开始有读不到的；`relaunchReadDelay` 取 30 ms

## 同步器（`Sources/Flotilla/Dock/DockTileSynchronizer.swift`）

- `start()` 在 `applicationWillFinishLaunching` 里调用：被 stub 拉起时，URL 事件先于 `applicationDidFinishLaunching` 送达，面板与同步器要在此之前就绪
  - 先做一次对账：每个根文件夹都有 stub，tile 按“添加 tile 的条件”添加；多余的 stub 与 tile 删除
    - tile 按 stub 独占的 `<id>` 目录匹配，stub bundle 已被用户删掉时同样删除条目
    - 多余的 tile 也包括 Dock 偏好里指向 `DockTiles/` 下、目录已不存在的条目
  - 再订阅 `FolderStore.didChangeNotification` 与 `Preferences.didChangeNotification`，用 KVO 观察 `NSApp.effectiveAppearance`，并用 `DockPreferences.observeTiles(_:)` 观察 Dock 偏好里的 tile
- 变更后合并处理（防抖 0.5 秒）：
  1. 重新渲染每个根文件夹的图标，底板按 `NSApp.effectiveAppearance` 取深浅（见 01），按需更新 stub 的 icns 与 plist
  2. 把各根文件夹 tile 的期望状态写进 Dock 偏好（`apply`）：tile 集合或名称有变化，或 stub 被改写过（条目换新的 `GUID`）
  3. 偏好有改动就重启 Dock，每次同步只重启一次；只有图标变化时，实测（macOS 27）Dock 不会自动刷新，`touch` bundle、重新注册 Launch Services、替换自定义图标都无效，因此同样靠新的 `GUID` 加重启
- Dock 重启后的核对：
  - 实测（macOS 27）：
    - 新 Dock 只在启动时读取偏好：旧 Dock 退出后立即被拉起，启动后约 70–85 ms 读取 `persistent-apps`
    - 被终止的 Dock 若带着未写的状态，会在终止时把启动时读到的条目写回，盖掉 Flotilla 在它运行期间写入的改动：刚接受过拖放、刚在 Dock 里拖动过 tile，或新增 tile 后启动还不到 4.1 秒、还没把补全字段的条目写回时
    - 新增 tile 后重启的 Dock 在启动后 4.1–4.2 秒把补全字段的条目写回一次（多次实测）；删除、改名、只换 `GUID` 后重启的 Dock 没有观察到写回
  - 旧 Dock 退出后（`restartDock` 的回调）按本次同步的同一份期望再 `apply` 一次，不再算 stub 改写：终止时的写回丢掉的条目补回、回退的名称与位置改回、被盖掉的 `GUID` 换新
  - 有补写时，补写完成得早于新 Dock 启动后 `relaunchReadDelay`（`isReadByRelaunchedDock`）才算新 Dock 读到了；否则再重启一次 Dock，回到上一步。一次同步最多重启 3 次 Dock，超过就记日志放弃：偏好里已是期望状态，Dock 下一次重启时读到
    - 实测（macOS 27）7 次终止写回（拖放 3 次、拖放同时加回 tile 2 次、新增 tile 后 4 秒内改名 2 次），补写都在第一次重启里完成，守卫通过，新 Dock 显示的名称与图标都是补写的
    - 再重启时被终止的新 Dock 只活了几十毫秒，实测（1 次）launchd 约 1 秒后才拉起下一个 Dock
  - 没有补写时不必判断：新 Dock 读到的要么是第一次写入的内容，要么是与期望一致的写回
  - 新 Dock 读到期望状态后才算同步结束：确认待添加的 tile（见下），删掉多余的 stub，发出 `didSynchronizeNotification`
  - 每次变更只重启一次 Dock；只有赶上终止写回、补写又晚于新 Dock 读取时才多重启
- 根文件夹被删除、或被拖成子文件夹：删掉 tile 与 stub；子文件夹被拖成根文件夹：新建 tile 与 stub。
- 添加 tile 的条件（需求 10，纯逻辑在 `DockTileAdditionTracker`）：
  - 用户可以像其它 App 一样把 tile 拖出 Dock，拖出后不再自动加回；tile 不在 Dock 上的根文件夹照常生成与更新 stub，只是不动 Dock 偏好，重新添加时直接引用
  - 只在两种情况下向 Dock 添加 tile：根文件夹是新出现的（上一次同步时还不是根文件夹），或用户在设置窗口点了“添加到 Dock”
    - 同步器创建时的根文件夹都视为已同步过：Flotilla 没运行时不会有新的根文件夹出现，此时缺少 tile 的根文件夹都是被用户拖出去的
  - 添加过 tile 的根文件夹先待添加，直到确认 tile 已经加上：核对通过时新 Dock 读到的偏好里有它，或某次同步看到 tile 在 Dock 上
    - 核对放弃时仍待添加，之后的同步再加
    - 确认加上之后 tile 不在 Dock 上，就是被用户拖出去的；tile 出现后立即拖出也一样，不加回
    - 待添加的根文件夹被删除或被拖成子文件夹时不再添加
  - 设置窗口里新建的根文件夹在输入名称期间搁置：不添加 tile，也不算被拖出；名称编辑结束后解除搁置并同步一次，tile 带着最终名称出现，Dock 只重启一次（见 05）
- 查询与请求：
  - `rootFolderIDsRemovedFromDock()` 给出被用户拖出 Dock 的根文件夹（tile 不在 Dock 上、下一次同步也不会添加；Dock 上现有的 tile 取 `DockPreferences.folderIDs(ofTilesIn:)` 对 stub 目录的结果）
  - `addTile(for:)` 把根文件夹记为待添加并安排一次同步
  - `holdTile(for:)`、`releaseTile(for:)` 搁置与解除搁置新建的根文件夹
- 每次同步结束后发出 `DockTileSynchronizer.didSynchronizeNotification`（`object` 为同步器），设置窗口据此刷新 tile 的状态。
- Dock 偏好里的 tile 变化时发出 `DockTileSynchronizer.dockTilesDidChangeNotification`（`object` 为同步器），不触发同步：用户把 tile 拖出 Dock 后，实测 Dock 约 4.1 秒才把删除写进偏好，设置窗口据此立即刷新状态。
- 系统切换深浅外观：Flotilla 没有固定外观，渲染 stub 图标时读取的 `NSApp.effectiveAppearance` 随系统变化，触发一次同步；底板颜色变了，stub 被改写、tile 换新的 `GUID`，每次切换 Dock 重启一次（Dock 按 `GUID` 缓存 tile 图标，见上文）。

## 信号链路验证

- 点击 tile：stub 被启动，Flotilla 收到 URL，`DockFolderPresenter` 收到对应 id。
- Flotilla 未运行时点击 tile：Flotilla 被拉起并收到 URL。
- 从访达把 App 或文件拖到 tile 上：tile 高亮，stub 以打开文档的方式被启动，Flotilla 收到 `flotilla://folder/<id>/items?path=…`，由 `DockTileRequest` 解析，经 `FolderItem(url:title:)` 分类后加入该根文件夹，访达里的文件夹同样加入（见 07）；整个过程不激活 Flotilla，前台 App 保持前台。
- 实测（macOS 27，tile 在左侧 App 区域）：点击 tile 时 Dock 不弹跳、不显示运行指示灯，前台 App 保持前台；图标按渲染结果原样显示，系统没有另套灰色底板。

## 单元测试

- Dock 偏好条目构造（纯函数）
- stub 目录结构与 plist 内容（写到临时目录）
- `.icns` 写入
- Dock 重启后的核对：按同一份期望补写被终止写回盖掉的条目，没有写回时不补写；补写是否赶在新 Dock 读取之前（纯逻辑）

## 验收

- 新建根文件夹后 Dock 左侧的 App 区域出现 tile，图标含 App 预览；修改预览数量后图标更新；重命名后 tile 名更新；删除后 tile 消失
- 点击 tile 后 `DockFolderPresenter` 收到对应 id
- 前后导出 Dock 偏好比对，除 Flotilla 的 tile 外没有其它改动
- 测试用的文件夹与 tile 全部清理干净
