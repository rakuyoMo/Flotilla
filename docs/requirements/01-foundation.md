# 01 基础骨架与设置

先读 [00 总览](00-overview.md)。本阶段交付 App 骨架、数据模型与持久化、设置窗口、状态栏、组图标渲染器，以及 URL 事件入口。Dock tile（02）与面板（03）不在本阶段。

## App 骨架

### 入口与 Info.plist

- `FlotillaApp.main()`：创建 `NSApplication.shared`，挂上 `AppDelegate`，`run()`。
- `Sources/Flotilla/Info.plist` 新增：
  - `LSUIElement = true`：Flotilla 没有 Dock 图标（需求 6）
  - `CFBundleURLTypes`：注册 scheme `flotilla`，`CFBundleURLName = com.rakuyo.flotilla.url`
  - `CFBundleAllowMixedLocalizations = true`：让 App 显示名等来自其它 bundle 的文字按系统语言本地化，不受 Flotilla 自身支持的语言限制
  - `CFBundleDevelopmentRegion = en`：系统语言不在 Flotilla 支持的语言之内时，界面文字回落到英文
  - `NSAppTransportSecurity` 里只有 `NSAllowsArbitraryLoadsInWebContent = true`：只为网页内容放开明文 HTTP，让 “添加网页…” 自动获取 `http://` 网页的标题（见 09）
- 启动时调用 `NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "flotilla")`，让当前这份 App 成为 scheme 的处理者。
  - 原因：重新打包后 bundle 内容变了，Launch Services 的旧注册可能失效。

### 单实例

同一时间只允许一个 Flotilla 运行：两个实例会同时改写 Dock 偏好。

- `applicationWillFinishLaunching` 最先检查：`NSRunningApplication.runningApplications(withBundleIdentifier:)` 里有当前进程以外的实例，就激活它，然后立即结束当前进程
- 检查早于一切初始化：不开始 Dock 同步，不创建状态栏图标，不注册 URL scheme
- 不同路径的副本 bundle id 相同，同样只能运行一个

### 激活策略

有可见窗口时用 `.regular`，窗口全部关闭后回到 `.accessory`（需求 6）：

- 启动即 `.accessory`（`LSUIElement`），此时没有任何窗口
- 显示设置窗口前切到 `.regular`，切换后延迟到下一个 run loop 再激活并把窗口带到最前：从 `.accessory` 切到 `.regular` 后系统需要时间准备 Dock 图标
  - 激活用 `NSApp.activate(ignoringOtherApps: true)`，不用协作式的 `activate()`：最近一次用户输入不是发给 Flotilla 时（例如用辅助功能按下 “设置…”），`activate()` 被系统忽略，窗口开在其它 App 后面（macOS 27 实测）
- 设置窗口关闭后，若没有其它可见窗口，切回 `.accessory`
- 面板（03 阶段）不算窗口：它从不改变激活策略，也从不激活 Flotilla

### App 图标

Dock 与 ⌘Tab 里的 Flotilla 图标跟随 “系统设置 › 外观 › 图标与小组件样式”，由 `AppIconController` 负责。

- 包里有两份 icns，由打包脚本从 `Resources/` 下的两张母版生成：白天版 `AppIcon`（Info.plist 的 `CFBundleIconFile`，即默认图标）与夜间版 `AppIconDark`
- 各样式的做法：

  | 样式 | Flotilla 的做法 | Dock 上的效果 |
  |---|---|---|
  | 默认 | 不设运行时图标 | 白天版 |
  | 深色 · 始终 | `NSApp.applicationIconImage` 设为夜间版 | 夜间版 |
  | 深色 · 自动 | 深色外观时同 “深色 · 始终”，浅色外观时不设 | 随系统深浅外观 |
  | 透明 · 浅色 | 不设 | 系统把白天版去色成灰度 |
  | 透明 · 深色 | 设为去色后的夜间版 | 深灰底、浅灰图案 |
  | 透明 · 自动 | 深色外观时同 “透明 · 深色”，浅色外观时不设 | 随系统深浅外观 |
  | 色调 · 浅色 | 不设 | 系统按亮度给白天版着色 |
  | 色调 · 深色 | 设为按色调颜色着色的夜间版 | 深底、色调颜色的图案 |
  | 色调 · 自动 | 深色外观时同 “色调 · 深色”，浅色外观时不设 | 随系统深浅外观 |

  - “不设” 即 `applicationIconImage = nil`：Dock 只对包里的默认图标做透明、色调处理
  - 运行时设置的图标 Dock 原样显示，所以透明、色调的深色子变体由 `DarkIconStyleRenderer` 先处理好夜间版再设：
    - 两种处理都只看像素的 Rec. 709 亮度 L（在 sRGB 编码值上计算），透明度不变
    - 透明 · 深色：灰度 = 0.075 + 0.79 L
    - 色调 · 深色：各通道 = 0.08 + 0.92 L × 色调颜色的对应通道；系统颜色按深色外观取值
    - 系数按 Dock 对包里白天版的处理效果拟合
  - 色调颜色取 `NSWorkspace.shared` 私有的 `currentIconAppearanceConfiguration` 所返回对象的 `resolvedIconTintColor`；取不到时不设运行时图标，由 Dock 按系统设置的颜色处理白天版，只是底板是浅色
  - 取不到夜间版资源或处理失败时同样不设：上一种样式设的图标与当前样式不符
  - 没有 “图标与小组件样式” 的系统（macOS 15 起、26 之前）上 `AppleIconAppearanceTheme` 不存在，按 “默认” 处理：显示白天版，与系统里其它 App 一致
- 启动时、`NSApplication.didBecomeActiveNotification` 时、样式或色调颜色变化时、系统深浅外观变化时重新设置：`.accessory` 期间设的图标切到 `.regular` 后不沿用
- 访达、启动台等处只显示包里的白天版：没有 `actool`，生成不了 Assets.car；icns 内嵌的深色变体系统也不读

实测（macOS 27）：

- 样式存在全局偏好 `AppleIconAppearanceTheme` 里；“默认” 时键不存在，其余取值为 `RegularDark`、`RegularAutomatic`、`ClearLight`、`ClearDark`、`ClearAutomatic`、`TintedLight`、`TintedDark`、`TintedAutomatic`
- 色调颜色存在 `AppleIconAppearanceTintColor` 里；“自动” 时键不存在，选定颜色时为英文颜色名，如 `Orange`
- 样式或色调颜色变化时，`NSWorkspace.shared.notificationCenter` 发出 `NSWorkspaceIconAppearanceConfigurationDidChangeNotification`（名称不在公开头文件里），此时全局偏好已是新值
- `NSWorkspace.shared` 响应私有选择子 `currentIconAppearanceConfiguration`，返回 SkyLight 的 `SLSIconAppearanceConfiguration`；其 `resolvedIconTintColor` 是 `NSColor`：选定橙色时为 `systemOrangeColor`，“自动” 时为 `systemBlueColor`
- 运行时设置的 `applicationIconImage` 在任何样式下都原样显示；设回 `nil` 后 Dock 立即恢复对包里默认图标的处理
- Dock 对包里默认图标做的透明 · 深色、色调 · 深色处理，输出都是像素亮度的线性函数；色调处理是亮度与色调颜色逐通道相乘
- 深色样式下系统不会把 icns 变暗：不设运行时图标时 Dock 仍显示白天版
- `NSWorkspace.shared.icon(forFile:)` 取到的 App 图标已按当前样式处理，但只对 `.app` 有效：`CFBundleIconFile` 指向夜间版的 `.bundle` 取到的是通用的 bundle 图标
- 切换样式后 Dock 即时刷新 Flotilla 的图标，Dock 不重启

### 主菜单

用代码构建最小主菜单：

- App 菜单：“退出归帆”（⌘Q）
- “编辑” 菜单：撤销、重做、剪切、复制、粘贴、全选

设置窗口里的文本框依赖 “编辑” 菜单才能响应快捷键。

### URL 事件

- `AppDelegate.application(_:open:)` 接收 URL，由 `DockTileRequest` 解析（见 [05](05-refinements.md)、[06](06-files-and-web-pages.md)）：
  - `flotilla://folder/<uuid>` 交给 `DockGroupPresenter.handleURLSignal(groupID:)`
  - 把项拖到 tile 上的请求，确认 id 是根组后经 `GroupStore.addItems` 加入
  - 无法识别的 URL 一律忽略
- 处理 URL 事件时不得激活 Flotilla。

## 数据模型（`Sources/Flotilla/Model/`）

```swift
struct Group: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var items: [GroupItem]
}

enum GroupItem: Codable, Hashable, Identifiable {
    case app(AppReference)
    case group(Group)
    case file(FileReference)
    case webPage(WebPageReference)
}

struct AppReference: BookmarkedReference, Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL
    let bookmark: Data?
    let bundleIdentifier: String?
}
```

- `GroupItem.id` 返回所包含项的 id。
- `AppReference` 提供 `displayName`（`FileManager.default.displayName(atPath:)`）与 `icon`（`NSWorkspace.shared.icon(forFile:)`）。
  - 书签与文件的相同，App 移动或改名后据此跟到新位置（需求 19）
  - bundle id 在 App 更新后书签找不到装好的那一份时用来找回（需求 22）
  - 两者见 [08](08-finder-folder-stacks.md)
- 文件、网页两种情况（`FileReference`、`WebPageReference`）与为要加入的 URL 分类的 `GroupItem(url:title:)` 见 [06](06-files-and-web-pages.md)（需求 14）；访达文件夹与文件的书签见 [07](07-file-items-refinements.md)（需求 15、18）。
- JSON 编码里 `GroupItem` 用显式类型标签区分各种情况，解码要兼容任意嵌套深度。
  - 组的类型标签沿用 `folder`：已保存的数据靠它解码

### `GroupStore`

`@MainActor final class GroupStore`，`static let shared`，是组树的唯一数据源。

- 状态：`private(set) var rootGroups: [Group]`
- 查询：`group(id:)`（递归查找任意层级）、`parentGroup(of:)`（返回直接父组，根组返回 nil）
- 变更：
  - `addRootGroup(named:) -> Group`
  - `addSubgroup(named:to parentID:) -> Group?`
  - `addItems(_ items: [GroupItem], to groupID: UUID)`：把 App、文件与网页追加到末尾；同一组内已存在同类且 URL 相同的项时跳过（见 06）；去重之前先按书签更新该组里的 App 与文件（见 07、08）
  - `updateItemLocations(in:)`：按书签把 App 项与文件项跟到新位置（见 07、08）
  - `rename(groupID:to:)`
  - `remove(itemID:)`：组连同内容一起删
  - `move(itemID:to groupID: UUID?, at index: Int)`：`groupID` 为 nil 表示移到根层级（只允许组）；禁止把组移入自身或自己的子孙
- 每次变更后：原子写入持久化文件，并在主线程发出 `GroupStore.didChangeNotification`。
- 持久化：`~/Library/Application Support/Flotilla/folders.json`，可读的 JSON。
  - 文件名沿用 `folders.json`：已保存的数据就在这个文件里
  - 启动时加载；文件不存在则为空
  - 解析失败时把原文件改名为 `folders.json.broken-<时间戳>` 保留，然后从空开始
- 文件位置可通过构造函数注入，`shared` 使用默认位置；单元测试用临时目录。

### `Preferences`（`Sources/Flotilla/Preferences/`）

`@MainActor final class Preferences`，`static let shared`。

- `static let maximumPreviewIconCount = 4`
- `var previewIconCount: Int`：存 `UserDefaults`，默认 4，读写都夹在 `0...maximumPreviewIconCount`
- 变更后发出 `Preferences.didChangeNotification`
- `UserDefaults` 可注入，供测试

## 组图标渲染器（`Sources/Flotilla/Rendering/GroupIconRenderer.swift`）

需求 2 的渲染部分。02 用它生成 Dock 图标，03 用它显示子组。

```swift
enum GroupIconRenderer {
    static func render(
        group: Group,
        previewIconCount: Int,
        pointSize: CGFloat,
        appearance: GroupIconAppearance
    ) -> NSImage
}
```

- 返回的 `NSImage` 必须与分辨率无关（用绘制闭包构造），调用方可按任意像素尺寸栅格化；边线、投影等尺寸都按画布比例换算，16 px 到 1024 px 都成立。
- 底板颜色随系统的深浅外观分两套；形状、边线宽度、预览网格与投影两种外观完全相同。
  - 跟随的是系统的深浅外观（`AppleInterfaceStyle`），不是 “图标与小组件样式” 设置
  - `GroupIconAppearance`（`Rendering/`）只有 `dark`、`light` 两种，由 `NSAppearance` 按 `bestMatch(from: [.darkAqua, .aqua])` 归类，高对比度等变体归入对应的一种，与 `GroupPanelAppearance` 的归类方式相同
  - 颜色在调用 `render` 时就定下，不随绘制时的外观变化；外观变了由调用方重新渲染
  - 调用方：stub 图标按 `NSApp.effectiveAppearance`（见 02），面板网格按所在视图的 `effectiveAppearance`，视图在 `viewDidChangeEffectiveAppearance` 时重新渲染
- 以下几何以画布边长为 1，y 轴自上而下。
- 底板：哑光、半透明的圆角方形，位置、大小与圆角和 macOS 26 起系统 App 图标的底板一致
  - 范围 [100 / 1024, 924 / 1024]，按 1024 px 栅格化后不透明部分为 [100, 923]
  - 四角是与面板主体同款的连续曲率圆角（`ContinuousCorner`），半径为底板边长的 0.25；按 1024 px 栅格化后与系统 App 图标的轮廓相差不超过 2 px（每个角逐行比较较陡的一半、逐列比较较平的一半）
  - 竖直渐变，上亮下暗，整体半透明；轮廓内侧一条边线，宽 4.5 / 1024
  - 不画底板外的投影
  - 两种外观的颜色（灰度都在 generic gray gamma 2.2 色彩空间里取值）：

    | 外观 | 渐变顶部 | 渐变底部 | 不透明度 | 边线 |
    |---|---|---|---|---|
    | 浅色 | 1（白） | 0.84 | 0.9 | 黑色，不透明度 0.12 |
    | 深色 | 0.20 | 0.08 | 0.96 | 白色，不透明度 0.16 |

  - 深色取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）的 `glass-dark` 样式，换算到上面的结构：它的渐变两端是同一灰度色彩空间里的 0.20、0.08，不透明度同为 0.96，分别作为渐变两端的灰度与底板整体的不透明度；边线的白色、不透明度 0.16 照搬，宽度与浅色相同
  - 深色取值还没有与系统深色图标实测对照
- 预览：取 `group.items` 里前 `previewIconCount` 项（保持顺序，只跳过子组；App、文件与网页都算，见 07）的图标，按 2 × 2 网格放在底板上
  - `previewIconCount` 为 0 或组内只有子组、没有其它项时只画底板。
- 网格几何：
  - App 图标自带四边各 100 / 1024 的透明边，网格按可见底板定：每个预览的可见底板边长约 0.28，相邻两个间距约 0.064，整体居中，可见范围约 [0.186, 0.814]
  - 换算成单元格：边长 0.35，左上格原点 (0.152, 0.152)，格距 0.346
  - 填充顺序左上、右上、左下、右下
  - 每个图标在单元格内等比缩放居中
- 每个预览图标下方一层柔和投影：黑色，不透明度 0.3，模糊半径 14 / 1024，向下偏移 5 / 1024。

## 状态栏（`Sources/Flotilla/StatusBar/`）

需求 7。

- `StatusBarController`：方形的 `NSStatusItem`（`squareLength`），图标取自 `StatusBarIcon`
- `StatusBarIcon`：按矢量绘制 App 图标里那艘方帆船的剪影，template 模式，无障碍描述为当前语言下的 App 名（简繁中文为 “归帆” “歸帆”，日文为 “帰帆”，其它语言为 “Flotilla”）
  - 部件：桅杆、桅顶向右飘的三角旗、三面上下叠放的横帆（帆桁左高右低、越往下越宽，相邻两面之间留斜缝）、船尾高起而船首上翘的船身、船首斜桅
  - 画布 16 × 16 pt，船从桅顶到船底占满画布高度、左右居中，放进 22 pt 见方的状态栏按钮后四周各留 3 pt
  - 桅杆、甲板、船尾与船底落在整点上，1 倍屏幕上这些边缘不发虚
- 菜单：“设置…”（⌘,）、分隔线、“退出归帆”（⌘Q）
- “设置…” 打开设置窗口并把它带到最前（这是唯一允许激活 Flotilla 的场景）

## 设置窗口（`Sources/Flotilla/Settings/`）

一个窗口，标题 “设置”，关闭即隐藏，不退出 App。界面全部用代码构建（Auto Layout）。

### 组区

- `NSOutlineView` 展示完整的树：根组、子组、App、文件与网页。
  - 每行显示图标与名称；组的图标是固定的黄色文件夹（需求 35，见 12），根组与子组相同，不渲染其中的 App 图标，也不随预览数量与系统外观变化（需求 13）；App、文件与网页的图标用各自的 `icon`。
- 树随 `GroupStore.didChangeNotification` 刷新，尽量保留展开状态与选中项。
- 底部按钮：
  - “新建组”：选中组时在该组内新建子组，无选中项时新建根组；选中 App、文件、访达文件夹与网页时禁用，见 12
    - 默认名 “未命名组”，新建后立即进入重命名编辑
  - “添加…”：下拉按钮，菜单里是 “添加 App…” “添加文件…” “添加网页…”，都加入选中的组；只在选中组时可用，见 09、12
    - “添加 App…”：`NSOpenPanel`，只允许 `.applicationBundle`，允许多选，起始目录 `/Applications`
    - “添加文件…”：选择文件与访达文件夹，见 07
    - “添加网页…”：输入网址与可选的标题，见 09
- 右键菜单：“删除” 删除右键点到的那一项，其余各项按那一行的类型给出，见 10
- 重命名：双击组名进入编辑；App、文件与网页的名称不可编辑。
- 拖放：
  - 树内拖动排序与移动：App、文件与网页可拖到任意组内；组可拖到其它组内，也可拖到根层级；禁止拖入自身或自己的子孙
  - 从访达拖入 App、文件与访达文件夹，从浏览器拖入网页到某个组上，加入该组（见 06、07）

### 通用区

- “组图标内显示的图标数量”：`NSPopUpButton`，选项 0–4，绑定 `Preferences.previewIconCount`
- “访达文件夹”：`NSButton` 复选框 “显示隐藏文件”，默认不勾，绑定 `Preferences.showsHiddenFiles`；切换后不发设置变更通知，见 08 的需求 23
- “辅助功能权限”：显示 “已授权” 或 “未授权”（`AXIsProcessTrusted()`）
  - 旁边一个 “打开系统设置” 按钮，打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`
  - 窗口每次显示时刷新状态

## 工程

- `Package.swift` 新增 `.testTarget(name: "FlotillaTests", dependencies: ["Flotilla"])`
- `AGENTS.md` 的目录结构补上新目录与测试目录

## 单元测试（`Tests/FlotillaTests/`）

- 模型：嵌套结构 JSON 编解码往返一致
- `GroupStore`：增删改查、移动（含禁止移入子孙）、持久化到临时目录后重新加载一致、损坏文件的处理
- `Preferences`：默认值与夹取
- `StatusBarIcon`：是 template 图、无障碍描述为各语言下的 App 名；在 16 pt 画布里上下占满、左右居中；1 倍下桅杆、甲板与船底落在整像素上
- `GroupIconRenderer`：0–4 个预览都能渲染、`previewIconCount` 超过 App 数量时不崩溃、输出尺寸正确，以上在深浅两种外观下都成立；两种外观的底板透明区域逐像素相同；深色底板比中灰暗、浅色比中灰亮，都是上亮下暗；深色边线亮于底板内部、浅色边线暗于内部
- `GroupIconAppearance`：高对比度、vibrant 等变体归入对应的深色或浅色；面板网格里的组图标在视图外观切换后换成对应外观的版本
- `AppIconController`：深色、透明、色调三种样式的 “深色” 子变体（深色样式为 “始终”）不看外观，换成夜间版、去色的夜间版、着色的夜间版；“自动” 子变体只在深色外观（含高对比度、vibrant 变体）下同样换；默认样式与透明、色调的 “浅色” 子变体在任何外观下都不设运行时图标
- `DarkIconStyleRenderer`：去色后红、绿、蓝相等；着色后亮部的色相与色调颜色一致；黑色变成中性的深色；明暗顺序与透明度不变；夜间版母版处理后比白天版暗，平均亮度低于一半
- 单实例：同一 bundle id 的实例里只有当前进程时不算重复启动；另有实例时，不论它排在当前进程之前还是之后都能找出

## 验收

- `mise run bundle` 后 `open build/Flotilla.app`：Dock 上没有 Flotilla 图标；状态栏出现图标；菜单能打开设置窗口，此时 Dock 图标出现，关闭窗口后消失
- 其它 App 在前台时打开设置窗口，Flotilla 成为前台 App、设置窗口在最前；关闭后重开同样如此
- 设置窗口打开期间切换 “图标与小组件样式”、色调颜色或系统深浅外观，Dock 上的 Flotilla 图标随即按上文 “App 图标” 一节变化；透明 · 深色、色调 · 深色下是深底，与相邻系统 App 的图标一致
- Flotilla 运行时再启动一份：新的一份立即退出，Dock 偏好不变
- 设置窗口能新建嵌套组、添加 App、重命名、拖放、删除；重启 App 后数据仍在
- 终端执行 `open "flotilla://folder/<某个根组 id>"` 后，`DockGroupPresenter` 收到该 id，且 Flotilla 没有被激活
- `mise run swift:lint` 与 `swift test` 通过
