#!/usr/bin/env bash

# 检查某个版本的更新说明是否齐全：docs/release-notes/<X.Y.Z>/ 下每种语言一份 .md，都存在且有内容
# 发版脚本、更新清单脚本，以及 “更新说明” 与 “发布” 两个 workflow 都调用这一份检查
# 用法：./Scripts/check-release-notes.sh X.Y.Z

set -euo pipefail

# 以仓库根目录为工作目录，从任意位置调用结果都一致
cd "$(dirname "$0")/.."

# 与 Sources/Flotilla/Resources/ 下的 .lproj 同名，App 支持的每种语言各一份说明
# Scripts/embed-release-notes.swift 里有同一组语言，两边同步修改
readonly LANGUAGES=(en zh-Hans zh-Hant ja ko de fr es)

if [[ $# -ne 1 ]]; then
    echo "错误：需要恰好一个参数，用法：./Scripts/check-release-notes.sh X.Y.Z" >&2
    exit 1
fi

readonly VERSION="$1"
readonly NOTES_DIR="docs/release-notes/$VERSION"

# 逐份检查，把所有问题一次列全，补齐时不必反复运行
problems=()

for language in "${LANGUAGES[@]}"; do
    file="$NOTES_DIR/$language.md"

    if [[ ! -f "$file" ]]; then
        problems+=("缺少 $file")
        continue
    fi

    # 只有空白字符的说明与空文件一样，更新窗口不会显示说明区
    if ! grep -q '[^[:space:]]' "$file"; then
        problems+=("$file 没有内容")
    fi
done

if [[ ${#problems[@]} -gt 0 ]]; then
    echo "错误：${VERSION} 的更新说明不全：" >&2
    printf '  - %s\n' "${problems[@]}" >&2
    exit 1
fi
