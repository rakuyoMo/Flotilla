# 06 组里的文件与网页

先读 [00 总览](00-overview.md) 与 01–05 五份文档，并以 05 阶段合入后的代码为基线。本阶段交付需求 14：组里除了 App 与子组，还可以放文件与网页，像 Dock 右侧区域那样。

## 规则

- 组里的项在 App、子组之外新增两种：
  - **文件**：访达里 App 以外的任何文件，包括 `.rtfd`、`.pages` 这类在访达里显示成单个文件的文件包
    - 访达文件夹（不是文件包的目录，包括卷）同样是文件，见 [07](07-file-items-refinements.md)
    - `.webloc` 这类网址文件按文件处理
  - **网页**：scheme 为 `http` 或 `https` 的网址，连同加入时浏览器给出的网页标题（可能没有）
- 加入途径与 App 现有的拖放对齐：
  - 设置窗口：从访达拖文件、从浏览器拖网页到组的行上；“添加文件…” 见 07，“添加网页…” 见 09
  - Dock tile：从访达拖文件到 tile 上；网页不能拖到 tile 上
  - “添加 App…” 保持只选 App
- 文件带书签，移动或改名后跟到新位置（见 07）；找不到文件时，点击后系统按 `NSWorkspace` 的默认设置弹出 “找不到” 的提示，同时记日志，面板收起
- 网页只记网址与加入时的标题，不抓取网页标题或网站图标
- 同一个组里，同类且 URL 相同的项只出现一次；网页只比网址，标题不同也算同一个网页。
- 文件与网页和 App 一样只能放在组里，不能放在根层级。
- tile 与面板里子组图标的预览（需求 2）按顺序取前几项，只跳过子组，App、文件与网页都算，见 07。
- 本阶段不新增本地化文字；“添加文件…” 与预览数量的文字见 07。

## 数据模型

```swift
/// 对一个文件的引用
struct FileReference: BookmarkedReference, Codable, Hashable, Identifiable {
    let id: UUID

    /// 文件包、访达文件夹与卷是目录 URL，其余是文件 URL
    let url: URL

    /// 书签，见 07
    let bookmark: Data?
}

/// 对一个网页的引用
struct WebPageReference: Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL

    /// 浏览器给出的，或 “添加网页…” 里填写、自动获取到的标题（见 09）；都没有时为 nil
    let title: String?
}

enum GroupItem: Codable, Hashable, Identifiable {
    case app(AppReference)
    case group(Group)
    case file(FileReference)
    case webPage(WebPageReference)
}
```

- `FileReference`：`displayName` 为 `FileManager.default.displayName(atPath:)`，`icon` 为 `NSWorkspace.shared.icon(forFile:)`，与 `AppReference` 相同；名称以 `.` 开头、没有扩展名的文件与访达文件夹按内容类型取，见 08 的需求 23。
  - 访达文件夹的层级里，面板网格另给文件换上内容缩略图，见 08 的 “文件的内容缩略图”
- `WebPageReference`：
  - `displayName`：有标题用标题，没有时用 `url.absoluteString`
  - `icon`：与 Dock 右侧网页 tile 相同，取 `/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns`（蓝色地球）；所有网页共用，只加载一次；读不到时退回网址文件（`com.apple.web-internet-location`）的图标
    - 实测（macOS 27）：Dock 右侧网页 tile 的图标与 `BookmarkIcon.icns` 逐像素比对一致；`NSWorkspace` 按 `com.apple.web-internet-location`、`com.apple.internet-location`、`public.url` 取到的图标都不是它
- JSON 与 App、子组一样平铺，类型标签为 `file` 与 `webPage`：

  ```json
  { "type": "file", "id": "…", "url": "file:///Users/…/报告.pdf" }
  { "type": "webPage", "id": "…", "url": "https://example.com/", "title": "Example Domain" }
  ```

  - 没有标题时不写 `title` 键
  - 只有 `app`、`folder` 的旧数据照常解码

### 分类

要加入组的 URL 只在一处分类，设置窗口的拖入、“添加 App…” “添加文件…” “添加网页…”（见 09）与拖到 tile 上的项共用：

```swift
extension GroupItem {
    /// 为要加入组的 URL 建一个新项：App bundle 为 App，其余存在的一切为文件，http、https 网址为网页；
    /// 不存在的文件与其它网址返回 nil
    init?(url: URL, title: String?)
}
```

- 本地 URL：
  - 路径先标准化（`standardizedFileURL`），同一个 App 或文件不因 URL 写法不同（结尾斜杠、`..`）而重复加入
  - 读不到资源属性（文件不存在）时为 nil
  - App 的判断用 `AppReference.isApplicationBundle(_:)`，按目录 URL 记录
  - 其余目录（文件包、访达文件夹、卷）是文件，按目录 URL 记录，见 07
  - 其余都是文件，按文件 URL 记录
- 网址：scheme 不区分大小写，只接受 `http` 与 `https`
  - 标题去掉首尾空白，空串视为没有
- 实测：空的 `.app` 目录内容类型是 `com.apple.application-bundle`。

### `GroupStore`

- `addItems(_ items: [GroupItem], to groupID: UUID)`：
  - 把 App、文件与网页追加到组末尾，一次提交，只发一次变更通知
  - 与该组已有的项、以及本批已加入的项同类且 URL 相同时跳过
  - 子组只由 `addSubgroup(named:to:)` 新建，传进来就忽略
  - 传入的项由 `GroupItem(url:title:)` 新建，id 不与树里已有的项重复
- `canMove`：App、文件与网页都只能放进组，不能放在根层级。

## 设置窗口

- 从外部拖入，与拖 App 相同：只能落在组的行上，追加到末尾，高亮整个组的行。
  - outline view 在已有的类型之外注册 `.URL`（`public.url`）
  - 逐个剪贴板项取 URL：先 `public.file-url`，没有再 `public.url`
  - 网页标题取同一剪贴板项的 `public.url-name`
  - 实测（macOS 27）：从 Chrome 地址栏左侧的 “查看网站信息” 按钮拖出网址，剪贴板只有一项，其中 `public.url` 是网址、`public.url-name` 是网页标题
  - 交给 `GroupItem(url:title:)`；一个能加入的项都没有时不接收，例如只拖了已不存在的文件或 `ftp:` 网址
- 文件行、网页行显示图标与 `displayName`，名称不可编辑。
- 拖动排序、移入其它组、删除，规则与 App 行相同；文件行与网页行不能作为落点。
- “添加 App…” 保持只选 App，选中的 URL 经 `GroupItem(url:title:)` 后交给 `addItems`；“添加文件…” 见 07，“添加网页…” 见 09。

## 面板

- 网格里文件与网页和 App 一样显示图标与 `displayName`。
- 点击：
  - 文件用默认 App 打开，网页用默认浏览器打开：`NSWorkspace.shared.open(_:configuration:completionHandler:)`
  - 访达文件夹在面板里展开，见 [08](08-finder-folder-stacks.md)
  - 打开失败时记日志，写法与 App 启动失败相同
  - `OpenConfiguration` 用默认设置（`promptsUserIfNeeded` 为真），打开失败时系统另外提示用户，例如找不到文件时弹出 “找不到”
  - 随即收起面板，与需求 9 对 App 的处理一致
- App 仍用 `openApplication(at:configuration:)` 启动。

## Dock tile

### stub 声明可接收文件

- stub 的 `CFBundleDocumentTypes` 保留接收 App 的一项（见 05），追加一项：
  - `CFBundleTypeName = File`
  - `CFBundleTypeRole = Viewer`
  - `LSHandlerRank = None`
  - `LSItemContentTypes = [public.data, com.apple.package]`
- `LSHandlerRank` 必须是 `None`：实测（macOS 27）`Alternate` 会让 stub 出现在访达的 “打开方式” 里。
- 实测（macOS 27）：
  - 从访达把 `.txt`、`.pdf`、`.rtfd`、`.webloc` 与未知扩展名的文件拖到 tile 上，tile 压暗为放置目标，松手后以 `odoc` 拉起 stub，`application(_:open:)` 收到文件 URL；前台 App 仍是访达
  - `.app` 仍被接收
  - stub 不出现在访达的 “打开方式” 里，各类文件的默认打开 App 不变
  - 访达文件夹同样高亮并拉起 stub：声明了 `public.data` 或 `com.apple.package`，Dock 就对文件夹一并接收，只有声明具体类型时才按类型判断；它作为文件加入，见 07
  - 改写 Info.plist 并 `lsregister -f` 之后，不重启 Dock，下一次拖动就按新声明判断
- stub 的 Info.plist 与期望不同时，下一次同步按 02 的逐字节比对改写它（连同可执行文件）并重新登记。

### 请求

- stub 由拖放启动时打开 `flotilla://folder/<id>/items?path=<路径>&path=<路径>`：每个被拖的项一个 `path`，取值为它的 POSIX 路径；stub 只会收到文件 URL
- `DockTileRequest`：

  ```swift
  enum DockTileRequest: Equatable {
      /// 展开或收起根组的面板
      case toggleGroup(UUID)

      /// 把拖到 tile 上的这些项加入根组
      case addItems(groupID: UUID, fileURLs: [URL])

      init?(url: URL)
  }
  ```

  - `path` 用 `URL(filePath:)` 还原：stub 送来的文件包、App 与文件夹路径以 `/` 结尾，还原成目录 URL；分类时还会再规整
  - 没有任何 `path` 时为 nil
- `AppDelegate.application(_:open:)`：`.addItems` 先确认 id 是根组，再逐个经 `GroupItem(url:title:)` 分类后交给 `addItems`；已不存在的文件在分类时被略过。

### 网页

- 网页不能拖到 tile 上，只能拖进设置窗口。
- Dock 只在 stub 提供服务（`NSServices`）时接收网址的拖放，那会在 “系统设置 › 键盘 › 键盘快捷键 › 服务” 里给每个根组加一项。

## 单元测试

- 编解码：文件、网页（有、没有标题）往返一致；没有标题时 JSON 里没有 `title`；只有 `app`、`folder` 的旧 JSON 照常解码
- `GroupItem(url:title:)`，用临时目录：
  - 普通文件为文件；文件包（`.rtfd` 目录）为文件，按目录 URL 记录；`.app` 目录为 App
  - 不存在的路径为 nil；访达文件夹、卷根目录见 07
  - 同一个 App 的不同 URL 写法得到同一个 URL
  - `http`、`https` 为网页并带标题；标题去掉首尾空白，只有空白时为 nil；`ftp:`、`mailto:` 为 nil
- `GroupStore.addItems`：
  - 同类同 URL 去重，包括已有的与同一批里的
  - App、文件、网页混在一批只发一次变更通知
  - 子组被忽略
  - 文件与网页不能移到根层级，能在组之间移动
- 设置窗口的数据源（用只带剪贴板的 `NSDraggingInfo` 替身，不开窗口）：
  - 带 `public.url` 与 `public.url-name` 的剪贴板落在组的行上，加入带标题的网页
  - 文件 URL 加入文件；一个能加入的都没有时不接收，见 07
  - 落在文件行或网页行上不接收
- 组图标的预览见 07
- `DockTileRequest`：`items` 路由的解析，路径含空格、中文与 URL 的保留字符，文件包、App 路径以 `/` 结尾时还原成目录 URL；多个 `path` 保持顺序；没有 `path` 的 URL 为 nil
- stub 的 Info.plist：含上述 File 一项，`LSHandlerRank` 为 `None`；已登记的 stub 改写 Info.plist 并重新登记后，能接收 App 与普通文件

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 设置窗口：
  - 从访达把 `.txt`、`.pdf` 拖到组的行上，加入；拖访达文件夹的结果见 07
  - 从 Chrome 把网址拖到组的行上，加入并带标题
  - 文件行、网页行显示图标与名称，双击不进入编辑；能拖动排序、移入其它组，不能拖到根层级
- 面板：
  - 显示文件与网页
  - 点文件用默认 App 打开并收起；点网页用默认浏览器打开并收起
- Dock tile：
  - 从访达把 `.txt`、`.pdf` 拖到 tile 上：tile 高亮，松手后加入该组；前台 App 保持前台
  - 拖访达文件夹的结果见 07
  - 把 App 拖到 tile 上照常加入
  - 访达的 “打开方式” 里没有 stub
- tile 与面板里子组图标的预览见 07
- 退出重开 Flotilla 后数据仍在
