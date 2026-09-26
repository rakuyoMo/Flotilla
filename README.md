# Flotilla

在 macOS 的 Dock 上增加“文件夹”，把多个 App 分类收纳进去。点击文件夹，它会在 Dock 上展开，显示其中的 App；点击 App 即可打开。

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
