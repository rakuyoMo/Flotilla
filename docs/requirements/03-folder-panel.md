# 03 展开面板

先读 [00 总览](00-overview.md)，并以 02 阶段合入后的代码为基线。本阶段交付需求 1（嵌套导航）、3、4、5、6、8、9：把 01 阶段的 `DockFolderPresenter` 占位替换成真正的面板，以及定位 tile 的 `DockTileLocator`。

## 参照物与实测

原生参照：放在 Dock 右侧区域、“查看内容方式”为“网格”的真实文件夹，点击后弹出的窗口。实测一律使用临时创建的原生文件夹 tile，内容用中性的测试文件；不要打开陛下 Dock 上已有的文件夹，其中是个人资料，截图不得包含。

本文档的数值都来自一次实测，环境：macOS 27、主屏 1470 × 956 pt（2 倍）、深色外观、Dock 在底部、`tilesize` 64、放大开启（`largesize` 70）、自动隐藏开启。标注“未能实测”的项，实现时加 `#warning("TODO: ...")`。

实测手段：

- 几何：读取 Dock 进程的 AX 树
  - 原生弹窗是被点击 tile 的子元素 `AXGroup`，其下有标题 `AXStaticText`、子层级的返回按钮 `AXButton`，以及 `AXScrollArea` → `AXGrid` → 每项一个 `AXImage`
  - 内部元素的 frame 与可见位置一致
  - `AXGroup` 自身的 frame 水平方向与面板主体一致；竖直方向顶边比主体低 2 pt，底边在尾巴尖端下方 4 pt
- 外观：在纯色背景上截图，按像素分析
- 动画：`screencapture -v` 录屏，用 AVFoundation 逐帧分析
- 触发：`CGEvent` 模拟点击，或对 tile 执行 `AXPress`；模拟点击会移动鼠标，只在陛下确认不使用电脑的时段进行
- 临时原生文件夹 tile 只加在 Dock 右侧区域，测完删除这些 tile 与文件夹，Dock 偏好恢复原样

原生弹窗的结构：

- 面板主体是圆角矩形，面向 Dock 的边上有一个指向 tile 的尾巴
- 顶部是标题区：根层级与子层级都显示当前文件夹名；子层级另在标题区左侧显示返回按钮
- 标题区下方是网格。原生在网格最后追加一格“在访达中打开”，Flotilla 没有这一格（需求 4）。下文的“网格项数”对原生是文件数 + 1，对 Flotilla 是 `folder.items` 的数量

原生行为里明确不做的两处：不提供“在访达中打开”（需求 4）；展开时不改变 Dock 上 tile 的外观（需求 8；原生展开时 tile 图标换成一个向下的箭头）。

## 定位（`Sources/Flotilla/Panel/DockTileLocator.swift`）

- 输入根文件夹 id，通过 `DockTileBundleBuilder.bundleURL(for:)` 得到 stub URL，在 Dock 进程的 AX 树里找 `AXURL` 与之相同（标准化后比较）的 tile。
- 输出 `DockTileAnchor`：tile 在 AppKit 屏幕坐标系里的 frame、Dock 所贴的屏幕边（下、左、右）、所在的 `NSScreen`。AX 给出的坐标以主屏左上角为原点、y 向下，必须换算。
- 权限：第一次需要时用 `AXIsProcessTrustedWithOptions` 带提示地请求，每次启动最多提示一次。
- Dock 方向取自 Dock 偏好（`com.apple.dock`）的 `orientation`，缺省为底部。
- Dock 区域：实测（macOS 27）Dock 进程在 Dock 层级只有一个铺满整个屏幕的窗口，`CGWindowListCopyWindowInfo` 给不出 Dock 的范围，无权限时又读不到 AX。因此按 Dock 偏好估算：沿 Dock 所贴的屏幕边、厚度为 `tilesize` + 30 pt 的条带（`tilesize` 为 64 时，AX 实测 Dock 列表 `AXList` 朝屏幕内侧的边距屏幕边缘 94 pt）。这个区域用于判断一次点击是否落在 Dock 区域。
- 退化：无权限或找不到 tile 时，锚点取鼠标当前位置在 Dock 方向上的投影：Dock 在底部时 x 取鼠标 x、y 取上述 Dock 区域的顶边。实测开启自动隐藏时，Dock 重启后到第一次显示之前，AX 给出的所有 tile frame 都是宽度为 0 的无效值（`(0, -6, 0, 16)`），同样按找不到 tile 处理。
- 尾巴尖端对准的位置，放大与未放大两种状态实测一致：
  - x = tile frame 中心 x − 5 pt
  - Dock 在底部时，y 在 tile frame 顶边向 tile 内 1 pt 处
  - 放大开启时点击瞬间 tile 处于放大状态，直接用这一刻读到的 frame
  - 只在 Dock 右侧区域测得；左侧区域的偏移是否镜像为 + 5 pt 未能实测：原生文件夹只能放在右侧

## 点击信号

两条路径最终都交给 `DockFolderPresenter`：

1. 快速路径（有辅助功能权限时）：全局鼠标事件监听（`NSEvent.addGlobalMonitorForEvents`）配合 `AXUIElementCopyElementAtPosition`，识别点击是否落在 Flotilla 的 tile 上（按 `AXURL` 与 stub URL 比对）。stub 要等 Dock 拉起进程才发出信号，快速路径让面板出现的时机与原生一致。
2. URL 路径：02 阶段的 stub 打开 `flotilla://folder/<id>`。无权限时这是唯一路径。

必须满足的行为：

- 展开的时机与原生一致：在 tile 上按下、抬起时展开；按住不放满约 0.5 s 时不等抬起即展开；按下后拖动（调整 Dock 顺序）不展开。原生文件夹 tile 按住不放不会弹出 Dock 菜单
- 展开状态下点击同一 tile：收起，不得出现“先收起再展开”
- 展开状态下点击另一个 Flotilla tile：切换到那个文件夹
- 点击面板以外的其它任何位置（桌面、其它窗口、菜单栏、Dock 上的其它项；左键、右键、中键）：收起。实测原生在其它窗口上右键不收起，本项目按需求 5 一律收起
- 同一次点击会先后经过两条路径：快速路径处理过的点击，其 URL 在 1 秒内到达时忽略
- 无权限时无法判断点击是否落在 tile 上，再次点击 tile 会先按“外部点击”收起，随后 URL 才到达。规则：面板因点击 Dock 区域而收起后 1 秒内，到达的同一文件夹 URL 视为这次点击的一部分，忽略

## 面板窗口（`Sources/Flotilla/Panel/FolderPanel.swift`）

- `NSPanel`，`styleMask = [.borderless, .nonactivatingPanel]`，`level = .popUpMenu`（高于 Dock），`isOpaque = false`，`backgroundColor = .clear`，`hasShadow = false`（阴影按“外观”一节自绘），`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`，`hidesOnDeactivate = false`，`isFloatingPanel = true`，`animationBehavior = .none`
- 可以成为 key window（接收 Esc），但绝不激活 Flotilla：显示用 `orderFrontRegardless()`，不得调用 `NSApp.activate`（需求 6）
- 面板不是 key window 时，面板内的第一次点击也要生效（`acceptsFirstMouse`）
- 全局只有一个面板实例，复用

## 外观（`Sources/Flotilla/Panel/FolderPanelBackgroundView.swift`）

- 形状：圆角矩形加一个指向 tile 的尾巴，合成一条路径。尾巴在面向 Dock 的那条边上，尖端对准 tile（位置见“定位”）；面板因贴近屏幕边缘被夹住时，尾巴仍对准 tile。
- 面板主体：圆角 26 pt，连续曲率（与 `cornerCurve = .continuous` 的形状一致）。
- 尾巴：两条边与面板边成 45°（尖角 90°），在面板边上的底宽 19.5 pt；尖端倒圆，半径约 4 pt，倒圆后从面板边到尖端 8 pt；两条边与面板边相接处是半径约 4 pt 的内凹圆角。
- 位置：面板主体面向 Dock 的边距尾巴尖端 8 pt。未被夹住时，面板主体的水平中心 = 尾巴尖端 x + 3 pt，即原生面板并不以尾巴为中线。面板主体与屏幕左右边缘至少留 32 pt：右边缘为实测，左边缘按对称处理。
- 材质：macOS 26 及以上用 `NSGlassEffectView`（`style = .regular`）：在白、灰、黑、红四种纯色背景上与原生颜色一致，原生略亮，差异不超过 11 / 255。macOS 15 用 `NSVisualEffectView`（`.popover`、`.behindWindow`、`.active`），未能实测：本机是 macOS 27。用 mask 把材质裁成上述形状。
- 描边：沿轮廓一条 1 像素（0.5 pt）的边缘线，外侧偏暗、内侧偏亮，强弱随边的朝向变化。以下是 8 位灰度 128 的背景上的读数：
  - 竖直边以暗线为主，约 50
  - 水平边以亮线为主，约 157，内侧再有一像素约 139
  - 尾巴斜边暗线与亮线兼有
  - `NSGlassEffectView` 本身不带这条线，需要自绘
- 浅色外观：未能实测，本机为深色外观，测量不改动陛下的外观设置。
- 阴影：比系统窗口阴影更淡、更宽，并且偏向下方。
  - 同条件下 `NSPanel` 的系统阴影在边缘处更深（左右 12.5%、上 7%、下 19%），约 20 pt 内就衰减完，与原生不符
  - 原生阴影在白底上的变暗幅度：

  | 边 | 边缘处 | 向外 5 pt | 向外 15 pt | 向外 29 pt |
  |---|---|---|---|---|
  | 左、右 | 8.6% | 6.7% | 3.1% | 0.8% |
  | 上 | 5.5% | 3.9% | 1.6% | 0.4% |
  | 下 | 12.2% | 10.2% | 11.5 pt 处 7.5%，更远处未测 | 未测 |

## 网格

文件：`FolderGridLayout`（纯计算）、`FolderGridView`、`FolderGridItemView`。

- 项的顺序就是 `folder.items` 的顺序。App 项显示 `AppReference.icon` 与 `displayName`；子文件夹项显示 `FolderIconRenderer.render(folder:previewIconCount:pointSize:)`（数量取 `Preferences.shared.previewIconCount`）与 `name`。
- 面板主体内：顶部是高 32 pt 的标题区，其下是网格；网格左右各留 17 pt、底部留 12 pt。单元格 128 × 128 pt，彼此紧贴、没有间距。
- 面板主体尺寸：宽 = 128 × 列数 + 34，高 = 128 × 显示行数 + 44；尾巴另占 8 pt。
- 图标：水平居中，中心距单元格顶边 56 pt。图标主体宽 81 pt；macOS 26 起 App 图标主体占图标画布的 80%，即图标画布约 101 pt。
- 文字：13 pt 系统字体、常规、白色、居中；只显示一行，过长时在中间省略（`…`），最大宽度约 120 pt；基线距单元格顶边 119 pt。
- 悬停：没有任何高亮。
- 按下：该项图标变暗到原亮度的约 47.5%（RGB × 0.475），文字与背景不变；在同一项上抬起才触发（进入子文件夹或启动 App）。
- 列数规则（c 为网格项数）：
  - 取 n = ⌈√c⌉，在 n 列与 n + 1 列中取总格数更少的一个：比较 n × ⌈c / n⌉ 与 (n + 1) × ⌈c / (n + 1)⌉，前者不大于后者时取 n 列
  - 行数 = ⌈c / 列数⌉
  - 行数超过 5 时改为 7 列，行数 = ⌈c / 7⌉
  - 实测覆盖 c = 1–11、13、17、20、21、26、31、36、101，全部符合
- 滚动：最多显示 5 行，超出时网格区域高度固定为 5 行，网格在其中垂直滚动（按像素平滑滚动）。滚动时面板主体右侧内边距里出现 7 pt 宽的 overlay 滚动条，右缘距面板主体右边 3 pt，与网格区域等高，静止后隐藏。
- 屏幕较小时面板仍不得超出所在屏幕：高度超过 `visibleFrame` 减 16 pt 时按能完整显示的行数固定高度并滚动，宽度同样不超过屏幕。未能实测：本机只有一块 1470 × 956 pt 的屏幕。
- 空文件夹：面板按 1 格的尺寸显示（主体 162 × 172 pt），格内为空。原生空文件夹也是 1 格，只有“在访达中打开”。

`FolderGridLayout` 的输入是项数、屏幕可用尺寸，输出列数、行数、单元格 frame 列表、面板尺寸、是否需要滚动，必须有单元测试。

## 嵌套导航（需求 1）

- 点击子文件夹项：在同一个面板里进入该子文件夹，网格内容替换为它的 `items`；面板按新内容重新计算尺寸与位置，尾巴仍对准 tile。
- 标题区（`FolderNavigationHeaderView`）：根层级与子层级都显示当前文件夹名，14 pt 系统字体、常规、白色，水平居中，基线距面板主体顶边约 23.5 pt。子层级在标题区左侧显示返回按钮，根层级没有返回按钮。
- 返回按钮：21 × 22 pt，左上角距面板主体左边 15 pt、顶边 7 pt；圆角矩形（半径约 5 pt），白色填充，不透明度约 42%，按下时约 61%，悬停不变；中间是一个白色的向左 chevron，高约 7 pt。点击返回上一层。
- 进入的转场：新层级的整块面板（背景、标题区与网格）以被点击的子文件夹图标中心为锚点，按“展开”同样的缩放与不透明度曲线出现；旧层级原地淡出、不缩放，约 0.08 s 内消失。转场在鼠标抬起时开始。
- 返回的转场：当前层级按“收起”同样的方式缩向父层级中该子文件夹图标的中心并淡出；父层级原地淡入、不缩放，约 0.07 s 完成。
- Esc：在任何层级都直接收起整个面板，不逐层返回。

## 展开与收起动效

- 锚点：整个面板（背景与内容一起）绕 tile 图标中心缩放，即面板主体水平中心线上、尾巴尖端向 Dock 内约 35 pt 处（Dock 在底部时在尖端下方）。展开初期面板叠在 Dock 的 tile 上，像从 tile 里长出来。
- 展开：缩放 0.1 → 1，0.23 s，时间曲线 ease-out cubic（控制点 0.33, 1, 0.68, 1）；不透明度 0 → 1，约 0.15 s，ease-out。从鼠标抬起（或按住满 0.5 s）的那一刻开始。
- 收起：缩放 1 → 0，0.23 s，时间曲线（控制点 0.25, 0.1, 0.25, 1）；不透明度 1 → 0，0.15 s，ease-in。不透明度先到 0，所以收起约 0.15 s 时就已看不见。
- 两个动画都可以被打断：快速连点时以最后一次操作为准，不能出现残影或卡在中间状态。
- 实现：窗口 frame 设为最终尺寸，并向 Dock 方向延伸到盖住锚点，否则展开初期叠在 tile 上的部分会被窗口边界裁掉；动画只作用于 `contentView.layer` 的 transform 与 opacity，锚点设在 tile 图标中心。

## 行为规则

- `toggle(folderID:)`：未展开时展开该文件夹的根层级；已展开同一文件夹时收起；已展开另一个文件夹时直接切换，旧面板立即消失，新面板按展开动画出现。
- 收起的触发：见“点击信号”；另有 Esc、点击 App 项（需求 9）、屏幕参数变化、正在展示的文件夹被删除。
- 点击 App 项：`NSWorkspace.shared.openApplication(at:configuration:)`，随即收起面板。
- 展示期间 `FolderStore` 变化：当前文件夹被删则收起；内容变化则重建网格，能保留当前层级就保留。
- 面板不得让 Flotilla 成为活动 App；不得对 Dock tile 做任何事。
- 实测原生展开期间 Dock 一直保持显示，鼠标离开 Dock 也不隐藏；放大状态冻结在点击那一刻，鼠标经过其它 tile 也不放大；收起后 Dock 才按自动隐藏规则隐藏。Flotilla 做不到让 Dock 保持显示时，面板位置保持不动、不跟随 Dock 移动，差异写进汇报。
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
