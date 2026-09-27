#!/usr/bin/env bash

# 编译 release 版本，组装成 build/Flotilla.app，并做 ad-hoc 签名

set -euo pipefail

# 以仓库根目录为工作目录，从任意位置调用结果都一致
cd "$(dirname "$0")/.."

# App 名称：可执行文件与源码目录都按它查找，须与 Package.swift 中的 target 名一致
readonly APP_NAME="Flotilla"

# Dock tile 的 stub 可执行文件名，须与 Package.swift 中的 target 名一致
readonly TILE_NAME="FlotillaDockTile"

# 打包产物的路径
readonly APP_PATH="build/$APP_NAME.app"

# 编译 release 产物，并取得可执行文件所在目录
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

# 按 macOS App 的包结构组装
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$TILE_NAME" "$APP_PATH/Contents/MacOS/$TILE_NAME"
cp "Sources/$APP_NAME/Info.plist" "$APP_PATH/Contents/Info.plist"

# 五种语言的界面文字
cp -R "Sources/$APP_NAME/Resources/"*.lproj "$APP_PATH/Contents/Resources/"

# 嵌套代码要先于外层签名：stub 可执行文件单独签一次
codesign --force --sign - "$APP_PATH/Contents/MacOS/$TILE_NAME"

# 组装后重新签名，把 Info.plist 一并纳入签名
codesign --force --sign - "$APP_PATH"
