# 09 设置窗口的 “添加…” 菜单与添加网页

先读 [00 总览](00-overview.md) 与 01–08 八份文档，并以 08 阶段合入后的代码为基线。本阶段交付需求 24：设置窗口的 “添加 App…” “添加文件…” 两个按钮合并为一个 “添加…”，点击后弹出菜单，菜单里另有 “添加网页…”，输入网址与可选的标题把网页加入文件夹，标题留空时自动获取网页的标题。

## 规则

### 按钮行与菜单

- “添加 App…” 与 “添加文件…” 两个按钮合并为一个 “添加…”：`NSPopUpButton` 的 pull-down（`pullsDown = true`），点击后在按钮下方弹出菜单
- 按钮行从左到右：新建文件夹 · 添加… · 添加到 Dock ⋯⋯ 删除
- 菜单从上到下：添加 App… · 添加文件… · 添加网页…
  - pull-down 的第一项是按钮上显示的 “添加…”，不出现在菜单里
  - 其后三项各自带 target 与 action，选中后直接调用对应的方法
- 可用条件与原来的两个按钮相同：有选中项时 “添加…” 可用；三项都加入选中项所属的文件夹（`containingFolderID`）
- “添加 App…” “添加文件…” 的行为不变（见 01、07），原来的键 `folders.addApps`、`folders.addFiles` 原样用作菜单项的标题
- 外观：pull-down 与相邻的按钮同高 24 pt，按钮行保持默认的垂直居中；实测（macOS 27）第一条基线距顶 16.75 pt，按钮是 17 pt

### “添加网页…” 的提示框

`Settings/AddWebPageAlert` 持有 `NSAlert`、网址框与标题框，做两个输入框的 delegate，确认后把要加入的网页交给调用方。

- 以 sheet 弹出 `NSAlert`，挂在设置窗口上，与 “添加 App…” 的选择面板一致：
  - 标题（`messageText`）：添加网页
  - 说明（`informativeText`）：输入网页的网址，标题可留空。
  - 附件（`accessoryView`）：上下两个单行输入框（`NSTextField(string:)`），相距 8 pt
    - 网址框在上，占位文字 “网址”；设为窗口的 `initialFirstResponder`，弹出时就是第一响应者，可以直接打字、⌘V 粘贴
    - 标题框在下，占位文字 “标题（可选）”；获取标题期间的样子见 “自动获取标题”
    - Tab 从网址框到标题框，Shift-Tab 回来：提示框的窗口按位置排出 Tab 的顺序，不另外设 `nextKeyView`
  - 按钮：“添加” 是第一个按钮，即默认按钮，两个框里按回车都触发它；“取消” 的 key equivalent 显式设为 Esc：只有英文标题 “Cancel” 会自动得到 Esc
- 网址不是可用的网址时 “添加” 禁用，随输入实时更新（`controlTextDidChange(_:)`，键入与粘贴都会触发）；空输入时禁用；标题框的内容不影响它
  - 提示框不会在用户确认后才报错，也不必再弹第二个提示框
- 点 “添加”：把网页加入弹出时选中项所属的文件夹
  - 标题框有内容：去掉首尾空白后作为标题，显示名就是它
  - 标题框空着：先不带标题加入，显示名是网址，与没有标题的拖入网页一致；取到标题后补上（见 “自动获取标题”）
- 点 “取消” 或按 Esc：什么都不变
- 弹出期间那个文件夹被删掉：`addItems` 找不到它，什么都不做
- 两个输入框都与上方的说明文字左右对齐，不把提示框撑宽：
  - 先不带附件 `layout()` 一次，得到提示框的宽度；输入框宽 = 提示框内容宽 − 2 × 20
  - 正文宽度随按钮标题变化：英文 “Cancel” 把提示框撑到 265 pt，正文宽 225；其它四种语言提示框 260 pt，正文宽 220（实测 macOS 27）
- `FolderTreeViewController` 只在菜单项被点时取目标文件夹、弹出提示框，把要加入的网页交给 `store.addItems`，把晚到的标题交给自己的 `fillTitle(_:ofWebPageWithID:)`
  - 输入框的 delegate 是 `AddWebPageAlert`，不是 `FolderTreeViewController`：后者已是树里改名输入框的 delegate，`controlTextDidEndEditing(_:)` 会被两边混用
  - 弹出期间由 `beginSheetModal` 的完成回调持有 `AddWebPageAlert`：输入框的 delegate 是弱引用

### 输入怎样成为网页

`AddWebPageAlert.webPage(from:)`。这条规则只属于 “添加网页…”，不改 `FolderItem(url:title:)` 与拖入的规则。

1. 去掉首尾空白与换行；结果为空 → 不可用
2. 中间还有空白 → 不可用（多半是把一句话当成了网址）
3. 开头不是 `scheme://` 时在前面补 `https://`，像浏览器地址栏那样：`apple.com` → `https://apple.com`，`localhost:8080/a` → `https://localhost:8080/a`
   - scheme 按 RFC 3986：字母开头，其后是字母、数字、`+`、`-`、`.`
   - 只看开头：查询参数里的 `://` 不算，`apple.com/?u=https://x.com` → `https://apple.com/?u=https://x.com`，`localhost:8080/?next=http://x` → `https://localhost:8080/?next=http://x`
   - 开头已有 scheme 的不补：`ftp://example.com` 保持原样，到第 6 条被判为不可用
4. `URL(string:)` 解析失败，或解析出的网址没有主机名（如只输入了 `https://`）→ 不可用
5. 文件 URL → 不可用：在交给分类之前就挡下，不让它去碰文件系统
6. 是不是网页交给 `FolderItem(url:title:)`，标题传标题框里的文字：它只收 `http`、`https`（不区分大小写），标题去掉首尾空白、空串视为没有
7. 除以上之外不做任何规整：大小写、末尾斜杠、`www.` 都保持用户输入的样子

### 加入与去重

- 经 `FolderStore.addItems` 加入，照它的去重：同一个文件夹里已有同一网址的网页时不重复加入（见 06）

### 自动获取标题

`Settings/WebPageTitleFetcher` 用系统的 LinkPresentation（`LPMetadataProvider`）获取网页的标题：`shouldFetchSubresources = false`，`timeout` 10 s。跳转、编码与 HTML 实体都由它处理，Flotilla 不解析 HTML。

- 为什么关掉附带资源：默认连带下载图标、预览图等附带资源，实测 2.8–6.6 s；关掉之后 0.5–3.4 s，标题照样取到（见 “平台事实”）
- 何时获取：
  - 网址框的内容变成可用的网址，并且停顿 0.3 s 不再变，就为这个网址开始获取，取的是补好 scheme 之后的网址
  - 网址再变：取消正在进行的那一次，重新计时；不可用的网址不获取
- 标题框任何时候都能输入，获取期间也一样
- 取到的标题去掉首尾空白，空串当作没取到
- 怎样填：
  - 取到时标题框空着才填进去；用户自己输入的内容绝不覆盖
  - 网址变了：标题框里仍是自动填进去、用户没改过的旧标题就清空，等新网址的结果；用户自己输入的保留
  - 取不到（失败、超时、网页没有标题）：什么都不填，不提示错误
  - 不是 HTML 的网址（PDF、图片等）：LinkPresentation 给出去掉扩展名的文件名，照样填入（见 “平台事实”）
- 转圈与占位文字：
  - 正在获取、且标题框空着时，标题框内右端显示小号转圈（`NSProgressIndicator`，spinning，small，16 × 16 pt，距标题框的右边与上下各 4 pt），占位文字换成 “正在获取标题…”
  - 转圈盖在标题框上面，不占标题框的位置
  - 取完（取到或取不到），或标题框里有了内容：转圈隐藏，占位文字恢复 “标题（可选）”
- 点 “添加”：
  - 标题框有内容：带着它加入，取消正在进行的获取
  - 标题框空着：先不带标题加入；正在进行的那一次继续，不重新发起；还在等停顿的不再等，立刻开始；取到后补到刚加入的那一项上
- 点 “取消” 或按 Esc：取消正在进行的获取，作废正在等的停顿，什么都不加入
- 被取消的那一次晚到的结果丢掉：LinkPresentation 取消之后仍会调用完成回调（见 “平台事实”），每次获取带编号，只认最新的一次
- 提示框关掉之后，获取的完成回调持有 `AddWebPageAlert`，直到结果到达；它把标题与那一项的 id 交给 `beginSheetModal` 的 `titleHandler`。`FolderTreeViewController` 不直接碰 LinkPresentation
- `AddWebPageAlert.init(fetchTitle:waitForPause:)` 接收取标题与等停顿的方法：App 里用 `WebPageTitleFetcher` 与 0.3 s 的 `Task.sleep`，单元测试传入假实现，不联网、不真的等待

### 补标题

- `FolderStore.fillTitle(_:ofWebPageWithID:)`：只在这一项仍在、是网页、标题仍为 nil 时才改，位置与 id 不变；改了就提交并发一次变更通知，没改就什么都不做
  - 去重时没有真正加入（同一个文件夹里已有同一网址）：按 id 找不到，什么都不做
- 正在编辑文件夹名时不补：补标题会重建树，重建会结束编辑并提交输入到一半的名称；与 `updateItemLocations()` 一样按 `isEditingFolderName` 判断
  - `FolderTreeViewController` 先按网页项的 id 记下，编辑结束再补
  - 按回车或点别处结束编辑：在 `controlTextDidEndEditing(_:)` 里改名之后补
  - 按 Esc 取消编辑：outline view 不发 `controlTextDidEndEditing(_:)`；在 `control(_:textView:doCommandBy:)` 里排一个主线程任务，outline view 结束编辑之后补
- 补标题不改写 stub、不重启 Dock：
  - stub 改写与否看 Info.plist 与图标是否逐字节变化（`DockTileBundleBuilder.write(folder:icon:)`）：Info.plist 里随文件夹变化的只有根文件夹的名称与 id；网页在图标里用所有网页共用的地球图标，与标题无关
  - Dock 偏好改动与否看各 tile 的条目（`DockPreferences.apply`）：标签是根文件夹的名称，stub 没改写就不换 GUID
  - 变更通知仍会让 `DockTileSynchronizer` 同步一次：重新渲染图标、比对一致，不写文件

## 设置窗口

- 窗口尺寸不变（见 07）：最窄时文件夹区宽 530
- 按钮行宽（`NSStackView` 默认间距 8，四个控件之间含两侧 gravity 区之间共三个间距），实测（macOS 27）：

  | en | zh-Hans | zh-Hant | ja | ko |
  |---|---|---|---|---|
  | 362 | 344 | 331.5 | 352.5 | 327.5 |

  - 最窄时文件夹区宽 530，比最宽的 en 多 168
  - “添加…” 宽 80.5–84 pt：pull-down 的宽度只取决于第一项的标题

## 本地化

键与文字：

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `folders.add` | Add… | 添加… | 加入… | 追加… | 추가… |
| `folders.addWebPage` | Add Web Page… | 添加网页… | 加入網頁… | Webページを追加… | 웹 페이지 추가… |
| `folders.webPageAlert.message` | Add Web Page | 添加网页 | 加入網頁 | Webページを追加 | 웹 페이지 추가 |
| `folders.webPageAlert.informative` | Enter the address of the web page. The title is optional. | 输入网页的网址，标题可留空。 | 輸入網頁的網址，標題可留空。 | WebページのURLを入力してください。タイトルは省略できます。 | 웹 페이지의 주소를 입력하십시오. 제목은 비워 둘 수 있습니다. |
| `folders.webPageAlert.addressPlaceholder` | Address | 网址 | 網址 | URL | 주소 |
| `folders.webPageAlert.titlePlaceholder` | Title (Optional) | 标题（可选） | 標題（可選） | タイトル（オプション） | 제목(선택 사항) |
| `folders.webPageAlert.fetchingTitle` | Fetching Title… | 正在获取标题… | 正在取得標題… | タイトルを取得中… | 제목 가져오는 중… |
| `folders.webPageAlert.add` | Add | 添加 | 加入 | 追加 | 추가 |
| `folders.webPageAlert.cancel` | Cancel | 取消 | 取消 | キャンセル | 취소 |

- 省略号用 `…`（U+2026），与 “添加 App…” 一致
- `.strings` 里新键放在 “设置窗口的文件夹区” 一段，顺序与界面一致

## 单元测试

- 输入怎样成为网页（`AddWebPageAlertTests`）：
  - 完整网址原样采用：`https://www.apple.com/cn/`、`http://example.com/path?q=1`、`HTTPS://EXAMPLE.COM`；得到的是网页项，标题为 nil
  - 首尾空白、换行被去掉
  - 补 `https://`：`apple.com`、`apple.com/path?q=1`、`localhost:8080`，以及查询参数里带着网址的 `apple.com/?u=https://x.com`、`localhost:8080/?next=http://x`
  - 不可用：空串、只有空白、`hello world`、`https://`、`ftp://example.com`
  - `file:///Applications` 不可用，这个目录存在也不成为文件项
- 提示框（`AddWebPageAlertTests`）：
  - 提示框自己是两个输入框的 delegate；刚弹出时 “添加” 禁用，网址输入 `apple.com` 后可用，改成 `ftp://x` 又禁用，标题框的内容不影响它（直接改输入框的值，再按 delegate 的方式通知）
  - “添加” 的 key equivalent 是回车，“取消” 是 Esc
  - 标题、说明、按钮与两个占位文字用的是上表的键（测试进程读不到译文，读到的是键名）
  - 网址框在上、标题框在下，`layout()` 之后都与说明文字左右对齐；网址框是窗口的 `initialFirstResponder`
  - 以 sheet 弹出后网址框是第一响应者，Tab 到标题框，Shift-Tab 回来
- 自动获取标题（`AddWebPageAlertTests`，`AddWebPageAlertStub` 代替取标题与等停顿，由测试决定停顿何时结束、何时交出什么标题）：
  - 不可用的网址、停顿之前都不获取；停顿之内网址又变了就重新计时，只为最后的网址获取一次，取的是补好 scheme 的网址
  - 获取期间网址变了：前一次被取消，停顿之后为新网址重新获取
  - 取到时标题框空着就填，首尾空白去掉；取不到或只有空白时保持空着
  - 用户输入的标题不被覆盖；换网址时自动填的旧标题清空、换成新网址的，被取消的那一次晚到的结果丢掉；换网址时用户输入的保留
  - 获取期间标题框可以输入；转圈与 “正在获取标题…” 只在获取中、标题框空着时显示，取完恢复
- 添加与取消（`AddWebPageAlertTests`，以 sheet 挂在放在所有屏幕之外的窗口上，`performClick(_:)` 点按钮）：
  - 标题框有内容：带着去掉首尾空白的标题加入，获取被取消，之后取到的标题不补
  - 标题框空着、正在获取：先不带标题加入，取到后补到这一项上，只获取一次
  - 标题框空着、还在等停顿：立刻开始获取，停顿结束时不重复获取
  - 标题框空着、取不到：网页照样加入，显示名是网址，什么都不补
  - “取消”：获取被取消，正在等的停顿作废，什么都不加入，之后取到的标题不补
- 补标题：
  - `FolderStoreTests`：标题为 nil 的网页补上，位置与 id 不变，只发一次通知，重新加载后仍在；已有标题的网页、不是网页的项、找不到的项都不变，也不发通知
  - `FolderTreeViewControllerTests`（离屏窗口里用 `editColumn` 造出编辑文件夹名的状态）：没在编辑时立刻补；编辑中先不补，编辑没被打断、输入到一半的名称没有提交，点别处结束编辑后名称与标题都写进去；按 Esc 取消编辑后补上，名称保持原样
  - `DockTileBundleBuilderTests`：网页补上标题，stub 不改写
- 文件夹区（`FolderTreeViewControllerTests`）：
  - 按钮行是四个控件，顺序为 新建文件夹、添加…、添加到 Dock、删除；“添加…” 是 pull-down
  - “添加…” 的菜单依次是 添加 App…、添加文件…、添加网页…，各自接到对应的方法，target 是文件夹区
  - 无选中项时 “添加…” 禁用；选中一行后可用
  - 按钮行宽：五种语言各一例，见 07；“添加…” 换上译文后第一项的标题就是译文，宽度与只有这一项的 pull-down 相同
- 新键五种语言齐全：`LocalizationTests` 自动覆盖

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 按钮行与菜单：
  - 按钮行从左到右为 新建文件夹 · 添加… · 添加到 Dock ⋯⋯ 删除；“添加…” 右侧有下拉箭头，与相邻按钮同高，文字基线看起来对齐
  - 无选中项时 “添加…” 禁用；选中任意一行后可用
  - 点 “添加…”：菜单在按钮下方弹出，依次是 添加 App… · 添加文件… · 添加网页…
  - 五种语言下把窗口拉到最窄，按钮行完整显示、不截断、不重叠
- “添加 App…” “添加文件…”：选择面板与加入的结果与合并之前相同（见 01、07）
- “添加网页…”：
  - 以 sheet 挂在设置窗口上弹出；标题 “添加网页”、说明 “输入网页的网址，标题可留空。”
  - 说明下方上下两个输入框，占位文字 “网址” “标题（可选）”；两个框都与说明文字左右对齐，五种语言下提示框都没有被输入框撑宽
  - 弹出后不点输入框直接打字，文字进入网址框；⌘V 能粘贴；Tab 到标题框，Shift-Tab 回来
  - 空输入时 “添加” 禁用；输入 `apple.com` 后可用；改成 `hello world` 或 `ftp://example.com` 又禁用；粘贴进来的网址同样实时更新；`apple.com/?u=https://x.com` 可用
  - “添加” 可用时，两个框里按回车都等同点 “添加”；禁用时回车不加入
  - 按 Esc 等同点 “取消”，什么都不加入；中文、日文、韩文界面下同样如此
  - 同一个文件夹里再加一次同一网址：不重复
- 自动获取标题：
  - 键入 `apple.com` 停顿一下：标题框内右端出现小号转圈，占位文字变成 “正在获取标题…”；一两秒后标题框填上网页的标题，转圈消失
  - 转圈期间在标题框里打字：转圈消失，占位文字恢复；取到的标题不覆盖打的字
  - 自动填上标题之后改网址：标题清空，停顿之后重新获取；自己打的标题改网址后仍在
  - 填了标题点 “添加”：网页以这个标题出现在选中项所属文件夹的末尾，行里显示蓝色地球图标与标题；面板里同样显示，点击用默认浏览器打开
  - 标题框留空、转圈期间就点 “添加”：网页先以网址出现，取到后这一行换成标题，面板里同样
  - 键入网址后立刻（不到 0.3 s）点 “添加”：同上，取到后补上
  - 标题框留空点 “添加” 之后，马上新建文件夹或双击文件夹名开始改名：输入到一半的名称不被打断；按回车、点别处或按 Esc 结束编辑之后，标题才补上
  - 取不到标题的网址（不存在的域名、`http://` 网址）：网页照样加入，显示网址，不提示错误
  - 补上标题时 Dock 不重启
- 设置窗口的标题：五种语言下依次为 Settings、设置、設定、設定、설정
- 退出重开 Flotilla 后数据仍在

## 平台事实

以下都是 macOS 27 上的实测。

- pull-down 的 `NSPopUpButton`：
  - `title` 读到的是第一项的标题；给 `title` 赋值换掉的正是第一项的标题，按钮显示的文字与宽度随之改变
  - 宽度只取决于第一项的标题，菜单里其它项再长也不变
  - 菜单项自带 target 与 action 时，`menu.performActionForItem(at:)` 调用的是菜单项自己的 action，不是按钮的；之后按钮上显示的仍是第一项
  - 高 24 pt，与 `NSButton(title:target:action:)` 相同；第一条基线距顶 16.75 pt，按钮是 17 pt；`bezelStyle` 为 `.automatic`、`.push`、`.flexiblePush` 时都一样
- `NSAlert`：
  - 只有标题正好是英文 “Cancel” 的按钮自动得到 Esc，与进程的语言无关；“取消” “キャンセル” “취소” 都没有
  - 第一个按钮自动成为默认按钮，key equivalent 是回车
  - 按钮并排，提示框最窄 260 pt，按钮标题放不下时随之变宽：英文 “Add” “Cancel” 时 265 pt
  - 标题与说明距左右两边各 20 pt
  - 附件比提示框内容宽 − 32 窄时居中放置，不改变提示框的宽度；更宽时提示框随之变宽，附件距左右各 16 pt
  - `initialFirstResponder` 起初为 nil，`layout()` 把它设为左边的按钮，即第二个加入的按钮；在 `layout()` 之前或之后设成输入框，再 `layout()` 都保持是输入框
  - 按钮设成禁用后，`layout()` 不会改回可用
  - 窗口的 `autorecalculatesKeyViewLoop` 为真：附件里上下放两个输入框，不设 `nextKeyView`，网址框 Tab 到标题框，标题框 Shift-Tab 回到网址框
  - 附件里放两个 24 pt 高的输入框、相距 8 pt 时，简体中文的提示框为 260 × 274 pt（一个输入框时 260 × 242）
  - 不上屏的进程里也能以 sheet 弹出：`beginSheetModal(for:)` 让父窗口的 `isVisible` 变为真（测试把父窗口放在所有屏幕之外）；对按钮 `performClick(_:)` 同步结束 sheet 并调用完成回调
  - 不上屏时 `performKeyEquivalent(with:)` 送回车不会触发默认按钮：提示框的窗口不是 key
- `NSOutlineView` 编辑文件夹名：
  - 离屏窗口里 `editColumn(_:row:with:select:)` 同样让字段编辑器成为窗口的第一响应者
  - 对字段编辑器 `doCommand(by:)` 送 `cancelOperation(_:)`：先经 `control(_:textView:doCommandBy:)`，返回之后 outline view 同步结束编辑，第一响应者回到 outline view；在那里排的主线程任务在这之后执行
- LinkPresentation（`LPMetadataProvider`）：
  - 完成回调在后台队列调用
  - 耗时（冷启动，每个网址单独一个进程）：默认连带附带资源 2.8–6.6 s；`shouldFetchSubresources = false` 时 python.org 1.0–1.2、rust-lang.org 1.4–1.8、douban.com 0.5–0.7、zhihu.com 2.2–2.7、wikipedia.org 2.9、apple.com/cn 3.4 s，标题照样取到
  - 用 `URLSession` 读到 `</title>` 为止的耗时与它相近（0.5–2.2 s），但编码与 HTML 实体要自己处理，默认的 User-Agent 下豆瓣返回手机版的标题
  - B 站首页取到的是 “验证码_哔哩哔哩”：被当成了机器人
  - 不存在的域名约 4.3 s 后失败（`LPError.metadataFetchFailed`）
  - `http://` 网址：带 Info.plist、没有 `NSAppTransportSecurity` 的进程（与 Flotilla 相同）0.26 s 就失败（`metadataFetchFailed`），ATS 挡下了明文 HTTP；没有 Info.plist 的命令行进程能取到
  - `timeout` 不是硬上限：命令行进程设了 10 s 取 `http://httpforever.com`，47.85 s 后才以 `metadataFetchTimedOut` 结束
  - `cancel()` 之后完成回调不会立即到达：0.1 s 时取消，回调 1.0–2.6 s 后才带着 `metadataFetchCancelled` 到达，约是本来取完的时候
  - 不是 HTML 的网址以去掉扩展名的文件名作标题：`…/dummy.pdf` 得到 “dummy”，`…/favicon.ico` 得到 “favicon”
- `URL(string:)`：
  - 路径里的空格与中文被百分号编码，不会解析失败：`hello world` 解析成没有 scheme、没有主机名的 `hello%20world`；`https://apple.com/中文` 的路径成为 `%E4%B8%AD%E6%96%87`
  - 主机名里有空格、末尾带换行时解析失败：`https://a b.com`、`https://apple.com\n` 都为 nil
  - 中文域名转成 punycode：`https://例子.中国/路径` 解析成 `https://xn--fsqu00a.xn--fiqs8s/%E8%B7%AF%E5%BE%84`
  - `localhost:8080` 解析成 scheme 为 `localhost`、没有主机名的网址
  - `https://` 没有主机名；`file:///Applications` 没有主机名，`file://localhost/Applications` 的主机名是 `localhost`，两者 `isFileURL` 都为真
  - `HTTPS://EXAMPLE.COM` 保留原样的大小写
