# 09 设置窗口的 “添加…” 菜单与添加网页

先读 [00 总览](00-overview.md) 与 01–08 八份文档，并以 08 阶段合入后的代码为基线。本阶段交付需求 24：设置窗口的 “添加 App…” “添加文件…” 两个按钮合并为一个 “添加…”，点击后弹出菜单，菜单里另有 “添加网页…”，输入网址把网页加入文件夹。

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

`Settings/AddWebPageAlert` 持有 `NSAlert` 与输入框，做输入框的 delegate，确认后把要加入的网页交给调用方。

- 以 sheet 弹出 `NSAlert`，挂在设置窗口上，与 “添加 App…” 的选择面板一致：
  - 标题（`messageText`）：添加网页
  - 说明（`informativeText`）：输入网页的网址。
  - 附件（`accessoryView`）：单行输入框（`NSTextField(string:)`），设为窗口的 `initialFirstResponder`，弹出时就是第一响应者，可以直接打字、⌘V 粘贴
  - 按钮：“添加” 是第一个按钮，即默认按钮，回车触发；“取消” 的 key equivalent 显式设为 Esc：只有英文标题 “Cancel” 会自动得到 Esc
- 输入不是可用的网址时 “添加” 禁用，随输入实时更新（`controlTextDidChange(_:)`，键入与粘贴都会触发）；空输入时禁用
  - 提示框不会在用户确认后才报错，也不必再弹第二个提示框
- 点 “添加”：把网页加入弹出时选中项所属的文件夹，标题为 nil，显示名就是网址，与没有标题的拖入网页一致
- 点 “取消” 或按 Esc：什么都不变
- 弹出期间那个文件夹被删掉：`addItems` 找不到它，什么都不做
- 输入框与上方的说明文字左右对齐，不把提示框撑宽：
  - 先不带附件 `layout()` 一次，得到提示框的宽度；输入框宽 = 提示框内容宽 − 2 × 20
  - 正文宽度随按钮标题变化：英文 “Cancel” 把提示框撑到 265 pt，正文宽 225；其它四种语言提示框 260 pt，正文宽 220（实测 macOS 27）
- `FolderTreeViewController` 只在菜单项被点时取目标文件夹、弹出提示框、把结果交给 `store.addItems`
  - 输入框的 delegate 是 `AddWebPageAlert`，不是 `FolderTreeViewController`：后者已是树里改名输入框的 delegate，`controlTextDidEndEditing(_:)` 会被两边混用
  - 弹出期间由 `beginSheetModal` 的完成回调持有 `AddWebPageAlert`：输入框的 delegate 是弱引用

### 输入怎样成为网页

`AddWebPageAlert.webPage(from:)`。这条规则只属于 “添加网页…”，不改 `FolderItem(url:title:)` 与拖入的规则。

1. 去掉首尾空白与换行；结果为空 → 不可用
2. 中间还有空白 → 不可用（多半是把一句话当成了网址）
3. 没有 `://` 时在前面补 `https://`，像浏览器地址栏那样：`apple.com` → `https://apple.com`，`localhost:8080/a` → `https://localhost:8080/a`
4. `URL(string:)` 解析失败，或解析出的网址没有主机名（如只输入了 `https://`）→ 不可用
5. 文件 URL → 不可用：在交给分类之前就挡下，不让它去碰文件系统
6. 是不是网页交给 `FolderItem(url:title:)`，标题传 nil：它只收 `http`、`https`（不区分大小写）
7. 除以上之外不做任何规整：大小写、末尾斜杠、`www.` 都保持用户输入的样子

### 加入与去重

- 经 `FolderStore.addItems` 加入，照它的去重：同一个文件夹里已有同一网址的网页时不重复加入（见 06）

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
| `folders.webPageAlert.informative` | Enter the address of the web page. | 输入网页的网址。 | 輸入網頁的網址。 | WebページのURLを入力してください。 | 웹 페이지의 주소를 입력하십시오. |
| `folders.webPageAlert.add` | Add | 添加 | 加入 | 追加 | 추가 |
| `folders.webPageAlert.cancel` | Cancel | 取消 | 取消 | キャンセル | 취소 |

- 省略号用 `…`（U+2026），与 “添加 App…” 一致
- `.strings` 里新键放在 “设置窗口的文件夹区” 一段，顺序与界面一致

## 单元测试

- 输入怎样成为网页（`AddWebPageAlertTests`）：
  - 完整网址原样采用：`https://www.apple.com/cn/`、`http://example.com/path?q=1`、`HTTPS://EXAMPLE.COM`；得到的是网页项，标题为 nil
  - 首尾空白、换行被去掉
  - 补 `https://`：`apple.com`、`apple.com/path?q=1`、`localhost:8080`
  - 不可用：空串、只有空白、`hello world`、`https://`、`ftp://example.com`
  - `file:///Applications` 不可用，这个目录存在也不成为文件项
- 提示框（`AddWebPageAlertTests`，不开窗口）：
  - 提示框自己是输入框的 delegate；刚弹出时 “添加” 禁用，输入 `apple.com` 后可用，改成 `ftp://x` 又禁用（直接改输入框的值，再按 delegate 的方式通知）
  - “添加” 的 key equivalent 是回车，“取消” 是 Esc
  - 标题、说明、按钮的文字用的是上表的键（测试进程读不到译文，读到的是键名）
  - 输入框是窗口的 `initialFirstResponder`；`layout()` 之后与说明文字左右对齐
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
  - 以 sheet 挂在设置窗口上弹出；标题 “添加网页”、说明 “输入网页的网址。”；输入框与说明文字左右对齐，五种语言下提示框都没有被输入框撑宽
  - 弹出后不点输入框直接打字，文字进入输入框；⌘V 能粘贴
  - 空输入时 “添加” 禁用；输入 `apple.com` 后可用；改成 `hello world` 或 `ftp://example.com` 又禁用；粘贴进来的网址同样实时更新
  - “添加” 可用时按回车等同点 “添加”；禁用时回车不加入
  - 按 Esc 等同点 “取消”，什么都不加入；中文、日文、韩文界面下同样如此
  - 点 “添加” 后：网页出现在选中项所属文件夹的末尾，行里显示蓝色地球图标与网址；面板里同样显示，点击用默认浏览器打开
  - 同一个文件夹里再加一次同一网址：不重复
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
- `URL(string:)`：
  - 路径里的空格与中文被百分号编码，不会解析失败：`hello world` 解析成没有 scheme、没有主机名的 `hello%20world`；`https://apple.com/中文` 的路径成为 `%E4%B8%AD%E6%96%87`
  - 主机名里有空格、末尾带换行时解析失败：`https://a b.com`、`https://apple.com\n` 都为 nil
  - 中文域名转成 punycode：`https://例子.中国/路径` 解析成 `https://xn--fsqu00a.xn--fiqs8s/%E8%B7%AF%E5%BE%84`
  - `localhost:8080` 解析成 scheme 为 `localhost`、没有主机名的网址
  - `https://` 没有主机名；`file:///Applications` 没有主机名，`file://localhost/Applications` 的主机名是 `localhost`，两者 `isFileURL` 都为真
  - `HTTPS://EXAMPLE.COM` 保留原样的大小写
