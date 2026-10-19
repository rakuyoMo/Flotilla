# 13 访达文件夹按实际外观显示

先读 [00 总览](00-overview.md) 与 01–12 十二份文档，并以 12 阶段合入后的代码为基线。本阶段交付需求 36–38：访达文件夹按访达里的实际外观显示，即标签的颜色，以及 emoji 或符号；外观变了，开着的面板、设置窗口与 Dock 上的组图标随即更新；访达文件夹在面板里展开后，其中的子文件夹同样按实际外观显示。

## 规则

### 需求 36 按实际外观显示

- 范围：组里的访达文件夹，在这些地方都按访达里的实际外观显示
  - 面板里组的层级：访达文件夹的单元格
  - 组图标的预览：面板里子组的组图标、Dock 上根组 tile 的组图标
  - 设置窗口的行
- 实际外观即 QuickLook 按 `.icon` 给的图标，与访达里看到的相同：
  - 标签的颜色：有几个带颜色的标签时取最后一个，无色的标签不算
  - 文件夹正面的 emoji 或符号
- 用 `NSWorkspace` 的图标（`FileReference.icon`）：
  - 没上色、没有 emoji 或符号的访达文件夹
  - 换过自定义图标的访达文件夹：显示自定义图标，打了颜色标签也不着色，与访达相同
  - macOS 15：访达本来就不按标签给文件夹上色，也没有 emoji 与符号
- 设置窗口里组这一行的黄色文件夹（需求 35，见 [12](12-groups.md)）不变
- 打了黄色标签的访达文件夹，在设置窗口里与组的黄色文件夹图标相同，靠名称后标出的位置（需求 21）与组的展开三角区分

### 读外观

`Sources/Flotilla/Model/FinderFolderAppearance.swift`，从访达文件夹的扩展属性同步读出：

- 标签的颜色：`com.apple.metadata:_kMDItemUserTags`，二进制 plist 的字符串数组，每项是 “名称\n颜色号”
  - 颜色号 1–7：灰 1、绿 2、紫 3、蓝 4、黄 5、红 6、橙 7
  - 0 或没写颜色号的标签无色，不算
  - 取最后一个带颜色的标签的颜色号，没有时为 nil
- emoji 与符号：`com.apple.icon.folder#S` 的原始字节，没有时为 nil
  - 只当不透明的数据比较、不解析：访达实际写入的完整格式没见过样本
- 是否换过自定义图标：`com.apple.FinderInfo` 偏移 8 起的 2 字节是大端的 Finder flags，`0x0400`（kHasCustomIcon）置位即有
- 读不到的（属性不存在、文件夹已删除、没有权限）都当作没有
- 向 QuickLook 取图的条件（`needsQuickLookIcon`）：macOS 26 及以上，没有自定义图标，且有颜色或有 emoji 与符号

### 取图与缓存

`Sources/Flotilla/Rendering/FinderFolderIconStore.swift`：

- 启动时建好（`FinderFolderIconStore.shared`，跟着 `GroupStore.shared`），在组合根注入，面板、设置窗口与 Dock 同步器共用；测试里另建实例，取图换成假实现
- 访达文件夹图标的取法只在这里：面板的单元格、子组与 tile 的组图标（`GroupIconRenderer`）、设置窗口的行（`GroupTreeCellView`）都经它
- 取图：`QLThumbnailGenerator`，只要 `.icon`
  - 按路径新建 URL 去取，不拿长期持有的 `FileReference.url`：同一个 URL 对象取过一次图，改了标签再取仍是旧颜色（见 “平台事实”）
  - 依次取下面各档，每档取位图（`cgImage`），合成一张 `NSImage`；各张位图的点尺寸都设成同一个，绘制时按像素挑出不小于所需的那张，显示时都不放大

    | 用在 | 请求的边长与倍率 | 出图 |
    |---|---|---|
    | 设置窗口的行 | 20 pt × 1、20 pt × 2 | 24 px、48 px |
    | 面板的单元格 | 101 pt × 1、101 pt × 2 | 128 px、256 px |
    | Dock 上 tile 的预览格 | 179.2 pt × 2：512 pt 的画布 × 0.35，iconset 最大一档 1024 px | 512 px |

  - 任何一档取不出（QuickLook 报错、文件夹已删除）：与缩略图一样，取不出是常态，不记日志；取图结束，照样发出通知
    - 路径上有东西：退回 `NSWorkspace` 的图标
    - 路径上现在没有东西（取图途中被改名、挪走或删除，或挪走之后赶上全部重取）：保留已有的图与版本，与下文 “核对” 的规则一致；通知让推迟了的 Dock 同步补上，输入没变，不重画
  - 每换进一张新图，这个访达文件夹的图就换一个版本（图标库里递增的整数）：外观变了、深浅外观或图标样式切换后重取，都换
  - 一次取图超过 2 s 没有结果：不再算作取图中，发出通知；之后结果到了、又没有被更新的一次取图顶替，照常换进缓存、换版本、发通知
    - 依据：各档串行取图通常在 0.3 s 内结束（见 “平台事实”）；2 s 是给 Dock 同步推迟设的上限，QuickLook 迟迟不回（如没有响应的网络卷）时，所有根组的同步不跟着一起卡住
- 对外：
  - `icon(of:)`：按 `FileReference` 同步取图，缓存里有就用，没有就是 `FileReference.icon`；不是访达文件夹的文件同样给 `FileReference.icon`
  - `iconVersion(of:)`：当前所用图的版本；用 `NSWorkspace` 的图标时为 nil
  - `isLoadingIcon(of:)`：是否还在取图；取图超过 2 s 还没有结果的不再算
  - `didUpdateIconNotification`：一个访达文件夹取图结束，或取图超过 2 s 还没有结果时在主线程发出，`userInfo` 的 `folderPathKey` 是它的路径；换上新图、退回 `NSWorkspace` 的图标、取不出都算取图结束
- `start()`：按当前的组树开始监听、取图；macOS 26 之前什么也不做

### 需求 37 外观变了随即更新

- 跟着组树走：组树变化时，取全部层级（含子组）里的访达文件夹，按路径增删监听
  - 新加入的：开始监听，读出外观，要用 QuickLook 的随即取图
  - 已在监听的：核对一次路径上的文件夹，规则与收到事件时相同（见下文 “核对”）；新文件夹放到原路径上晚于事件之后的那次核对、挪走的文件夹又没有事件来时，靠这里发现
  - 不在组树里的：停止监听、关掉描述符，丢掉缓存，还没结束的取图作废
    - 已在监听的路径上现在没有东西（文件夹被改名、挪走或删除）时，组里这一项还在，路径照样算在组树里，不停止监听
  - 同一个访达文件夹放进几个组，按路径只监听、只取一次
- 监听：每个访达文件夹一个 kqueue（`Sources/Flotilla/Model/FinderFolderWatcher.swift`），`open(_, O_EVTONLY)` 加 `DispatchSource.makeFileSystemObjectSource`，要 `.attrib`、`.delete` 与 `.rename`
  - 事件源在主队列上，回调就在主线程；释放即取消，取消时关掉描述符
  - 文件夹打不开时没有监听，外观照样读
  - 接上监听时记下路径上文件夹的身份（`Sources/Flotilla/Model/FileIdentity.swift`：`stat` 的设备号与 inode），先记身份、再打开；不用 `URL` 的资源值，它会被缓存
- 收到事件：合并约 0.2 s 内的事件后核对这个路径
- 核对：读路径上现在的身份
  - 路径上没有东西（文件夹被改名、挪走或删除）：什么也不改，监听、身份、外观与图都保持原样，不通知
    - 组里这一项的 URL 随后由 `GroupStore` 按书签跟到新位置（见 [07](07-file-items-refinements.md) 的 “按书签找当前位置”），那时旧路径从组树里拿掉、新路径接上，照常处理
    - 挪走的文件夹之后再有事件，同样走到这里，不按旧路径读出 “没有外观”：否则改一次名，根组预览里的访达文件夹先退回 `NSWorkspace` 的图标、跟到新位置后再换回，stub 改写两次、Dock 重启两次
  - 有东西、身份与接上监听时记下的不同（含那时没有、现在有了）：按 “换了文件夹” 处理
  - 身份相同：重读外观
    - 外观没变（只是权限、时间戳等其它属性变了）：什么也不做，不取图、不通知
    - 变了、要用 QuickLook：重新取图；旧图留到新图取到再换，期间仍按旧图显示
    - 变了、不用 QuickLook（去掉了颜色与 emoji、符号，或换上了自定义图标）：丢掉旧图，退回 `NSWorkspace` 的图标，发出通知
- 被更新的一次取图顶替、或已从组树里拿掉之后才到的结果，丢掉
- 换了文件夹：同一路径上换成了另一个文件夹，如访达里拷贝同名文件夹时选了 “替换”、删掉后在原处新建同名的
  - 丢掉旧的监听，在这个路径上重新接上监听、重读外观
  - 要用 QuickLook 的：重新取图，旧图留到新图取到再换
  - 不用的：丢掉旧图，退回 `NSWorkspace` 的图标，发出通知
- 系统深浅外观（KVO 观察 `NSApplication.shared.effectiveAppearance`）、图标样式（`NSWorkspaceIconAppearanceConfigurationDidChangeNotification`，见 [01](01-foundation.md)）变了：要用 QuickLook 的全部重取
- QuickLook 的结果在它自己的队列上，回到主线程再动缓存
- 面板（`GroupGridView`）开着时收到通知：
  - 已建的格里，这个访达文件夹换上当前的图；之后才建的格建的时候就取当前的图
  - 预览里有这个访达文件夹的子组，重画它的组图标；预览里没有它的子组不重画
- 设置窗口（`GroupTreeViewController`）开着时收到通知：已经创建出来的行里，这个访达文件夹的行按当前的图重新填充
  - 不重建树：选中、展开与正在编辑的组名都不受影响
- Dock 同步（`DockTileSynchronizer`，见 [02](02-dock-tile.md)）：
  - 图标的输入加上预览里各访达文件夹所用图的版本（`GroupIconInputs.previewFinderFolderIconVersions`），与 `previewItems` 一一对应
    - 预览里的访达文件夹换进新图（外观变了、深浅外观或图标样式切换后重取），输入变了：重画、按像素比对；在容差内就不改写 stub、Dock 不重启，图标变了就改写 stub、换 `GUID`、Dock 重启一次
    - 只换了预览之外的访达文件夹的图，输入不变：不重画、不改写，Dock 不重启
  - 订阅 `didUpdateIconNotification`，与组树的变更一样走 0.5 s 的防抖
  - 根组的预览里有还在取图的访达文件夹时，推迟这次同步，等取完的通知再同步；QuickLook 取不出也算取完
    - 目的：不先按 `NSWorkspace` 的蓝色文件夹改写 stub、取到后再按实际外观改写，让 Dock 连着重启两次
    - 最多推迟 2 s：一次取图到 2 s 还没有结果，发出的通知让推迟了的同步补上，按当前的图（旧图，或 `FileReference.icon`）渲染；结果之后到了，再按新图同步一次
    - 刚加进组的上色访达文件夹：组树变化先安排一次同步，取图结束再安排一次；取图在防抖间隔内结束时两次合成一次，晚于防抖间隔时前一次同步推迟
  - 启动时同理：`applicationWillFinishLaunching` 在 `updateItemLocations()` 之后、Dock 同步开始之前调用 `FinderFolderIconStore.shared.start()`，第一次同步等预览里的访达文件夹取完，同样最多等 2 s
  - Flotilla 没运行时变的外观：启动后第一次同步本来就渲染并按像素比对，不另做处理

### 需求 38 访达文件夹层级里的子文件夹

- 面板里访达文件夹的层级（见 [08](08-finder-folder-stacks.md) 的 “文件的内容缩略图”）里，建格时读子文件夹的外观
  - 先看 URL 是不是目录：读目录时已按是不是目录规整，文件不多读资源属性与扩展属性
  - macOS 26 之前不读，子文件夹照旧请求 `.thumbnail`
- 要用 QuickLook 的子文件夹：与文件的内容缩略图一样，格在看得见附近时请求，滚出时取消，网格离开窗口时全部取消
  - 请求 `.icon`，不是 `.thumbnail`；边长 101 pt（`GroupPanelMetrics.iconSize`），倍率取面板所在屏幕的
  - 画满 101 pt 的图标画布，与其它格的图标一样大；不像缩略图那样放进 100 pt 的画布居中
  - 按路径新建 URL 去取，理由同上
- 不监听：回到这一层时重建网格，照常重新读
- 其余的子文件夹与文件照旧：请求 `.thumbnail`，子文件夹生成不出缩略图，保持图标

## 平台事实

macOS 27.0.1 实测。

### 取图

- `NSWorkspace.icon(forFile:)` 与 `URLResourceValues.effectiveIcon`：标签的颜色、emoji 与符号一律不画，给默认的蓝色文件夹
- `QLThumbnailGenerator` 按 `.icon` 取，给系统画好的文件夹：
  - 七种标签颜色各自正确
  - 多个标签时取最后一个带颜色的；无色标签不算，`[红, 无色]` 与 `[无色, 红]` 都是红
  - `com.apple.icon.folder#S` 里的 emoji 与符号画在文件夹正面
- 换过自定义图标（`NSWorkspace.setIcon`）的文件夹：两种取法都给自定义图标，打了颜色标签也不着色
- 出图的像素边长取不小于请求的标准档：20 pt × 1 → 24 px，20 pt × 2 → 48 px，101 pt × 1 → 128 px，101 pt × 2 → 256 px，179 pt × 2 → 512 px，512 pt × 2 → 1024 px
- 结果的 `nsImage` 总按 2 倍出图：20 pt × 1 的请求，`cgImage` 是 24 px，`nsImage` 里的位图却是 48 px；要按倍率取位图，用 `cgImage`
- 一张 `NSImage` 里放几张像素不同、点尺寸相同的位图，绘制时挑出像素不小于所需的最小那张：20 pt 的 1 倍、2 倍取 24、48 px，101 pt 的 1 倍、2 倍取 128、256 px，179 pt 的 2 倍取 512 px
- 耗时：某种外观、某种尺寸第一次取 17–51 ms；同一种之后再取约 0–1 ms；5 档串行取图通常在 0.3 s 内结束
- 完成回调在 QuickLook 自己的队列上

### 扩展属性

- 标签：`com.apple.metadata:_kMDItemUserTags`，二进制 plist 的字符串数组，每项是 “名称\n颜色号”；0 或没写颜色号为无色，QuickLook 不着色
- `URLResourceValues.labelNumber` 读的是 Finder 信息里旧的标签位：只写了标签扩展属性时是 0，不能用来判断颜色
- 用 `NSURL.setResourceValue(["绿色"], forKey: .tagNamesKey)` 打标签，写进去的是 “绿色\n0”（无色）：测试里直接写扩展属性
- emoji 与符号：`com.apple.icon.folder#S`，内容是 JSON，如 `{"emoji":"🍕"}`、`{"sym":"star.fill"}`
  - 按这两种写法写入，QuickLook 照画；同样的数据写成二进制 plist 时 QuickLook 不画
- 自定义图标：`com.apple.FinderInfo` 共 32 字节，偏移 8 起的 2 字节是大端的 Finder flags，`0x0400`（kHasCustomIcon）置位即有；`URLResourceValues.customIcon` 对这样的文件夹给 nil，不能用

### 旧颜色

- 同一个 `URL` 对象取过一次图，改了标签再取，仍是旧颜色：过了 12 s、换了请求尺寸、改了目录的修改时间都一样
- 下面三种情况都能取到新颜色：
  - 对这个 URL 调 `removeAllCachedResourceValues()`
  - 按路径新建一个 `URL`
  - 主线程的 run loop 转过一圈
- QuickLook 自己不按文件缓存：另一个进程、新建的 URL 立刻拿到新颜色

### 察觉变化

- 文件夹 `open(_, O_EVTONLY)` 加 `DispatchSource.makeFileSystemObjectSource`：
  - 改标签扩展属性、`tagNames`、`labelNumber`，删标签，写 `com.apple.icon.folder#S`，都在 1 ms 内收到 `.attrib`
  - 改一次 `tagNames` 会在约 15 ms 内连着来 3 个 `.attrib`
  - 同一卷内改名后，旧的描述符照样收到事件；改名本身是 `.rename`
  - 文件夹里新建文件是 `.write`，不是 `.attrib`
  - 删除文件夹来的是 `.delete`，同卷内挪走、改名来的是 `.rename`，两者都不带 `.attrib`
- `.attrib` 也会因权限、时间戳等其它属性的变化而来，不一定是外观变了
- 事件源不取消就释放：之后不再回调，但取消处理不执行，描述符一直开着

### 系统版本

- macOS 26 起访达才按颜色标签给文件夹上色（见 12 的 “平台事实”）；`com.apple.icon.folder#S` 也是 macOS 26 起才有

## 单元测试

- 依赖 macOS 26 取图与监听的用例按 `.enabled(if: FinderFolderAppearance.isSupported)` 启用：测试目标里的扩展，`#available(macOS 26, *)`；之前的系统上 `needsQuickLookIcon` 恒为 false，图标库的 `start()` 什么也不做
- 读外观（`FinderFolderAppearanceTests`，临时目录里建文件夹、直接写扩展属性）：两种系统上都跑，`needsQuickLookIcon` 的期望按系统版本给出
  - 没有扩展属性：没有颜色、emoji 与符号，不用 QuickLook
  - 无色标签（颜色号 0、只有名称）：没有颜色
  - 单个颜色：取它的颜色号，用 QuickLook
  - 多个颜色取最后一个；颜色在前、无色在后时仍是那个颜色
  - 只有 `com.apple.icon.folder#S`：原样记下，用 QuickLook
  - 有自定义图标：打了红色标签也不用 QuickLook
  - 已删除的文件夹：当作没有
- 取图（`FinderFolderIconStoreTests`，真的 QuickLook）：
  - 打了红色标签的：设置窗口与面板的 1 倍、2 倍下，文件夹正面中央是红色
  - 没上色的、换过自定义图标的：不取图，与 `NSWorkspace` 的图标逐像素相同
  - 只有 emoji 的：取图，与 `NSWorkspace` 的图标不同
  - 走真的 QuickLook 的用例（这里的，以及 `GroupTreeCellViewTests`、`FileThumbnailLoaderTests` 的）最多等约 10 s：CI 上 QuickLook 冷启动加各档串行请求，2 s 可能不够
  - 经图标库取图的，等到图换上为止，不按通知的次数等：取图慢过 2 s 时，先到的是 “不再等” 的通知
- 监听（`FinderFolderIconStoreTests`，取图换成假实现，标签照常写在临时目录的文件夹上）：
  - 取完之前还在取图，取完之后不是
  - 取图迟迟不回：2 s 后不再算取图中、发出通知；结果之后到了照常换上，再通知一次
  - 子组里的访达文件夹同样监听、取图
  - 改了标签：1 s 内换上新图、发出通知，图的版本换成新的
  - 去掉标签：退回 `NSWorkspace` 的图标，同样通知
  - 只改了无关的属性（`chmod`）：不重取图、不通知，图还是原来那张
  - 从组树里拿掉之后：再改标签不取图、不通知
  - 原路径上换了文件夹（挪走后在原处放了打着别的颜色标签的新文件夹）：换上新文件夹的图，之后改新文件夹的标签照样察觉
  - 改名挪走、原路径上没有东西：不通知，图与版本都不变；挪走的文件夹再有属性变化、组树因别的改动变了，都一样。按书签跟到新位置之后，旧路径停止监听，新路径接上、取到同样外观的图
  - 挪走之后在原处放了新文件夹，挪走的那个没有事件来：组树一变就核对出来，接上新文件夹的监听、换上它的图
  - 取不出：退回 `NSWorkspace` 的图标，也算取完，照样通知
  - 挪走之后赶上全部重取、取图途中被挪走，结果取不出：取图结束、照样通知，已有的图与版本保留
  - 等通知按轮数而不按时钟（测试目标里的 `Polling.wait`，`GroupGridDragTests` 等落定也用它）：整套测试一起跑时，回到主线程的任务排在其它测试后面，会晚到几秒
- 监听器（`FinderFolderWatcherTests`）：释放之后改扩展属性不再回调，打开着这个文件夹的描述符随之关掉；文件夹被删除、改名都回调
- 图标的输入（`GroupIconInputsTests`）：预览里的访达文件夹换了图，输入不同；外观没变、只是重取换进新图（模拟样式切换），同样不同；预览之外的换了图，输入相同
- 设置窗口：
  - `GroupTreeCellViewTests`：打了红色标签的访达文件夹，这一行的图标在 1 倍、2 倍下都是红色（真的 QuickLook）
  - `GroupTreeViewControllerTests`：收到通知后这一行换上新图；选中、展开与正在编辑的组名都不变
- 面板：
  - `GroupGridFinderFolderIconTests`：网格建好之后才取到图，访达文件夹的格换上新图；预览里有它的子组重画，预览格里画的正是新图；只有 App 的子组不重画
  - `GroupGridThumbnailTests`：访达文件夹的层级里，上了色的、有 emoji 的子文件夹请求 `.icon`，没上色的子文件夹与文件请求 `.thumbnail`；结果换上发起请求的那一格
  - `FileThumbnailLoaderTests`：子文件夹的 `.icon` 画满 101 pt 的图标画布，与 QuickLook 按 101 pt 给的图标逐像素相同（真的 QuickLook）
- 不写会走到 `DockTileSynchronizer.synchronize()`、`start()` 或 `DockPreferences.restartDock` 的测试：`restartDock` 按进程名结束真实的 Dock；同步器的推迟与订阅由屏上验收覆盖
- 只在临时目录里建文件夹、打标签；不在 `~/Library/Application Support/Flotilla` 写东西

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 要上屏看的：
  - 访达里给组里的访达文件夹打上颜色标签、换颜色、去掉标签、加上 emoji 或符号：面板、设置窗口与 Dock 上组图标的预览都与访达里一样，1 s 内换上
  - 真实 Dock 上的重启次数：
    - 运行时改了根组预览里访达文件夹的颜色：stub 改写一次、tile 换 `GUID`、Dock 重启一次
    - 改了不在任何预览里的访达文件夹：stub 不改写，Dock 不重启
    - 把上色的访达文件夹加进根组的预览：Dock 只重启一次，不先出现蓝色文件夹
    - 退出 Flotilla，改了预览里访达文件夹的颜色再启动：Dock 只重启一次
  - 受保护位置（“文稿” “桌面” “下载” 等）里的访达文件夹：启动时读外观、开始监听，会不会比面板里第一次打开它更早弹出隐私授权框
  - 切换浅色、深色外观与 “图标与小组件样式” 后，上色的访达文件夹换成对应的样子
  - 访达文件夹在面板里展开后，上了色、有 emoji 或符号的子文件夹与访达里一样，大小与其它格的图标相同
  - 打了黄色标签的访达文件夹与组的黄色文件夹，在设置窗口里靠名称后的位置与展开三角区分
- 不变的：
  - 没上色的、换过自定义图标的访达文件夹，各处与 `NSWorkspace` 的图标逐像素相同
  - 设置窗口里组这一行仍是黄色文件夹
  - macOS 15 上不读外观、不监听、不向 QuickLook 取图，访达文件夹各处都是 `NSWorkspace` 的图标
