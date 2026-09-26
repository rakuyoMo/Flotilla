# Flotilla 需求总览

本目录是 Flotilla 的需求文档。`00` 是总览与公共约定，`01`–`04` 是按实现顺序拆分的四个阶段，每个阶段由一名实现者独立完成。

## 目标

在 Dock 上放置“文件夹”，把 App 分类收纳进去。点击文件夹，在 Dock 上方以“网格”样式展开其中的 App；交互、动效与位置以 macOS 原生 Dock 文件夹（放在 Dock 右侧区域、显示为网格）为准，一比一还原。

原生行为里明确**不做**的两处：展开内容中不提供“在访达中打开”；展开时 Dock 上的文件夹图标不做外观变化。

## 需求清单

编号沿用原始需求，后续文档用“需求 N”引用。

1. 允许文件夹嵌套。
2. Dock 上的文件夹图标要实时渲染出文件夹内的 App 图标。上限在 App 内写死为 4，用户可在 0–4 之间调整；0 表示只显示文件夹图标。
3. 点击 Dock 上的文件夹图标，固定按“网格”样式展开内容；动效与位置与原生一比一还原。
4. 展开内容中不提供“在访达中打开”。
5. 展开状态下再次点击该图标，收起；展开状态下点击其它区域或其它 App，也收起。
6. 展开内容时，Dock 上不出现 Flotilla 的活动图标。
7. 提供一个状态栏图标，用于快速打开设置页面。
8. 展开时 Dock 上的文件夹图标不需要变化。
9. 点击展开内容中的 App 图标，直接启动该 App，同时收起展开内容。

初版不给用户更多选择：除需求 2 的数量设置外，不增加任何其它设置项，不提供网格以外的展示样式。

## 术语

| 术语 | 含义 |
|---|---|
| 文件夹 | Flotilla 管理的 App 分组，可嵌套；数据由 Flotilla 自己保存，不对应磁盘目录 |
| 根文件夹 | 没有父文件夹的文件夹；每个根文件夹对应 Dock 上的一个 tile |
| tile | Dock 上的一个图标 |
| stub | 代表根文件夹放进 Dock 的占位 App bundle，点击它即触发展开 |
| 面板 | 点击 tile 后在 Dock 上方展开的网格弹窗 |
| 预览图标数 | 需求 2 中渲染进文件夹图标的 App 图标数量上限，0–4 |

## 总体方案

Flotilla 是一个无 Dock 图标的常驻后台 App（`LSUIElement`），只有状态栏图标与设置窗口。

- **Dock 集成**：Dock 只能放 App 与文件，因此每个根文件夹对应一个由 Flotilla 生成的 stub App bundle，写入 Dock 偏好（`com.apple.dock`）后重启 Dock 使其出现。stub 的图标即按需求 2 渲染的文件夹图标。
- **点击信号**：点击 tile 时 Dock 启动 stub；stub 以不激活任何 App 的方式打开 `flotilla://folder/<根文件夹 id>`，随即退出。Flotilla 作为该 URL scheme 的处理者收到事件，展开或收起面板。Flotilla 未运行时，Launch Services 会先启动它。
- **面板定位**：通过 Accessibility API 读取 Dock 进程里该 tile 的屏幕位置与尺寸，面板居中对准 tile。未获得辅助功能权限时，退化为以收到点击信号时的鼠标位置为锚点。
- **面板本身**：不激活 Flotilla 的悬浮面板（`NSPanel`，nonactivating），窗口层级高于 Dock；外观、几何、动效对照原生逐项还原。

## 模块划分

代码全部在 `Sources/Flotilla/` 下，按职责分子目录；每个文件一个类型。下表是各阶段共同遵守的接口契约，类型名与职责不得私自更改；实现细节由各阶段文档规定。

| 目录 | 类型 | 职责 | 阶段 |
|---|---|---|---|
| `Model/` | `Folder` | 文件夹：`id`、`name`、`items` | 01 |
| `Model/` | `FolderItem` | 文件夹内的一项：App 或子文件夹 | 01 |
| `Model/` | `AppReference` | 对一个 App bundle 的引用 | 01 |
| `Model/` | `FolderStore` | 文件夹树的唯一数据源：增删改查、持久化、变更通知 | 01 |
| `Preferences/` | `Preferences` | 用户设置：预览图标数 | 01 |
| `Rendering/` | `FolderIconRenderer` | 把文件夹渲染成图标（需求 2） | 01 |
| `StatusBar/` | `StatusBarController` | 状态栏图标与菜单（需求 7） | 01 |
| `Settings/` | `SettingsWindowController` 等 | 设置窗口 | 01 |
| 根目录 | `AppDelegate` | 应用生命周期、主菜单、URL 事件分发 | 01 |
| `Panel/` | `DockFolderPresenter` | 面板的展开、收起、切换；URL 事件的最终接收者 | 01 占位，03 实现 |
| `Dock/` | `DockTileBundleBuilder` | 生成、更新、删除 stub bundle | 02 |
| `Dock/` | `IconFileWriter` | 把 `NSImage` 写成 `.icns` | 02 |
| `Dock/` | `DockPreferences` | 读写 `com.apple.dock`，增删 tile，重启 Dock | 02 |
| `Dock/` | `DockTileSynchronizer` | 让 Dock 上的 tile 与根文件夹保持一致 | 02 |
| `Panel/` | `DockTileLocator` | 通过 Accessibility 定位 tile | 03 |
| `Panel/` | `FolderPanel` 及各视图 | 面板窗口、背景、网格、导航 | 03 |
| `Sources/FlotillaDockTile/` | stub 的可执行文件 | 打开 `flotilla://` URL 后退出 | 02 |
| `Tests/FlotillaTests/` | 单元测试 | Swift Testing | 各阶段 |

## 阶段与顺序

四个阶段在同一分支上顺序进行，后一阶段以前一阶段合入后的代码为基线：

1. [01 基础骨架与设置](01-foundation.md)：App 骨架、数据模型与持久化、设置窗口、状态栏、文件夹图标渲染、URL 事件入口
2. [02 Dock tile](02-dock-tile.md)：stub 生成、`.icns` 写入、Dock 偏好读写、tile 与根文件夹同步
3. [03 展开面板](03-folder-panel.md)：面板定位、外观、网格、嵌套导航、动效、收起规则
4. [04 集成验收](04-integration.md)：端到端验证、文档回写、清理

## 公共约束

- 遵守 [AGENTS.md](../../AGENTS.md) 的全部规范，特别是“产物可追溯性”一节：需求之外的东西不写进代码。
- 新建或编辑 `.swift` 文件后必须运行 `mise run swift:lint`，不通过就 `mise run swift:format` 后再查。
- 纯逻辑（模型、持久化、几何计算、plist 条目构造）必须有 Swift Testing 单元测试，`swift test` 全部通过。
- 拿不准或靠推测写下的地方，用 `#warning("TODO: ...")` 标记，并在完成汇报里列出。
- 修改 Dock 偏好之前必须先备份 `com.apple.dock`；只增删 Flotilla 自己的 tile，不碰其它任何 tile。
- 不增加需求清单之外的设置项、菜单项与功能。
