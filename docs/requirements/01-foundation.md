# 01 基础骨架与设置

先读 [00 总览](00-overview.md)。本阶段交付 App 骨架、数据模型与持久化、设置窗口、状态栏、文件夹图标渲染器，以及 URL 事件入口。Dock tile（02）与面板（03）不在本阶段。

## App 骨架

### 入口与 Info.plist

- `FlotillaApp.main()`：创建 `NSApplication.shared`，挂上 `AppDelegate`，`run()`。
- `Sources/Flotilla/Info.plist` 新增：
  - `LSUIElement = true`：Flotilla 没有 Dock 图标（需求 6）
  - `CFBundleURLTypes`：注册 scheme `flotilla`，`CFBundleURLName = com.rakuyo.flotilla.url`
  - `CFBundleAllowMixedLocalizations = true`：让 App 显示名等来自其它 bundle 的文字按系统语言本地化，不受 Flotilla 自身支持的语言限制
  - `CFBundleDevelopmentRegion = en`：系统语言不在 Flotilla 支持的语言之内时，界面文字回落到英文
- 启动时调用 `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "flotilla")`，让当前这份 App 成为 scheme 的处理者。
  - 原因：重新打包后 bundle 内容变了，Launch Services 的旧注册可能失效。

### 单实例

同一时间只允许一个 Flotilla 运行：两个实例会同时改写 Dock 偏好。

- `applicationWillFinishLaunching` 最先检查：`NSRunningApplication.runningApplications(withBundleIdentifier:)` 里有当前进程以外的实例，就激活它，然后立即结束当前进程
- 检查早于一切初始化：不开始 Dock 同步，不创建状态栏图标，不注册 URL scheme
- 不同路径的副本 bundle id 相同，同样只能运行一个

### 激活策略

需求 6 的参照物是陛下自己的 Hassan-macOS（`Components/AppPresentation/Sources/Internal/Operations/ActivationPolicyOperations.swift`）：有可见窗口时用 `.regular`，窗口全部关闭后回到 `.accessory`。

Flotilla 照此办理：

- 启动即 `.accessory`（`LSUIElement`），此时没有任何窗口
- 显示设置窗口前切到 `.regular`，切换后延迟到下一个 run loop 再激活并把窗口带到最前：从 `.accessory` 切到 `.regular` 后系统需要时间准备 Dock 图标
  - 激活用 `NSApp.activate(ignoringOtherApps: true)`，不用协作式的 `activate()`：最近一次用户输入不是发给 Flotilla 时（例如用辅助功能按下“设置…”），`activate()` 被系统忽略，窗口开在其它 App 后面（macOS 27 实测）
- 设置窗口关闭后，若没有其它可见窗口，切回 `.accessory`
- 面板（03 阶段）不算窗口：它从不改变激活策略，也从不激活 Flotilla

### App 图标

Dock 与 ⌘Tab 里的 Flotilla 图标跟随“系统设置 › 外观 › 图标与小组件样式”，由 `AppIconController` 负责。

- 包里有两份 icns，由打包脚本从 `Resources/` 下的两张母版生成：白天版 `AppIcon`（Info.plist 的 `CFBundleIconFile`，即默认图标）与夜间版 `AppIconDark`
- 各样式的做法：

  | 样式 | Flotilla 的做法 | Dock 上的效果 |
  |---|---|---|
  | 默认 | 不设运行时图标 | 白天版 |
  | 深色 · 始终 | `NSApp.applicationIconImage` 设为夜间版 | 夜间版 |
  | 深色 · 自动 | 深色外观时设为夜间版，浅色外观时不设 | 随系统深浅外观 |
  | 透明（浅色、深色、自动） | 不设 | 系统把白天版去色成灰度 |
  | 色调（浅色、深色、自动） | 不设 | 系统按亮度给白天版着色 |

  - “不设”即 `applicationIconImage = nil`：Dock 只对包里的默认图标做透明、色调处理
  - 透明、色调的深色子变体下仍是浅底，与系统 App 的深底图标不同
- 启动时、`NSApplication.didBecomeActiveNotification` 时、样式变化时、系统深浅外观变化时重新设置：`.accessory` 期间设的图标切到 `.regular` 后不沿用
- 访达、启动台等处只显示包里的白天版：没有 `actool`，生成不了 Assets.car；icns 内嵌的深色变体系统也不读

实测（macOS 27）：

- 样式存在全局偏好 `AppleIconAppearanceTheme` 里；“默认”时键不存在，其余取值为 `RegularDark`、`RegularAutomatic`、`ClearLight`、`ClearDark`、`ClearAutomatic`、`TintedLight`、`TintedDark`、`TintedAutomatic`
- 色调颜色存在 `AppleIconAppearanceTintColor` 里；“自动”时键不存在，选定颜色时为英文颜色名，如 `Orange`
- 样式或色调颜色变化时，`NSWorkspace.shared.notificationCenter` 发出 `NSWorkspaceIconAppearanceConfigurationDidChangeNotification`（名称不在公开头文件里），此时全局偏好已是新值
- 运行时设置的 `applicationIconImage` 在任何样式下都原样显示；设回 `nil` 后 Dock 立即恢复对包里默认图标的处理
- 深色样式下系统不会把 icns 变暗：不设运行时图标时 Dock 仍显示白天版
- 切换样式后 Dock 即时刷新 Flotilla 的图标，Dock 不重启

### 主菜单

用代码构建最小主菜单：

- App 菜单：“退出 Flotilla”（⌘Q）
- “编辑”菜单：撤销、重做、剪切、复制、粘贴、全选

设置窗口里的文本框依赖“编辑”菜单才能响应快捷键。

### URL 事件

- `AppDelegate.application(_:open:)` 接收 URL；只处理 `flotilla://folder/<uuid>`，其它一律忽略。
- 解析出 id 后交给 `DockFolderPresenter`。
- 处理 URL 事件时不得激活 Flotilla。

### `DockFolderPresenter` 占位

`Sources/Flotilla/Panel/DockFolderPresenter.swift`：`@MainActor final class`，`static let shared`，`func toggle(folderID: UUID)`。

本阶段方法体只打一条包含 id 的日志，并加 `#warning("TODO: 面板由 03 阶段实现")`。

## 数据模型（`Sources/Flotilla/Model/`）

```swift
struct Folder: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var items: [FolderItem]
}

enum FolderItem: Codable, Hashable, Identifiable {
    case app(AppReference)
    case folder(Folder)
}

struct AppReference: Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL
}
```

- `FolderItem.id` 返回所包含项的 id。
- `AppReference` 提供 `displayName`（`FileManager.default.displayName(atPath:)`）与 `icon`（`NSWorkspace.shared.icon(forFile:)`）。
- JSON 编码里 `FolderItem` 用显式类型标签区分两种情况，解码要兼容任意嵌套深度。

### `FolderStore`

`@MainActor final class FolderStore`，`static let shared`，是文件夹树的唯一数据源。

- 状态：`private(set) var rootFolders: [Folder]`
- 查询：`folder(id:)`（递归查找任意层级）、`parentFolder(of:)`（返回直接父文件夹，根文件夹返回 nil）
- 变更：
  - `addRootFolder(named:) -> Folder`
  - `addSubfolder(named:to parentID:) -> Folder?`
  - `addApps(_ urls: [URL], to folderID: UUID)`：同一文件夹内已存在相同 URL 的 App 时跳过
  - `rename(folderID:to:)`
  - `remove(itemID:)`：文件夹连同内容一起删
  - `move(itemID:to folderID: UUID?, at index: Int)`：`folderID` 为 nil 表示移到根层级（只允许文件夹）；禁止把文件夹移入自身或自己的子孙
- 每次变更后：原子写入持久化文件，并在主线程发出 `FolderStore.didChangeNotification`。
- 持久化：`~/Library/Application Support/Flotilla/folders.json`，可读的 JSON。
  - 启动时加载；文件不存在则为空
  - 解析失败时把原文件改名为 `folders.json.broken-<时间戳>` 保留，然后从空开始
- 文件位置可通过构造函数注入，`shared` 使用默认位置；单元测试用临时目录。

### `Preferences`（`Sources/Flotilla/Preferences/`）

`@MainActor final class Preferences`，`static let shared`。

- `static let maximumPreviewIconCount = 4`
- `var previewIconCount: Int`：存 `UserDefaults`，默认 4，读写都夹在 `0...maximumPreviewIconCount`
- 变更后发出 `Preferences.didChangeNotification`
- `UserDefaults` 可注入，供测试

## 文件夹图标渲染器（`Sources/Flotilla/Rendering/FolderIconRenderer.swift`）

需求 2 的渲染部分。02 用它生成 Dock 图标，03 用它显示子文件夹。

```swift
enum FolderIconRenderer {
    static func render(
        folder: Folder,
        previewIconCount: Int,
        pointSize: CGFloat,
        appearance: FolderIconAppearance
    ) -> NSImage
}
```

- 返回的 `NSImage` 必须与分辨率无关（用绘制闭包构造），调用方可按任意像素尺寸栅格化；边线、投影等尺寸都按画布比例换算，16 px 到 1024 px 都成立。
- 底板颜色随系统的深浅外观分两套；形状、边线宽度、预览网格与投影两种外观完全相同。
  - 跟随的是系统的深浅外观（`AppleInterfaceStyle`），不是“图标与小组件样式”设置
  - `FolderIconAppearance`（`Rendering/`）只有 `dark`、`light` 两种，由 `NSAppearance` 按 `bestMatch(from: [.darkAqua, .aqua])` 归类，高对比度等变体归入对应的一种，与 `FolderPanelAppearance` 的归类方式相同
  - 颜色在调用 `render` 时就定下，不随绘制时的外观变化；外观变了由调用方重新渲染
  - 调用方：stub 图标按 `NSApp.effectiveAppearance`（见 02），面板网格按所在视图的 `effectiveAppearance`，视图在 `viewDidChangeEffectiveAppearance` 时重新渲染
- 以下几何以画布边长为 1，y 轴自上而下。
- 底板：哑光、半透明的圆角方形，位置、大小与圆角和 macOS 26 起系统 App 图标的底板一致
  - 范围 [100/1024, 924/1024]，按 1024 px 栅格化后不透明部分为 [100, 923]
  - 四角是与面板主体同款的连续曲率圆角（`ContinuousCorner`），半径为底板边长的 0.25；按 1024 px 栅格化后与系统 App 图标的轮廓相差不超过 2 px（每个角逐行比较较陡的一半、逐列比较较平的一半）
  - 竖直渐变，上亮下暗，整体半透明；轮廓内侧一条边线，宽 4.5/1024
  - 不画底板外的投影
  - 两种外观的颜色（灰度都在 generic gray gamma 2.2 色彩空间里取值）：

    | 外观 | 渐变顶部 | 渐变底部 | 不透明度 | 边线 |
    |---|---|---|---|---|
    | 浅色 | 1（白） | 0.84 | 0.9 | 黑色，不透明度 0.12 |
    | 深色 | 0.20 | 0.08 | 0.96 | 白色，不透明度 0.16 |

  - 深色取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）的 `glass-dark` 样式，换算到上面的结构：它的渐变两端是同一灰度色彩空间里的 0.20、0.08，不透明度同为 0.96，分别作为渐变两端的灰度与底板整体的不透明度；边线的白色、不透明度 0.16 照搬，宽度与浅色相同
  - 深色取值还没有与系统深色图标实测对照
- 预览：取 `folder.items` 里前 `previewIconCount` 个 `.app` 项（保持顺序，跳过子文件夹）的图标，按 2×2 网格放在底板上
  - `previewIconCount` 为 0 或文件夹内没有 App 时只画底板。
- 网格几何：
  - App 图标自带四边各 100/1024 的透明边，网格按可见底板定：每个预览的可见底板边长约 0.28，相邻两个间距约 0.064，整体居中，可见范围约 [0.186, 0.814]
  - 换算成单元格：边长 0.35，左上格原点 (0.152, 0.152)，格距 0.346
  - 填充顺序左上、右上、左下、右下
  - 每个图标在单元格内等比缩放居中
- 每个预览图标下方一层柔和投影：黑色，不透明度 0.3，模糊半径 14/1024，向下偏移 5/1024。

## 状态栏（`Sources/Flotilla/StatusBar/StatusBarController.swift`）

需求 7。

- `NSStatusItem`，图标用 SF Symbol `folder`（template 模式）
- 菜单：“设置…”（⌘,）、分隔线、“退出 Flotilla”（⌘Q）
- “设置…”打开设置窗口并把它带到最前（这是唯一允许激活 Flotilla 的场景）

## 设置窗口（`Sources/Flotilla/Settings/`）

一个窗口，标题“Flotilla 设置”，关闭即隐藏，不退出 App。界面全部用代码构建（Auto Layout）。

### 文件夹区

- `NSOutlineView` 展示完整的树：根文件夹、子文件夹、App。
  - 每行显示图标与名称；文件夹图标用系统的通用文件夹图标（`NSWorkspace.shared.icon(for: .folder)`），根文件夹与子文件夹相同，不渲染其中的 App 图标，也不随预览数量与系统外观变化（需求 13）；App 图标用 `AppReference.icon`。
- 树随 `FolderStore.didChangeNotification` 刷新，尽量保留展开状态与选中项。
- 底部按钮：
  - “新建文件夹”：有选中项时在其所属文件夹内新建子文件夹（选中的是文件夹则在该文件夹内），无选中项时新建根文件夹
    - 默认名“未命名文件夹”，新建后立即进入重命名编辑
  - “添加 App…”：`NSOpenPanel`，只允许 `.applicationBundle`，允许多选，起始目录 `/Applications`；加入选中项所属的文件夹；无选中项时按钮禁用
  - “删除”：删除选中项；无选中项时禁用
- 重命名：双击文件夹名进入编辑；App 名不可编辑。
- 拖拽：
  - 树内拖拽排序与移动：App 可拖到任意文件夹内；文件夹可拖到其它文件夹内，也可拖到根层级；禁止拖入自身或自己的子孙
  - 从访达拖入 `.app` 到某个文件夹上，加入该文件夹

### 通用区

- “文件夹图标内显示的 App 图标数量”：`NSPopUpButton`，选项 0–4，绑定 `Preferences.previewIconCount`
- “辅助功能权限”：显示“已授权”或“未授权”（`AXIsProcessTrusted()`）
  - 旁边一个“打开系统设置”按钮，打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
  - 窗口每次显示时刷新状态

## 工程

- `Package.swift` 新增 `.testTarget(name: "FlotillaTests", dependencies: ["Flotilla"])`
- `AGENTS.md` 的目录结构表补上新目录与测试目录

## 单元测试（`Tests/FlotillaTests/`）

- 模型：嵌套结构 JSON 编解码往返一致
- `FolderStore`：增删改查、移动（含禁止移入子孙）、持久化到临时目录后重新加载一致、损坏文件的处理
- `Preferences`：默认值与夹取
- `FolderIconRenderer`：0–4 个预览都能渲染、`previewIconCount` 超过 App 数量时不崩溃、输出尺寸正确，以上在深浅两种外观下都成立；两种外观的底板透明区域逐像素相同；深色底板比中灰暗、浅色比中灰亮，都是上亮下暗；深色边线亮于底板内部、浅色边线暗于内部
- `FolderIconAppearance`：高对比度、vibrant 等变体归入对应的深色或浅色；面板网格里的文件夹图标在视图外观切换后换成对应外观的版本
- `AppIconController`：深色 · 始终、深色 · 自动遇到深色外观（含高对比度、vibrant 变体）时取夜间版，其母版比默认图标暗；其余样式与外观都不设运行时图标
- 单实例：同一 bundle id 的实例里只有当前进程时不算重复启动；另有实例时，不论它排在当前进程之前还是之后都能找出

## 验收

- `mise run bundle` 后 `open build/Flotilla.app`：Dock 上没有 Flotilla 图标；状态栏出现图标；菜单能打开设置窗口，此时 Dock 图标出现，关闭窗口后消失
- 其它 App 在前台时打开设置窗口，Flotilla 成为前台 App、设置窗口在最前；关闭后重开同样如此
- 设置窗口打开期间切换“图标与小组件样式”，Dock 上的 Flotilla 图标随即按上文“App 图标”一节变化
- Flotilla 运行时再启动一份：新的一份立即退出，Dock 偏好不变
- 设置窗口能新建嵌套文件夹、添加 App、重命名、拖拽、删除；重启 App 后数据仍在
- 终端执行 `open "flotilla://folder/<某个根文件夹 id>"` 后，`DockFolderPresenter` 收到该 id，且 Flotilla 没有被激活
- `mise run swift:lint` 与 `swift test` 通过
