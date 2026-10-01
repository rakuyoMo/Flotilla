# 08 App 跟随移动与更新、访达里的文件夹展开、位置与隐藏文件

先读 [00 总览](00-overview.md) 与 01–07 七份文档，并以 07 阶段合入后的代码为基线。本阶段交付需求 19–23：

- 需求 19：App 移动或改名后，这一项自动跟到新位置
- 需求 20：访达里的文件夹在面板里像 Dock 叠放那样展开，网格末尾有“在访达中打开”
- 需求 21：设置窗口里，访达里的文件夹这一行在名称后标出所在位置
- 需求 22：App 更新后，文件夹里的这一项仍打开装好的那一份
- 需求 23：设置里的开关，访达里的文件夹在面板里展开时显示隐藏文件

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
- 不提供排序或显示方式的选择，不监听磁盘变化（00：“初版不给用户更多选择”）；是否显示隐藏文件是唯一的开关，见需求 23

### 需求 22 App 更新后不跟丢

- App 更新之后，这一项仍打开装好的那一份：在需求 19 的书签跟随之上多三条，只对 App；文件仍按 07 跟进废纸篓
- 不跟进废纸篓：书签解析到废纸篓里（用户的 `~/.Trash`，或其它卷上的 `.Trashes`）时，这一项的位置与书签都不变
  - 废纸篓里的 App 启动不了，见“平台事实”
  - 更新时旧版本移进废纸篓之后，新版本放回原路径：解析按路径优先，这时解析到新版本，书签过期，照常重建
  - 判断用 `FileManager.getRelationship(_:of:in:toItemAt:)`：目录 `.trashDirectory`，域传空，结果为 `.contains`；抛错按不在废纸篓里处理
- 记下 bundle id：`AppReference.bundleIdentifier`
  - 加入时（`FolderItem(url:title:)`）从 bundle 的 `Info.plist` 读，读不到为 nil
  - 旧数据没有这个字段，解码为 nil；原路径上的 App 还在时补上，与补建书签同一时机
  - 跟到新位置、重建书签时按当前位置重读；读不到就沿用旧值
  - 每次都从磁盘读（`CFBundleCopyInfoDictionaryInDirectory`）：`Bundle(url:)` 按路径缓存，见“平台事实”
- 按 bundle id 找回：书签解析失败、或解析到废纸篓里，且有 bundle id 时，问 Launch Services 要这个 bundle id 的 App（`NSWorkspace.urlForApplication(withBundleIdentifier:)`）
  - 这两种情况下原路径上一定没有东西：解析按路径优先
  - 拿到的 App 存在、不在废纸篓里：跟过去，URL 按 `normalizedURL(_:)` 规整，按新位置建书签，id 不变
  - 拿不到、已不存在或在废纸篓里：保持原样
  - 书签记录的卷没有挂载：不找回，保持原样；卷挂回来照常按书签解析
    - App 放在外接卷上、卷没挂载时，书签解析失败、原路径上也没有东西，但 App 仍在那个卷上
    - 判断（`AppReference.isVolumeMounted(recordedIn:)`）：从书签里读出卷的 UUID（`URL.resourceValues(forKeys:fromBookmarkData:)`），在已挂载的卷（`FileManager.mountedVolumeURLs`）里找同一个 UUID；书签里读不到卷的 UUID 时按没挂载处理，见“平台事实”
  - 没有书签的旧数据：原路径上没有东西又有 bundle id 时，同样按 bundle id 找回
- 实现：`AppReference.relocatedApp(applicationURL:isVolumeMounted:)` 先按共用的 `relocated()` 跟随，再按上面三条取舍
  - 位置、书签与 bundle id 都不用改时为 nil，`FolderStore` 只在有变化时提交
  - Launch Services 的查询与卷是否挂载的判断是参数，默认走 `NSWorkspace` 与 `isVolumeMounted(recordedIn:)`，测试里换成假实现；`FolderStore` 不传它们
- 调用时机与需求 19 相同；覆盖到哪些更新方式见“平台事实”

### 需求 23 显示隐藏文件

- 设置窗口通用区一行：左列“访达里的文件夹：”，右列复选框“显示隐藏文件”，默认不勾，见 01 的“通用区”
  - `Preferences.showsHiddenFiles`，`UserDefaults` 键 `showsHiddenFiles`
  - 切换它不发 `Preferences.didChangeNotification`：`DockTileSynchronizer` 监听这个通知，收到就重画 stub 图标，可能改写 stub、重启 Dock，而这个开关与 tile 的图标无关
  - 面板读访达里的文件夹时取当时的值；切换要点设置窗口，面板这时已经收起，不监听设置的变化
- 文字：两个新键；用词与 `Localizable.strings` 已有的一致，ja 的“不可視ファイル”与 ko 的“… 보기”取自访达自己的界面文字

  | 键 | en | zh-Hans | zh-Hant | ja | ko |
  |---|---|---|---|---|---|
  | `general.finderFolders` | Finder folders: | 访达里的文件夹： | Finder 裡的檔案夾： | Finderのフォルダ： | Finder 폴더: |
  | `general.showHiddenFiles` | Show hidden files | 显示隐藏文件 | 顯示隱藏檔案 | 不可視ファイルを表示 | 숨김 파일 보기 |

- 只影响访达里的文件夹的层级：Flotilla 的文件夹的层级、设置窗口的树、Dock 上 tile 的图标都不变，“在访达中打开”那一格也不变
- 打开后与访达的 ⌘⇧. 一致（实测见“平台事实”）：
  - 显示：资源属性 `isHiddenKey` 为真的项都显示，包括以 `.` 开头的文件与目录、带 `hidden` 标志的文件；只有名为 `.DS_Store`、`.localized` 的仍不显示
  - 半透明：隐藏的项图标与名称的不透明度都是 0.5（`FolderPanelMetrics.hiddenItemOpacity`）；有内容缩略图的隐藏文件同样换上缩略图、同样半透明
  - 排序不变：隐藏的项与其它项混在一起，按显示名 `localizedStandardCompare` 排，开头的 `.` 也参与比较
  - 按下：照旧压暗，与半透明叠加
- 是否隐藏在读目录时一并预取，不逐项再读；`FinderFolderContents.hiddenItemIDs` 记下本次展开里隐藏的项，网格据此把它们的单元格设成半透明
- 图标与访达一致：名称以“.”开头、没有扩展名的文件与访达里的文件夹，`FileReference.icon` 按资源属性 `contentTypeKey` 的类型取（`NSWorkspace.icon(for:)`），取不到类型时照旧
  - `icon(forFile:)` 把名称开头的“.”后面当成扩展名，`.a`、`.zip` 会是归档、压缩包的图标，`.bundle` 目录会是 bundle 的图标（实测见“平台事实”）；按类型取，前两个是 `public.data` 的空白文稿，后一个是文件夹
  - 照旧用 `icon(forFile:)`：有扩展名的（`.甲.txt`、`.swiftlint.yml`）、名称不以“.”开头的、符号链接、文件包；符号链接这样才带替身箭头，文件包按类型取是带“?”的文稿
  - 粘贴过自定义图标的这类文件与文件夹显示类型的图标，不显示自定义图标
  - 面板、设置窗口的树、Dock 上 tile 的预览都用 `FileReference.icon`，三处一致，不随“显示隐藏文件”变化

## 数据模型

```swift
/// 带书签的本地引用：App 与文件共用同一套规则
protocol BookmarkedReference {
    var id: UUID { get }
    var url: URL { get }
    var bookmark: Data? { get }

    /// 同一项换成给定位置与书签后的引用，id 不变
    func replacingLocation(with url: URL, bookmark: Data?) -> Self
}

struct AppReference: BookmarkedReference, Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL

    /// 建不起来时为 nil，只按路径找
    let bookmark: Data?

    /// 读不到时为 nil
    let bundleIdentifier: String?
}
```

- `BookmarkedReference` 的扩展提供 `normalizedURL(_:)` 与 `relocated()`，`AppReference` 与 `FileReference` 共用，规则见 07
  - `replacingLocation(with:bookmark:)`：文件只换位置与书签；App 还按新位置重读 bundle id，读不到时沿用原来的
  - App 在 `relocated()` 之上另有 `relocatedApp(applicationURL:isVolumeMounted:)`，见需求 22
- `AppReference` 的书签与文件的完全相同：
  - `FolderItem(url:title:)` 新建 App 项时带上 `url.bookmarkData()`，建不起来为 nil
  - JSON 键 `bookmark`，nil 时不写；没有这个键的数据照常解码，书签为 nil
- bundle id 的 JSON 键 `bundleIdentifier`，nil 时不写；没有这个键的数据照常解码，bundle id 为 nil

  ```json
  { "type": "app", "id": "…", "url": "file:///Applications/Safari.app/", "bookmark": "Ym9va…", "bundleIdentifier": "com.apple.Safari" }
  ```

- `FolderStore.updateItemLocations(in:)` 按书签更新 App 项与文件项：App 项用 `relocatedApp()`，文件项用 `relocated()`；`FolderTreeViewController.updateItemLocations()` 同理

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

- `contentsOfDirectory`，按需求 23 的设置跳过或显示隐藏文件；显示时 `.DS_Store`、`.localized` 仍不显示
  - 读目录时一次预取排序、分类与半透明要用的属性：显示名（`localizedNameKey`）、是否目录、内容类型、是否隐藏；之后只用预取的值，不再逐项读磁盘
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

### 文件的内容缩略图

- 范围：只在访达里的文件夹的层级，网格里的文件显示内容缩略图，与原生叠放一致
  - 由层级内容决定（`FolderPanelLevelContent.showsFileThumbnails`），面板据此把 `FileThumbnailLoader` 交给网格；没有它的网格里文件显示图标
  - Flotilla 的文件夹的层级、设置窗口、Dock 上 tile 的图标都不变，文件仍是 `FileReference.icon`
  - App 与子目录照旧显示图标；生成不出缩略图的（`.zip` 等没有缩略图扩展的类型、已删除、没有权限）保持图标
  - 生成不出是常态，不当错误记日志
- 何时换上：单元格建好时先显示图标；格在看得见附近时请求缩略图，生成后回到主线程换上，只落到发起请求的那一格
  - 看得见附近：可见区域上下各多一行，与“网格只建看得见的格”建格的范围相同
  - 只为看得见附近的格保留请求：排版与每一步滚动时，滚出这个范围、请求还没完成的格取消请求；还没换上缩略图的格回到这个范围时重新请求；已经换上的保持原样，不再请求
  - 原因：QuickLook 按请求的先后生成；滚过的格的请求取消了，快速滚过上千项后，看得见的格才不必排在它们后面（耗时见“平台事实”）
  - `prepareContent(in:)` 为预绘区域提前建的格先只建格，进入看得见附近时才请求
  - 首屏：排版时建出的格随即请求
  - 网格离开窗口（离开这一层的转场结束、面板收起、文件夹树变化重建）时，取消还没完成的请求，之后到达的结果丢掉
- 画法：`QLThumbnailGenerator`，`iconMode = true`，只要 `.thumbnail`
  - 画布 100 pt（`FolderPanelMetrics.fileThumbnailSize`），`scale` 取面板所在屏幕的倍数
  - 100 pt 的画布居中放进 101 pt 的图标画布，中心与图标相同
  - 圆角、亮边与投影都来自 QuickLook 的图标模式
  - 按下：与其它格一样把图乘以 0.475；投影是纯黑的，乘完不变
- 原生实测（macOS 27、深色、tilesize 64）：
  - 有缩略图：`.txt`（空文件是一张白纸）、`.md`、`.rtf`、`.rtfd`、`.pdf`、`.png`、`.jpg`；指向 `.txt` 的符号链接显示目标的缩略图，没有替身角标
  - 显示图标：`.zip` 是通用文稿图标，子目录是文件夹图标
  - 大小与位置：保持比例缩放进 88 × 88 pt 的框（长边 88 pt），中心在格内 (64, 56)，与图标中心相同
    - `.txt`、`.md` 66 × 88；`.rtf`、`.rtfd` 68.5 × 88；A4 的 `.pdf` 62.5 × 88；1600 × 1000 的 `.png` 88 × 55；700 × 1100 的 `.png` 56 × 88
  - 装饰：四角圆角，半径约 3.5 pt；图片内侧一圈 1 pt 的亮边，约等于白色 25% 叠在图片上，是缩略图自身的一部分；没有卷角
  - 投影：黑色，向下偏约 1 pt，下方延伸约 5 pt；紧贴下边处不透明度约 0.18，左右紧贴处 0.13，上边紧贴处 0.08
  - 按下：缩略图连同亮边 RGB × 0.475，投影与名称不变
  - 原生在进入的转场第一帧（约 33 ms）就已是缩略图；Flotilla 先显示图标，请求到结果的耗时见“平台事实”
- 实测依据：QuickLook 按 100 pt 画布、2 倍、图标模式生成的缩略图叠在同样的灰底上，与原生的外接框（含与不含投影）、中心与投影剖面逐项相同；Flotilla 单元格离屏画出的结果也相同
  - 按 101 pt 画布生成时，页面长边是 89 pt
  - 屏上对照：同一个目录在 Flotilla 面板与原生叠放里，按格子对齐、不平移逐像素比，13 个有缩略图的文件在灰、黑两种底上图标区最大差都是 2，外接框逐项相同；按下 `.txt`、`.png` 最大差也是 2

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
  - 浅色：叠暗（plus-darker）到面板材质上，`compositingFilter` 取 `plusD`
    - 每个通道平时减 127 / 255，按下时减 194 / 255；图是 1 减去这个量的 sRGB 灰
    - 实测依据：黑、灰、白、红四种底色窗上，圆圈与箭头都比材质低 127（按下 194），低于 0 的通道截止；大小、位置与形状与深色相同
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

## 隐私授权框的用途说明

- 第一次读受保护的位置时系统弹出授权框（见“平台事实”），框里显示 Flotilla 写明的用途：读取访达里的文件夹的内容，在面板里展开
- 每个会弹授权框的位置一个键，六个键用同一句话；授权框的标题已写明 App 名与位置，说明里不重复位置

  | 键 | 位置 |
  |---|---|
  | `NSDocumentsFolderUsageDescription` | 文稿 |
  | `NSDesktopFolderUsageDescription` | 桌面 |
  | `NSDownloadsFolderUsageDescription` | 下载 |
  | `NSFileProviderDomainUsageDescription` | iCloud 云盘等文件提供方 |
  | `NSRemovableVolumesUsageDescription` | 外接卷 |
  | `NSNetworkVolumesUsageDescription` | 网络卷 |

- 英文写在 `Info.plist`（开发语言 `en`）；五个 `.lproj` 各有一张 `InfoPlist.strings`，键与 `Info.plist` 相同
  - 用词与 `Localizable.strings` 一致：zh-Hant 用“Finder”“檔案夾”

  | 语言 | 文案 |
  |---|---|
  | en | Flotilla needs to read the contents of Finder folders to expand them in its panel on the Dock. |
  | zh-Hans | Flotilla 需要读取访达里文件夹的内容，才能在 Dock 上的面板里展开它们。 |
  | zh-Hant | Flotilla 需要讀取 Finder 裡檔案夾的內容，才能在 Dock 上的面板裡展開它們。 |
  | ja | FinderのフォルダをDockのパネルで展開するには、Flotillaがフォルダの内容を読み込む必要があります。 |
  | ko | Finder 폴더를 Dock의 패널에서 펼치려면 Flotilla가 폴더의 내용을 읽어야 합니다. |

## 平台事实

以下都是 macOS 27、APFS 上的实测。

- 书签解析**路径优先**：原路径上换成了另一个同名项（旧的被移走）时，解析到原路径，`bookmarkDataIsStale` 为真
  - 这时按当前位置重建书签（07 的“书签过期时重建”），之后新的那个再移动，跟着新的走
- App 更新：用与仓库相同的 `BookmarkedReference`、`AppReference` 模拟各种更新方式，每一步按 Flotilla 的做法刷新一次
  - `renamex_np` 原子交换（Sparkle 2）、两步改名（旧版本先挪到临时目录）、旧版本移进废纸篓再放新版本、原地换 `Contents`、删除后拷贝、`FileManager.replaceItemAt`：刷新落在更新完成之后时，记录的路径都不变，书签过期后重建，点击打开新版本
  - 刷新落在“旧版本已挪走、新版本还没放进来”的空档里时，书签只找得到临时目录或废纸篓里的旧版本；按路径优先，之后也只会解析回那里，旧版本删掉后解析失败。需求 22 的不跟进废纸篓、按 bundle id 找回针对的正是这种情况
    - 现实的例子：手动先把旧版本拖进废纸篓、再装新版本，中间展开过文件夹；`brew upgrade --cask` 先把旧版本挪回 Caskroom、解压新版本，最后放进 `/Applications` 并删掉旧版本
  - Flotilla 没运行期间，App 先被原地更新、又被移动，而旧版本还在废纸篓里：书签只找得到废纸篓里的旧版本，需求 22 按 bundle id 找到新版本的新位置
  - 覆盖不到的：刷新落在空档里、旧版本挪到废纸篓以外的地方且一直没有删掉时，这一项留在旧版本上
- 废纸篓里的 App 启动不了：`NSWorkspace.openApplication` 失败，`NSCocoaErrorDomain` 3587，“could not be launched because it is in the Trash”
- 废纸篓的判断（`FileManager.getRelationship(_:of: .trashDirectory, in:toItemAt:)`）：
  - 域传空时，`~/.Trash` 与其它卷上 `.Trashes/<uid>` 里的项都是 `.contains`；只传 `.userDomainMask` 时认不出其它卷的
  - 其它卷上不在废纸篓里的项，域传空时抛错（不支持）；不存在的路径同样抛错
  - 临时目录里自造的 `.Trash` 不算废纸篓
  - 其它卷用 `hdiutil` 建的 APFS 映像实测
- 书签记录的卷没有挂载（`hdiutil` 建的映像挂在 `/Volumes` 下实测）：
  - 按 `[.withoutUI, .withoutMounting]` 解析失败，错误是 `NSCocoaErrorDomain` 4（文件不存在），与卷挂着、文件已删除时相同，从错误分不出卷没挂载
  - `URL.resourceValues(forKeys:fromBookmarkData:)` 照样读得出书签记录的卷：卷的 URL、UUID、名称；卷没挂载时，`mountedVolumeURLs` 里没有这个 UUID
  - 卷挂回原位置：照常解析到原路径，书签不过期
  - 书签按 UUID 认卷：同一个卷挂到别的位置，照样解析到新位置；同名的另一个卷挂在原位置时，原路径上没有东西就解析失败，有同名的项就按路径优先解析到它、书签过期
  - APFS、HFS+、FAT32、exFAT 卷的书签都记着卷的 UUID；网络卷未实测
  - 启动卷的系统卷与数据卷在 Foundation 里是 `/` 一个卷：临时目录、`/System/Applications` 里的项，书签记录的卷 URL 都是 `/`，UUID 都是数据卷的；`mountedVolumeURLs`（`options` 传空）里 `/` 的 UUID 也是它，不单独列出 `/System/Volumes/Data`
  - 用仓库里的 `BookmarkedReference`、`AppReference` 走一遍：卷挂着、卸载、挂回原位置时 `relocatedApp` 都返回 nil；挂着时删掉卷上的 App，按 bundle id 跟到另一份
- `Bundle(url:)` 按路径缓存：原地把 bundle 换成另一个 `CFBundleIdentifier` 后，读到的仍是旧值；`CFBundleCopyInfoDictionaryInDirectory` 读到新值
- 资源属性：
  - 指向目录的符号链接 `isDirectory` 为假，按文件处理
  - `.app`、`.rtfd` 的 `isPackage` 为真；`/` 是目录、不是文件包
  - 在主线程上，一个 URL 读过的资源属性会缓存到主线程 run loop 下一次运行；测试里同一个 URL 先读属性、再删文件、再读，读到的仍是删除前的值
- 访达的 ⌘⇧.（图标视图、深色）：
  - 显示 `isHiddenKey` 为真的全部项：以 `.` 开头的文件与目录、带 `hidden` 标志的文件；只有 `.DS_Store`、`.localized` 仍不显示
  - 带 `hidden` 标志的 `Icon\r` 显示为 `Icon?`，与预取的显示名相同
  - 隐藏的项半透明：名称按底色算不透明度 0.499；图标的斜率 0.50，垫在比底色略亮的中性灰上，按底色折算 0.53–0.54
  - 有内容缩略图的隐藏文件同样显示缩略图、同样半透明
  - 排序与按显示名 `localizedStandardCompare` 完全一致：隐藏的项与其它项混排，开头的 `.` 当普通字符参与比较
  - 访达按下即选中，没有单独的按下样子；隐藏的项选中后图标仍半透明
  - ⌘⇧. 不写 `com.apple.finder` 的 `AppleShowAllFiles`
- 名称以“.”开头、没有扩展名的项的图标（探针在临时目录里造各种名称，逐一对照 `icon(forFile:)` 与按类型取的图标）：
  - `URL.pathExtension` 与 `NSString.pathExtension` 都为空；资源属性的类型是 `public.data`，可执行的是 `public.unix-executable`，目录是 `public.folder`
  - `NSWorkspace.icon(forFile:)` 却把开头的“.”后面当成扩展名：
    - 文件：`.a`、`..a` 是归档图标，`.z`、`.zip` 是压缩包，`.json`、`.pdf`、`.png`、`.txt`、`.mp3`、`.gitignore` 是对应类型或认领这个扩展名的 App 给的图标，名为 `.app` 的文件是带“?”的文稿；可执行的 `.sh` 是 shell 脚本的图标，按类型取是可执行文件的图标
    - 普通目录：`.rtfd`、`.pages`、`.key`、`.bundle`、`.framework`、`.pkg`、`.photoslibrary` 是对应文稿或 bundle 的图标；它们的 `isPackage` 为假，Launch Services 的种类是“文件夹”，QuickLook 的 `.icon` 表示也是文件夹；访达 ⌘⇧. 下名为 `.bundle`、`.pkg`、`.rtfd`、`.app` 的普通目录都是文件夹图标
    - 不是已知扩展名的（`.中`、`.env`、`.git`、`.config`）与按类型取的相同
  - 资源属性 `effectiveIconKey` 与 `icon(forFile:)` 相同
  - 符号链接：类型是 `public.symlink`，`icon(forFile:)` 是目标的图标加替身箭头，同样按名称当扩展名：名为 `.zip` 的链接是压缩包加箭头，指向 `.a` 的链接是归档加箭头
  - 带 bundle 标志的目录：`isPackage` 为真，类型是 `com.apple.package`，按类型取是带“?”的文稿
  - 粘贴过自定义图标：`icon(forFile:)` 与 `effectiveIconKey` 给出自定义图标，按类型取给出类型的图标；`customIconKey` 读出来是 nil
  - 访达 ⌘⇧. 下 `.a`、`.z`、`.zip`、`.json`、`.gitignore`、`.中` 都是带“?”的通用文稿；没有扩展名的普通文件（如 `n`）同样带“?”，按 `public.data` 取的是不带“?”的空白文稿
- `contentsOfDirectory` 的 `.skipsHiddenFiles` 跳过以 `.` 开头的项，也跳过带 `hidden` 标志的项
- 打开已不存在的项：`NSWorkspace.open` 用默认的 `OpenConfiguration`（`promptsUserIfNeeded` 为真）时，回调给出错误，同时 `CoreServicesUIAgent` 弹出“找不到该文件。”的提示框，有“好”与帮助按钮
  - 实测的是已删除的访达里的文件夹；已删除的文件走同一个打开方法、同一份设置，没有单独实测
- 隐私授权：第一次读“文稿”“桌面”“下载”、iCloud 云盘、外接或网络卷时，系统弹出授权框，读取等到用户回答；允许就展开，拒绝就按读不出内容处理
  - 授权框里有 Flotilla 的用途说明，见“隐私授权框的用途说明”
  - 键与授权服务的对应取自 `/System/Library/PrivateFrameworks/TCC.framework/Support/tccd` 的字符串，授权框文案在同一框架的 `Localizable.loctable`
  - iCloud 云盘是文件提供方扩展（`com.apple.fileprovider-nonui`），授权框属于 `kTCCServiceFileProviderDomain`，对应 `NSFileProviderDomainUsageDescription`
    - 这个服务的授权框文案是 `“%@”想要访问受“%@”管理的文件。`，后一处是文件提供方的名称
  - 授权框由 `UserNotificationCenter` 显示，属于别的进程
    - 发起读取的进程结束后，授权框仍留在屏上
    - 用户点它的按下由全局鼠标监听收到；主线程这时被读取占住，按下排到读取结束后才处理
  - 用途说明的显示在屏上实测过：用带同样 `Info.plist` 与 `InfoPlist.strings` 的临时 App 读“文稿”触发
    - 授权框标题是 `“TCCProbe”想访问“文稿”文件夹中的文件。`，标题下是按系统语言取的那一句（系统语言为简体中文，显示 zh-Hans 那句）
  - Flotilla 自己点“允许”“不允许”之后的展开与回退未在屏上验证
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
  - 预取再加上是否隐藏（需求 23）没有可测的差别：release 构建的独立进程读 1000 个文件，加与不加都约 0.03 s
  - 测量方式：测试进程（debug 构建）里离屏读临时目录，把网格放进 5 行高的滚动视图，排版后把可见区域画进位图；单位秒，每个条件在三到四个进程里各测三到五次，每个进程的第一次最慢
  - 首屏含建首屏的格（图标与显示名）、排版与绘制；扩展名各不相同时波动更大

  | 项数 | 读目录 | 建网格 | 首屏 | 合计 |
  |---|---|---|---|---|
  | 1000，8 种常见扩展名 | 0.10–0.18 | 0.00–0.06 | 0.05–0.23 | 0.16–0.45 |
  | 1000，扩展名各不相同 | 0.11–0.19 | 0.00 | 0.07–0.37 | 0.19–0.49 |

- QuickLook 缩略图（`QLThumbnailGenerator`，图标模式，画布 100 pt、2 倍）：
  - 完成回调在 QuickLook 自己的队列上，不在主线程
  - 返回的 `nsImage` 就是画布大小（100 × 100 pt），只带一张 2 倍的位图（200 × 200 px）
  - 目录与 `.zip` 给出错误 `QLThumbnailErrorDomain` 0，已删除的文件给出 `NSCocoaErrorDomain` 4，都在几毫秒内返回；空 `.txt` 也有缩略图
  - `cancel(_:)` 之后完成回调照样会来，给出错误 `QLThumbnailErrorDomain` 5（已取消）；取消一个没发出过的请求什么也不发生
  - 投影的像素预乘后 RGB 都是 0，只有不透明度
  - 耗时：独立进程同时请求 15 个从没生成过缩略图的新文件（12 个 `.txt`、2 个 `.png`、1 个 `.pdf`），三轮里第一个结果 8–10 ms 到达，中位 24–32 ms，最后一个 40–49 ms；同一批再请求，全部到达 6–27 ms
  - 1000 个 `.txt` 的目录开着缩略图，按上面的方式测四次：读目录到首屏画好 0.07–0.14 s，首屏的缩略图在排版后 22–32 ms 内全部换上；一行一行滚到底，每一步同步补建（含发出请求）不超过 10 ms
  - 按请求的先后生成：独立进程一次请求 1000 个从没生成过缩略图的 `.txt`，最后 42 个 16.1–16.6 s 才到
    - 发出后随即取消前 958 个：最后 42 个 0.14–0.30 s 内到齐，与只请求这 42 个（0.10–0.27 s）相当；取消 958 个在调用线程上共 44 ms
    - 已经交给生成的请求取消后照样生成出图：下面快速滚到底的测量里，1000 个 `.txt` 取消的约 915 个请求中 13–30 个、400 张 `.png` 取消的约 321 个中 15–17 个仍生成出图
  - 快速滚到底之后，看得见的格的缩略图全部到位要多久（单位秒）：
    - 测量方式：测试进程（debug 构建）离屏读一个从没生成过缩略图的目录，网格放进 5 行高的滚动视图，每 15 ms 滚 400 pt 到底，不绘制；从停在底部量到看得见的格全部换上；每次换一个新目录
    - 首屏：同一进程里，排版后首屏的缩略图全部换上的耗时

    | 目录 | 建格即请求、不取消 | 只保留看得见附近的请求 | 首屏 |
    |---|---|---|---|
    | 1000 个 `.txt` | 11.3–19.6（6 次） | 0.63–1.33（9 次） | 0.32–0.94 |
    | 400 张 1600 × 1000 的 `.png` | 6.1–6.3（3 次） | 0.75–0.88（3 次） | 0.69–0.89 |

    - 只保留看得见附近的请求时，到底之后等的是 QuickLook 生成这一屏新文件，与首屏相当
    - 一行一行滚到底（同一时段、同一方式），每一步同步补建加请求、取消：只保留看得见附近的请求时中位 9.9–12.3 ms、p90 15.7–17.8 ms；建格即请求、不取消时中位 14.1–15.0 ms、p90 20.9–22.3 ms（各两次）

  - 屏上实测（release 构建，面板 5 行、7 列；屏上的时刻从 60 帧/秒的录屏逐帧读，请求与生成的时刻取自 QuickLook 缩略图服务的统一日志）：
    - 第一次进入一个目录，文件都从没生成过缩略图：
      - 请求在松开后几十毫秒内全部发出，之后的时间都在 QuickLook 生成；屏上换上比 QuickLook 交出结果晚 10–60 ms
      - 从转场开始到首屏全部换上，随文件数与 QuickLook 当时的负载，在约 50 ms 到 0.62 s 之间
      - 12 个 `.txt`、2 张 `.png`（三次）：全部换上约 50 ms 到 0.33 s；两张图在转场第 2 帧换上（两次）
      - 首屏 35 个 `.txt`：只有这 35 个文件的目录中位约 0.42 s（7 次，0.35–0.47 s）；1000 个文件的目录一次 0.62 s
    - 快速滚到底：每 15 ms 发一次 400 像素的滚轮事件，共 60 次；从网格停下量到看得见的格全部换上（单位秒）

      | 目录 | 新文件 | 同一目录再滚一次（缩略图已生成过） |
      |---|---|---|
      | 1000 个 `.txt` | 0.72–0.78（两个目录） | 0.17 |
      | 400 张 1600 × 1000 的 `.png` | 0.28 | 0.10 |

      - 滚动途中与停下后逐帧查，没有空白格，也没有落错格
    - 滚回：
      - 滚回中段：这些格滚过时请求已取消，网格停下后先显示图标，0.43–0.55 s 内全部换上
      - 回到顶部：这些格已换上缩略图，网格停下的第一帧就是缩略图

## 单元测试

- 需求 19（`FolderStoreItemLocationTests`，临时目录里造 `.app` 目录）：
  - App 改名、移到别的目录：URL 更新、id 不变、只发一次通知
  - 原路径换成新版本、旧版本移到别处：URL 不变、书签重建；之后移动新版本，跟到新版本的新位置
  - 没有书签的 App 项：App 还在时补上书签；已删除时不变、不发通知
  - `addItems`：App 改名后把新路径加入同一个文件夹，不重复
  - 分类：新建的 App 项带书签，书签解析回这个 App
  - 编解码：App 有、没有书签都往返一致，没有书签时 JSON 里没有 `bookmark`
- 需求 20：
  - 目录内容（`FinderFolderContentsTests`）：默认跳过隐藏文件；按 `localizedStandardCompare` 排序；App、访达里的文件夹、文件包、普通文件、指向目录的符号链接各自的分类；同一次展开里 id 不变；目录已删除时抛错
    - 预取的结果与逐项单独读取一致：顺序按 `FileManager.displayName(atPath:)`（“Tool.app”排在“Tool 2.app”前）、URL 等于 `normalizedURL(_:)` 的结果、App 的判断相同
  - 导航解析（`FolderPanelNavigationTests`）：Flotilla 文件夹 → 访达里的文件夹 → 其中的子目录逐层解析；那一项被删除、目录已删除、没有权限时为 nil；那一项的 URL 变了时按新 URL 读，更深的层级照常解析
  - 读取期间的按下（`FinderFolderReadPeriodsTests`）：读取期间（含开始与结束那一刻）的按下被忽略；读取之前、之后的按下照旧处理；先后两次读取之后，第一次读取期间的按下仍被忽略
  - 格数（`FolderPanelLevelContentTests`）：访达里的文件夹为目录项数 + 1，空目录为 1；Flotilla 文件夹没有这一格；网格按格数摆出单元格
    - 只有访达里的文件夹的层级显示文件的内容缩略图
  - 文件的内容缩略图（`FolderGridThumbnailTests`，生成缩略图换成假实现，不经 QuickLook）：
    - 访达里的文件夹的层级：文件先显示图标，缩略图生成后换上；后请求的先到时，各自落在发起请求的那一格
    - Flotilla 的文件夹的层级：同一个文件不请求缩略图，保持图标
    - 子目录与生成不出缩略图的文件保持图标；App 不请求缩略图
    - 网格离开窗口时，还没完成的请求全部取消，之后晚到的结果不换上
    - 滚动（100 个文件，15 行显示 5 行）：
      - 请求还没完成的格滚出看得见附近：请求取消，之后晚到的结果不换上
      - 还没换上缩略图的格滚回来：重新请求，结果落到这一格
      - 已经换上缩略图的格滚出再滚回：不再请求
      - 快速滚到底：还没完成的请求只剩看得见附近的格，按格的先后排列
      - 预绘区域提前建的格不请求，滚进看得见附近才请求
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
    - “在访达中打开”的图标：深色 `plusL`、平时 124、按下 50；浅色 `plusD`、平时 128、按下 61
    - “在访达中打开”的图标按 100 pt 摆放，中心与其它格的图标相同
- 需求 21（`FolderTreeCellViewTests`）：
  - 家目录之内的访达里的文件夹显示 `~/…`，家目录以外显示完整路径，`/` 不显示
  - 文件、文件包、已删除的访达里的文件夹、Flotilla 文件夹不显示；复用显示过位置的行视图不残留
  - 宽度不够时先截断位置，名称保持完整
  - 位置在中间省略
- 需求 22（`AppReferenceRelocationTests`，临时目录里造带 `CFBundleIdentifier` 的 bundle；废纸篓用真的，用例结束时删掉自己放进去的项；Launch Services 换成假实现）：
  - 刷新落在空档里、旧版本在废纸篓：不跟进去；新版本放回原路径后，记录的仍是原路径，书签按新版本重建，之后新版本移动时跟着它走
  - 刷新落在空档里、旧版本挪到临时目录：先跟过去；旧版本删掉后按 bundle id 跟回新版本
  - 更新后又被移动、旧版本在废纸篓：按 bundle id 找到新版本的新位置
  - Launch Services 给不出、给出的在废纸篓里或已不存在：保持原样，返回 nil
  - App 在原处：返回 nil，不问 Launch Services
  - 卷没挂载（判断换成假实现；删掉 App 让书签解析失败）：Launch Services 给出别处同一个 bundle id 的 App 也保持原样，返回 nil；卷挂回来、原路径上又有这个 App 时，照常解析到原路径，不问 Launch Services
  - 卷挂着、原路径上的 App 删掉：按 bundle id 找回；卷是否挂载用真的判断，临时目录所在的启动卷判为挂载着
  - bundle id：旧数据在 App 还在时补上；没有书签、原路径上没有东西的旧数据按 bundle id 找回；跟到新位置时重读，读不到时沿用旧值
  - 文件移进废纸篓仍跟过去
  - 分类：新建的 App 项带 bundle id，没有 `Info.plist` 时为 nil
  - 编解码：bundle id 往返后保留，nil 时 JSON 里没有 `bundleIdentifier`；没有这个键的旧数据照常解码
- 需求 23：
  - 目录内容（`FinderFolderContentsTests`）：默认跳过以 `.` 开头的文件与目录、带 `hidden` 标志的文件；打开后它们都读出来并标为隐藏，`.DS_Store` 与 `.localized` 仍不显示；关掉后再读又被跳过
  - 网格（`FolderGridHiddenItemTests`）：隐藏的项半透明，普通的项不透明；按下隐藏的项照样压暗，半透明不变
  - 设置（`PreferencesTests`）：默认不显示；切换不发 `Preferences.didChangeNotification`
  - 设置窗口（`GeneralSettingsViewControllerTests`）：复选框反映当前的值，点击后写回；五种语言下窗口最窄时，各行控件不被压窄、不越出通用区
  - 图标（`FileReferenceIconTests`，临时目录里造文件；图标按 32 pt、2 倍栅格化后逐字节比较）：
    - `.a`、`.zip` 与按 `public.data` 取的相同；`.bundle` 目录与按文件夹类型取的相同
    - 照旧按 `icon(forFile:)`：粘贴过自定义图标的 `.甲.txt` 与 `n` 显示自定义图标；名为 `.链接` 的符号链接；带 bundle 标志的 `.包`
- 新键五种语言齐全：`LocalizationTests` 自动覆盖
- 隐私授权框的用途说明（`PrivacyUsageDescriptionTests`）：
  - `Info.plist` 有上表六个键，值非空
  - 五张 `InfoPlist.strings` 都能解析、没有空值，键集合与 `Info.plist` 里的用途说明键相同

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- App 跟随移动：
  - Flotilla 运行时在访达里给文件夹里的 App 改名：展开面板后是新名称，点击能启动
  - 退出 Flotilla、移动 App、再启动：tile 图标与面板都用上新位置
- 访达里的文件夹：
  - 点击后在面板里展开，标题是它的名称，有返回按钮；内容按名称排序，默认不含隐藏文件
  - 其中的 App 点击启动、文件点击打开，面板收起；其中的文件夹继续进入，返回时缩回被点的图标
  - 最后一格“在访达中打开”：访达打开这一层，面板收起；图标的大小、颜色与按下的样子与原生叠放一致；按下后拖出面板再抬起也触发
  - 空文件夹只有“在访达中打开”一格；已删除的访达里的文件夹点击后系统弹出“找不到”的提示，同时记日志，面板收起
  - 上千项的访达里的文件夹点开不卡顿；快速滚动（含惯性）时不出现空白格
  - 文件的内容缩略图：每个文件有没有缩略图与原生叠放一致；缩略图的大小、位置与原生相差不超过 1 pt，圆角、亮边与投影一致，按下压暗、投影不变
    - Flotilla 的文件夹里的同一个文件仍是图标
    - 进入子目录再返回、收起再展开，缩略图照常换上；上千项的目录滚动途中缩略图陆续换上，没有落错格
- 隐私授权框：第一次读受保护的位置时，授权框里显示 Flotilla 的用途说明，语言跟随系统
- 设置窗口：访达里的文件夹这一行在名称后显示灰色的位置；把窗口拉窄时先截断位置，在中间省略，开头的 `~/` 与最后一级目录都看得到
- App 更新：
  - Flotilla 运行时，先把文件夹里的 App 拖进废纸篓、展开一次面板，再放入新版本：再展开面板，点击启动的是新版本
  - 退出 Flotilla，原地更新 App 后再把新版本移到别处（旧版本留在废纸篓），再启动：tile 图标与面板都用上新版本的新位置
- 显示隐藏文件：
  - 默认不勾：访达里的文件夹展开后不含隐藏文件
  - 勾上后再展开：以 `.` 开头的文件与目录、带 `hidden` 标志的文件出现，图标与名称半透明，顺序与访达 ⌘⇧. 一致；`.DS_Store`、`.localized` 不出现；有缩略图的隐藏文件显示半透明的缩略图；按下压暗
  - 切换开关时 Dock 不重启，tile 不变
  - 五种语言下把窗口拉到最窄，这一行完整显示
