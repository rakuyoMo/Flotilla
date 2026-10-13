<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/readme-header-zh-dark.png">
    <img alt="归帆" src="docs/resources/readme-header-zh-light.png" width="100%">
  </picture>
</p>

<div align="center">

[English](README.md) | 简体中文

在 macOS 的 Dock 上增加 “组”：把 App、文件、访达文件夹与网页分类收纳进去，点击组即在 Dock 上方以网格展开，与原生 Dock 文件夹一样。

[![官网](https://img.shields.io/badge/website-blog.rakuyo.dev%2FFlotilla-0089C2)](https://blog.rakuyo.dev/Flotilla/zh/)
[![CI](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml/badge.svg)](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-panel-zh-dark.jpg">
    <img
      alt="“常用” 组在 Dock 上方以网格展开，里面是几个 App 与一个访达文件夹，尾巴指向组的 tile"
      src="docs/resources/screenshot-panel-zh-light.jpg"
      width="482"
    >
  </picture>
</p>

## 简介

原生的 Dock 文件夹只能放在 Dock 右侧，而且每一个都是磁盘上的一个文件夹。

归帆（Flotilla）把 “组” 放进 Dock 左侧的 App 区域。组由归帆自己保存，不对应磁盘上的文件夹，收纳进去的 App 都留在原处。像 Dock 右侧区域那样，组里也可以放文件、访达文件夹与网页。

点击组，它会在 Dock 上方以网格展开；外观、动效与位置一比一还原原生 Dock 文件夹的网格样式。

App 名在简体中文下显示为 “归帆”，繁体中文下为 “歸帆”，日文下为 “帰帆”，其它语言下为 “Flotilla”。

## 功能

- **与 App 并排的组**：每个顶层的组在 Dock 的 App 区域里都有自己的 tile，名称就是组名
- **App、文件、访达文件夹与网页**：在一个组里随意混放；文件用默认 App 打开，网页用默认浏览器打开
- **组可以嵌套**：组里还能放组；在面板里点击子组即可进入，返回按钮回到上一层
- **与 Dock 文件夹一样的网格**：点击 tile，组在 Dock 上方展开，尾巴指向 tile
- **访达文件夹像叠放那样展开**：点击访达文件夹，在同一个面板里浏览其中的内容，文件显示内容缩略图，网格末尾是 “在访达中打开”；设置里可以打开显示隐藏文件
- **实时渲染的组图标**：tile 显示组内前几项的图标，数量可选，最多 4 个；底板跟随系统的浅色、深色外观
- **拖进来就加入**：把 App、文件与访达文件夹拖到 Dock 上组的 tile 上，或把它们连同网页拖到设置窗口的组上
- **在面板里直接整理**：拖动调整顺序；把一项拖出面板，停到浮出 “移除” 再松开，即从组里删除，就像把图标拖离 Dock
- **跟随移动与更新**：App 与文件移动或改名后，组里的这一项自动跟到新位置；App 更新后仍打开装好的那一份
- **不打扰**：归帆在后台运行，只有一个状态栏图标；展开面板时 Dock 上不出现归帆，也不抢走当前 App 的焦点
- **五种语言**：英文、简体中文、繁体中文、日文、韩文，跟随系统语言；其它语言显示英文

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-stack-zh-dark.jpg">
    <img
      alt="访达文件夹 “壁纸” 在面板里展开，显示其中图片的缩略图，末尾是 “在访达中打开”"
      src="docs/resources/screenshot-stack-zh-light.jpg"
      width="738"
    >
  </picture>
</p>

## 安装

归帆需要 macOS 15 或更高版本，以及搭载 Apple 芯片的 Mac。

1. 在 [官网](https://blog.rakuyo.dev/Flotilla/zh/download/) 或 [Releases](https://github.com/rakuyoMo/Flotilla/releases) 页面下载最新版本的 `Flotilla-X.Y.Z.zip`
2. 双击解压，把 `Flotilla.app` 拖到 “应用程序” 文件夹
   - 访达按系统语言显示它的名称，简体中文下为 “归帆”
3. 打开归帆

### 第一次打开

归帆没有经过 Apple 公证。第一次打开时，系统会提示 Apple 无法验证它是否包含恶意软件，并拒绝打开。

点击 “完成” 关闭提示，然后按以下步骤放行：

1. 打开 “系统设置 › 隐私与安全性”
   - macOS 27 里这一页是 “隐私与安全”
2. 向下滚动到 “安全性”，在提示这个 App 已被阻止的那一行点击 “仍要打开”
   - 这个按钮只在尝试打开归帆之后的一小时内出现
3. 按提示输入登录密码确认

之后归帆就能像其它 App 一样正常打开。

也可以在终端里移除它的隔离属性，之后直接打开：

```bash
xattr -d com.apple.quarantine /Applications/Flotilla.app
```

## 需要的权限

### 辅助功能

归帆通过辅助功能读取 Dock 的界面信息，用来：

- 找到组的 tile（Dock 上的一个图标）在屏幕上的位置，让面板和它的尾巴对准 tile
- 识别鼠标在 tile 上的点击，在抬起的一刻就展开，与系统自带的 Dock 文件夹时机一致

没有这项权限时仍然可以使用，区别是：

- 面板以点击时鼠标所在的位置为准摆放，不一定正好对准 tile
- 要等 Dock 启动 tile 之后面板才会出现，比有权限时稍慢

授权：

- 没有这项权限时，每次启动归帆后第一次点击 tile，系统会弹出授权提示
- 授权的位置是 “系统设置 › 隐私与安全性 › 辅助功能”
  - macOS 27 里这一页是 “隐私与安全 › 设备控制和数据访问”

归帆使用 ad-hoc 签名，换用新版本后，原来的授权可能失效，需要重新授权。

### 文件与文件夹

访达文件夹如果在 “文稿” “桌面” “下载” 等位置，面板第一次展开它时，系统会先询问是否允许访问。

归帆要读取文件夹的内容，才能在面板里展开它。

## 快速上手

归帆待在状态栏里，图标是一艘帆船。点击它并选择 “设置…” 打开设置窗口；同一个菜单里还有 “退出归帆”。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-settings-zh-dark.png">
    <img
      alt="设置窗口：“组” 下展开了 “常用” 组，下方是 “通用” 区"
      src="docs/resources/screenshot-settings-zh-light.png"
      width="732"
    >
  </picture>
</p>

### 新建组

1. 在 “组” 下点击 “新建组”，输入名称后按回车
   - Dock 的 App 区域随即出现这个组的 tile；Dock 会短暂重启来显示它
   - 要在某个组里新建子组，先选中那个组；子组出现在上一级的面板里，不单独占一个 tile
2. 选中这个组，点击 “添加…”，选择要添加的内容：
   - “添加 App…”：选择 App
   - “添加文件…”：选择文件与访达文件夹
   - “添加网页…”：输入网址与可选的标题；标题留空时，归帆自动获取网页的标题
3. 也可以拖进来：
   - 从访达拖 App、文件与访达文件夹，或从浏览器拖网页，放到设置窗口里的组上
   - 把 App、文件与访达文件夹拖到 Dock 上这个组的 tile 上；网页只能在设置窗口里添加

### 使用面板

- 点击组的 tile 展开面板，点击其中一项即可打开
- 点击子组或访达文件夹即可进入；返回按钮回到上一层
- 再次点击 tile、点击别处或按 Esc，面板收起
- 在组里拖动一项，调整它的位置
- 把一项拖出面板，停在那里直到浮出 “移除”，松开即从组里删除
  - 变的只是组，App 或文件本身不动
  - “移除” 浮出之前松开，这一项落回原位

### 管理组

在设置窗口里：

- 双击组即可重命名
- 拖动行来调整顺序，或移进其它组
- 右键点按或按住 Control 点按一行，弹出更多操作：
  - 组：“添加到 Dock” “删除”
  - App、文件或访达文件夹：“在访达中显示” “删除”
  - 网页：“在默认浏览器中打开” “编辑…” “删除”
- “删除” 会把组连同其中的内容一起删除，不弹确认
- 访达文件夹在名称后标出所在位置，网页在名称后标出网址

要去掉组的 tile，像其它 App 那样把它拖出 Dock 即可。归帆不会自己把它加回去：这个组标出 “不在 Dock 上”，在它的右键菜单里点 “添加到 Dock” 即可加回。

### 设置

“通用” 下：

- “组图标内显示的图标数量”：tile 显示几项的图标，0–4；为 0 时 tile 只显示组图标本身
- “访达文件夹：显示隐藏文件”：访达文件夹在面板里展开时显示隐藏文件
- “辅助功能权限”：是否已授权，旁边有 “打开系统设置” 按钮；见 [辅助功能](#辅助功能)

## 工作原理

### Dock tile

Dock 只能放 App 与文件，所以归帆为每个顶层的组生成一个占位 App，放进 Dock；它的图标就是组图标。

点击 tile 时 Dock 启动占位 App。它不把任何 App 带到前台，打开一个 `flotilla://` URL 后随即退出，归帆据此展开或收起面板。归帆没有运行时，系统会先启动它。

拖到 tile 上的项也经同样的途径交给归帆。

### Dock 偏好

归帆通过修改 Dock 偏好（`com.apple.dock`）把 tile 加到 Dock 上：

- 只增删改归帆自己的 tile，位于 `persistent-apps`，即 Dock 左侧的 App 区域；其它 tile 与 Dock 的其它设置都不动
- 每次改动后结束 Dock 进程，由系统自动重新启动 Dock，改动随之生效
  - 更新 tile 的图标也是这样的改动，所以组的预览变化、系统切换浅色与深色外观时，Dock 都会重启
- 每次运行中第一次改动之前，先把整个 `com.apple.dock` 偏好导出备份
  - 位置：`~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`
  - 最多保留最新的 5 份

### 数据与设置

数据保存在 `~/Library/Application Support/Flotilla`：

- `folders.json`：组的数据
- `DockTiles/`：代表每个根组放进 Dock 的占位 App
- `Backups/`：Dock 偏好的备份

设置保存在偏好设置域 `com.rakuyo.flotilla`。

### 联网

归帆只在 “添加网页…” 与 “编辑…” 的提示框里获取网页标题时联网。

## 从源码构建

只需要 Xcode Command Line Tools 与 [mise](https://mise.jdx.dev)，不需要安装 Xcode。

Command Line Tools 需要 26 或更高版本，即 Swift 6.2 与 macOS 26 SDK：`Package.swift` 声明的是 `swift-tools-version: 6.1`，但面板在 macOS 26 上用到的 `NSGlassEffectView` 只在 macOS 26 SDK 里才有。

受 Command Line Tools 的限制，工程这样组织：

- 由 Swift Package Manager 管理
- 界面全部用 AppKit 代码构建：没有 SwiftUI 宏的实现插件
- 测试用 Swift Testing：没有 XCTest
- 不用 asset catalog、storyboard 与 xib：没有 `actool` 与 `ibtool`

详见 [AGENTS.md](AGENTS.md) 的 “Command Line Tools 的限制”。

```bash
# 编译 debug 版本
mise run build

# 编译 release 版本，打包为 build/Flotilla.app 并 ad-hoc 签名
mise run bundle

# 启动打包好的 App
open build/Flotilla.app
```

编译时的两条 `ld: warning: search path ... not found` 可以忽略：它们指向 Command Line Tools 里本来就没有的目录。

## 开发

### 测试

```bash
swift test
```

- 偶尔报 `plugin for module 'TestingMacros' not found` 而编译失败时，重跑即可；刚跑过 `mise run swift:format` 之后更容易出现
- 在 git worktree 里每次都会报，要显式给出插件目录：

  ```bash
  swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
  ```

### 代码规范

代码风格以 [RakuyoKit/swift](https://github.com/RakuyoKit/swift) 为准。

```bash
# 按代码规范自动格式化
mise run swift:format

# 检查代码规范
mise run swift:lint
```

### 日志

zsh 里的 `log` 是内建命令，查看系统日志要写全路径 `/usr/bin/log`：

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.rakuyo.flotilla"'
```

### 开发时的辅助功能权限

- 打包产物是 ad-hoc 签名，重新打包后原来的辅助功能授权可能失效，需要重新授权
- 两种启动方式的权限判定不同，可以分别用来验证有权限、无权限两条路径：
  - 从终端直接运行 `build/Flotilla.app/Contents/MacOS/Flotilla` 时，进程沿用终端的辅助功能授权
  - 用 `open build/Flotilla.app` 启动时，按归帆自己的授权判定

### 单实例

同一 bundle id 的归帆已在运行时，新启动的那一份会激活已在运行的那一份，然后立即退出。

启动 `build/Flotilla.app` 之前，先退出已安装的归帆。

### Dock 偏好

调试时修改 Dock 偏好之前，先备份：

```bash
defaults export com.apple.dock <文件>
```

### 官网

[官网](https://blog.rakuyo.dev/Flotilla/zh/) 由 `website/` 组装而成，部署在 GitHub Pages 上，详见 [AGENTS.md](AGENTS.md) 的 “官网”。

```bash
# 组装官网到 build/site/
mise run site:build

# 组装后在本机预览，地址为 http://localhost:8000/Flotilla/
mise run site:preview
```

组装时用 `gh` 取 Release 数据，要先用 `gh auth login` 登录。

## 参与贡献

- 提交 PR 之前，确认 `mise run swift:lint` 与 `swift test` 都通过；CI 也会运行它们，并编译与打包
- 分支命名、commit message 等协作规范见 [AGENTS.md](AGENTS.md)
- 各功能的行为由 [docs/requirements](docs/requirements) 里的需求文档规定

## 许可证

归帆以 [GNU General Public License v3.0](LICENSE) 许可证发布。
