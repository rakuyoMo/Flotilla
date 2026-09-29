# 06 文件夹里的文件与网页

先读 [00 总览](00-overview.md) 与 01–05 五份文档，并以 05 阶段合入后的代码为基线。本阶段交付需求 14：文件夹里除了 App 与子文件夹，还可以放文件与网页，像 Dock 右侧区域那样。

## 规则

- 文件夹里的项在 App、子文件夹之外新增两种：
  - **文件**：访达里 App 以外的任何文件，包括 `.rtfd`、`.pages` 这类在访达里显示成单个文件的文件包
    - 普通文件夹（不是文件包的目录，包括卷）不接收
    - `.webloc` 这类网址文件按文件处理
  - **网页**：scheme 为 `http` 或 `https` 的网址，连同加入时浏览器给出的网页标题（可能没有）
- 与 App 一样只记路径或网址：
  - 不跟踪文件的移动或改名；文件不在了，点击时记日志
  - 不抓取网页标题或网站图标
- 同一个文件夹里，同类且 URL 相同的项只出现一次；网页只比网址，标题不同也算同一个网页。
- 文件与网页和 App 一样只能放在文件夹里，不能放在根层级。
- tile 与面板里子文件夹图标的预览（需求 2）只取 App 图标，跳过子文件夹、文件与网页；“文件夹图标内显示的 App 图标数量”的设置不变。
- 不新增本地化文字。

## 数据模型

```swift
/// 对一个文件的引用
struct FileReference: Codable, Hashable, Identifiable {
    let id: UUID

    /// 文件包是目录 URL，其余是文件 URL
    let url: URL
}

/// 对一个网页的引用
struct WebPageReference: Codable, Hashable, Identifiable {
    let id: UUID
    let url: URL

    /// 浏览器没给标题，或给的是空白时为 nil
    let title: String?
}

enum FolderItem: Codable, Hashable, Identifiable {
    case app(AppReference)
    case folder(Folder)
    case file(FileReference)
    case webPage(WebPageReference)
}
```

- `FileReference`：`displayName` 为 `FileManager.default.displayName(atPath:)`，`icon` 为 `NSWorkspace.shared.icon(forFile:)`，与 `AppReference` 相同。
- `WebPageReference`：
  - `displayName`：有标题用标题，没有时用 `url.absoluteString`
  - `icon`：网址文件（`com.apple.web-internet-location`）的图标
- JSON 与 App、子文件夹一样平铺，类型标签为 `file` 与 `webPage`：

  ```json
  { "type": "file", "id": "…", "url": "file:///Users/…/报告.pdf" }
  { "type": "webPage", "id": "…", "url": "https://example.com/", "title": "Example Domain" }
  ```

  - 没有标题时不写 `title` 键
  - 只有 `app`、`folder` 的旧数据照常解码

### 分类

要加入文件夹的 URL 只在一处分类，设置窗口的拖入、“添加 App…”与拖到 tile 上的 App 共用：

```swift
extension FolderItem {
    /// 为要加入文件夹的 URL 建一个新项：App bundle 为 App，其余文件与文件包为文件，http、https 网址为网页；
    /// 普通文件夹、不存在的文件与其它网址返回 nil
    init?(url: URL, title: String?)
}
```

- 本地 URL：
  - 路径先标准化（`standardizedFileURL`），同一个 App 或文件不因 URL 写法不同（结尾斜杠、`..`）而重复加入
  - 读不到资源属性（文件不存在）时为 nil
  - App 的判断用 `AppReference.isApplicationBundle(_:)`，按目录 URL 记录
  - 其余目录：`isPackage` 为真时是文件，按目录 URL 记录；否则是普通文件夹，为 nil
  - 其余都是文件，按文件 URL 记录
- 网址：scheme 不区分大小写，只接受 `http` 与 `https`
  - 标题去掉首尾空白，空串视为没有
- 实测：新建的空 `.rtfd` 目录 `isPackage` 为真；空的 `.app` 目录内容类型是 `com.apple.application-bundle`；卷根目录 `isPackage` 为假。

### `FolderStore`

- `addApps(_:to:)` 改为 `addItems(_ items: [FolderItem], to folderID: UUID)`：
  - 把 App、文件与网页追加到文件夹末尾，一次提交，只发一次变更通知
  - 与该文件夹已有的项、以及本批已加入的项同类且 URL 相同时跳过
  - 子文件夹只由 `addSubfolder(named:to:)` 新建，传进来就忽略
  - 传入的项由 `FolderItem(url:title:)` 新建，id 不与树里已有的项重复
- `canMove`：App、文件与网页都只能放进文件夹，不能放在根层级。

## 设置窗口

- 从外部拖入，与拖 App 相同：只能落在文件夹行上，追加到末尾，高亮整个文件夹行。
  - outline view 在已有的类型之外注册 `.URL`（`public.url`）
  - 逐个剪贴板项取 URL：先 `public.file-url`，没有再 `public.url`
  - 网页标题取同一剪贴板项的 `public.url-name`
  - 交给 `FolderItem(url:title:)`；一个能加入的项都没有时不接收，例如只拖了普通文件夹
- 文件行、网页行显示图标与 `displayName`，名称不可编辑。
- 拖动排序、移入其它文件夹、删除，规则与 App 行相同；文件行与网页行不能作为落点。
- “添加 App…”保持只选 App，选中的 URL 经 `FolderItem(url:title:)` 后交给 `addItems`。

## 面板

- 网格里文件与网页和 App 一样显示图标与 `displayName`。
- 点击：
  - 文件用默认 App 打开，网页用默认浏览器打开：`NSWorkspace.shared.open(_:configuration:completionHandler:)`
  - 打开失败时记日志，写法与 App 启动失败相同
  - 随即收起面板，与需求 9 对 App 的处理一致
- App 仍用 `openApplication(at:configuration:)` 启动。

## 单元测试

- 编解码：文件、网页（有、没有标题）往返一致；没有标题时 JSON 里没有 `title`；只有 `app`、`folder` 的旧 JSON 照常解码
- `FolderItem(url:title:)`，用临时目录：
  - 普通文件为文件；文件包（`.rtfd` 目录）为文件，按目录 URL 记录；`.app` 目录为 App
  - 普通文件夹、卷根目录与不存在的路径为 nil
  - 同一个 App 的不同 URL 写法得到同一个 URL
  - `http`、`https` 为网页并带标题；标题去掉首尾空白，只有空白时为 nil；`ftp:`、`mailto:` 为 nil
- `FolderStore.addItems`：
  - 同类同 URL 去重，包括已有的与同一批里的
  - App、文件、网页混在一批只发一次变更通知
  - 子文件夹被忽略
  - 文件与网页不能移到根层级，能在文件夹之间移动
- 设置窗口的数据源（用只带剪贴板的 `NSDraggingInfo` 替身，不开窗口）：
  - 带 `public.url` 与 `public.url-name` 的剪贴板落在文件夹行上，加入带标题的网页
  - 文件 URL 加入文件；只有普通文件夹时不接收
  - 落在文件行或网页行上不接收
- 文件夹图标的预览跳过子文件夹、文件与网页

## 文档回写

- 00：目标、需求清单第 14 条、术语里“文件夹”的定义、模块划分表、阶段列表
- 01：数据模型、`FolderStore` 的 `addItems`、设置窗口的行与拖入、预览跳过的项
- 02、05：`addApps` 改为 `addItems`
- 03：网格的项、点击文件与网页的行为、收起的触发
- `README.md`：开头一句，以及“管理文件夹”“Dock 上的文件夹”“展开与收起”三节
- `AGENTS.md`：项目概述；需求文档范围改为 01–06

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 设置窗口：
  - 从访达把 `.txt`、`.pdf` 拖到文件夹行上，加入；拖普通文件夹不接收
  - 从 Chrome 把网址拖到文件夹行上，加入并带标题
  - 文件行、网页行显示图标与名称，双击不进入编辑；能拖动排序、移入其它文件夹，不能拖到根层级
- 面板：
  - 显示文件与网页
  - 点文件用默认 App 打开并收起；点网页用默认浏览器打开并收起
- tile 与面板里子文件夹的图标只预览 App
- 退出重开 Flotilla 后数据仍在
