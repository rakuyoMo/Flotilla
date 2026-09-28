# Flotilla

在 macOS 的 Dock 上增加“文件夹”，把多个 App 分类收纳进去。点击文件夹，它会在 Dock 上展开，显示其中的 App；点击 App 即可打开。

## 安装

需要 macOS 15 或更高版本。

1. 在 [Releases](https://github.com/rakuyoMo/Flotilla/releases) 页面下载最新版本的 `Flotilla-X.Y.Z.zip`
2. 双击解压，把 `Flotilla.app` 拖到“应用程序”文件夹
3. 打开 Flotilla

### 第一次打开

Flotilla 没有经过 Apple 公证。第一次打开时，系统会提示 Apple 无法验证它是否包含恶意软件，并拒绝打开。

点击“完成”关闭提示，然后按以下步骤放行：

1. 打开“系统设置 › 隐私与安全性”
   - macOS 27 里这一页是“隐私与安全”
2. 向下滚动到“安全性”，在提示 Flotilla 已被阻止的那一行点击“仍要打开”
   - 这个按钮只在尝试打开 Flotilla 之后的一小时内出现
3. 按提示输入登录密码确认

之后 Flotilla 就能像其它 App 一样正常打开。

也可以在终端里移除 Flotilla 的隔离属性，之后直接打开：

```bash
xattr -d com.apple.quarantine /Applications/Flotilla.app
```

## 使用方法

Flotilla 启动后没有 Dock 图标，只在菜单栏显示一个小帆船图标。

界面语言跟随系统，支持英文、简体中文、繁体中文、日文、韩文；其它语言显示英文。

### 管理文件夹

点击菜单栏图标，选择“设置…”打开设置窗口。

设置窗口打开期间 Dock 上会出现 Flotilla 的图标，关闭后消失。

这个图标跟随“系统设置 › 外观 › 图标与小组件样式”：选“深色”时换成夜间版；“透明”“色调”选“深色”时换成去色、着色后的夜间版，选“浅色”时由系统处理白天版；选“自动”则随系统深浅外观。访达里始终显示白天版。

- **新建文件夹**：没有选中项时新建根文件夹；选中某一项时，在它所属的文件夹里新建子文件夹
- **加入 App**：选中某一项后点击“添加 App…”，选中的 App 会加入该项所属的文件夹；也可以从访达把 App 拖到文件夹上
- **重命名**：新建后直接输入名称，之后双击文件夹名修改
- **整理**：在树里拖动即可排序、移入其它文件夹，或把子文件夹拖到最外层成为根文件夹
- **删除**：选中后点击“删除”，文件夹连同其中的内容一起删除

“文件夹图标内显示的 App 图标数量”可在 0–4 之间调整，0 表示只显示空白的圆角底板。

### Dock 上的文件夹

每个根文件夹对应 Dock 上的一个 tile（Dock 上的一个图标）：

- tile 出现在 Dock 左侧 App 区域的末尾，可以像其它 App 一样拖动调整位置
- tile 的名称是文件夹名，图标是一块磨砂的圆角方形底板，上面按 2×2 排着前几个 App 的图标；底板随系统外观为浅色或深色
- 根文件夹增删、改名，或 tile 的图标需要更新（包括切换系统深浅外观）时，Dock 会重启一次来刷新 tile
- 新建的根文件夹在名称输入完成（按回车、点别处或按 Esc）之后才出现在 Dock 上，tile 直接带着这个名称
- 从访达把一个或多个 App 拖到 tile 上，松手后它们加入这个文件夹；拖其它文件不会被接收
- 可以像其它 App 一样把 tile 拖出 Dock，Flotilla 不会再把它加回，重启 Flotilla 后也一样
  - 设置窗口里，这个文件夹的名称右侧显示“不在 Dock 上”
  - 选中它后点击“添加到 Dock”，tile 回到 Dock
  - 新建的根文件夹，以及拖到最外层成为根文件夹的子文件夹，仍会自动出现在 Dock 上

### 展开与收起

- 点击 tile，文件夹在 Dock 上方以网格展开
- 点击其中的 App：启动它，同时收起
- 点击其中的子文件夹：在同一个面板里进入；点击左上角的返回按钮回到上一层
- 再次点击 tile、点击面板以外的任何位置，或按 Esc：收起

Flotilla 没有运行时点击 tile，系统会先启动 Flotilla，再展开文件夹。

## 辅助功能权限

Flotilla 通过辅助功能读取 Dock 的界面信息，用来：

- 找到 tile 在屏幕上的位置，让面板和它的尾巴对准 tile
- 识别鼠标在 tile 上的点击，在抬起的一刻就展开，与系统自带的 Dock 文件夹时机一致

没有这项权限时仍然可以使用，区别是：

- 面板以点击时鼠标所在的位置为准摆放，不一定正好对准 tile
- 要等 Dock 启动 tile 之后面板才会出现，比有权限时稍慢

授权入口：

- 第一次点击 tile 时系统会弹出授权提示，每次启动 Flotilla 最多提示一次
- 也可以在设置窗口的“辅助功能权限”一行点击“打开系统设置”，在“隐私与安全性 › 辅助功能”里打开 Flotilla
  - macOS 27 里这一页是“隐私与安全 › 设备控制和数据访问”
  - 这一行会显示当前是否已授权

Flotilla 使用 ad-hoc 签名，换用新版本或重新打包后，原来的授权可能失效，需要重新授权。

## Flotilla 对 Dock 的改动

Dock 上的 tile 是通过修改 Dock 偏好（`com.apple.dock`）加上去的：

- 只增删改 Flotilla 自己的 tile，位于 `persistent-apps`，即 Dock 左侧的 App 区域；其它 tile 与 Dock 的其它设置都不动
- 每次改动后结束 Dock 进程，由系统自动重新启动 Dock，改动随之生效
- 每次运行中第一次改动之前，先把整个 `com.apple.dock` 偏好导出备份
  - 位置：`~/Library/Application Support/Flotilla/Backups/com.apple.dock-<yyyyMMdd-HHmmss>.plist`
  - 最多保留最新的 5 份

## 彻底移除

1. 在设置窗口里删除全部根文件夹，等 Dock 重启、Flotilla 的 tile 消失
   - 如果 Flotilla 已经无法运行，直接把残留的 tile 拖出 Dock
2. 从菜单栏图标的菜单里选择“退出 Flotilla”
3. 删除数据目录 `~/Library/Application Support/Flotilla`，其中包括：
   - `folders.json`：文件夹数据
   - `DockTiles/`：代表每个根文件夹放进 Dock 的占位 App
   - `Backups/`：Dock 偏好的备份
4. 删除设置：`defaults delete com.rakuyo.flotilla`
5. 在“系统设置 › 隐私与安全性 › 辅助功能”里移除 Flotilla
   - macOS 27 里这一页是“隐私与安全 › 设备控制和数据访问”
6. 删除 Flotilla.app

## 构建

只需要 Xcode Command Line Tools 与 [mise](https://mise.jdx.dev)，不需要安装 Xcode。

```bash
# 编译并打包，产物为 build/Flotilla.app
mise run bundle

# 启动
open build/Flotilla.app
```

## 许可证

[GNU General Public License v3.0](LICENSE)
