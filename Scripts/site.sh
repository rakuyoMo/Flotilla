#!/usr/bin/env bash

# 组装官网到 build/site/：由模板与各语言文案生成页面与 404 页，拷入样式、脚本，从母版生成位图，
# 取 GitHub 上的全部 Release 与各语言的更新说明写成 releases.json

set -euo pipefail

# 以仓库根目录为工作目录，从任意位置调用结果都一致
cd "$(dirname "$0")/.."

# 组装产物的目录，由 .github/workflows/pages.yml 上传部署
readonly SITE_DIR="build/site"

# 位图的输出目录，页面按这个路径引用
readonly IMAGE_DIR="$SITE_DIR/assets/img"

# App 图标的白天版与夜间版母版
readonly ICON_LIGHT="Sources/Flotilla/Resources/AppIcon.png"
readonly ICON_DARK="Sources/Flotilla/Resources/AppIconDark.png"

# README 的头图、截图与帆船画稿
readonly RESOURCE_DIR="docs/resources"

# 1. 清空并重建产物目录，按 website/pages/ 的模板与 website/locales/ 的文案生成每种语言的页面，
#    由 website/404.html 生成 404 页，再拷入样式、脚本；模板与文案的源文件不进产物
rm -rf "$SITE_DIR"
mkdir -p "$SITE_DIR"
swift Scripts/generate-site-pages.swift website "$SITE_DIR"
cp -R website/assets "$SITE_DIR/"
mkdir -p "$IMAGE_DIR"

# 2. 从母版生成位图

# App 图标：导航与页脚以 32 pt 显示，通知卡片以 40 pt 显示，页头与收尾区以 128 pt 显示，各生成 2 倍边长的一张；
# 示意图里的图标比 128 pt 小，共用最大的一张
for SIDE in 64 80 256; do
    sips -z "$SIDE" "$SIDE" "$ICON_LIGHT" \
        --out "$IMAGE_DIR/app-icon-light-$SIDE.png" > /dev/null

    sips -z "$SIDE" "$SIDE" "$ICON_DARK" \
        --out "$IMAGE_DIR/app-icon-dark-$SIDE.png" > /dev/null
done

# 主屏幕图标用白天版
sips -z 180 180 "$ICON_LIGHT" \
    --out "$IMAGE_DIR/apple-touch-icon.png" > /dev/null

# 标签页图标以 16 pt 显示，浅色、深色外观各一张
sips -z 32 32 "$ICON_LIGHT" \
    --out "$IMAGE_DIR/favicon-light.png" > /dev/null

sips -z 32 32 "$ICON_DARK" \
    --out "$IMAGE_DIR/favicon-dark.png" > /dev/null

# 截图原样拷贝
cp "$RESOURCE_DIR"/screenshot-* "$IMAGE_DIR/"

# 社交分享图：英文页、中文页各用自己语言的浅色头图，缩到 1200 px 宽
sips --resampleWidth 1200 "$RESOURCE_DIR/readme-header-en-light.png" \
    --out "$IMAGE_DIR/og-en.png" > /dev/null

sips --resampleWidth 1200 "$RESOURCE_DIR/readme-header-zh-light.png" \
    --out "$IMAGE_DIR/og-zh.png" > /dev/null

# 帆船画稿：浅色用日、深色用月，转成 JPEG 并缩到 1000 px 宽
sips --resampleWidth 1000 -s format jpeg -s formatOptions 72 \
    "$RESOURCE_DIR/sailing-ship-sun-brush.png" \
    --out "$IMAGE_DIR/sailing-ship-sun.jpg" > /dev/null

sips --resampleWidth 1000 -s format jpeg -s formatOptions 72 \
    "$RESOURCE_DIR/sailing-ship-crescent-moon-brush.png" \
    --out "$IMAGE_DIR/sailing-ship-moon.jpg" > /dev/null

# 3. 取 GitHub 上的全部 Release，整理成页面用到的字段

# 仓库名：CI 里由 GitHub Actions 给出；本机按 origin 的 URL 查询，有多个 remote 时结果也确定
REPOSITORY="${GITHUB_REPOSITORY:-}"

if [[ -z "$REPOSITORY" ]]; then
    REPOSITORY="$(
        gh repo view "$(git remote get-url origin)" \
            --json nameWithOwner \
            --jq .nameWithOwner
    )"
fi

# 请求 GitHub 渲染好的 HTML 正文，页面不需要 Markdown 解析器；
# 请求失败时脚本在这里报错退出，不写空数组冒充 “没有 Release”
RELEASES="$(
    gh api --paginate \
        -H "Accept: application/vnd.github.html+json" \
        "repos/$REPOSITORY/releases?per_page=100"
)"

# 分页时每页输出一个数组，先合并；去掉草稿，保留预发布，按发布时间从新到旧；
# 正文按语言代码分开，`en` 是 Release 的正文
RELEASES="$(jq -s 'add | [.[] | select(.draft | not) | {
    tag: .tag_name,
    name,
    url: .html_url,
    publishedAt: .published_at,
    prerelease,
    bodyHtml: {en: .body_html},
    assets: [.assets[] | {name, size, url: .browser_download_url}]
} ] | sort_by(.publishedAt) | reverse' <<< "$RELEASES")"

# 4. 语言清单里的其它语言，正文取 docs/release-notes/<版本号>/<语言代码>.md，请求 GitHub 渲染成 HTML；
#    没有这份说明的版本不写这种语言，页面退回英文；渲染失败时与取 Release 失败一样报错退出
for TAG in $(jq -r '.[].tag' <<< "$RELEASES"); do
    for LANGUAGE in $(jq -r '.[].code | select(. != "en")' website/locales/languages.json); do
        NOTES_FILE="docs/release-notes/${TAG#v}/$LANGUAGE.md"

        if [[ ! -f "$NOTES_FILE" ]]; then
            continue
        fi

        HTML="$(
            gh api markdown \
                -f mode=gfm \
                -f context="$REPOSITORY" \
                -F text=@"$NOTES_FILE"
        )"

        RELEASES="$(
            jq \
                --arg tag "$TAG" \
                --arg language "$LANGUAGE" \
                --arg html "$HTML" \
                '(.[] | select(.tag == $tag) | .bodyHtml[$language]) = $html' \
                <<< "$RELEASES"
        )"
    done
done

printf '%s\n' "$RELEASES" > "$SITE_DIR/releases.json"

# 5. 打印组装结果
echo "官网已组装到 $(pwd)/$SITE_DIR"
