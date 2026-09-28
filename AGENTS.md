# AGENTS.md

本文件是协作 Agent（Claude Code、Codex 等）在本仓库工作时的指引，同时也是人类阅读的协作规范源。

## 项目概述

Flotilla 是一个原生 macOS App：在 Dock 上增加“文件夹”，把多个 App 分类收纳进去；点击文件夹后在 Dock 上展开，显示其中的 App，点击即可打开。

- 纯开源的个人工具，只在 GitHub 分发
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
| `mise run release <版本号>` | 为新版本开 release PR，见“发布流程” |

## 目录结构

```
Sources/Flotilla/       App 源码
  Model/                文件夹数据模型与持久化
  Preferences/          用户设置
  Rendering/            文件夹图标渲染
  StatusBar/            状态栏图标与菜单
  Settings/             设置窗口
  Resources/            五种语言的 Localizable.strings，不参与编译，由打包脚本拷入 .app
  Panel/                Dock 上展开的面板
  Dock/                 stub 生成、Dock 偏好读写与 tile 同步
  Info.plist            App 包的 Info.plist，不参与编译，由打包脚本拷入 .app
Sources/FlotillaDockTile/  Dock tile 的 stub 可执行文件，由打包脚本拷入 .app
Tests/FlotillaTests/    单元测试（Swift Testing）
Scripts/bundle.sh       打包脚本：组装 .app 并签名
Scripts/release.sh      发版脚本：改版本号并开 release PR
docs/requirements/      需求文档：00 为总览，01–05 为按实现顺序拆分的阶段
.github/workflows/      GitHub Actions：`ci.yml` 检查与构建，`release.yml` 发布新版本
.claude/skills/release/ Claude Code 的 `release` skill：用自然语言发布新版本
```

## 开发注意事项

### 辅助功能权限

- 打包产物是 ad-hoc 签名，重新打包后原来的辅助功能授权可能失效，需要在“系统设置 › 隐私与安全性 › 辅助功能”里重新授权
  - macOS 27 里这一页是“隐私与安全 › 设备控制和数据访问”
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

- 尽可能使用模块化思想，组件、文件、类型都要符合“**高内聚低耦合**”
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
- 中文与英文之间、中文与数字之间留一个空格
- 使用中文弯引号（`“”`），不使用直引号（`""`）

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

> 名字来自一个段子：让 AI 做番茄炒蛋，它加了东坡肉；删掉之后，它又把菜名改成“番茄炒蛋（无东坡肉）”。东坡肉和它的影子都不该存在。

本节管的不是代码风格，是**产物里能出现什么**。

**产物** = 代码、注释、命名、commit message、PR 文案、文档。

**产物只有两个输入：需求与仓库现状。** 模型自己的想法、多轮讨论里出现过又被否掉的东西、上一版草稿，都不是输入。

判据一句话：**产物里的每一个元素，都要能指出它来自需求的哪一句、或仓库的哪个既有模式；指不出来的，不写。** 追溯不到的就是 dead code：删除，不在代码里解释。

讨论、试错、被否掉的方案、认错与解释，都只留在对话里；产物只装最终状态，不装任何相对中间稿、相对对话的描述。

### 铁律

1. **歧义取最小。** 需求没说清的地方按最小解释做，不按最丰富的；“以防以后要”不是理由。
2. **想加的，说，不做。** 觉得需求之外还该有什么，在回复末尾用一句话列出，交给用户；不实现、不写进注释，也不为它留 TODO。
3. **注释只写“是什么、为什么这样”。** “为什么”只写结论，不复述论证，不指向自己考虑过的其它做法；不写“暂不”“无需”“后续可”“也可以”。
4. **纠错无痕。** 被指出“不该有”的东西是**错误**，不是被否决的**方案**：抹平，不解释它曾经存在，并把为它而存在的参数、导入、辅助方法、测试、文档提及一并清掉。
5. **按身份命名。** 名字说它是什么，不说它比上一版少了什么；“无 XX”“不含 XX”这类靠“没有什么”定义的名字不用。
6. **最小改动的基准是仓库原状，不是自己的上一版草稿。** 理解错了就从纠正后的理解重写，草稿没有任何需要保留的价值。
7. **为没看过对话的人写。** 产物的读者是未来维护者与 reviewer，他们看不到会话；删掉对话记录后说不通、没价值的句子，一律不写。
8. **上下文被压缩或恢复之后，以仓库现状为准，不以摘要为准。** 摘要会保留“否决了什么”，而那正是不该进产物的东西；续做前重读相关的代码与文档。

**唯一允许写“为什么不”的情形**：一个没看过对话的未来维护者也很可能自己走到那条错路上。此时只留**一句**警示，不复述论证。“自己刚想到 / 刚犯过”不构成理由。

### 交付前自检（必做，放在每次产出的最后一步）

对本次新增的每个元素——代码、注释、名字、commit / PR 文案、文档——问两个问题：

- 指得出它来自需求的哪一句、或仓库的哪个既有模式吗？指不出 → 删
- 删掉对话记录后，这句话还说得通、还有价值吗？说不通 → 删

命中了即改，不必征询。本节的违反是**规范违反**，不是“代码风格偏好”，review 时不得以后者为由过滤。

## 工作纪律

- **以验证为目标。** 先定义成功标准，循环到验证通过为止，而不是把步骤走完就算完成
- **冲突要摆出来，不要折中。** 两种写法互相矛盾时，选一种（更新的、验证更充分的），说明理由，并标出另一种待清理；不要混用
- **测试验证意图。** 测试要表达“为什么这个行为重要”；业务逻辑改了还不会失败的测试是错的
- **失败要大声说。** 有步骤被静默跳过，就不能说“完成”；有测试被跳过，就不能说“测试通过”；默认把不确定说出来，而不是藏起来

## 参考项目

以下开源项目实现过类似功能。本项目采用 GPL-3.0，引入外部代码前先看对方的许可证：

- **可以引入代码**（MIT，须保留原版权与许可声明）：
  - [goranimperator/imperator-dockfolders](https://github.com/goranimperator/imperator-dockfolders)
  - [wjvalue/macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)
  - [sil-so/macos-dock-folders](https://github.com/sil-so/macos-dock-folders)
- **只能参考思路，不能引入代码**：
  - [takuarc/FolderDock](https://github.com/takuarc/FolderDock)：自定义许可证禁止商用，与 GPL-3.0 不兼容
  - [benianwalls/Dock-Folders-App](https://github.com/benianwalls/Dock-Folders-App)：没有许可证

## 发布流程

版本号记在 `Sources/Flotilla/Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion` 里，两者始终相同，格式为 `X.Y.Z`：三段都是不带前导零的整数，不带 `v`。

发布一个新版本：

1. 在 `main` 上运行 `mise run release X.Y.Z`，脚本先检查以下各项，任一不满足就报错退出，不做任何改动：
   - 当前在 `main` 分支
   - 工作区干净
   - 本地 `main` 与 `origin/main` 一致
   - tag `vX.Y.Z` 在远端不存在
   - `gh` 已登录
   - 本地与远端都没有 `release/X.Y.Z` 分支
2. 检查通过后，脚本切出 `release/X.Y.Z` 分支，把 Info.plist 的两个版本号改成新版本，提交并推送到 `origin`，再向 `main` 开标题为 `release: X.Y.Z` 的 PR
   - `origin` 须是本仓库：fork 来的 PR 拿不到发布所需的写权限
3. 等 CI 通过后合并 PR
4. 合并后，GitHub Actions 自动：
   - 在合并提交上打 tag `vX.Y.Z`
   - 打包并压缩为 `Flotilla-X.Y.Z.zip`
   - 创建 GitHub Release，附上 zip 与自动生成的更新说明

标题以 `release:` 开头（不区分大小写）的 PR 合并后，以下任一情况都会让发布失败：

- 标题不是完整的 `release: X.Y.Z`
- Info.plist 的两个版本号与标题不一致
- tag `vX.Y.Z` 已存在

失败时到仓库的 Actions 页面查看原因，修好后再运行一次 `mise run release X.Y.Z`。

也可以对 Claude Code 说“发布 X.Y.Z”，由 [`release` skill](.claude/skills/release/SKILL.md) 走完开 PR、等 CI、合并、等发布的全过程。

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
  - `release`：发布新版本，由 `mise run release` 生成，见“发布流程”
- 简述用中文写成一句“改动结果”；`release` 例外，简述就是版本号本身，如 `release: 1.0.0`
- 标题不超过 50 个字符，中文一字算一，可用 `printf '%s' '<标题>' | wc -m` 核对
- 不含任何 AI 署名：`Co-Authored-By`、`Generated with`、🤖 之类的行与尾注一律不写

## 本文件的回写约定

- 协作规范、目录约定、流程纪律等长期信息写入本文件，不写入 `CLAUDE.md`（stub，只含 `@AGENTS.md`）
- 发现 `CLAUDE.md` 沉淀了规范内容，搬回本文件并恢复 stub
- 本文件正文不使用 `@路径` 语义（避免被 Claude Code 误展开），引用其它文件统一用 Markdown 链接
