#!/usr/bin/env bash

# 将已打包的 App 压缩、签名，并生成 GitHub Release 使用的 Sparkle 更新清单

set -euo pipefail

cd "$(dirname "$0")/.."

readonly APP_PATH="build/Flotilla.app"
readonly UPDATES_PATH="build/updates"
readonly SPARKLE_TOOLS=".build/artifacts/sparkle/Sparkle/bin"
readonly RELEASES_URL="https://github.com/rakuyoMo/Flotilla/releases"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
readonly VERSION

# 每份清单只包含本次发布的完整安装包，复用目录时先移除上次生成的产物
rm -rf "$UPDATES_PATH"
mkdir -p "$UPDATES_PATH"

# 不带扩展属性，避免解压后出现破坏 App 签名的 ._* 文件
ditto -c -k --norsrc --keepParent "$APP_PATH" "$UPDATES_PATH/Flotilla-$VERSION.zip"

# 本机使用 App 专属的钥匙串项目；CI 经标准输入传入 secret，私钥不写进命令参数或文件
signing_options=(--account com.rakuyo.flotilla)

if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    signing_options=(--ed-key-file -)
fi

printf '%s' "${SPARKLE_PRIVATE_KEY:-}" | "$SPARKLE_TOOLS/generate_appcast" \
    "${signing_options[@]}" \
    --download-url-prefix "$RELEASES_URL/download/v$VERSION/" \
    --full-release-notes-url "$RELEASES_URL/tag/v$VERSION" \
    --link "https://flotilla.rakuyo.dev/" \
    --maximum-deltas 0 \
    "$UPDATES_PATH"
