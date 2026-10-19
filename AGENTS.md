# AGENTS.md

本文件是协作 Agent（Claude Code、Codex 等）在本仓库工作时的指引，同时也是人类阅读的协作规范源。

## 项目概述

Flotilla 是一个原生 macOS App：在 Dock 上增加 “组”，把多个 App 分类收纳进去，组里也可以放文件、访达文件夹与网页；点击组后在 Dock 上展开，显示其中的内容，点击即可打开，访达文件夹则像 Dock 叠放那样继续展开。

- 中文名 “归帆”，繁体写作 “歸帆”：简繁中文环境下 App 以这个名字显示，中文界面文案提到 App 时也写这个名字
- 日文名 “帰帆”：日文环境下 App 以这个名字显示，日文界面文案提到 App 时也写这个名字
- 纯开源的个人工具，只在 GitHub 分发
- 官网为 <https://flotilla.rakuyo.dev/>，由 GitHub Pages 托管，见 “官网”
- 许可证为 [GPL-3.0](LICENSE)

## 技术栈与环境

- Swift 6 + AppKit，工程由 Swift Package Manager 管理
- 开发环境只有 Xcode Command Line Tools，**不安装 Xcode**
- 最低支持 macOS 15

### Command Line Tools 的限制

- **不能用 SwiftUI**：Command Line Tools 不带 `@State` 等宏的实现插件 `SwiftUIMacros`，编译直接报错；界面一律用 AppKit
- **没有 XCTest**：单元测试用 Swift Testing（`import Testing`），通过 `swift test` 运行
- **没有 `actool` 与 `ibtool`**：不能编译 `.xcassets`，也不能用 storyboard / xib，界面全部用代码构建
- **编译时的两条 `ld: warning: search path ... not found` 可以忽略**：它们指向 Command Line Tools 里本来就没有的目录

## 常用命令

`mise.toml` 是所有工具脚本的统一入口，优先使用其中已定义的任务。

| 命令 | 作用 |
|---|---|
| `mise run build` | 编译 debug 版本 |
| `mise run bundle` | 编译 release 版本，打包为 `build/Flotilla.app` 并 ad-hoc 签名 |
| `open build/Flotilla.app` | 启动打包好的 App |
| `swift test` | 运行单元测试 |
| `mise run swift:format` | 按代码规范自动格式化 |
| `mise run swift:lint` | 检查代码规范 |
| `mise run release <版本号>` | 为新版本开 release PR，见 “发布流程” |
| `mise run site:build` | 组装官网到 `build/site/`，见 “官网” |
| `mise run site:preview` | 组装官网并在本机预览，地址为 `http://localhost:8000/` |

## 目录结构

```
Sources/Flotilla/       App 源码
  Model/                组的数据模型与持久化
  Preferences/          用户设置
  Rendering/            组图标渲染、App 图标的透明与色调处理
  StatusBar/            状态栏图标与菜单
  Settings/             设置窗口
  Resources/            五种语言的 Localizable.strings、InfoPlist.strings 与白天、夜间两版 App 图标母版，不参与编译；
                        由打包脚本拷入 .app，图标母版转成 icns；官网的 App 图标与 favicon 也由图标母版生成
  Panel/                Dock 上展开的面板
  Dock/                 stub 生成、Dock 偏好读写与 tile 同步
  Info.plist            App 包的 Info.plist，不参与编译，由打包脚本拷入 .app
Sources/FlotillaDockTile/  Dock tile 的 stub 可执行文件，由打包脚本拷入 .app
Tests/FlotillaTests/    单元测试（Swift Testing）
Scripts/appcast.sh      更新清单脚本：压缩打包好的 App，生成嵌入更新说明的签名更新清单，输出到 build/updates/
Scripts/bundle.sh       打包脚本：组装 .app 并签名
Scripts/check-release-notes.sh  检查某个版本的更新说明是否齐全，发版脚本、更新清单脚本与两个 workflow 共用
Scripts/embed-release-notes.swift  把每种语言的更新说明与更新日志页链接嵌进更新清单，由 appcast.sh 调用
Scripts/generate-site-pages.swift  官网页面生成脚本：按语言清单与各语言文案，把页面模板生成每种语言的页面，由 site.sh 调用
Scripts/release.sh      发版脚本：改版本号，连同这一版的更新说明开 release PR
Scripts/site.sh         官网组装脚本：生成页面、拷入 404 页与样式脚本、生成位图、取 Release 数据与各语言的更新说明，输出到 build/site/
docs/release-notes/     每个版本的更新说明：X.Y.Z/ 下每种语言一份 <语言>.md，见 “更新说明”
docs/requirements/      需求文档：00 为总览，01–13 为按实现顺序拆分的阶段
docs/resources/         README 的头图 readme-header-<en|zh>-<light|dark>.png：英文、中文各一套，各有浅色、深色两版；
                        README 的截图 screenshot-<panel|stack|settings>-<en|zh>-<light|dark>.<jpg|png>，分法同头图；
                        帆船画稿 sailing-ship-*.png；
                        官网组装时从这里取截图与帆船画稿，并由浅色头图生成分享图
website/                官网源码：pages/ 下是页面模板，locales/ 下是语言清单 languages.json 与每种语言一份的文案 <语言代码>.json，
                        组装时生成每种语言的页面，英文在根目录，简体中文、繁体中文、日文、韩文分别在 zh/ zh-hant/ ja/ ko/；
                        404.html 只有英文，原样拷贝；
                        assets/ 下是样式与脚本，位图在组装时生成，不进仓库
.github/workflows/      GitHub Actions：ci.yml 检查与构建，release-notes.yml 检查 release PR 的更新说明，release.yml 发布新版本，pages.yml 组装并部署官网
.claude/skills/release/ Claude Code 的 release skill：用自然语言发布新版本
.claude/agents/         Claude Code 的 flotilla-implementer 代理：按阶段需求文档实现功能
README.md               英文 README：介绍、功能、安装、权限、使用方法、工作原理与对系统的改动、从源码构建、开发与贡献说明
README-ZH.md            README.md 的简体中文版，与它同步修改
```

## 开发注意事项

### 辅助功能权限

- 打包产物是 ad-hoc 签名，重新打包后原来的辅助功能授权可能失效，需要在 “系统设置 › 隐私与安全性 › 辅助功能” 里重新授权
  - macOS 27 里这一页是 “隐私与安全 › 设备控制和数据访问”
- 从终端直接运行 `build/Flotilla.app/Contents/MacOS/Flotilla` 时，进程沿用终端的辅助功能授权
- 用 `open build/Flotilla.app` 启动时按 Flotilla 自己的授权判定；没有授权时，第一次点击 tile 会弹出授权提示
- 两种启动方式可以分别用来验证有权限、无权限两条路径

### 测试与日志

- `swift test` 偶尔编译失败，报 `plugin for module 'TestingMacros' not found`，重跑即可；刚跑过 `mise run swift:format` 之后更容易出现
  - 在 git worktree 里每次都会报，要显式给出插件目录：`swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`
- zsh 里的 `log` 是内建命令，查看系统日志要写全路径 `/usr/bin/log`，例如：

  ```bash
  /usr/bin/log show --last 5m --predicate 'subsystem == "com.rakuyo.flotilla"'
  ```

### Dock 偏好

- 调试时修改 Dock 偏好之前，先用 `defaults export com.apple.dock <文件>` 备份
- 只增删 Flotilla 自己的 tile，不碰其它 tile 与 Dock 的其它设置

## 协作约定

- 对用户的每一次发言，都先 **ultrathink** 再回答
- 实现需求时，拿不准或靠推测写下的地方，用 `#warning("TODO: ...")` 标记，并在修改完成后汇报

## 编码规范

### 通用

- 尽可能使用模块化思想，组件、文件、类型都要符合 “**高内聚低耦合**”
- 使用**提前返回**优化执行逻辑
- 私有方法放在文件最后面，越是工具性质的方法越靠后
- 每个文件末尾保留**一个**空行：不能让代码成为最后一行，也不能有多个连续空行

### Swift

- **每个文件只包含一个类型**（struct / class / enum / protocol）
  - 文件名与类型名一致
  - 辅助类型也独立成文件，访问级别用默认的 `internal`（不显式写出），不用 `private`
- 闭包里尽量用 `$0`、`$1` 等简写参数
  - 参数超过 2 个时写完整参数名
  - 嵌套闭包中，内层要引用外层的参数时，外层必须用命名参数

### 中文行文

- 日志、代码注释、文档使用中文
- 中文与英文之间、中文与数字之间、符号和文本之间留一个空格，如 `2 × 2`、`100 / 1024`、`A → B`、`——`
  - 引号的外侧同样留空格，连着的几个引号之间也留，如 `访达文件夹如果在 “文稿” “桌面” “下载” 等位置`
  - 紧贴不留空格的：
    - 范围号 `–`（`01–08`）与负号（`−5 pt`）
    - 数字后的单位符号（`5.5%`、`45°`）
    - 英文词内的连字符（`ad-hoc`）
    - 快捷键（`⌘⇧.`）
    - 与数字连写的记号（`#22`、`@2x`）
    - 括号与引号的内侧
    - 全角括号的外侧（`归帆（Flotilla）在`）
    - 挨着中文标点或位于行首、行尾的一侧（`见 “发布流程”。`）
- 使用中文弯引号（`“”`），不使用直引号（`""`）
- 照抄系统原生文案的界面文字保持原样，不按本节的空格规则改动
- `// MARK:` 的分节名：
  - 顶层的 `// MARK: -` 用英文：类型名由格式化工具生成，`Private`、`Helpers` 等与之一致
  - 类型体内的用中文

### 注释

- 每个类型、属性、函数（特别是构造函数）的声明都要有完整注释
- 函数实现内部按功能块补充必要说明，帮助读者快速理解意图；**禁止逐行翻译代码**
- **禁止行尾注释**

### 简洁性

- 不为只用一次的逻辑创建抽象层
- 除非逻辑会复用、能显著提升可读性，或有明确的业务边界，否则不新增只调用另一个函数的 wrapper
- 优先使用项目已有的工具和组件，不新造轮子

### 代码规范验证流程

代码风格以 [RakuyoKit/swift](https://github.com/RakuyoKit/swift) 为准；运行过任一 `mise run` 任务后，规则原文位于 `.build/checkouts/swift/Sources/RakuyoSwiftFormatTool/`。

- 新建或编辑 `.swift` 文件后，必须运行 `mise run swift:lint`
- 不通过时先运行 `mise run swift:format` 自动修复，再运行 `mise run swift:lint`，通过才算完成

## 产物可追溯性（番茄炒蛋原则）

> 名字来自一个段子：让 AI 做番茄炒蛋，它加了东坡肉；删掉之后，它又把菜名改成 “番茄炒蛋（无东坡肉）”。东坡肉和它的影子都不该存在。

本节管的不是代码风格，是**产物里能出现什么**。

**产物** = 代码、注释、命名、commit message、PR 文案、文档。

**产物只有两个输入：需求与仓库现状。** 模型自己的想法、多轮讨论里出现过又被否掉的东西、上一版草稿，都不是输入。

判据一句话：**产物里的每一个元素，都要能指出它来自需求的哪一句、或仓库的哪个既有模式；指不出来的，不写。** 追溯不到的就是 dead code：删除，不在代码里解释。

讨论、试错、被否掉的方案、认错与解释，都只留在对话里；产物只装最终状态，不装任何相对中间稿、相对对话的描述。

### 铁律

1. **歧义取最小。** 需求没说清的地方按最小解释做，不按最丰富的；“以防以后要” 不是理由。
2. **想加的，说，不做。** 觉得需求之外还该有什么，在回复末尾用一句话列出，交给用户；不实现、不写进注释，也不为它留 TODO。
3. **注释只写 “是什么、为什么这样”。** “为什么” 只写结论，不复述论证，不指向自己考虑过的其它做法；不写 “暂不” “无需” “后续可” “也可以”。
4. **纠错无痕。** 被指出 “不该有” 的东西是**错误**，不是被否决的**方案**：抹平，不解释它曾经存在，并把为它而存在的参数、导入、辅助方法、测试、文档提及一并清掉。
5. **按身份命名。** 名字说它是什么，不说它比上一版少了什么；“无 XX” “不含 XX” 这类靠 “没有什么” 定义的名字不用。
6. **最小改动的基准是仓库原状，不是自己的上一版草稿。** 理解错了就从纠正后的理解重写，草稿没有任何需要保留的价值。
7. **为没看过对话的人写。** 产物的读者是未来维护者与 reviewer，他们看不到会话；删掉对话记录后说不通、没价值的句子，一律不写。
8. **上下文被压缩或恢复之后，以仓库现状为准，不以摘要为准。** 摘要会保留 “否决了什么”，而那正是不该进产物的东西；续做前重读相关的代码与文档。

**唯一允许写 “为什么不” 的情形**：一个没看过对话的未来维护者也很可能自己走到那条错路上。此时只留**一句**警示，不复述论证。“自己刚想到 / 刚犯过” 不构成理由。

### 交付前自检（必做，放在每次产出的最后一步）

对本次新增的每个元素 —— 代码、注释、名字、commit / PR 文案、文档 —— 问两个问题：

- 指得出它来自需求的哪一句、或仓库的哪个既有模式吗？指不出 → 删
- 删掉对话记录后，这句话还说得通、还有价值吗？说不通 → 删

命中了即改，不必征询。本节的违反是**规范违反**，不是 “代码风格偏好”，review 时不得以后者为由过滤。

## 工作纪律

- **以验证为目标。** 先定义成功标准，循环到验证通过为止，而不是把步骤走完就算完成
- **冲突要摆出来，不要折中。** 两种写法互相矛盾时，选一种（更新的、验证更充分的），在回复里说明理由并指出另一种待清理；不要混用
- **测试验证意图。** 测试要表达 “为什么这个行为重要”；业务逻辑改了还不会失败的测试是错的
- **失败要大声说。** 有步骤被静默跳过，就不能说 “完成”；有测试被跳过，就不能说 “测试通过”；默认把不确定说出来，而不是藏起来

## 参考项目

以下开源项目实现过类似功能。本项目采用 GPL-3.0，引入外部代码前先看对方的许可证：

- **可以引入代码**（MIT，须保留原版权与许可声明）：
  - [goranimperator/imperator-dockfolders](https://github.com/goranimperator/imperator-dockfolders)
  - [wjvalue/macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)
  - [sil-so/macos-dock-folders](https://github.com/sil-so/macos-dock-folders)
- **只能参考思路，不能引入代码**：
  - [takuarc/FolderDock](https://github.com/takuarc/FolderDock)：自定义许可证禁止商用，与 GPL-3.0 不兼容
  - [benianwalls/Dock-Folders-App](https://github.com/benianwalls/Dock-Folders-App)：没有许可证

## 官网

官网 <https://flotilla.rakuyo.dev/> 是本仓库在 GitHub Pages 上的项目页。

自定义域名 `flotilla.rakuyo.dev` 在仓库的 Pages 设置里配置，DNS 上是指向 `rakuyomo.github.io` 的 CNAME 记录；`rakuyomo.github.io/Flotilla/` 会跳转过来。

### 源码与组装

- 源码在 `website/`，只放手写的模板、文案、样式与脚本，不放位图，也不放生成的页面：
  - `pages/`：页面模板，相对路径即每种语言目录下的输出路径
  - `locales/languages.json`：语言清单，按语言菜单的顺序排列；第一项是英文，兼作默认语言与兜底语言
  - `locales/<语言代码>.json`：这种语言的全部文案，按页面与区块嵌套分组，顺序与页面从上到下一致；几页共用的放 `common`
  - `404.html` 与 `assets/` 原样拷贝
- 模板里的占位符有两类，由 `Scripts/generate-site-pages.swift` 替换：
  - `{{home.hero.title}}`：文案，按 HTML 原样插入，可带 `<strong>` `<code>` `<wbr>` 等行内标记；多行的文案在文案文件里写成字符串数组，不写缩进，插入时续行补上占位符所在行的缩进
  - `{{@lang}}`：`@` 开头，按语言清单与页面算出的值或片段，如语言代码、到站点根目录的相对路径、`hreflang` 备选链接、语言菜单、`<head>` 里的跳转脚本；可用的名称见脚本里的 `computedValues`
  - 模板用到而某种语言缺少的键、文案文件里模板没用到的键、语言清单与文案文件对不上、未知的占位符、用在属性值里的值含 `"` 或换行，都会报错，不生成任何页面
- 各语言不同的链接写在语言清单每一项的 `links` 里，模板里写作 `{{@links.名称}}`，如 README 与其中章节的链接
  - 它们不放文案文件：翻译只改文案文件，繁体由简体改写时也不会把 `README-ZH.md#开发` 这样的锚点转成繁体而失效
  - 随语言换、又和句子一起翻译的链接留在文案里，如 Apple 支持文章的链接与文章标题
- `mise run site:build` 运行 `Scripts/site.sh`，组装到 `build/site/`：
  - 按模板与文案生成每种语言的页面，拷入 `404.html` 与 `assets/`；模板与文案的源文件不进产物
  - 用 `sips` 从 App 图标母版生成图标与 favicon，从 `docs/resources/` 的浅色头图生成分享图、把帆船画稿转成 JPEG，截图原样拷入
  - 用 `gh api` 取 GitHub 上的全部 Release，整理成 `build/site/releases.json`；`gh` 要先登录
  - `releases.json` 里每个版本的正文按语言代码分开：`en` 是 Release 的正文；语言清单里的其它语言取 `docs/release-notes/<版本号>/<语言代码>.md`，用 `gh api markdown` 渲染成 HTML，没有这份说明的版本不写这种语言
- 页面运行时只读同源的 `releases.json`，不请求 GitHub API；读不到时退回到指向 GitHub Releases 的链接
- 更新日志按页面语言显示正文，这个版本没有这种语言的正文时显示英文
- `mise run site:preview` 组装后在本机起服务，地址为 `http://localhost:8000/`

### 部署

由 `.github/workflows/pages.yml` 完成：

- 推送到 `main`、且改动涉及组装用到的文件时，组装并部署；`docs/release-notes/` 也在其中，改了更新说明推送到 `main` 后会重新部署
- 向 `main` 提 PR、且改动涉及同样的文件时，只组装、不部署，提前发现组装失败
- “发布” workflow 成功后重新部署，更新下载链接与更新日志
- 在 GitHub 上改了 release notes 之后，到仓库的 Actions 页面手动运行 “官网” workflow
  - 这样改正文只影响 GitHub 与官网的英文更新日志：其它语言的更新日志显示 `docs/release-notes/` 里同名的说明，要改就改那一份
  - App 的更新窗口显示的是发布时签进更新清单的那份说明，不随之改变

### 维护

- 改结构改 `pages/` 下的模板；改文案时，每种语言的文案文件同步改，各文件的键保持一致
- 页面上的事实以 README 为准，文案能照搬就照搬
- 站内链接一律用相对路径；每页在 `<html data-root>` 上声明自己到站点根目录的相对路径，脚本据此拼地址
  - `404.html` 会在任意不存在的路径下返回，用 `<base href="/">` 固定相对路径的起点
- 语言选择由每页 `<head>` 里的跳转脚本先于渲染完成：
  - 在语言菜单里选过的语言优先：
    - 菜单的链接带着 `?lang=<语言代码>`，目标页把它记进 `localStorage` 的 `flotilla.language`，再从地址里去掉这个参数
    - 选择随链接带到目标页，所以中键或在新标签页打开也算选择
  - 没选过时按浏览器的首选语言：只看 `navigator.languages` 的第一项，补全文字后按 “语言 + 文字” 与语言清单比对，`zh-CN` `zh-SG` 是简体中文，`zh-TW` `zh-HK` 是繁体中文
  - 网站没有这种语言时用英文；目标语言与本页不同时，跳到那种语言的同一页面，保留锚点
  - 地址里没有可用的 `lang` 参数、浏览器又禁止站点存储（读取 `localStorage` 抛错）时不跳转：这时不知道选过的语言，按浏览器语言跳转会把选了别的语言的人带回去
  - `404.html` 只有英文，不跳转
- 新增一种语言不用改生成脚本、模板、样式与页面脚本：语言菜单、`hreflang`、跳转与更新日志都按语言清单生成，繁体中文、日文、韩文的字体与排版已在样式里备好。要做的是：
  1. 在语言清单登记一项：语言代码与 `Sources/Flotilla/Resources/` 下的 `.lproj` 同名；目录用小写的语言代码加 `/`，如 `zh-hant/` `ja/` `ko/`，简体中文保持 `zh/`，README-ZH 与已发布的更新清单都链到它；`links` 照已有的语言写全
  2. 截图与分享图：`imageLanguage` 繁体中文用 `zh`，其余用 `en`
  3. 新建 `locales/<语言代码>.json`，键与 `en.json` 一致：繁体由简体中文改写，其余由英文翻译；术语与该语言的 `Localizable.strings` 一致，App 名照 `InfoPlist.strings`；简繁中文按 “中文行文”，日文、韩文的引号等照各自 `Localizable.strings` 的用法
  4. 把 `Scripts/embed-release-notes.swift` 里这种语言的更新日志页改成它自己的页面

## 发布流程

展示版本与构建号记在 `Sources/Flotilla/Info.plist` 中：

- `CFBundleShortVersionString` 是展示版本，格式为 `X.Y.Z`：三段都是不带前导零的非负整数，不带 `v`
- `CFBundleVersion` 是独立的正整数构建号，每次发布增加 `1`，跨展示版本持续递增；Sparkle 按构建号比较新旧版本

发布一个新版本：

1. 写这一版的更新说明，放在 `docs/release-notes/X.Y.Z/`，见 “更新说明”；可以先合并进 `main`，也可以留在工作区，由下一步带进发布提交
2. 在 `main` 上运行 `mise run release X.Y.Z`，脚本先检查以下各项，任一不满足就报错退出，不做任何改动：
   - 当前在 `main` 分支
   - 除 `docs/release-notes/X.Y.Z/` 下的新增或改动外，工作区干净
   - 这一版的更新说明齐全：每种语言一份，都有内容
   - 本地 `main` 与 `origin/main` 一致
   - tag `vX.Y.Z` 在远端不存在
   - `gh` 已登录
   - `origin` 是本仓库而不是 fork：fork 的 PR 拿不到发布所需的写权限
   - 本地与远端都没有 `release/X.Y.Z` 分支
   - Info.plist 的当前构建号是正整数
3. 检查通过后，脚本切出 `release/X.Y.Z` 分支，把 Info.plist 的展示版本改成 `X.Y.Z`，构建号增加 `1`，连同工作区里这一版的更新说明一起提交并推送到 `origin`，再向 `main` 开标题为 `release: X.Y.Z` 的 PR
   - 推送或开 PR 失败时，脚本删掉发布分支，更新说明留在工作区
4. 等 CI 通过后合并 PR；标题以 `release:` 开头的 PR，“更新说明” workflow 按 Info.plist 的展示版本检查更新说明是否齐全，改标题时也会重新检查
5. 合并后，GitHub Actions 自动：
   - 在合并提交上打 tag `vX.Y.Z`
   - 打包并压缩为 `Flotilla-X.Y.Z.zip`，生成签名的更新清单，每种语言的更新说明都嵌在清单里
   - 创建 GitHub Release：名称为 `vX.Y.Z`，正文是这一版的 `en.md`，附上 zip 与更新清单
   - 官网随后重新部署，更新下载链接与更新日志，见 “官网”

发布后：

- App 的更新窗口按用户的语言显示这一版的更新说明
- “已是最新版本” 提示框里的 “版本历史记录” 按用户的语言打开官网的英文或中文更新日志页

标题以 `release:` 开头（不区分大小写）的 PR 合并后，以下任一情况都会让发布失败：

- 标题不是完整的 `release: X.Y.Z`
- Info.plist 的展示版本与标题中的版本号不一致
- Info.plist 的构建号或合并前 `main` 的构建号不是正整数，或本次构建号未比合并前的构建号增加 `1`
- tag `vX.Y.Z` 已存在
- 这一版的更新说明不全

失败时到仓库的 Actions 页面查看原因，修好后再运行一次 `mise run release X.Y.Z`。

也可以对 Claude Code 说 “发布 X.Y.Z”，由 [`release` skill](.claude/skills/release/SKILL.md) 走完起草更新说明、开 PR、等 CI、合并、等发布的全过程。

## 更新说明

每个版本的更新说明放在 `docs/release-notes/X.Y.Z/`，每种语言一份：`en.md` `zh-Hans.md` `zh-Hant.md` `ja.md` `ko.md`，与 `Sources/Flotilla/Resources/` 下的 `.lproj` 同名。

- `mise run appcast` 把每份说明嵌进签名的更新清单，App 的更新窗口按用户的语言显示其中一份
- `en.md` 同时是 GitHub Release 的正文；官网的英文更新日志显示 Release 正文，其它语言显示同名的说明，没有时退回英文
- `Scripts/check-release-notes.sh X.Y.Z` 检查每份都存在且有内容：发版脚本、更新清单脚本，以及 “更新说明” 与 “发布” 两个 workflow 都调用它

### 写法

- 写给用户看：只写用户能感知的改动
  - 不写 PR 编号与链接
  - 不写文档、CI、测试、重构、官网这类与 App 行为无关的改动
- 不写顶层标题：更新窗口、GitHub、官网都会显示版本号
- 按类别分节，节标题用 `###`，取下表中该语言的叫法，只保留有内容的节；每条列表项写一个改动
- Markdown 只用 `###` 标题、无序列表、粗体、链接
- App 名照各语言的 `InfoPlist.strings`：`en` `ko` 写 Flotilla，`zh-Hans` 写 “归帆”，`zh-Hant` 写 “歸帆”，`ja` 写 “帰帆”
- 界面上的叫法与该语言的 `Localizable.strings` 一致
- `zh-Hans` `zh-Hant` 按 “中文行文” 一节；`ja` `ko` 的引号等写法照各自 `Localizable.strings` 的现有用法

| 语言 | 新增 | 改进 | 修复 |
|---|---|---|---|
| `en` | New | Improved | Fixed |
| `zh-Hans` | 新增 | 改进 | 修复 |
| `zh-Hant` | 新增 | 改進 | 修正 |
| `ja` | 新機能 | 改善 | 修正 |
| `ko` | 새 기능 | 개선 | 수정 |

## 分支命名

- 只用两种前缀，后接 `rakuyo/<简述>`：
  - `fix/`：修缺陷
  - `feature/`：其它改动，包括新功能、文档、排版整改等
- `<简述>` 用小写英文单词，以连字符连接，如 `feature/rakuyo/chinese-name-readme`
- 前缀不随提交类型变化：提交类型是 `feat`、`docs`、`style` 等时，分支前缀仍是 `feature/`
- 发版分支 `release/X.Y.Z` 不在此列，由 `mise run release` 生成，见 “发布流程”

## commit message

- 格式为 `<type>: <简述>`，代码标识用反引号，默认不带正文
- type 取值：
  - `feat`：新增或改变行为
  - `fix`：修缺陷
  - `refactor`：行为不变的结构调整
  - `docs`：只动文档
  - `chore`：构建、依赖、流程工具
  - `style`：行为不变的排版、注释措辞、命名整改
  - `test`：只动测试
  - `release`：发布新版本，由 `mise run release` 生成，见 “发布流程”
- 简述用中文写成一句 “改动结果”；`release` 例外，简述就是版本号本身，如 `release: 1.0.0`
- 标题不超过 50 个字符，中文一字算一，可用 `printf '%s' '<标题>' | wc -m` 核对
- 不含任何 AI 署名：`Co-Authored-By`、`Generated with`、🤖 之类的行与尾注一律不写

## PR 标题与描述

PR 文案与 commit message 一样是产物，受 “产物可追溯性” 一节约束：为没看过对话的人写，只在对话里成立的说法不写。release PR 的标题与描述由 `mise run release` 生成，见 “发布流程”。

### 标题

- 与 commit message 同一格式：`<type>: <简述>`，type 取值、反引号、50 字上限都相同
- 简述是一句 “改动结果”，不带主语；一个 PR 做了几件事就并列写出，如 `feat: 面板标题按原生对齐，访达文件夹里的文件显示内容缩略图`
- type 按 PR 的主要改动取

### 描述

按下面的顺序写，哪一节没有内容就整节不写：

1. 开头一两句说清做了什么、为什么；承接上一个 PR 的写 “承接 #编号”，对应需求编号的写上所在的阶段文档，如 “需求 19–21（08 文档）”
2. `## 改动`：按关注点分条，每条说清行为上的结果；关键的新类型顺带点到即可，不罗列改动的文件，diff 本身就有
3. `## 验证`：lint、单元测试数量、打包与签名、屏上实测的场景与数据、审查结论
4. `## 未验证`：没验到的项与原因，如 “开发机只有 macOS 27”
5. `## 注意`：平台限制、与原生仍有的差别、留下的 `#warning`

口吻是作者向 reviewer 说明：自然的中文，不带 “我”，不刻板也不俏皮；事实与数字照实写，不含任何 AI 署名。

## 本文件的回写约定

- 协作规范、目录约定、流程纪律等长期信息写入本文件
- 仓库里不放 `CLAUDE.md`：Claude Code 默认只在项目没有 `CLAUDE.md` 时读取本文件
  - 发现仓库里出现了 `CLAUDE.md`，把其中的规范搬进本文件，再删掉它
- 本文件正文不使用 `@路径` 语义（避免被 Claude Code 误展开），引用其它文件统一用 Markdown 链接
