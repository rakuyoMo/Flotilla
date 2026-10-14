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
mkdir -p \
    "$APP_PATH/Contents/MacOS" \
    "$APP_PATH/Contents/Resources" \
    "$APP_PATH/Contents/Frameworks"
cp "$BIN_DIR/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"
cp "$BIN_DIR/$TILE_NAME" "$APP_PATH/Contents/MacOS/$TILE_NAME"
cp "Sources/$APP_NAME/Info.plist" "$APP_PATH/Contents/Info.plist"

# 保留框架的符号链接与辅助进程；更新器在安装和重新启动时需要完整的 Sparkle bundle
readonly SPARKLE_ARTIFACT=".build/artifacts/sparkle/Sparkle"
readonly SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$SPARKLE_FRAMEWORK"
cp "$SPARKLE_ARTIFACT/LICENSE" "$APP_PATH/Contents/Resources/Sparkle-LICENSE.txt"

# 五种语言的界面文字、App 名与隐私授权框里的用途说明
cp -R "Sources/$APP_NAME/Resources/"*.lproj "$APP_PATH/Contents/Resources/"

# App 图标：白天版与夜间版的母版各生成一份 icns；
# 白天版是 Info.plist 的 `CFBundleIconFile` 指向的默认图标，夜间版由 App 运行时按 “图标与小组件样式” 取用

# 中间的 iconset 放在临时目录，脚本退出时删除
ICONSET_ROOT="$(mktemp -d)"
trap 'rm -rf "$ICONSET_ROOT"' EXIT

for ICON_NAME in AppIcon AppIconDark; do
    MASTER="Sources/$APP_NAME/Resources/$ICON_NAME.png"
    ICONSET="$ICONSET_ROOT/$ICON_NAME.iconset"
    mkdir "$ICONSET"

    # iconutil 要求的五档边长，每档再配一张 @2x
    for SIDE in 16 32 128 256 512; do
        sips -z "$SIDE" "$SIDE" "$MASTER" \
            --out "$ICONSET/icon_${SIDE}x${SIDE}.png" > /dev/null

        sips -z "$((SIDE * 2))" "$((SIDE * 2))" "$MASTER" \
            --out "$ICONSET/icon_${SIDE}x${SIDE}@2x.png" > /dev/null
    done

    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/$ICON_NAME.icns"
done

# 嵌套代码从内到外签名，保留 Sparkle 辅助进程所需的 entitlements
for SERVICE in Downloader Installer; do
    codesign --force --sign - --preserve-metadata=entitlements \
        "$SPARKLE_FRAMEWORK/Versions/B/XPCServices/$SERVICE.xpc"
done

codesign --force --sign - "$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
codesign --force --sign - "$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
codesign --force --sign - "$SPARKLE_FRAMEWORK"

# Dock stub 是独立的可执行文件，也在外层 App 签名前签好
codesign --force --sign - "$APP_PATH/Contents/MacOS/$TILE_NAME"

# 组装后重新签名，把 Info.plist 一并纳入签名
codesign --force --sign - "$APP_PATH"

# 框架、XPC 服务与 App 都必须通过验证，才交给发布脚本压缩
codesign --verify --deep --strict "$APP_PATH"
