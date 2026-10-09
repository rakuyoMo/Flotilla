# 09 设置窗口的 “添加…” 菜单与添加网页

先读 [00 总览](00-overview.md) 与 01–08 八份文档，并以 08 阶段合入后的代码为基线。本阶段交付需求 24：设置窗口的 “添加 App…” “添加文件…” 两个按钮合并为一个 “添加…”，点击后弹出菜单，菜单里另有 “添加网页…”，输入网址与可选的标题把网页加入组，标题留空时自动获取网页的标题。

## 规则

### 按钮行与菜单

- “添加 App…” 与 “添加文件…” 两个按钮合并为一个 “添加…”：`NSPopUpButton` 的 pull-down（`pullsDown = true`），点击后在按钮下方弹出菜单
- 按钮行从左到右：新建组 · 添加…；“添加到 Dock” 与 “删除” 在组树的右键菜单里，见 10
- 菜单从上到下：添加 App… · 添加文件… · 添加网页…
  - pull-down 的第一项是按钮上显示的 “添加…”，不出现在菜单里
  - 其后三项各自带 target 与 action，选中后直接调用对应的方法
- 只在选中组时 “添加…” 可用（需求 31，见 12）；三项都加入选中的组（`containingGroupID`）
- “添加 App…” “添加文件…” 的行为不变（见 01、07），原来的键 `groups.addApps`、`groups.addFiles` 原样用作菜单项的标题
- 外观：pull-down 与相邻的按钮同高 24 pt，按钮行保持默认的垂直居中；实测（macOS 27）第一条基线距顶 16.75 pt，按钮是 17 pt

### “添加网页…” 的提示框

`Settings/WebPageAlert` 持有 `NSAlert`、网址框与标题框，做两个输入框的 delegate，确认后把要加入的网页交给调用方；网页的 “编辑…” 同样用它，见 10。

- 以 sheet 弹出 `NSAlert`，挂在设置窗口上，与 “添加 App…” 的选择面板一致：
  - 标题（`messageText`）：添加网页
  - 说明（`informativeText`）：输入网页的网址，标题可留空。
  - 附件（`accessoryView`）：上下两个单行输入框（`NSTextField(string:)`），相距 8 pt
    - 网址框在上，占位文字 “网址”；弹出时就是第一响应者，可以直接打字、⌘V 粘贴：设为窗口的 `initialFirstResponder`，`beginSheetModal` 之后再显式 `makeFirstResponder`，见 “平台事实”
    - 标题框在下，占位文字 “标题（可选）”；获取标题期间的样子见 “自动获取标题”
    - Tab 从网址框到标题框，Shift-Tab 回来：提示框的窗口按位置排出 Tab 的顺序，不另外设 `nextKeyView`
  - 按钮：“添加” 是第一个按钮，即默认按钮，两个框里按回车都触发它；“取消” 的 key equivalent 显式设为 Esc：只有英文标题 “Cancel” 会自动得到 Esc
- 网址不是可用的网址时 “添加” 禁用，随输入实时更新（`controlTextDidChange(_:)`，键入与粘贴都会触发）；空输入时禁用；标题框的内容不影响它
  - 提示框不会在用户确认后才报错，也不必再弹第二个提示框
- 点 “添加”：把网页加入弹出时选中的组
  - 标题框有内容：去掉首尾空白后作为标题，显示名就是它
  - 标题框空着：先不带标题加入，显示名是网址，与没有标题的拖入网页一致；取到标题后补上（见 “自动获取标题”）
- 点 “取消” 或按 Esc：什么都不变
- 弹出期间那个组被删掉：`addItems` 找不到它，什么都不做
- 两个输入框都与上方的说明文字左右对齐，不把提示框撑宽：
  - 先不带附件 `layout()` 一次，得到提示框的宽度；输入框宽 = 提示框内容宽 − 2 × 20
  - 正文宽度随按钮标题变化：英文 “Cancel” 把提示框撑到 265 pt，正文宽 225；其它四种语言提示框 260 pt，正文宽 220（实测 macOS 27）
- `GroupTreeViewController` 只在菜单项被点时取目标组、弹出提示框，把要加入的网页交给 `store.addItems`，把晚到的标题交给自己的 `fillTitle(_:of:)`
  - 输入框的 delegate 是 `WebPageAlert`，不是 `GroupTreeViewController`：后者已是树里改名输入框的 delegate，`controlTextDidEndEditing(_:)` 会被两边混用
  - 弹出期间由 `beginSheetModal` 的完成回调持有 `WebPageAlert`：输入框的 delegate 是弱引用

### 输入怎样成为网页

`WebPageAlert.webPage(from:)`。这条规则只属于网页的提示框（“添加网页…” 与网页的 “编辑…”，见 10），不改 `GroupItem(url:title:)` 与拖入的规则。

1. 去掉首尾空白与换行；结果为空 → 不可用
2. 中间还有空白 → 不可用（多半是把一句话当成了网址）
3. 开头不是 `scheme://` 时在前面补 `https://`，像浏览器地址栏那样：`apple.com` → `https://apple.com`，`localhost:8080/a` → `https://localhost:8080/a`
   - scheme 按 RFC 3986：字母开头，其后是字母、数字、`+`、`-`、`.`
   - 只看开头：查询参数里的 `://` 不算，`apple.com/?u=https://x.com` → `https://apple.com/?u=https://x.com`，`localhost:8080/?next=http://x` → `https://localhost:8080/?next=http://x`
   - 开头已有 scheme 的不补：`ftp://example.com` 保持原样，到第 6 条被判为不可用
4. `URL(string:)` 解析失败，或解析出的网址没有主机名（如只输入了 `https://`）→ 不可用
   - 交给 `URL(string:)` 之前，主机名之后的中文等非 ASCII 字符先按 UTF-8 编码，已有的百分号编码照原样（见 [12](12-groups.md) 的需求 34）
5. 文件 URL → 不可用：在交给分类之前就挡下，不让它去碰文件系统
6. 是不是网页交给 `GroupItem(url:title:)`，标题传标题框里的文字：它只收 `http`、`https`（不区分大小写），标题去掉首尾空白、空串视为没有
7. 除以上之外不做任何规整：大小写、末尾斜杠、`www.` 都保持用户输入的样子

### 加入与去重

- 经 `GroupStore.addItems` 加入，照它的去重：同一个组里已有同一网址的网页时不重复加入（见 06）

### 自动获取标题

`Settings/WebPageTitleFetcher` 用系统的 LinkPresentation（`LPMetadataProvider`）获取网页的标题：`shouldFetchSubresources = false`。跳转、编码与 HTML 实体都由它处理，Flotilla 不解析 HTML。

- 为什么关掉附带资源：默认连带下载图标、预览图等附带资源，实测 2.8–6.6 s；关掉之后 0.5–3.4 s，标题照样取到（见 “平台事实”）
- `http://` 网址同样取得到：Info.plist 的 `NSAppTransportSecurity` 里只设 `NSAllowsArbitraryLoadsInWebContent`，只为网页内容放开明文 HTTP；没有它时 ATS 挡下 `http://` 网址（见 “平台事实”）
- 何时获取：
  - 网址框的内容变成可用的网址，并且停顿 0.3 s 不再变，就为这个网址开始获取，取的是补好 scheme 之后的网址
  - 网址再变：取消正在进行的那一次，重新计时；不可用的网址不获取
- 时限：一次获取最多等 10 s
  - 从开始获取算起，0.3 s 的停顿不算在内；点 “添加” 之后获取继续，时限仍从开始获取时算起，不重新计时
  - 到时还没有结果：取消这一次，当作取不到
  - 到时之后才到的结果一律丢掉：包括取消之后才到的完成回调，也包括到时之后才取到的标题
  - 时限由 `WebPageAlert` 掐断，不设 LinkPresentation 的 `timeout`：它不是硬上限（见 “平台事实”）
- 标题框任何时候都能输入，获取期间也一样
- 取到的标题去掉首尾空白，空串当作没取到
- 怎样填：
  - 取到时标题框空着才填进去；用户自己输入的内容绝不覆盖
  - 网址变了：标题框里仍是自动填进去、用户没改过的旧标题就清空，等新网址的结果；用户自己输入的保留
  - 取不到（失败、到时、网页没有标题、标题只是文件名）：什么都不填，不提示错误
- 不是网页的网址（PDF、图片等）：LinkPresentation 拿网址里的文件名充当标题（见 “平台事实”），当作取不到
  - `WebPageTitleFetcher.isFileName(_:of:)` 判断：标题与跳转之后的网址（`LPLinkMetadata.url`）最后一段去掉扩展名完全相同，就是文件名
  - LinkPresentation 不公开内容类型，只能拿标题与网址比；在后台队列的完成回调里判断完，只把标题字符串带回主线程
  - 大小写敏感，与 LinkPresentation 给出的一致：`/about` 的网页标题 “About” 保留
  - 网页自己的标题恰好与文件名相同时（`/Report.html` 的 “Report”）分辨不出，同样不填
- 转圈与占位文字：
  - 正在获取、且标题框空着时，标题框内右端显示小号转圈（`NSProgressIndicator`，spinning，small，16 × 16 pt，距标题框的右边与上下各 4 pt），占位文字换成 “正在获取标题…”
  - 转圈盖在标题框上面，不占标题框的位置
  - 取完（取到或取不到），或标题框里有了内容：转圈隐藏，占位文字恢复 “标题（可选）”
- 点 “添加”：
  - 标题框有内容：带着它加入，取消正在进行的获取
  - 标题框空着：先不带标题加入；正在进行的那一次继续，不重新发起；还在等停顿的不再等，立刻开始；取到后补到刚加入的那一项上
- 点 “取消” 或按 Esc：取消正在进行的获取，作废正在等的停顿，什么都不加入
- 被取消或已到时的那一次晚到的结果丢掉：LinkPresentation 取消之后仍会调用完成回调（见 “平台事实”），每次获取带编号，只认最新的一次
- 提示框关掉之后，获取的完成回调持有 `WebPageAlert`，直到结果到达；它把标题连同不带标题交出的那一份网页（`WebPageReference`：id、取标题的网址，标题为 nil）交给 `beginSheetModal` 的 `titleHandler(_ title: String, _ webPage: WebPageReference)`。`GroupTreeViewController` 不直接碰 LinkPresentation
  - 交出的那一份的网址就是取标题的网址：每次网址变化都取消之前的获取，交出时正在进行或随即开始的获取，取的就是它
- `WebPageAlert.init(editing:fetchTitle:waitForPause:waitForTimeLimit:)` 接收取标题、等停顿与等时限的方法（`editing` 见 10）：App 里用 `WebPageTitleFetcher`，停顿与时限分别是 0.3 s 与 10 s 的 `Task.sleep`；单元测试传入假实现，不联网、不真的等待

### 补标题

- `GroupStore.fillTitle(_:of:)`：按交来的那一份网页的 id 找，只在这一项仍在、是网页、网址仍是取标题时的那个、标题仍为 nil 时才改，位置与 id 不变；改了就提交并发一次变更通知，没改就什么都不做
  - 网址已不是取标题时的那个：晚到的标题不属于它，丢掉；保存之后网址又被改掉时会这样，见 10 的 “编辑…”
  - 去重时没有真正加入（同一个组里已有同一网址）：按 id 找不到，什么都不做
- 正在编辑组名时不补：补标题会重建树，重建会结束编辑并提交输入到一半的名称；与 `updateItemLocations()` 一样按 `isEditingGroupName` 判断
  - `GroupTreeViewController` 把标题连同交来的那一份网页按先后记下，编辑结束后依次交给 `fillTitle(_:of:)`，由它按上一条取舍
  - 同一项先后记下的几条都留着：旧网址的标题可能晚到，不能把新网址的挤掉
  - 按回车或点别处结束编辑：在 `controlTextDidEndEditing(_:)` 里改名之后补
  - 按 Esc 取消编辑：outline view 不发 `controlTextDidEndEditing(_:)`；在 `control(_:textView:doCommandBy:)` 里排一个主线程任务，outline view 结束编辑之后补
- 补标题不改写 stub、不重启 Dock：
  - stub 改写与否看 Info.plist 是否逐字节变化、图标是否按像素变化（见 02，`DockTileBundleBuilder.write(group:icon:)`）：Info.plist 里随组变化的只有根组的名称与 id；网页在图标里用所有网页共用的地球图标，与标题无关
  - Dock 偏好改动与否看各 tile 的条目（`DockPreferences.apply`）：标签是根组的名称，stub 没改写就不换 GUID
  - 变更通知仍会让 `DockTileSynchronizer` 同步一次：重新渲染图标、比对一致，不写文件

## 设置窗口

- 窗口尺寸不变（见 07）：最窄时组区宽 530
- 按钮行宽的实测见 10
- “添加…” 宽 80.5–84 pt：pull-down 的宽度只取决于第一项的标题

## 本地化

键与文字：

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `groups.add` | Add… | 添加… | 加入… | 追加… | 추가… |
| `groups.addWebPage` | Add Web Page… | 添加网页… | 加入網頁… | Webページを追加… | 웹 페이지 추가… |
| `groups.webPageAlert.message` | Add Web Page | 添加网页 | 加入網頁 | Webページを追加 | 웹 페이지 추가 |
| `groups.webPageAlert.informative` | Enter the address of the web page. The title is optional. | 输入网页的网址，标题可留空。 | 輸入網頁的網址，標題可留空。 | WebページのURLを入力してください。タイトルは省略できます。 | 웹 페이지의 주소를 입력하십시오. 제목은 비워 둘 수 있습니다. |
| `groups.webPageAlert.addressPlaceholder` | Address | 网址 | 網址 | URL | 주소 |
| `groups.webPageAlert.titlePlaceholder` | Title (Optional) | 标题（可选） | 標題（可選） | タイトル（オプション） | 제목(선택 사항) |
| `groups.webPageAlert.fetchingTitle` | Fetching Title… | 正在获取标题… | 正在取得標題… | タイトルを取得中… | 제목 가져오는 중… |
| `groups.webPageAlert.add` | Add | 添加 | 加入 | 追加 | 추가 |
| `groups.webPageAlert.cancel` | Cancel | 取消 | 取消 | キャンセル | 취소 |

- 省略号用 `…`（U+2026），与 “添加 App…” 一致
- `.strings` 里新键放在 “设置窗口的组区” 一段，顺序与界面一致

## 单元测试

- 输入怎样成为网页（`WebPageAlertTests`）：
  - 完整网址原样采用：`https://www.apple.com/cn/`、`http://example.com/path?q=1`、`HTTPS://EXAMPLE.COM`；得到的是网页项，标题为 nil
  - 首尾空白、换行被去掉
  - 补 `https://`：`apple.com`、`apple.com/path?q=1`、`localhost:8080`，以及查询参数里带着网址的 `apple.com/?u=https://x.com`、`localhost:8080/?next=http://x`
  - 不可用：空串、只有空白、`hello world`、`https://`、`ftp://example.com`
  - `file:///Applications` 不可用，这个目录存在也不成为文件项
- 提示框（`WebPageAlertTests`）：
  - 提示框自己是两个输入框的 delegate；刚弹出时 “添加” 禁用，网址输入 `apple.com` 后可用，改成 `ftp://x` 又禁用，标题框的内容不影响它（直接改输入框的值，再按 delegate 的方式通知）
  - “添加” 的 key equivalent 是回车，“取消” 是 Esc
  - 标题、说明、按钮与两个占位文字用的是上表的键（测试进程读不到译文，读到的是键名）
  - 网址框在上、标题框在下，`layout()` 之后都与说明文字左右对齐；网址框是窗口的 `initialFirstResponder`
  - 以 sheet 弹出，`beginSheetModal` 一返回网址框就是第一响应者；Tab 到标题框，Shift-Tab 回来
- 自动获取标题（`WebPageAlertTests`，`WebPageAlertStub` 代替取标题、等停顿与等时限，由测试决定停顿何时结束、哪一次获取到时、何时交出什么标题）：
  - 不可用的网址、停顿之前都不获取；停顿之内网址又变了就重新计时，只为最后的网址获取一次，取的是补好 scheme 的网址
  - 获取期间网址变了：前一次被取消，停顿之后为新网址重新获取
  - 取到时标题框空着就填，首尾空白去掉；取不到或只有空白时保持空着
  - 用户输入的标题不被覆盖；换网址时自动填的旧标题清空、换成新网址的，被取消的那一次晚到的结果丢掉；换网址时用户输入的保留
  - 获取期间标题框可以输入；转圈与 “正在获取标题…” 只在获取中、标题框空着时显示，取完恢复
- 添加与取消（`WebPageAlertTests`，以 sheet 挂在放在所有屏幕之外的窗口上，`performClick(_:)` 点按钮）：
  - 标题框有内容：带着去掉首尾空白的标题加入，获取被取消，之后取到的标题不补
  - 标题框空着、正在获取：先不带标题加入，取到后补到这一项上，只获取一次
  - 标题框空着、还在等停顿：立刻开始获取，停顿结束时不重复获取
  - 标题框空着、取不到：网页照样加入，显示名是网址，什么都不补
  - “取消”：获取被取消，正在等的停顿作废，什么都不加入，之后取到的标题不补
- 时限（`WebPageAlertTests`）：
  - 获取进行中到时：这一次被取消，转圈隐藏、占位文字恢复；之后再交出这个网址的标题，标题框也不填
  - 不带标题加入之后到时：这一次被取消，这一项保持显示网址，之后才到的标题不补
  - 换了网址之后，旧网址那一次到时：新的获取不被取消，转圈还在，取到的标题照样填入
  - 已经取完之后到时：不再取消，填好的标题保留
- `WebPageTitleFetcherTests`：
  - Info.plist 的 `NSAppTransportSecurity` 只有 `NSAllowsArbitraryLoadsInWebContent` 一个键，值为真
  - 认得出文件名：`dummy.pdf`、`favicon.ico`、`picture.png`、`plain.txt`、没有扩展名的 `noext`、以 `/` 结尾的 `dir/`、`dummy.v2.pdf`（“dummy.v2”）、百分号编码的 `my%20file.pdf` 与中文文件名、带查询参数或片段的 `dummy.pdf`
  - 网页自己的标题保留：普通网页、首页（有无末尾斜杠），以及只是大小写与文件名不同的 “About”（`/about`）、“Dummy”（`/dummy.pdf`）
- 补标题：
  - `GroupStoreTests`：标题为 nil 的网页补上，位置与 id 不变，只发一次通知，重新加载后仍在；已有标题的网页、不是网页的项、找不到的项都不变，也不发通知
  - `GroupTreeViewControllerTests`（离屏窗口里用 `editColumn` 造出编辑组名的状态）：没在编辑时立刻补；编辑中先不补，编辑没被打断、输入到一半的名称没有提交，点别处结束编辑后名称与标题都写进去；按 Esc 取消编辑后补上，名称保持原样
  - `DockTileBundleBuilderTests`：网页补上标题，stub 不改写
- 组区（`GroupTreeViewControllerTests`）：
  - 按钮行是两个控件，顺序为 新建组、添加…（见 10）；“添加…” 是 pull-down
  - “添加…” 的菜单依次是 添加 App…、添加文件…、添加网页…，各自接到对应的方法，target 是组区
  - “添加…” 只在选中组时可用：没有选中项，或选中 App、文件、访达文件夹、网页时禁用（见 12）
  - 按钮行宽：五种语言各一例，见 07；“添加…” 换上译文后第一项的标题就是译文，宽度与只有这一项的 pull-down 相同
- 新键五种语言齐全：`LocalizationTests` 自动覆盖

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过
- 按钮行与菜单：
  - 按钮行从左到右为 新建组 · 添加…（见 10）；“添加…” 右侧有下拉箭头，与相邻按钮同高，文字基线看起来对齐
  - 选中根组或子组时 “添加…” 可用；没有选中项，或选中 App、文件、访达文件夹、网页时禁用（见 12）
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
  - 同一个组里再加一次同一网址：不重复
- 自动获取标题：
  - 键入 `apple.com` 停顿一下：标题框内右端出现小号转圈，占位文字变成 “正在获取标题…”；一两秒后标题框填上网页的标题，转圈消失
  - 转圈期间在标题框里打字：转圈消失，占位文字恢复；取到的标题不覆盖打的字
  - 自动填上标题之后改网址：标题清空，停顿之后重新获取；自己打的标题改网址后仍在
  - 填了标题点 “添加”：网页以这个标题出现在选中的组的末尾，行里显示蓝色地球图标与标题；面板里同样显示，点击用默认浏览器打开
  - 标题框留空、转圈期间就点 “添加”：网页先以网址出现，取到后这一行换成标题，面板里同样
  - 键入网址后立刻（不到 0.3 s）点 “添加”：同上，取到后补上
  - 标题框留空点 “添加” 之后，马上新建组或双击组名开始改名：输入到一半的名称不被打断；按回车、点别处或按 Esc 结束编辑之后，标题才补上
  - 取不到标题的网址（不存在的域名）：网页照样加入，显示网址，不提示错误
  - `http://example.com`：同样取得到标题 “Example Domain”
  - PDF、图片的网址（如 `https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf`）：转圈消失，标题框不填；留空加入的那一项保持显示网址
  - 迟迟没有响应的网址：转圈最多 10 s 就消失，标题框不填，之后也不会突然填上；留空加入的那一项保持显示网址
  - 补上标题时 Dock 不重启
- 设置窗口的标题：五种语言下依次为 Settings、设置、設定、設定、설정
- 退出重开 Flotilla 后数据仍在

## 平台事实

以下除注明外都是 macOS 27 上的实测。

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
  - macOS 26（CI 的 `macos-26` 镜像，测试进程里）：`initialFirstResponder` 设成网址框后以 sheet 弹出，`beginSheetModal` 返回时窗口的第一响应者不是网址框，Tab 之后才到网址框；macOS 27 上返回时已经是网址框，键盘导航关闭时 `initialFirstResponder` 留着 `layout()` 设的按钮也是
  - 按钮设成禁用后，`layout()` 不会改回可用
  - 窗口的 `autorecalculatesKeyViewLoop` 为真：附件里上下放两个输入框，不设 `nextKeyView`，网址框 Tab 到标题框，标题框 Shift-Tab 回到网址框
  - 附件里放两个 24 pt 高的输入框、相距 8 pt 时，简体中文的提示框为 260 × 274 pt（一个输入框时 260 × 242）
  - 不上屏的进程里也能以 sheet 弹出：`beginSheetModal(for:)` 让父窗口的 `isVisible` 变为真（测试把父窗口放在所有屏幕之外）；对按钮 `performClick(_:)` 同步结束 sheet 并调用完成回调
  - 不上屏时 `performKeyEquivalent(with:)` 送回车不会触发默认按钮：提示框的窗口不是 key
- `NSOutlineView` 编辑组名：
  - 离屏窗口里 `editColumn(_:row:with:select:)` 同样让字段编辑器成为窗口的第一响应者
  - 对字段编辑器 `doCommand(by:)` 送 `cancelOperation(_:)`：先经 `control(_:textView:doCommandBy:)`，返回之后 outline view 同步结束编辑，第一响应者回到 outline view；在那里排的主线程任务在这之后执行
- LinkPresentation（`LPMetadataProvider`）：
  - 完成回调在后台队列调用
  - 耗时（冷启动，每个网址单独一个进程）：默认连带附带资源 2.8–6.6 s；`shouldFetchSubresources = false` 时 python.org 1.0–1.2、rust-lang.org 1.4–1.8、douban.com 0.5–0.7、zhihu.com 2.2–2.7、wikipedia.org 2.9、apple.com/cn 3.4 s，标题照样取到
  - 用 `URLSession` 读到 `</title>` 为止的耗时与它相近（0.5–2.2 s），但编码与 HTML 实体要自己处理，默认的 User-Agent 下豆瓣返回手机版的标题
  - B 站首页取到的是 “验证码_哔哩哔哩”：被当成了机器人
  - 不存在的域名约 4.3 s 后失败（`LPError.metadataFetchFailed`）
  - `http://` 网址（可执行文件放进带 Info.plist 的 bundle 里直接运行）：
    - 没有 `NSAppTransportSecurity`：0.19–0.32 s 就失败（`metadataFetchFailed`），ATS 挡下了明文 HTTP；没有 Info.plist 的命令行进程能取到
    - 只设 `NSAllowsArbitraryLoadsInWebContent`：取得到，`http://example.com` 0.75–1.00 s 得到 “Example Domain”，`http://httpforever.com` 3.72 s；`http://neverssl.com` 一次 4.12 s 取到 “Connecting ...”，一次 10.89 s 后失败
    - 只设 `NSAllowsArbitraryLoads`：同样取得到，`http://example.com` 0.65 s
    - `https://example.com` 三种写法都在 0.99–1.24 s 取到
  - `timeout` 不是硬上限，默认 30 s：
    - 本地服务 60 s 后才响应时，不取消的话，不论设 5 s、10 s 还是默认，完成回调都在约 60.4 s 响应到达时才带着 `metadataFetchTimedOut` 到达
    - 命令行进程设了 10 s 取 `http://httpforever.com`，47.85 s 后才以 `metadataFetchTimedOut` 结束
  - `cancel()` 之后完成回调不会立即到达：
    - 0.1 s 时取消，回调 1.0–2.6 s 后才带着 `metadataFetchCancelled` 到达，约是本来取完的时候
    - 加载卡住时，早于 `timeout` 取消，回调在 `timeout` 到点时带着 `metadataFetchTimedOut` 到达：默认时 5 s、10 s 取消都在 30.01 s 到达，设 10 s 时 5 s、9 s 取消都在 10.01 s 到达
    - 不早于 `timeout` 取消，回调等到响应到达：设 10 s 时 10 s、12 s 取消都在 60.54 s 到达
  - 不是网页的网址以网址最后一段去掉扩展名作标题（本地服务与公开网址实测）：
    - PDF、PNG、ICO、纯文本都是：`…/dummy.pdf` 得到 “dummy”，`…/picture.png` 得到 “picture”，`…/favicon.ico` 得到 “favicon”，`…/plain.txt` 得到 “plain”
    - 用的是跳转之后的网址：`/redirect.pdf` 跳到 `/target-name.pdf` 得到 “target-name”；这时 `LPLinkMetadata.url` 是跳转之后的网址，`originalURL` 是原来的
    - 不看 `Content-Disposition`：响应另给了文件名 `other-name.pdf`，标题仍是网址里的 “disposition”
    - 路径没有扩展名、内容是 PDF：整段 “noext”；路径以 `/` 结尾：去掉斜杠的 “dir”
    - 只去掉最后一个扩展名：`dummy.v2.pdf` 得到 “dummy.v2”
    - 百分号编码的文件名给出解码之后的：`my%20file.pdf` 得到 “my file”，`%E4%B8%AD%E6%96%87.pdf` 得到 “中文”
    - 查询参数与片段不算：`dummy.pdf?download=1`、`dummy.pdf#page=2` 都得到 “dummy”
  - 没有 `<title>` 的网页标题为 nil，不拿文件名充当；`<title>` 恰好与文件名相同的网页（`/Report.html` 的 “Report”）与不是网页的网址给出的标题一样
- `URL(string:)`：
  - 路径里的空格与中文被百分号编码，不会解析失败：`hello world` 解析成没有 scheme、没有主机名的 `hello%20world`；`https://apple.com/中文` 的路径成为 `%E4%B8%AD%E6%96%87`
  - 主机名里有空格、末尾带换行时解析失败：`https://a b.com`、`https://apple.com\n` 都为 nil
  - 中文域名转成 punycode：`https://例子.中国/路径` 解析成 `https://xn--fsqu00a.xn--fiqs8s/%E8%B7%AF%E5%BE%84`
  - 替网址的一部分编码非 ASCII 字符或 `{`、`|` 等不合法的字符时，这部分里已有的 `%` 也再编码一次，其余部分不动：`https://example.com/归%20?q=%20` 解析成 `https://example.com/%E5%BD%92%2520?q=%20`
  - `localhost:8080` 解析成 scheme 为 `localhost`、没有主机名的网址
  - `https://` 没有主机名；`file:///Applications` 没有主机名，`file://localhost/Applications` 的主机名是 `localhost`，两者 `isFileURL` 都为真
  - `HTTPS://EXAMPLE.COM` 保留原样的大小写
