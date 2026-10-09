# 12 改称 “组”、按钮的可用条件与网页的网址

先读 [00 总览](00-overview.md) 与 01–11 十一份文档，并以 11 阶段合入后的代码为基线。本阶段交付需求 29–34：Flotilla 的分组改称 “组”，访达里的文件夹改称 “访达文件夹”；设置窗口里 “添加…” 只在选中组时可用，“新建组” 在选中组或没有选中项时可用；网页这一行在名称后标出网址；网址里的中文等按解码后的文字显示。

## 规则

### 需求 29、30 的叫法与范围

- 需求 29：Flotilla 管理的分组叫 “组”，免得与访达文件夹混淆
  - 根组、子组、组树、组区、组图标、组名都这样叫
- 需求 30：访达里的文件夹叫 “访达文件夹”，即磁盘上的目录，不含文件包（见 00 的 “术语”）
- 两条都适用于界面文字（五种语言）、代码、注释、日志、测试的说明文字与文档
- 以下 “文件夹” 不是组，照旧：
  - 原生 Dock 的文件夹与叠放：Dock 右侧区域里的文件夹，是实测对照的对象
  - 系统的通用文件夹图标：设置窗口里组这一行用的就是它（`NSWorkspace.shared.icon(for: .folder)`，见 05）
  - Flotilla 自己与测试用的目录，如 `Application Support/Flotilla`、测试建的临时目录
  - 照抄系统原生文案的界面文字

### 界面文字

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `groups.sectionTitle` | Groups | 组 | 組 | グループ | 그룹 |
| `groups.newGroup` | New Group | 新建组 | 新增組 | 新規グループ | 새로운 그룹 |
| `groups.untitledGroup` | Untitled Group | 未命名组 | 未命名組 | 名称未設定グループ | 제목 없는 그룹 |
| `general.previewIconCount` | Icons shown in group icon: | 组图标内显示的图标数量： | 組圖像內顯示的圖像數量： | グループアイコンに表示するアイコンの数： | 그룹 아이콘에 표시할 아이콘 수: |
| `general.finderFolders` | Finder folders: | 访达文件夹： | Finder 檔案夾： | Finderのフォルダ： | Finder 폴더: |

各语言用词的依据：

- zh-Hans 照需求原话：“新建组” “组图标内显示的图标数量” “访达文件夹”
- zh-Hant 按简体逐字转写，“组” 写作 “組”；“新增” “未命名” “圖像” 沿用这几个键原来的 zh-Hant 写法
- en、ja、ko 的 “组” 取访达的用词：“显示” 菜单的 “使用群组”，en 为 `Use Groups`、ja 为 `グループを使用`、ko 为 `그룹 사용`
  - 出处：`/System/Library/CoreServices/Finder.app/Contents/Resources/<语言>.lproj/LocalizableMerged.strings` 的 `N148.2` 键
  - 键名里有点，可用 `/usr/libexec/PlistBuddy -c 'Print :N148.2' <文件>` 复核；`plutil -extract` 会把点当成路径的分隔
  - “新規” “名称未設定” “새로운” “제목 없는” 沿用 `groups.newGroup`、`groups.untitledGroup` 原来的写法
- `general.finderFolders` 的 en `Finder folders:`、ja `Finderのフォルダ：`、ko `Finder 폴더:` 本来就是 “访达文件夹” 的意思
- 隐私授权框的用途说明用同样的叫法：zh-Hans 写 “访达文件夹”，zh-Hant 写 “Finder 檔案夾”；五种语言的全文见 [08](08-finder-folder-stacks.md) 的 “隐私授权框的用途说明”

### 代码、注释与文档

- Swift 里 Flotilla 的组叫 `Group`：
  - 类型：`Group`、`GroupItem`、`GroupStore`、`GroupIconRenderer`、`GroupTree*`、`GroupPanel*`、`GroupGrid*`、`GroupNavigation*`、`DockGroupPresenter*`
  - 成员、参数与局部变量：`group`、`groups`、`subgroup`，如 `rootGroups`、`addSubgroup(named:to:)`、`containingGroupID`
  - 本地化键的前缀：`groups.`
- 访达文件夹在代码里叫 finder folder：`FinderFolderContents`、`FileReference.isFinderFolder`、`general.finderFolders`
- 注释、日志、测试的说明文字与文档写 “组” “根组” “子组” “组树” “组区” “组图标” “组名” 与 “访达文件夹”
- 英文（README 与代码里的英文）写 group、root group、subgroup；Finder folder 照旧

### 仍叫 folder 的持久化名字

已保存的数据与 Dock 上已有的 stub 都靠这些名字，改了就读不出、点不开：

| 名字 | 是什么 | 说明 |
|---|---|---|
| `folders.json`、`folders.json.broken-<时间戳>` | 组树的持久化文件；解析失败时保留的原文件 | [01](01-foundation.md) 的 “`GroupStore`” |
| JSON 类型标签 `folder` | `GroupItem` 里组的类型标签 | 01 的 “数据模型” |
| URL host `folder`：`flotilla://folder/<id>`、`flotilla://folder/<id>/items?path=…` | stub 发给 Flotilla 的请求 | [02](02-dock-tile.md) 的 “stub 可执行文件” |
| `FlotillaFolderID` | stub Info.plist 里根组 id 的键 | 02 的 “stub bundle” |

- 代码里写下这些名字的地方各有一句注释，说明为什么还叫 folder；`folders.json.broken-<时间戳>` 由持久化文件的名字拼出，随它沿用

### 需求 31 “添加…” 的可用条件

- 只有选中的是组（根组或子组）时可用
- 没有选中项，或选中的是 App、文件（含文件包）、访达文件夹、网页时禁用
- 菜单三项的加入目标不变：选中的组（`containingGroupID` 对组的行就是它自己）

### 需求 32 “新建组” 的可用条件

- 选中组，或没有选中项时可用
- 选中的是 App、文件（含文件包）、访达文件夹、网页时禁用
- 行为不变：选中组时在这个组里新建子组，没有选中项时新建根组；新建后立即进入重命名

### 两个按钮怎样更新

- `GroupTreeViewController` 持有两个按钮（`newGroupButton`、`addPopUpButton`），由 `updateButtonRow()` 按选中项一起更新
- 时机：`loadView()`、选中项变化（`outlineViewSelectionDidChange(_:)`）、树重建之后（`reloadTree()`）
- 选中的组被删掉、树重建后没有选中项时，两个按钮随之变成 “新建组” 可用、“添加…” 禁用

### 需求 33 网页行标出网址

- 网页这一行，名称后用灰色小字显示网址：与访达文件夹的位置（需求 21，见 08）用同一个标签，样式、截断规则都相同
  - 小号系统字体、`secondaryLabelColor`
  - 宽度不够时先截断网址，再截断名称
  - 中间省略：网址的开头与末尾留着
- 网址取显示的网址（需求 34），与网页的 “编辑…” 提示框里填的网址一致
- 名称就是网址时不显示：没有标题时 `displayName` 就是网址（`WebPageReference.displayName`）；标题恰好与网址相同时同理
- 其余各行照旧：组、App、文件、文件包、已删除的访达文件夹不显示
- “编辑…” 保存或补上标题之后，树按变更通知重建，网址随之更新、出现或消失
- `GroupTreeCellView` 里显示它的仍是 `locationLabel`（读出用 `locationText`）：访达文件夹的位置或网页的网址

### 需求 34 网址的显示文字

- 显示的网址（`WebPageReference.displayAddress`）：从 `url.absoluteString` 出发，把百分号编码里能还原成可见非 ASCII 字符的 UTF-8 字节序列还原成文字，其余照原样
  - 例：`https://zh.wikipedia.org/wiki/%E5%BD%92%E5%B8%86` 显示为 `https://zh.wikipedia.org/wiki/归帆`
- 照原样的编码：
  - ASCII 字符的编码，如 `%20`、`%2F`、`%3F`、`%25`：还原后会改变网址的含义，也不能再原样解析回来
  - 不是合法 UTF-8 的编码，如 GBK 编码的 `%B9%E9`
  - 还原出来是空白、控制或格式字符的编码（Unicode 类别 Z*、Cc、Cf，如 U+3000、U+200B、U+202E）：显示出来看不见，或会打乱文字的顺序
- 大小写十六进制都还原，照原样的编码保留原来的大小写；`xn--` 开头的主机名照原样，不转换
- 用在三处：
  1. 设置窗口网页行名称后的网址（`GroupTreeCellView.location(of:)`）
  2. 没有标题时网页的名称（`WebPageReference.displayName`）：设置窗口与面板都显示它
  3. 网页 “编辑…” 提示框里预先填好的网址（`WebPageAlert`）
- 名称与网址相同就不显示网址这一条不变：比较的是两份显示文字
- “编辑…” 保存时照常经 `webPage(from:)` 解析（见 09）：
  - 主机名之后的非 ASCII 字符先按 UTF-8 编码，已有的百分号编码照原样，再交给 `URL(string:)`；主机名仍由 `URL(string:)` 转成 `xn--` 开头的写法
  - 实测（macOS 27）不能全交给 `URL(string:)`：它替网址的一部分编码非 ASCII 字符时，这部分里已有的 `%` 也再编码一次，`%20` 成了 `%2520`（见 09 的 “平台事实”）；显示的网址里，中文与照原样的编码常在同一部分
  - 路径、查询参数与片段用大写十六进制编码的网址，不改网址框直接保存，得到的 `url` 与原来相同；小写十六进制保存后变成大写
  - 主机名本身是百分号编码的网址，如 `https://%E5%BD%92.com/`，显示为 `https://归.com/`，保存后主机名变成 `xn--` 开头的写法

## 设置窗口

- 窗口尺寸不变（见 07）：最窄时组区宽 530
- 按钮行宽的实测见 10

## 单元测试

- 按钮（`GroupTreeViewControllerTests`，离屏窗口）：
  - 没有选中项、根组、子组、App、网页、文件、访达文件夹逐一选中：两个按钮的可用状态都符合需求 31、32
  - 选中的子组被删掉、树重建后没有选中项：“添加…” 变成禁用；选中的 App 被删掉之后：“新建组” 变成可用
  - 没有选中项时点 “新建组”：新建的是根组，排在最后
  - 选中子组时点 “新建组”：新建的是这个子组的子组，不是它所在的组的；根层级与它所在的组都没有多出组
  - 按钮行宽五种语言各一例照旧通过（见 07）
- 网址（`GroupTreeCellViewTests`）：
  - 有标题的网页：名称是标题，名称后是显示的网址
  - 没有标题、标题与网址相同：不显示
  - 路径里有中文的网页：名称后是还原后的网址；没有标题、标题与还原后的网址相同：只显示一次
  - 复用显示过网址的行视图去显示 App 或组：不残留
  - 宽度不够时先截断网址，名称保持完整
- 显示的网址（`WebPageReferenceTests`）：
  - 路径、查询参数、片段里的中文还原；小写十六进制同样还原；emoji 还原
  - `%20`、`%2F`、`%3F`、`%25`，GBK 的 `%B9%E9`，U+3000、U+200B、U+202E 保持原样，小写的连同大小写；同一段里的中文照常还原
  - 没有编码的网址原样不变，`xn--` 开头的主机名不转换
  - 没有标题时 `displayName` 是显示的网址；有标题时仍是标题
- 提示框（`WebPageAlertTests`）：
  - 编辑路径、查询参数、片段里有中文与 emoji 的网页：网址框填的是显示的网址；不改动直接保存，交出的网页与原来的相同，混着照原样的编码时也一样
  - `webPage(from:)`：同一部分里已有的百分号编码不再编码一次，如 `https://example.com/归%20帆`、`apple.com/search?q=归%26帆#归%20`；主机名里的中文转成 `xn--`：`https://例子.测试/归`
- 叫法：
  - 五张表的键一致、与代码引用一一对应：`LocalizationTests` 自动覆盖
  - 持久化名字的守卫原样通过：`GroupItemCodingTests` 的 `"folder"`、`DockTileRequestTests` 的 `flotilla://folder/…`、`DockTileBundleBuilderTests` 的 `FlotillaFolderID`、`GroupStoreTests` 的 `folders.json.broken-`

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 界面文字：
  - 五种语言下，组区标题、“新建组”、新建后的默认名、通用区的 “组图标内显示的图标数量” 与 “访达文件夹” 两行是上表的文字
  - 简繁中文下，第一次读受保护的位置时，授权框里的用途说明写的是 “访达文件夹” “Finder 檔案夾”
  - 五种语言下把窗口拉到最窄，按钮行完整显示、不截断、不重叠
- 按钮：
  - 没有选中项：“新建组” 可用，“添加…” 禁用；点 “新建组” 新建根组，名称定下后 Dock 上出现它的 tile
  - 选中根组或子组：两个都可用；“新建组” 在这个组里新建子组，“添加…” 的三项都加入这个组
  - 选中 App、文件、文件包、访达文件夹、网页：两个都禁用
  - 删掉选中的组：“新建组” 可用，“添加…” 禁用
- 网页行：
  - 有标题的网页：名称后是灰色小字的网址；没有标题的网页只显示一次网址
  - 用 “编辑…” 改网址后，标出的网址随之更新；清空标题保存后只剩网址，取到标题后网址出现在标题后
  - 把窗口拉窄：先截断网址、在中间省略，开头的 `https://` 与末尾看得到；再窄才截断名称
- 网址里的中文：
  - 加入 `https://zh.wikipedia.org/wiki/归帆` 并带标题：名称后是 `https://zh.wikipedia.org/wiki/归帆`，不是百分号编码
  - 不带标题：设置窗口与面板里的名称都是还原后的网址，设置窗口只显示一次
  - “编辑…”：网址框里是还原后的网址；不改动直接保存，标出的网址不变，“在默认浏览器中打开” 打开的仍是这个网页
  - 网址里的 `%20` 照原样显示
- 已有数据：
  - 之前保存的组照常读出，名称、内容与顺序不变
  - Dock 上已有的 tile 照常点击展开，把 App 拖到 tile 上照常加入
