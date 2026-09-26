# 03 展开面板

先读 [00 总览](00-overview.md)，并以 02 阶段合入后的代码为基线。本阶段交付需求 1（嵌套导航）、3、4、5、6、8、9：把 01 阶段的 `DockFolderPresenter` 占位替换成真正的面板，以及定位 tile 的 `DockTileLocator`。

## 参照物与实测

原生参照：放在 Dock 右侧区域、“查看内容方式”为“网格”的真实文件夹，点击后弹出的窗口。本机 Dock 右侧的“银行卡”文件夹就是网格模式，可直接对照；它是陛下的真实数据，只看不改。

本文档里标注“起始值”的数字都未经实测。实现前先实测，以实测为准，并把实测结论写回本文档对应位置、替换起始值；实测不了的保留起始值并加 `#warning("TODO: ...")`。

实测手段：

- 截图：`screencapture -x <文件>`，用 Read 查看
- 录屏：`screencapture -v -V <秒数> -x <文件>.mov`，再用 AVFoundation 逐帧导出，测量动画的时长、曲线与缩放锚点
- 几何：`AXIsProcessTrusted()` 为真时读取 Dock 进程的 AX 树；原生弹窗展开后，其中每一项都以 AX 元素暴露，`AXPosition` / `AXSize` 就是精确几何
- 触发：对 tile 的 AX 元素执行 `AXPress`，或用 `CGEvent` 模拟点击
- 布局规则：临时往 Dock 右侧加入若干原生文件夹 tile，分别装入 1、2、3、4、5、6、7、9、12、16、20、30 个文件，“查看内容方式”设为网格，逐一测量列数、行数与面板尺寸；测完删除这些 tile 与文件夹，Dock 偏好恢复原样

需要逐项对照的内容：

- 面板的尺寸、圆角、尾巴形状与位置、与 Dock 的间距、背景材质、描边与阴影
- 单元格尺寸、图标尺寸、文字字号与行数、悬停与按下的高亮
- 列数规则、滚动阈值
- 展开、收起、进入子文件夹、返回的动画
- 根层级与子层级是否显示标题、返回按钮
- 弹窗在按下还是抬起时出现
- Dock 自动隐藏与放大开启时（陛下本机的设置），展开期间 Dock 与弹窗的表现

原生行为里明确不做的两处：不提供“在访达中打开”（需求 4）；展开时不改变 Dock 上 tile 的外观（需求 8）。

## 定位（`Sources/Flotilla/Panel/DockTileLocator.swift`）

- 输入根文件夹 id，通过 `DockTileBundleBuilder.bundleURL(for:)` 得到 stub URL，在 Dock 进程的 AX 树里找 `AXURL` 与之相同（标准化后比较）的 tile。
- 输出 `DockTileAnchor`：tile 在 AppKit 屏幕坐标系里的 frame、Dock 所贴的屏幕边（下、左、右）、所在的 `NSScreen`。AX 给出的坐标以主屏左上角为原点、y 向下，必须换算。
- 权限：第一次需要时用 `AXIsProcessTrustedWithOptions` 带提示地请求，每次启动最多提示一次。
- 退化：无权限或找不到 tile 时，锚点取鼠标当前位置在 Dock 方向上的投影：Dock 在底部时 x 取鼠标 x、y 取 Dock 窗口顶边。Dock 窗口的 frame 取 `CGWindowListCopyWindowInfo` 里 owner 为 Dock、贴着屏幕边缘的窗口，Dock 方向也由此判断；这个 frame 同时用于判断一次点击是否落在 Dock 区域。
- 放大开启时，点击瞬间 tile 处于放大状态，鼠标离开 Dock 后 tile 缩回、中心移动。尾巴对准哪里以实测原生为准。

## 点击信号

两条路径最终都交给 `DockFolderPresenter`：

1. 快速路径（有辅助功能权限时）：全局鼠标事件监听（`NSEvent.addGlobalMonitorForEvents`）配合 `AXUIElementCopyElementAtPosition`，识别点击是否落在 Flotilla 的 tile 上（按 `AXURL` 与 stub URL 比对）。stub 要等 Dock 拉起进程才发出信号，快速路径让面板出现的时机与原生一致。
2. URL 路径：02 阶段的 stub 打开 `flotilla://folder/<id>`。无权限时这是唯一路径。

必须满足的行为：

- 展开的时机与原生一致（按下还是抬起，以实测为准）；在 tile 上按下后拖动（调整 Dock 顺序）不展开
- 展开状态下点击同一 tile：收起，不得出现“先收起再展开”
- 展开状态下点击另一个 Flotilla tile：切换到那个文件夹
- 点击面板以外的其它任何位置（桌面、其它窗口、菜单栏、Dock 上的其它项；左键、右键、中键）：收起
- 同一次点击会先后经过两条路径：快速路径处理过的点击，其 URL 在 1 秒内到达时忽略
- 无权限时无法判断点击是否落在 tile 上，再次点击 tile 会先按“外部点击”收起，随后 URL 才到达。规则：面板因点击 Dock 区域而收起后 1 秒内，到达的同一文件夹 URL 视为这次点击的一部分，忽略

## 面板窗口（`Sources/Flotilla/Panel/FolderPanel.swift`）

- `NSPanel`，`styleMask = [.borderless, .nonactivatingPanel]`，`level = .popUpMenu`（高于 Dock），`isOpaque = false`，`backgroundColor = .clear`，`hasShadow = true`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`，`hidesOnDeactivate = false`，`isFloatingPanel = true`，`animationBehavior = .none`
- 可以成为 key window（接收 Esc），但绝不激活 Flotilla：显示用 `orderFrontRegardless()`，不得调用 `NSApp.activate`（需求 6）
- 面板不是 key window 时，面板内的第一次点击也要生效（`acceptsFirstMouse`）
- 全局只有一个面板实例，复用

## 外观（`Sources/Flotilla/Panel/FolderPanelBackgroundView.swift`）

- 形状：圆角矩形加一个指向 tile 的尾巴，合成一条路径。尾巴在面向 Dock 的那条边上，尖端对准 tile；面板因贴近屏幕边缘被夹住时，尾巴仍对准 tile。
- 材质：macOS 26 及以上用 `NSGlassEffectView`；macOS 15 用 `NSVisualEffectView`（`.popover`、`.behindWindow`、`.active`）。用 mask 把材质裁成上述形状；边缘 1 像素描边，随浅色 / 深色外观变化。
- 起始值：圆角 20 pt；尾巴宽 24 pt、高 12 pt；尾巴尖端距 Dock 边缘 4 pt；内边距 16 pt。

## 网格

文件：`FolderGridLayout`（纯计算）、`FolderGridView`、`FolderGridItemView`。

- 项的顺序就是 `folder.items` 的顺序。App 项显示 `AppReference.icon` 与 `displayName`；子文件夹项显示 `FolderIconRenderer.render(folder:previewIconCount:pointSize:)`（数量取 `Preferences.shared.previewIconCount`）与 `name`。
- 单元格起始值：宽 112 pt、高 100 pt；图标 64 pt；图标与文字间距 4 pt；文字 12 pt 系统字体、居中、最多 2 行、尾部省略。
- 悬停高亮：单元格背景圆角矩形（起始值：圆角 8 pt）；按下时颜色更深。
- 列数规则以临时原生文件夹的实测为准，起始值：`columns = min(count, max(4, ceil(sqrt(count × 1.5))))`，行数按列数向上取整。
- 面板高度超过所在屏幕 `visibleFrame` 减 16 pt 边距时固定高度，网格放进 `NSScrollView` 垂直滚动，滚动条用 overlay 样式。宽度同样不超过屏幕。
- 面板尺寸 = 网格尺寸 + 内边距 + 标题区（有的话）。
- 空文件夹显示一个只有内边距的最小面板。

`FolderGridLayout` 的输入是项数、屏幕可用尺寸、是否有标题区，输出列数、行数、单元格 frame 列表、面板尺寸、是否需要滚动，必须有单元测试。

## 嵌套导航（需求 1）

- 点击子文件夹项：在同一个面板里进入该子文件夹，网格内容替换为它的 `items`；顶部出现导航头（`FolderNavigationHeaderView`）：返回按钮与当前文件夹名。返回按钮的样式与位置、根层级是否显示标题，以原生为准。
- 点击返回按钮：回到上一层。
- 转场起始值：旧内容淡出，新内容淡入并从 0.9 缩放到 1（进入）或反向（返回），0.2 秒；面板尺寸随内容变化做动画，尾巴始终对准 tile。
- Esc 的行为（直接收起，还是逐层返回）以原生为准。

## 展开与收起动效

- 展开起始值：以尾巴尖端为锚点，面板从 0.2 缩放到 1 并淡入，0.2 秒，ease-out。
- 收起起始值：反向，0.15 秒。
- 两个动画都可以被打断：快速连点时以最后一次操作为准，不能出现残影或卡在中间状态。
- 实现：窗口 frame 直接设为最终尺寸，动画只作用于 `contentView.layer` 的 transform 与 opacity，锚点设在尾巴尖端。

## 行为规则

- `toggle(folderID:)`：未展开时展开该文件夹的根层级；已展开同一文件夹时收起；已展开另一个文件夹时直接切换，旧面板立即消失，新面板按展开动画出现。
- 收起的触发：见“点击信号”；另有 Esc、点击 App 项（需求 9）、屏幕参数变化、正在展示的文件夹被删除。
- 点击 App 项：`NSWorkspace.shared.openApplication(at:configuration:)`，随即收起面板。
- 展示期间 `FolderStore` 变化：当前文件夹被删则收起；内容变化则重建网格，能保留当前层级就保留。
- 面板不得让 Flotilla 成为活动 App；不得对 Dock tile 做任何事。
- Dock 自动隐藏开启时，展开期间原生 Dock 是否保持显示以实测为准；Flotilla 做不到一致时，面板位置保持不动、不跟随 Dock 移动，差异写进汇报。
- Dock 在左侧或右侧时：尾巴在面向 Dock 的边，面板出现在 tile 旁边。底部 Dock 是首要目标，左右两种必须能用，精度可以放宽。
- 多显示器：面板出现在 tile 所在的屏幕，并整体保持在该屏幕内。

## 单元测试

- `FolderGridLayout`：列数、行数、单元格 frame、面板尺寸、滚动阈值
- AX 坐标到 AppKit 坐标的换算
- 面板位置计算：给定 tile frame、面板尺寸、屏幕 frame，输出面板 frame 与尾巴尖端位置，含贴边夹住的情况
- 能与 AppKit 解耦的 presenter 状态迁移，含“点击信号”一节的去重规则

## 验收

- 真实 Dock 上点击 tile：面板按原生时机展开，位置与尾巴对准 tile；再次点击收起；点击桌面、其它窗口、Dock 上其它 App 都收起；点击 App 项启动该 App 并收起；子文件夹能进入与返回
- 有、无辅助功能权限两种情况都验证
- 前台 App 全程保持前台，Dock 上没有 Flotilla 图标
- 与原生弹窗截图、录屏逐项对照，差异写进汇报
- 测量用的临时原生文件夹 tile 已删除，Dock 偏好与开始前一致
