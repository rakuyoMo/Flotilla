<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/readme-header-zh-dark.png">
    <img alt="归帆" src="docs/resources/readme-header-zh-light.png" width="100%">
  </picture>
</p>

<div align="center">

[English](README.md) | 简体中文

在 Dock 上给应用分组，文件、文件夹和网页也能放进去。

[![官网](https://img.shields.io/badge/website-flotilla.rakuyo.dev-0089C2)](https://flotilla.rakuyo.dev/zh/)
[![CI](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml/badge.svg)](https://github.com/rakuyoMo/Flotilla/actions/workflows/ci.yml)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

</div>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-panel-zh-dark.jpg">
    <img
      alt="Dock 上方展开了 “常用” 组，应用和文件夹以网格排列，面板底部的箭头指向组图标"
      src="docs/resources/screenshot-panel-zh-light.jpg"
      width="482"
    >
  </picture>
</p>

## 简介

Dock 自带的文件夹只能放在右侧，而且每个都对应磁盘上的一个文件夹。归帆（Flotilla）的组放在 Dock 左侧，和应用排在一起。应用、文件、文件夹和网页都能放进同一个组，原来的应用和文件不会被移动，也不用在磁盘上新建文件夹。

点击组图标，里面的内容会以网格展开，外观和动画都与 Dock 自带的文件夹一致。

## 功能

- **组里还能分组**：子组直接在同一个面板里打开

- **在面板里浏览文件夹**：文件夹像 Dock 叠放那样在面板里展开，显示文件缩略图

- **组图标预览**：组图标显示组里前几项的图标，最多 4 个

- **拖放**：把应用、文件或文件夹拖到 Dock 上的组图标就能加进组里，在面板里拖动项目可以调整顺序或移除

- **不会跟丢**：应用和文件移动或改名后，仍能从组里打开

- **菜单栏应用**：归帆在菜单栏运行，不会在 Dock 上多出自己的图标

- **支持八种语言**：英文、简体中文、繁体中文、日文、韩文、德文、法文和西班牙文

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-stack-zh-dark.jpg">
    <img
      alt="面板中打开了 “壁纸” 文件夹，显示图片缩略图，末尾有 “在访达中打开”"
      src="docs/resources/screenshot-stack-zh-light.jpg"
      width="738"
    >
  </picture>
</p>

## 安装

归帆需要搭载 Apple 芯片、运行 macOS 15 或更高版本的 Mac。

1. 从 [官网](https://flotilla.rakuyo.dev/zh/download/) 或 [GitHub Releases](https://github.com/rakuyoMo/Flotilla/releases) 下载最新的 `Flotilla-X.Y.Z.zip`
2. 双击解压，把归帆拖进 “应用程序” 文件夹
3. 打开归帆

### 第一次打开

归帆没有经过 Apple 公证，第一次打开时会被 macOS 拦下。点击 “完成” 关掉提示，然后：

1. 打开 “系统设置 › 隐私与安全性”
2. 向下滚动到 “安全性”，找到归帆被阻止的提示，点击 “仍要打开”
3. 输入登录密码确认

习惯用终端的话，也可以先移除隔离属性，再打开归帆：

```bash
xattr -d com.apple.quarantine /Applications/Flotilla.app
```

### 更新

归帆会自动检查更新。在设置的 “软件更新” 里可以立即检查、调整检查频率，或关闭自动检查。

## 权限

归帆借助辅助功能权限读取 Dock 的界面，这样面板才能对准组图标，并在松开鼠标时立即展开。

不开这项权限也能用，只是面板会出现在鼠标附近，不一定对得准组图标，展开也会慢一些。

系统提示时允许即可，也可以之后在 “系统设置 › 隐私与安全性 › 辅助功能” 里为归帆开启。macOS 27 里这一页是 “隐私与安全 › 设备控制和数据访问”。

归帆使用 ad-hoc 签名，更新后可能需要重新开启这项权限。

## 快速上手

点击菜单栏里的帆船图标，选择 “设置…” 来管理组。

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/resources/screenshot-settings-zh-dark.png">
    <img
      alt="设置窗口中展开了 “常用” 组，下方是 “通用” 设置"
      src="docs/resources/screenshot-settings-zh-light.png"
      width="732"
    >
  </picture>
</p>

### 新建组

1. 在 “组” 下点击 “新建组”，输入名称后按回车。Dock 会短暂重启，然后组图标出现在左侧的应用区域
   - 想新建子组，先选中上一级的组。子组显示在上一级的面板里，而不是 Dock 上

2. 选中组，点击 “添加…”，就能添加应用、文件、文件夹或网页

3. 也可以把应用、文件和文件夹拖到设置窗口里的组上，或拖到 Dock 上的组图标；网页可以从浏览器拖到设置窗口里

### 管理组

在设置窗口里，拖动项目可以调整顺序或移到其它组，右键点击一项还有 “删除” 等更多操作。删除组会连同里面的内容一起删掉，而且不会再确认。

也可以直接在面板里移除某一项：把它拖出面板，等 “移除” 出现后松手。

无论哪种方式，原来的应用和文件都不受影响。

把组图标拖出 Dock 只会移除图标。组仍留在设置窗口里，标为 “不在 Dock 上”，不会自动回到 Dock；要加回来，右键点击这个组，选择 “添加到 Dock”。

## 工作原理

### Dock tile

Dock 左侧只能放 App，所以归帆为每个顶层组生成一个占位 App，用组的名称和图标加进 Dock。点击图标时，Dock 会启动这个占位 App，它再通过 `flotilla://` URL 通知归帆展开或收起面板。

### Dock 偏好

归帆通过修改 Dock 偏好（`com.apple.dock`）来添加这些 tile，只改 `persistent-apps`（Dock 左侧的应用区域）里归帆自己的 tile，其它图标和 Dock 设置都不受影响。

每次修改后，归帆会结束 Dock 进程，由 macOS 自动重启 Dock，让改动生效。组图标更新时也要重启，比如系统在浅色、深色外观之间切换时。

每次启动后第一次修改之前，归帆都会先备份 `com.apple.dock`，最新的 5 份保存在 `~/Library/Application Support/Flotilla/Backups/`。

### 数据与设置

组的数据、占位 App 和 Dock 偏好的备份都保存在 `~/Library/Application Support/Flotilla`，设置保存在偏好设置域 `com.rakuyo.flotilla`。

### 联网

归帆只在两种情况下联网：添加或编辑网页时获取网页标题，以及从 GitHub Release 检查和下载更新。

## 从源码构建

需要 [mise](https://mise.jdx.dev) 和 Xcode Command Line Tools 26 或更高版本，不用安装完整的 Xcode。

```bash
# 编译 debug 版本
mise run build

# 编译 release 版本，打包为 build/Flotilla.app 并 ad-hoc 签名
mise run bundle

# 启动打包好的 App
open build/Flotilla.app
```

构建时出现的两条 `ld: warning: search path ... not found` 警告可以忽略。

## 开发

### 测试

```bash
swift test
```

偶尔会因 `plugin for module 'TestingMacros' not found` 编译失败，重新运行即可。在 git worktree 里每次都会失败，需要显式指定插件目录：

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

### 代码规范

代码风格以 [RakuyoKit/swift](https://github.com/RakuyoKit/swift) 为准：

```bash
# 按代码规范自动格式化
mise run swift:format

# 检查代码规范
mise run swift:lint
```

### 运行打包好的 App

同一时间只能运行一个归帆，所以启动 `build/Flotilla.app` 之前，先退出已安装的归帆。

本地打包使用 ad-hoc 签名，重新打包后可能需要再次授予辅助功能权限。

### 日志

归帆的日志写在 `com.rakuyo.flotilla` 子系统下：

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.rakuyo.flotilla"'
```

### 官网

[官网](https://flotilla.rakuyo.dev/zh/) 的源码在 `website/`，部署在 GitHub Pages 上。构建时会用 `gh` 获取版本信息，需要先运行 `gh auth login` 登录。详见 [AGENTS.md](AGENTS.md) 的 “官网” 一节。

```bash
# 组装官网到 build/site/
mise run site:build

# 组装后在本机预览，地址为 http://localhost:8000/
mise run site:preview
```

## 参与贡献

提交 PR 前，请确认 `mise run swift:lint` 和 `swift test` 都能通过。CI 也会运行这两项检查，然后编译、打包应用。

分支命名、提交信息等约定见 [AGENTS.md](AGENTS.md)，各项功能的具体要求见 [docs/requirements](docs/requirements)。

## 友链

[LINUX DO](https://linux.do)

## 许可证

归帆以 [GNU General Public License v3.0](LICENSE) 许可证发布。更新功能使用了 Sparkle，它的许可声明随 App 放在 `Contents/Resources/Sparkle-LICENSE.txt`。
