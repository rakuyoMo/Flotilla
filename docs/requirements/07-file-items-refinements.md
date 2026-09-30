# 07 访达里的文件夹、添加文件、预览与跟随移动

先读 [00 总览](00-overview.md) 与 01–06 六份文档，并以 06 阶段合入后的代码为基线。本阶段交付需求 15–18：

- 需求 15：访达里的文件夹可以作为一项加入文件夹
- 需求 16：设置窗口的“添加文件…”按钮
- 需求 17：文件夹图标的预览含文件与网页
- 需求 18：文件移动或改名后，文件项自动跟到新位置

两种“文件夹”在本文与代码注释里分开称呼：“文件夹”专指 Flotilla 的分组（见 00 的术语）；磁盘上的目录称“访达里的文件夹”。

## 规则

### 需求 15 访达里的文件夹

- 访达里的文件夹与文件是同一种项：`FolderItem.file(FileReference)`，JSON 类型标签仍是 `file`
- 要加入的本地 URL：
  - App bundle 为 App
  - 其余存在的一切为文件：普通文件、文件包、访达里的文件夹、卷
  - 不存在为 nil
- 加入途径与文件相同：
  - 设置窗口：从访达把文件夹拖到文件夹行上
  - Dock tile：从访达把文件夹拖到 tile 上
  - 设置窗口的“添加文件…”
- 面板里显示它在访达里的图标与名称；点击后在同一个面板里展开它的内容，见 [08](08-finder-folder-stacks.md)
- 其余与文件相同：名称不可编辑、只能放在文件夹里、同一个文件夹里按 URL 去重
- stub 的 `CFBundleDocumentTypes` 与 06 相同：06 实测 Dock 对访达里的文件夹也高亮并拉起 stub

### 需求 16 “添加文件…”

- 按钮排在“添加 App…”之后，按钮行为：新建文件夹 · 添加 App… · 添加文件… · 添加到 Dock ⋯⋯ 删除
- 可用条件与“添加 App…”相同：有选中项时可用，加入选中项所属的文件夹
- `NSOpenPanel` 以 sheet 弹出：
  - `canChooseFiles`、`canChooseDirectories`、`allowsMultipleSelection` 都为真
  - 不限类型，不设起始目录
  - 选中的 URL 经 `FolderItem(url:title:)` 交给 `addItems`：选到 App 时按分类规则成为 App

### 需求 17 预览含文件与网页

- 文件夹图标（需求 2）按顺序取前 `previewIconCount` 项，只跳过子文件夹；App、文件（含访达里的文件夹）与网页都算，各用自己的 `icon`
- 设置项的文字去掉“App”，键名 `general.previewIconCount` 不变，见下文“本地化”

### 需求 18 跟随移动

- 文件项（含访达里的文件夹）带书签跟随；App 同样带书签、按同一套规则跟随，见 08；网页不涉及
- 文件被移进废纸篓：跟着书签走
- 找不到文件（已删除、卷未挂载）：这一项保持原样，照旧显示；点击时系统按 `NSWorkspace` 的默认设置弹出“找不到”的提示，同时记日志，面板收起
  - 已删除的访达里的文件夹在 macOS 27 上实测弹出“找不到该文件。”，见 08 的“平台事实”
  - 已删除的文件没有单独实测：它与已删除的访达里的文件夹走同一个打开方法、同一份设置
- 点击打开时用的就是更新后的 URL，不另外解析书签

## 数据模型

```swift
/// 对一个文件的引用：访达里 App 以外的一切，包括文件包、访达里的文件夹与卷
struct FileReference: Codable, Hashable, Identifiable {
    let id: UUID

    /// 文件包、访达里的文件夹与卷是目录 URL，其余是文件 URL
    let url: URL

    /// 建不起来时为 nil，只按路径找
    let bookmark: Data?
}
```

- 书签是 `url.bookmarkData()` 建的普通书签：Flotilla 不在沙盒里，不用 security-scoped 书签
- JSON 键 `bookmark`，`Data` 按 `JSONEncoder` 的默认方式编成 base64；nil 时不写这个键；没有这个键的数据照常解码，书签为 nil

  ```json
  { "type": "file", "id": "…", "url": "file:///Users/…/资料/", "bookmark": "Ym9va…" }
  ```

### 分类

`FolderItem(url:title:)` 处理本地 URL：

1. `normalizedURL(_:)` 规整（App 与文件共用，见 08）：
   - 路径先标准化（`standardizedFileURL`），同一个文件不因 URL 写法不同而重复加入
   - 读不到资源属性（不存在）时为 nil
   - 目录按目录 URL 记录，其余按文件 URL 记录
2. `AppReference.isApplicationBundle(_:)` 为真时是 App
3. 其余是文件，带上 `try? url.bookmarkData()`

- 实测（macOS 27）：`standardizedFileURL` 会把已存在的 `/private/var/…` 写成 `/var/…`；卷根目录 `/` 能建书签

### 按书签找当前位置

```swift
extension BookmarkedReference {
    /// 按书签找到当前位置，返回更新后的引用；位置与书签都不用改、或找不到时为 nil
    func relocated() -> Self?
}
```

- App 与文件共用这一份规则与实现，见 08

- 有书签：
  - 解析选项 `[.withoutUI, .withoutMounting]`：不弹界面、不挂载卷
  - 解析失败：返回 nil
  - 位置变没变，比较两边 `resolvingSymlinksInPath()` 之后的路径：书签解析出的是 `/private/var/…`，记录的可能是 `/var/…`，这种写法差异不算移动
  - 位置变了：URL 换成新位置，经 `normalizedURL(_:)` 规整，id 不变
  - `bookmarkDataIsStale` 为真：按当前位置重建书签；重建失败时沿用旧书签
  - 位置没变、书签也没过期：返回 nil
- 没有书签：文件还在原路径时补建书签，URL 不变；建不起来时返回 nil
- 实测（macOS 27）：书签解析出的路径是 `/private/var/…` 这类解析过符号链接的写法；位置不变时 `bookmarkDataIsStale` 为假，改名、移动后为真；文件删除后解析抛错

### `FolderStore`

- `updateItemLocations(in folderID: UUID? = nil)`：按书签更新文件项与 App 项（App 见 08）
  - nil 为整棵树，否则限定这个文件夹及其子孙
  - 有变化时一次提交；没有变化时不提交、不发通知
- `addItems(_:to:)`：去重之前先更新目标文件夹及其子孙里的文件项，与加入合成一次提交
  - 文件改名后再把它拖进同一个文件夹，已有的那一项先跟到新路径，不会重复
  - 只有文件项跟到了新位置、没有新加入的项时同样提交

## 调用时机

1. **启动**：`applicationWillFinishLaunching` 里、开始 Dock 同步之前，更新整棵树；第一次同步渲染的 tile 图标就用上新位置
2. **展开面板**：`DockFolderPresenter` 展开根文件夹之后，用 `DispatchQueue.main.async` 推迟到下一轮主线程，更新这个根文件夹的子树
   - 有变化时经已有的 `folderStoreDidChange` → `panelController.reload()` 重建网格
   - 展开由 `apply` 调起，同步提交会在展开途中重入 `apply`；推迟也让展开不因解析书签而变慢
3. **设置窗口成为 key**：`windowDidBecomeKey` 里在刷新 Dock 状态之后更新整棵树
   - 正在编辑文件夹名时跳过：有变化就会重建树，重建会结束编辑并提交输入到一半的名称
   - 判断方式：窗口的第一响应者是字段编辑器，且它正在编辑的文本框在文件夹树里
4. **加入**：`addItems` 去重之前，见上文

## 设置窗口

- “添加文件…”见需求 16；树的行与拖入规则不变，访达里的文件夹按文件显示与处理
- 窗口尺寸由 `SettingsWindowController` 的常量给出：
  - `contentInset = 20`：内容区四边的边距，文件夹区宽 = 内容宽 − 40
  - `minimumContentSize = 570 × 480`，默认内容宽 620、高 600
- 按钮行宽（`NSStackView` 默认间距 8，五个按钮之间含两侧 gravity 区之间共四个间距），实测（macOS 27）：

  | en | zh-Hans | zh-Hant | ja | ko |
  |---|---|---|---|---|
  | 471 | 443 | 430 | 509 | 410 |

  - 最窄时文件夹区宽 530，比最宽的 ja 多 21
  - 按钮行放不下时按钮不会被压窄，而是把窗口内容撑宽：按钮的压缩阻力 750 高于窗口保持尺寸的优先级 500

## 本地化

新增一个键，改一个键的文字：

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `folders.addFiles` | Add Files… | 添加文件… | 加入檔案… | ファイルを追加… | 파일 추가… |
| `general.previewIconCount` | Icons shown in folder icon: | 文件夹图标内显示的图标数量： | 檔案夾圖像內顯示的圖像數量： | フォルダアイコンに表示するアイコンの数： | 폴더 아이콘에 표시할 아이콘 수: |

## 渲染器

- `FolderIconRenderer.render` 标注 `@MainActor`：`WebPageReference.icon` 只在主线程读取
- 按顺序惰性取前几项的图标，只读取用得上的

## 单元测试

- 分类（临时目录）：
  - 访达里的文件夹、卷根目录为文件，按目录 URL 记录
  - 不存在的路径为 nil
  - 新建的文件项带书签，书签能解析回这个文件
- 编解码：
  - 文件项有、没有书签都往返一致
  - 书签以 base64 写在 `bookmark` 键里；没有书签时 JSON 里没有 `bookmark`
  - 没有 `bookmark` 键的 JSON 照常解码
- 跟随（`FolderStoreItemLocationTests`，临时目录；App 的用例见 08）：
  - 文件改名、文件移到别的目录、访达里的文件夹改名：URL 更新、id 不变、只发一次变更通知
  - 只更新指定文件夹及其子孙，其它根文件夹不动
  - 什么都没变：不发通知
  - 记录的是 `/private/var/…` 写法、书签不变：不算移动，不发通知
  - 文件已删除：不变，不发通知
  - 没有书签的项，文件还在时补上书签
  - `addItems`：文件改名后把新路径加入同一个文件夹，不重复，只发一次通知
- 设置窗口数据源：访达里的文件夹拖到文件夹行上加入；已不存在的文件与 `ftp:` 网址不接收
- 预览：
  - 子文件夹被跳过，后面的文件、网页与 App 照常进入预览
  - 文件与网页进入预览，顺序不同画面不同
  - 混排时数量上限照旧
- 按钮行宽：五种语言各一例，按表里的文字给按钮换上标题，放进最窄时文件夹区宽度的离屏窗口；每个按钮不窄于标题需要的宽度、相邻不重叠、最右边不越出文件夹区
- 新键五种语言齐全：`LocalizationTests` 自动覆盖

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 访达里的文件夹：
  - 从访达拖到设置窗口的文件夹行上：加入，行里显示它的图标与名称，双击不进入编辑
  - 从访达拖到 tile 上：tile 高亮，松手后加入；前台 App 保持前台
  - 面板里显示它的图标与名称；点击后在面板里展开，见 08
- “添加文件…”：
  - 无选中项时禁用；选中项后可用，sheet 里能选文件与文件夹、能多选
  - 选中的文件、文件夹与 App 加入选中项所属的文件夹
  - 五种语言下把窗口拉到最窄，按钮行完整显示、不截断、不重叠
- 预览：文件夹里前几项是文件或网页时，tile 与面板里子文件夹的图标画出它们的图标；设置项文字为“文件夹图标内显示的图标数量”
- 跟随移动：
  - Flotilla 运行时在访达里给文件改名：展开面板后网格里是新名称，点击能打开
  - 退出 Flotilla、移动文件、再启动：tile 图标与面板都用上新位置
  - 设置窗口在后台时改名文件，切回设置窗口：行名更新；正在输入文件夹名时切走再切回，输入不被打断
  - 删除文件：这一项仍在，点击时系统弹出“找不到”的提示，同时记日志，面板收起
