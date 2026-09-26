# 03 展开面板

先读 [00 总览](00-overview.md)，并以 02 阶段合入后的代码为基线。本阶段交付需求 1（嵌套导航）、3、4、5、6、8、9：把 01 阶段的 `DockFolderPresenter` 占位替换成真正的面板，以及定位 tile 的 `DockTileLocator`。

## 参照物

原生参照：把任意真实文件夹放到 Dock 右侧区域，“显示为：文件夹”，“查看内容方式：网格”，点击后弹出的窗口。本机 Dock 右侧已有一个名为“银行卡”的文件夹处于网格模式，可直接对照。

对照方法：

- `screencapture -x <文件>` 截屏后用 Read 查看图片，本机已允许本进程截屏。
- 若 `AXIsProcessTrusted()` 为真，可用 Accessibility 读取 Dock 进程的元素树：按下“银行卡”tile 后，Dock 会把弹窗里的每一项作为 AX 元素暴露，其 `AXPosition` / `AXSize` 就是精确几何。
- 本文档里标注“起始值”的数字都没有实测过，能实测的以实测为准；实测不了的用起始值并加 `#warning("TODO: ...")`。

原生行为里明确不做的两处：不提供“在访达中打开”（需求 4）；展开时不改变 Dock 上 tile 的外观（需求 8）。

## 定位（`Sources/Flotilla/Panel/DockTileLocator.swift`）

- 输入根文件夹 id，通过 `DockTileBundleBuilder.bundleURL(for:)` 得到 stub URL，在 Dock 进程的 AX 树里找 `AXURL` 与之相同（标准化后比较）的 tile。
- 输出 `DockTileAnchor`：tile 在 AppKit 屏幕坐标系里的 frame、Dock 所贴的屏幕边（下、左、右）、所在的 `NSScreen`。AX 给出的坐标以主屏左上角为原点、y 向下，必须换算。
- 权限：第一次需要时用 `AXIsProcessTrustedWithOptions` 带提示地请求，每次启动最多提示一次。
- 退化：无权限或找不到 tile 时，锚点取鼠标当前位置在 Dock 方向上的投影：Dock 在底部时 x 取鼠标 x、y 取 Dock 窗口顶边；Dock 窗口的 frame 用 `CGWindowListCopyWindowInfo` 里 owner 为 Dock、贴着屏幕边缘的最大窗口取得，Dock 方向也由此判断。
- 提供“所有 Flotilla tile 的 frame”查询，供下文的快速路径判断点击命中。

## 点击信号

两条路径都通到 `DockFolderPresenter.toggle(folderID:)`：

1. 快速路径：全局 `mouseDown` 监听（`NSEvent.addGlobalMonitorForEvents`，不需要权限）里，判断点击位置是否落在某个 Flotilla tile 的 frame 内（需要 AX 权限才拿得到 frame）；命中就立即 `toggle`。原生弹窗在按下的瞬间出现，等 stub 启动再响应会慢一拍。
2. URL 路径：02 阶段的 stub 打开 `flotilla://folder/<id>`。若快速路径在 500 毫秒内已处理过同一文件夹，忽略这次 URL；否则 `toggle`。无权限时这是唯一路径。

## 面板窗口（`Sources/Flotilla/Panel/FolderPanel.swift`）

- `NSPanel`，`styleMask = [.borderless, .nonactivatingPanel]`，`level = .popUpMenu`（高于 Dock），`isOpaque = false`，`backgroundColor = .clear`，`hasShadow = true`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`，`hidesOnDeactivate = false`，`isFloatingPanel = true`，`animationBehavior = .none`
- 可以成为 key window（接收 Esc），但绝不激活 Flotilla：显示用 `orderFrontRegardless()`，不得调用 `NSApp.activate`（需求 6）
- 全局只有一个面板实例，复用

## 外观（`Sources/Flotilla/Panel/FolderPanelBackgroundView.swift`）

- 形状：圆角矩形加一个指向 tile 的尾巴，合成一条路径。尾巴在面向 Dock 的那条边上，尖端对准 tile 中心；面板因贴近屏幕边缘被夹住时，尾巴仍对准 tile。
- 材质：macOS 26 及以上用 `NSGlassEffectView`；macOS 15 用 `NSVisualEffectView`（`.popover`、`.behindWindow`、`.active`）。用 mask 把材质裁成上述形状；边缘 1 像素描边，随浅色 / 深色外观变化。
- 起始值：圆角 20 pt；尾巴宽 24 pt、高 12 pt；尾巴尖端距 Dock 边缘 4 pt；内边距 16 pt。

## 网格

文件：`FolderGridLayout`（纯计算）、`FolderGridView`、`FolderGridItemView`。

- 项的顺序就是 `folder.items` 的顺序。App 项显示 `AppReference.icon` 与 `displayName`；子文件夹项显示 `FolderIconRenderer.render(folder:previewIconCount:pointSize:)`（数量取 `Preferences.shared.previewIconCount`）与 `name`。
- 单元格起始值：宽 112 pt、高 100 pt；图标 64 pt；图标与文字间距 4 pt；文字 12 pt 系统字体、居中、最多 2 行、尾部省略。
- 悬停高亮：单元格背景圆角矩形（圆角 8 pt）；按下时颜色更深。
- 列数起始规则：`columns = min(count, max(4, ceil(sqrt(count × 1.5))))`，行数按列数向上取整。面板高度超过所在屏幕 `visibleFrame` 减 16 pt 边距时固定高度，网格放进 `NSScrollView` 垂直滚动，滚动条用 overlay 样式。宽度同样不超过屏幕。
- 面板尺寸 = 网格尺寸 + 内边距，非根层级再加导航头高度。
- 空文件夹显示一个只有内边距的最小面板。

`FolderGridLayout` 的输入是项数、屏幕可用尺寸、是否有导航头，输出列数、行数、单元格 frame 列表、面板尺寸、是否需要滚动，必须有单元测试。

## 嵌套导航（需求 1）

- 点击子文件夹项：推入该子文件夹，网格内容替换为它的 `items`；顶部出现导航头（`FolderNavigationHeaderView`）：左侧圆形返回按钮（SF Symbol `chevron.left`），中间标题为当前文件夹名。根层级不显示导航头。
- 点击返回按钮：弹出到上一层。
- 转场起始值：旧内容淡出，新内容淡入并从 0.9 缩放到 1（推入）或反向（返回），0.2 秒；面板尺寸随内容变化做动画，尾巴始终对准 tile。
- Esc 直接收起整个面板，不逐层返回。

## 展开与收起动效

- 展开起始值：以尾巴尖端为锚点，面板从 0.2 缩放到 1 并淡入，0.2 秒，ease-out。
- 收起起始值：反向，0.15 秒。
- 两个动画都可以被打断：快速连点时以最后一次操作为准，不能出现残影或卡在中间状态。
- 实现：窗口 frame 直接设为最终尺寸，动画只作用于 `contentView.layer` 的 transform 与 opacity，锚点设在尾巴尖端。

## 行为规则

- `toggle(folderID:)`：未展开时展开该文件夹的根层级；已展开同一文件夹时收起；已展开另一个文件夹时直接切换，旧面板立即消失，新面板按展开动画出现。
- 收起的触发：再次点击同一 tile（需求 5）；点击面板以外任何位置，包含左、右、中键（需求 5）；Esc；点击 App 项（需求 9）；屏幕参数变化；正在展示的文件夹被删除。
- 点击 Dock 上其它 Flotilla tile：属于“切换”，不是“收起后不动”。
- 点击 App 项：`NSWorkspace.shared.openApplication(at:configuration:)`，随即收起面板。
- 展示期间 `FolderStore` 变化：当前文件夹被删则收起；内容变化则重建网格，能保留当前层级就保留。
- 面板不得让 Flotilla 成为活动 App；不得对 Dock tile 做任何事。
- Dock 在左侧或右侧时：尾巴在面向 Dock 的边，面板出现在 tile 旁边。底部 Dock 是首要目标，左右两种必须能用，精度可以放宽。
- 多显示器：面板出现在 tile 所在的屏幕，并整体保持在该屏幕内。

## 单元测试

- `FolderGridLayout`：列数、行数、单元格 frame、面板尺寸、滚动阈值
- AX 坐标到 AppKit 坐标的换算
- 面板位置计算：给定 tile frame、面板尺寸、屏幕 frame，输出面板 frame 与尾巴尖端位置，含贴边夹住的情况
- 能与 AppKit 解耦的 presenter 状态迁移

## 验收

- 真实 Dock 上点击 tile：面板立即展开，居中对准 tile，尾巴指向 tile；再次点击收起；点击桌面、其它窗口、Dock 上其它 App 都收起；点击 App 项启动该 App 并收起；子文件夹能进入与返回
- 前台 App 全程保持前台，Dock 上没有 Flotilla 图标
- 与原生“银行卡”弹窗截图并排对照，逐项记录差异，写进汇报
