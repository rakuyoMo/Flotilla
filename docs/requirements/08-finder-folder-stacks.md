# 08 App 跟随移动、访达里的文件夹展开与位置

先读 [00 总览](00-overview.md) 与 01–07 七份文档，并以 07 阶段合入后的代码为基线。本阶段交付需求 19–21：

- 需求 19：App 移动或改名后，这一项自动跟到新位置
- 需求 20：访达里的文件夹在面板里像 Dock 叠放那样展开，网格末尾有“在访达中打开”
- 需求 21：设置窗口里，访达里的文件夹这一行在名称后标出所在位置

称呼沿用 07：“文件夹”专指 Flotilla 的分组；磁盘上的目录称“访达里的文件夹”。

## 规则

### 需求 19 App 跟随移动

- App 与文件用同一套规则、同一份实现：带书签，按书签跟到当前位置（规则见 07 的“按书签找到当前位置”）
- 调用时机与 07 相同：启动、展开面板后、设置窗口成为 key、`addItems` 去重前
- 网页不涉及

### 需求 20 访达里的文件夹在面板里展开

- 访达里的文件夹仍是 `.file(FileReference)`，不新增项的种类；变的只是面板里点击它的行为
- 什么算访达里的文件夹：点击时读资源属性，是目录且不是文件包（`isDirectory && !isPackage`），含卷
  - 文件包（`.rtfd`、`.pages` 等）、符号链接、替身、读不到属性（已删除）的，仍按文件用默认 App 打开
    - 已删除的打不开：系统按 `NSWorkspace` 的默认设置弹出“找不到”的提示，同时记日志，面板收起
  - 同一判断（`FileReference.isFinderFolder`）也用于目录内容的分类与设置窗口（需求 21）
- 点击访达里的文件夹：在同一个面板里进入它，与进入子文件夹相同
  - 新层级从被点击的图标里长出来，旧层级淡出；返回时缩回那个图标（转场见 03 的“嵌套导航”）
  - 标题是它在访达里的显示名；有返回按钮
  - 网格是目录内容，最后追加一格“在访达中打开”
- 读不出内容（已删除、没有权限、隐私授权被拒）：不进入，按 `NSWorkspace.open` 交给访达、收起面板，并记日志
- 读目录期间发生的鼠标按下，既不算点面板外，也不算点 tile：读取结束后处理到时忽略
  - 读取在主线程同步进行，第一次读受保护的位置时要等用户回答隐私授权框；用户点授权框的按下排到读取结束后才处理，当成点面板外会让刚进入的层级随即收起
  - 进入、返回与文件夹树变化重建时的读取都算
  - 读取之后的按下照旧：点面板外收起、点 tile 切换
- 不提供排序或显示方式的选择，不监听磁盘变化（00：“初版不给用户更多选择”）

## 数据模型

```swift
/// 带书签的本地引用：App 与文件共用同一套规则
protocol BookmarkedReference {
    var id: UUID { get }
    var url: URL { get }
    var bookmark: Data? { get }
    init(id: UUID, url: URL, bookmark: Data?)
}

struct AppReference: BookmarkedReference, Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL

    /// 建不起来时为 nil，只按路径找
    let bookmark: Data?
}
```

- `BookmarkedReference` 的扩展提供 `normalizedURL(_:)` 与 `relocated()`，`AppReference` 与 `FileReference` 共用，规则见 07
- `AppReference` 的书签与文件的完全相同：
  - `FolderItem(url:title:)` 新建 App 项时带上 `url.bookmarkData()`，建不起来为 nil
  - JSON 键 `bookmark`，nil 时不写；没有这个键的数据照常解码，书签为 nil

  ```json
  { "type": "app", "id": "…", "url": "file:///Applications/Safari.app/", "bookmark": "Ym9va…" }
  ```

- `FolderStore.updateItemLocations(in:)` 按书签更新 App 项与文件项；`FolderTreeViewController.updateItemLocations()` 同理

## 面板

### 层级与导航路径

- `FolderPanelLevelContent`：一个层级展示的内容
  - `.folder(Folder)`：Flotilla 的文件夹
  - `.finderFolder(FileReference, items:)`：访达里的文件夹与读出的各项
  - `id`：文件夹的 id，或访达里的文件夹这一项的 id
  - `cellCount`：网格格数，访达里的文件夹为目录项数 + 1，空目录为 1；Flotilla 的文件夹为项数
- 导航路径仍是 id 数组，`FolderPanelController.levelContent(at:in:finderFolderItems:)` 逐层解析：
  - 在当前层的项里找下一个 id：子文件夹取它本身，访达里的文件夹读出目录
  - 读目录由参数传入，测试里可替换
  - 根文件夹已不是根文件夹、某一层已不在上一层之内、已不再是访达里的文件夹、或某一层读不出来时为 nil
- `FolderPanelLevel.id` 即层级内容的 id；滚动位置按它记录

### 目录内容（`FinderFolderContents`）

- `contentsOfDirectory`，跳过隐藏文件
  - 读目录时一次预取排序与分类要用的属性：显示名（`localizedNameKey`）、是否目录、内容类型；之后只用预取的值，不再逐项读磁盘
  - 预取的显示名与 `FileManager.displayName(atPath:)` 相同；URL 用预取的“是否目录”按 `normalizedURL(_:)` 的同一规则规整
- 按显示名排序，`localizedStandardCompare`：访达“名称”的顺序，`a2` 在 `a10` 前，不区分大小写
- 分类：
  - App bundle 是 App：点击启动、收起面板
  - 其余是文件：访达里的文件夹点击继续进入，其它用默认 App 打开、收起面板
  - URL 按加入文件夹时的同一规则规整（`normalizedURL(_:)`）
- 各项只存在于这一次展开里，不进 `FolderStore`，不建书签
- id 在同一次展开里稳定，收起时清空：
  - 按“所在层级的 id → 名称”记住分配过的 id
  - 返回时父层级是重新读出来的，缩回动画按 id 找图标、滚动位置按层级 id 恢复
  - 按所在层级与名称记而不是按完整路径：最外层的访达里的文件夹按书签跟到新位置后，里面各项与更深的层级仍解析得到
- 读取在主线程同步进行；只在进入、返回与文件夹树变化重建时读取
  - 每次读取记下起止时间（`FinderFolderReadPeriods`，系统启动以来的秒数），读取失败也记；面板隐藏时清空
  - 全局与本地鼠标监听收到按下时，按事件自己的发生时间（`NSEvent.timestamp`）判断是否落在任一次读取期间，落在其中的忽略
  - 看任一次而不只看最近一次：连点两下时，第二下可能在第一次读取结束后又进入一层、再读一次，第一次读取期间的按下排在这之后才处理到

### 网格只建看得见的格

- `FolderGridView` 只为与可见区域相交的行建单元格，上下各多一行；建过的不删
  - Flotilla 文件夹与访达里的文件夹的层级相同
- 建的时机：
  - 排版（`layout()`）：第一次显示之前，恢复的滚动位置已经生效，建的正是那里的行
  - 滚动：clip view 的 bounds 一变就同步补建，新露出的行在画出来之前就有单元格
  - AppKit 准备可见区域时（`prepareContent(in:)`）：按它给的区域补建
- 图标中心（`iconCenter(of:)`）按布局计算，不依赖单元格是否已建：返回时父层级刚重建、还没排版
- 系统外观变化时只重画已建的格；之后补建的格按建的时候的外观渲染
- “在访达中打开”同样在它那一行露出时才建

### 文件夹树变化

- 展示期间 `reload()`：访达里的文件夹的层级重新读取；第一层按那一项当前的 URL 读，它可能刚按书签跟到新位置
- 那一项已不在所在的文件夹里、或某一层读不出来：与子文件夹被删除一样收起

### “在访达中打开”

- 只有访达里的文件夹的层级有这一格，排在所有项之后；Flotilla 文件夹的层级仍按需求 4 不提供
- 点击：`NSWorkspace.open` 打开这一层的目录，由访达打开，收起面板
- 文字：新键 `panel.openInFinder`，照抄 Dock 自己的 `SHOW_IN_FINDER`（`/System/Library/CoreServices/Dock.app/Contents/Resources/<语言>.lproj/Localizable.strings`），zh-Hant 取 Dock 的 `zh_TW`；这是界面文字，照原生原样，不加中英文之间的空格

  | 键 | en | zh-Hans | zh-Hant | ja | ko |
  |---|---|---|---|---|---|
  | `panel.openInFinder` | Open in Finder | 在访达中打开 | 在Finder裡打開 | Finderで開く | Finder에서 열기 |

- 图标：运行时读 Dock 的 `openinfinder.png`，读不到时退回系统符号 `arrowshape.turn.up.right.circle`
  - 这张图是 128 × 128 pt、透明底上的黑色圆圈与弯箭头，`Bundle(path:).image(forResource:)` 一并读到 1 倍与 2 倍图
  - 没有底板；按 100 × 100 pt 画，中心与其它格的图标相同，圆圈外径 64 pt、线宽 2.3 pt（原生实测，macOS 27、tilesize 64）
  - 在 2 倍图的 256 px 上着色，不缩放；显示时由 Core Animation 线性插值缩到屏上的 200 px，与原生逐像素相差不超过 2 / 255
  - 深色：叠加（plus-lighter）到面板材质上，图标所在图层的 `compositingFilter` 取 `plusL`
    - 每个通道平时加 124 / 255，按下时加 50 / 255；图是这个灰度的 sRGB 灰
    - 实测依据：黑、灰、白、红四种底色窗上，圆圈与箭头都比材质高出 124（按下 50），超过 255 的通道截止
  - 浅色未与原生对照：按深色的量对称取叠暗（`plusD`），平时减 124 / 255、按下减 50 / 255，代码里有 `#warning`
  - macOS 15 的 behind-window popover 材质上叠加是否生效未实测，代码里有 `#warning`
  - 系统外观变化时，单元格自己换颜色与合成方式
- 名称与其它格同一样式，按下时不变
- 按下与抬起按原生，与其它格不同：
  - 按下后图标变暗，一直保持到抬起；拖出单元格、拖出面板也不恢复
  - 在哪里抬起都触发
  - 实测依据：原生按住这一格拖到标题区、拖到面板之外再抬起，Dock 都在抬起时让访达打开这一层

## 设置窗口（需求 21）

- 访达里的文件夹这一行，名称后用灰色小字显示所在位置，样式与“不在 Dock 上”相同（小号系统字体、`secondaryLabelColor`）
- 位置：父目录的路径，家目录写成 `~`（例如 `~/Documents`）；`/` 没有父目录，不显示
- Flotilla 文件夹、App、文件、文件包、网页、已删除的访达里的文件夹都不显示
- 宽度不够时先截断位置，再截断名称：位置文字的横向压缩阻力比名称低 1
- 位置在中间省略：开头的 `~/` 与离它最近的那一级目录都留着
- 书签跟随改了 URL 后，树按通知重建，位置随之更新

## 平台事实

以下都是 macOS 27、APFS 上的实测。

- 书签解析**路径优先**：原路径上换成了另一个同名项（旧的被移走）时，解析到原路径，`bookmarkDataIsStale` 为真
  - 这时按当前位置重建书签（07 的“书签过期时重建”），之后新的那个再移动，跟着新的走；App 被原地更新成新版本（旧版本移进废纸篓）正是这种情况
  - 覆盖不到的：Flotilla 没运行期间，App 先被原地更新、又被移动，而旧版本仍在（例如在废纸篓里）时，书签指向旧版本
- 资源属性：
  - 指向目录的符号链接 `isDirectory` 为假，按文件处理
  - `.app`、`.rtfd` 的 `isPackage` 为真；`/` 是目录、不是文件包
  - 在主线程上，一个 URL 读过的资源属性会缓存到主线程 run loop 下一次运行；测试里同一个 URL 先读属性、再删文件、再读，读到的仍是删除前的值
- 打开已不存在的项：`NSWorkspace.open` 用默认的 `OpenConfiguration`（`promptsUserIfNeeded` 为真）时，回调给出错误，同时 `CoreServicesUIAgent` 弹出“找不到该文件。”的提示框，有“好”与帮助按钮
  - 实测的是已删除的访达里的文件夹；已删除的文件走同一个打开方法、同一份设置，没有单独实测
- 隐私授权：第一次读“文稿”“桌面”“下载”、iCloud 云盘、外接或网络卷时，系统弹出授权框，读取等到用户回答；允许就展开，拒绝就按读不出内容处理
  - 授权框属于别的进程，用户点它的按下由全局鼠标监听收到；主线程这时被读取占住，按下排到读取结束后才处理
  - 未在屏上触发验证
- 事件时间：`NSEvent.timestamp` 与 `ProcessInfo.systemUptime` 是同一个时钟，都是开机以来不含睡眠的秒数（`CLOCK_UPTIME_RAW`）
  - 测量时开机以来睡眠过约 22 小时：`systemUptime` 与 `CLOCK_UPTIME_RAW` 相等，比含睡眠的 `CLOCK_MONOTONIC_RAW` 少约 78700 s
  - 全局鼠标监听被动收到的移动、按下、抬起：`timestamp` 比处理时的 `systemUptime` 早 1–6 ms；对应 `CGEvent.timestamp` 是同一时刻的纳秒数
- 滚动视图与文档视图：
  - 文档视图刚放进 `NSClipView` 时（`viewDidMoveToSuperview`），clip view 还没按它翻转坐标，此时的 `visibleRect` 落在网格底部，不能据此建格
  - 新建的视图 `needsLayout` 默认为真，放进窗口后由窗口的排版调用它的 `layout()`
  - 窗口显示着时，`scroll(to:)` 会同步调用文档视图的 `prepareContent(in:)`，参数是新的可见区域；没有显示的窗口里不调用
- 耗时：从读目录到新层级首屏画好，1000 项在 0.5 s 以内
  - 网格只建看得见的格：面板显示 5 行、7 列时首屏只建 42 格，建网格本身不到 1 ms
  - 读目录一次预取属性；预取里最慢的是显示名
  - 测量方式：测试进程（debug 构建）里离屏读临时目录，把网格放进 5 行高的滚动视图，排版后把可见区域画进位图；单位秒，每个条件在三到四个进程里各测三到五次，每个进程的第一次最慢
  - 首屏含建首屏的格（图标与显示名）、排版与绘制；扩展名各不相同时波动更大

  | 项数 | 读目录 | 建网格 | 首屏 | 合计 |
  |---|---|---|---|---|
  | 1000，8 种常见扩展名 | 0.10–0.18 | 0.00–0.06 | 0.05–0.23 | 0.16–0.45 |
  | 1000，扩展名各不相同 | 0.11–0.19 | 0.00 | 0.07–0.37 | 0.19–0.49 |

## 单元测试

- 需求 19（`FolderStoreItemLocationTests`，临时目录里造 `.app` 目录）：
  - App 改名、移到别的目录：URL 更新、id 不变、只发一次通知
  - 原路径换成新版本、旧版本移到别处：URL 不变、书签重建；之后移动新版本，跟到新版本的新位置
  - 没有书签的 App 项：App 还在时补上书签；已删除时不变、不发通知
  - `addItems`：App 改名后把新路径加入同一个文件夹，不重复
  - 分类：新建的 App 项带书签，书签解析回这个 App
  - 编解码：App 有、没有书签都往返一致，没有书签时 JSON 里没有 `bookmark`
- 需求 20：
  - 目录内容（`FinderFolderContentsTests`）：隐藏文件被跳过；按 `localizedStandardCompare` 排序；App、访达里的文件夹、文件包、普通文件、指向目录的符号链接各自的分类；同一次展开里 id 不变；目录已删除时抛错
    - 预取的结果与逐项单独读取一致：顺序按 `FileManager.displayName(atPath:)`（“Tool.app”排在“Tool 2.app”前）、URL 等于 `normalizedURL(_:)` 的结果、App 的判断相同
  - 导航解析（`FolderPanelNavigationTests`）：Flotilla 文件夹 → 访达里的文件夹 → 其中的子目录逐层解析；那一项被删除、目录已删除、没有权限时为 nil；那一项的 URL 变了时按新 URL 读，更深的层级照常解析
  - 读取期间的按下（`FinderFolderReadPeriodsTests`）：读取期间（含开始与结束那一刻）的按下被忽略；读取之前、之后的按下照旧处理；先后两次读取之后，第一次读取期间的按下仍被忽略
  - 格数（`FolderPanelLevelContentTests`）：访达里的文件夹为目录项数 + 1，空目录为 1；Flotilla 文件夹没有这一格；网格按格数摆出单元格
  - 网格只建看得见的格（`FolderGridViewTests`，100 项加“在访达中打开”，15 行显示 5 行）：
    - 初始只建第 0–5 行；滚到第 8 行后补建第 7–13 行，已建的保留
    - 第一次排版前恢复到第 8 行：只建第 7–13 行
    - `prepareContent(in:)` 给的区域上下各多一行建好
    - 没建的格也给出图标中心，与建好后单元格里的一致
    - “在访达中打开”在最后一行露出时才建
  - 外观（`FolderIconAppearanceTests`）：外观变化之后才滚动建出的子文件夹格，图标是变化后外观的底板
  - 单元格（`FolderGridItemViewTests`）：
    - 各项拖出单元格后恢复平常的样子，在单元格外抬起不触发
    - “在访达中打开”拖出单元格、拖出面板仍是按下的样子，在那里抬起触发一次
    - “在访达中打开”的图标：深色 `plusL`、平时 124、按下 50；浅色 `plusD`、平时 131、按下 205
    - “在访达中打开”的图标按 100 pt 摆放，中心与其它格的图标相同
- 需求 21（`FolderTreeCellViewTests`）：
  - 家目录之内的访达里的文件夹显示 `~/…`，家目录以外显示完整路径，`/` 不显示
  - 文件、文件包、已删除的访达里的文件夹、Flotilla 文件夹不显示；复用显示过位置的行视图不残留
  - 宽度不够时先截断位置，名称保持完整
  - 位置在中间省略
- 新键五种语言齐全：`LocalizationTests` 自动覆盖

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- App 跟随移动：
  - Flotilla 运行时在访达里给文件夹里的 App 改名：展开面板后是新名称，点击能启动
  - 退出 Flotilla、移动 App、再启动：tile 图标与面板都用上新位置
- 访达里的文件夹：
  - 点击后在面板里展开，标题是它的名称，有返回按钮；内容按名称排序，不含隐藏文件
  - 其中的 App 点击启动、文件点击打开，面板收起；其中的文件夹继续进入，返回时缩回被点的图标
  - 最后一格“在访达中打开”：访达打开这一层，面板收起；图标的大小、颜色与按下的样子与原生叠放一致；按下后拖出面板再抬起也触发
  - 空文件夹只有“在访达中打开”一格；已删除的访达里的文件夹点击后系统弹出“找不到”的提示，同时记日志，面板收起
  - 上千项的访达里的文件夹点开不卡顿；快速滚动（含惯性）时不出现空白格
- 设置窗口：访达里的文件夹这一行在名称后显示灰色的位置；把窗口拉窄时先截断位置，在中间省略，开头的 `~/` 与最后一级目录都看得到
