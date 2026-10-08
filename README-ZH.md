# 归帆

[English](README.md) | 简体中文

归帆（Flotilla）在 macOS 的 Dock 上增加“文件夹”，把多个 App 分类收纳进去；像 Dock 右侧区域那样，文件夹里也可以放文件、访达里的文件夹与网页。

点击文件夹，它会在 Dock 上展开，显示其中的内容；点击即可打开，访达里的文件夹则像 Dock 叠放那样继续展开。

界面语言跟随系统：

- 支持英文、简体中文、繁体中文、日文、韩文；其它语言显示英文
- App 名在简体中文下显示为“归帆”，繁体中文下为“歸帆”，其它语言下为“Flotilla”

## 运行环境

macOS 15 或更高版本。

## 安装

1. 在 [Releases](https://github.com/rakuyoMo/Flotilla/releases) 页面下载最新版本的 `Flotilla-X.Y.Z.zip`
2. 双击解压，把 `Flotilla.app` 拖到“应用程序”文件夹
   - 简体中文的访达里，它显示为“归帆”
3. 打开归帆

### 第一次打开

归帆没有经过 Apple 公证。第一次打开时，系统会提示 Apple 无法验证它是否包含恶意软件，并拒绝打开。

点击“完成”关闭提示，然后按以下步骤放行：

1. 打开“系统设置 › 隐私与安全性”
   - macOS 27 里这一页是“隐私与安全”
2. 向下滚动到“安全性”，在提示这个 App 已被阻止的那一行点击“仍要打开”
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

- 找到文件夹的 tile（Dock 上的一个图标）在屏幕上的位置，让面板和它的尾巴对准 tile
- 识别鼠标在 tile 上的点击，在抬起的一刻就展开，与系统自带的 Dock 文件夹时机一致

没有这项权限时仍然可以使用，区别是：

- 面板以点击时鼠标所在的位置为准摆放，不一定正好对准 tile
- 要等 Dock 启动 tile 之后面板才会出现，比有权限时稍慢

授权：

- 没有这项权限时，每次启动归帆后第一次点击 tile，系统会弹出授权提示
- 授权的位置是“系统设置 › 隐私与安全性 › 辅助功能”
  - macOS 27 里这一页是“隐私与安全 › 设备控制和数据访问”

归帆使用 ad-hoc 签名，换用新版本后，原来的授权可能失效，需要重新授权。

### 文件与文件夹

访达里的文件夹如果在“文稿”“桌面”“下载”等位置，面板第一次展开它时，系统会先询问是否允许访问。

归帆要读取文件夹的内容，才能在面板里展开它。

## 对系统的改动

### Dock 偏好

归帆通过修改 Dock 偏好（`com.apple.dock`）把 tile 加到 Dock 上：

- 只增删改归帆自己的 tile，位于 `persistent-apps`，即 Dock 左侧的 App 区域；其它 tile 与 Dock 的其它设置都不动
- 每次改动后结束 Dock 进程，由系统自动重新启动 Dock，改动随之生效
- 每次运行中第一次改动之前，先把整个 `com.apple.dock` 偏好导出备份
  - 位置：`~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`
  - 最多保留最新的 5 份

### 数据与设置

数据保存在 `~/Library/Application Support/Flotilla`：

- `folders.json`：文件夹数据
- `DockTiles/`：代表每个根文件夹放进 Dock 的占位 App
- `Backups/`：Dock 偏好的备份

设置保存在偏好设置域 `com.rakuyo.flotilla`。

## 从源码构建

只需要 Xcode Command Line Tools 与 [mise](https://mise.jdx.dev)，不需要安装 Xcode。

受 Command Line Tools 的限制，工程这样组织：

- 由 Swift Package Manager 管理
- 界面全部用 AppKit 代码构建：没有 SwiftUI 宏的实现插件
- 测试用 Swift Testing：没有 XCTest
- 不用 asset catalog、storyboard 与 xib：没有 `actool` 与 `ibtool`

详见 [AGENTS.md](AGENTS.md) 的“Command Line Tools 的限制”。

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

## 许可证

[GNU General Public License v3.0](LICENSE)
