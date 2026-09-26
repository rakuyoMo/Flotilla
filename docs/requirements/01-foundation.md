# 01 基础骨架与设置

先读 [00 总览](00-overview.md)。本阶段交付 App 骨架、数据模型与持久化、设置窗口、状态栏、文件夹图标渲染器，以及 URL 事件入口。Dock tile（02）与面板（03）不在本阶段。

## App 骨架

### 入口与 Info.plist

- `FlotillaApp.main()`：创建 `NSApplication.shared`，挂上 `AppDelegate`，`run()`。
- `Sources/Flotilla/Info.plist` 新增：
  - `LSUIElement = true`：Flotilla 没有 Dock 图标（需求 6）
  - `CFBundleURLTypes`：注册 scheme `flotilla`，`CFBundleURLName = com.rakuyo.flotilla.url`
  - `CFBundleAllowMixedLocalizations = true`：Flotilla 自己没有本地化资源，缺少这个键时进程语言固定为英文，`FileManager.displayName` 给出 “Calculator” 而不是“计算器”
    - 加上后 App 名称跟随系统语言，与原生一致
- 启动时调用 `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "flotilla")`，让当前这份 App 成为 scheme 的处理者。
  - 原因：重新打包后 bundle 内容变了，Launch Services 的旧注册可能失效。

### 激活策略

需求 6 的参照物是陛下自己的 Hassan-macOS（`Components/AppPresentation/Sources/Internal/Operations/ActivationPolicyOperations.swift`）：有可见窗口时用 `.regular`，窗口全部关闭后回到 `.accessory`。

Flotilla 照此办理：

- 启动即 `.accessory`（`LSUIElement`），此时没有任何窗口
- 显示设置窗口前切到 `.regular`，切换后延迟到下一个 run loop 再激活并把窗口带到最前：从 `.accessory` 切到 `.regular` 后系统需要时间准备 Dock 图标
- 设置窗口关闭后，若没有其它可见窗口，切回 `.accessory`
- 面板（03 阶段）不算窗口：它从不改变激活策略，也从不激活 Flotilla

### 主菜单

用代码构建最小主菜单：

- App 菜单：“退出 Flotilla”（⌘Q）
- “编辑”菜单：撤销、重做、剪切、复制、粘贴、全选

设置窗口里的文本框依赖“编辑”菜单才能响应快捷键。

### URL 事件

- `AppDelegate.application(_:open:)` 接收 URL；只处理 `flotilla://folder/<uuid>`，其它一律忽略。
- 解析出 id 后调用 `DockFolderPresenter.shared.toggle(folderID:)`。
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
    static func render(folder: Folder, previewIconCount: Int, pointSize: CGFloat) -> NSImage
}
```

- 返回的 `NSImage` 必须与分辨率无关（用绘制闭包构造），调用方可按任意像素尺寸栅格化。
- 底图：系统通用文件夹图标（`NSWorkspace.shared.icon(for: .folder)`），铺满画布。
- 预览：取 `folder.items` 里前 `previewIconCount` 个 `.app` 项（保持顺序，跳过子文件夹）的图标，按 2×2 网格叠在文件夹正面
  - `previewIconCount` 为 0 或文件夹内没有 App 时只画底图。
- 网格几何（以画布边长为 1，y 轴自上而下）：
  - 外框 x ∈ [0.25, 0.75]、y ∈ [0.36, 0.86]
  - 单元格之间留 0.04 间距
  - 填充顺序左上、右上、左下、右下
  - 每个图标在单元格内等比缩放居中

## 状态栏（`Sources/Flotilla/StatusBar/StatusBarController.swift`）

需求 7。

- `NSStatusItem`，图标用 SF Symbol `folder`（template 模式）
- 菜单：“设置…”（⌘,）、分隔线、“退出 Flotilla”（⌘Q）
- “设置…”打开设置窗口并把它带到最前（这是唯一允许激活 Flotilla 的场景）

## 设置窗口（`Sources/Flotilla/Settings/`）

一个窗口，标题“Flotilla 设置”，关闭即隐藏，不退出 App。界面全部用代码构建（Auto Layout）。

### 文件夹区

- `NSOutlineView` 展示完整的树：根文件夹、子文件夹、App。
  - 每行显示图标与名称；文件夹图标用 `FolderIconRenderer` 渲染，App 图标用 `AppReference.icon`。
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
- `FolderIconRenderer`：0–4 个预览都能渲染、`previewIconCount` 超过 App 数量时不崩溃、输出尺寸正确

## 验收

- `mise run bundle` 后 `open build/Flotilla.app`：Dock 上没有 Flotilla 图标；状态栏出现图标；菜单能打开设置窗口，此时 Dock 图标出现，关闭窗口后消失
- 设置窗口能新建嵌套文件夹、添加 App、重命名、拖拽、删除；重启 App 后数据仍在
- 终端执行 `open "flotilla://folder/<某个根文件夹 id>"` 后，日志里出现该 id，且 Flotilla 没有被激活
- `mise run swift:lint` 与 `swift test` 通过
