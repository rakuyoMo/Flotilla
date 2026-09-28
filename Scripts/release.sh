#!/usr/bin/env bash

# 为新版本开 release PR：从 main 切出发布分支，把 Info.plist 的版本号改成新版本，提交、推送并创建 PR
# 用法：./Scripts/release.sh X.Y.Z

set -euo pipefail

# 以仓库根目录为工作目录，从任意位置调用结果都一致
cd "$(dirname "$0")/.."

# 版本号所在的 Info.plist
readonly INFO_PLIST="Sources/Flotilla/Info.plist"

# 版本号格式：三段都是不带前导零的非负整数，须与 .github/workflows/release.yml 的校验一致
readonly VERSION_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

# 输出中文报错并退出
fail() {
  echo "错误：$*" >&2
  exit 1
}

# 查询远端是否已有某个 ref；查询本身失败时无法下结论，直接报错退出
remote_has_ref() {
  local ref="$1"

  # `--exit-code` 下退出码 0 表示存在，2 表示不存在，其它表示查询本身失败
  local status=0
  git ls-remote --exit-code origin "$ref" > /dev/null \
    || status=$?

  if [[ "$status" -ne 0 && "$status" -ne 2 ]]; then
    fail "查询远端 ${ref} 失败，退出码 ${status}"
  fi

  [[ "$status" -eq 0 ]]
}

# 推送或开 PR 失败时收回发布分支，失败后重试不会被“分支已存在”拦住
discard_release_branch() {
  git switch main

  # 发布提交没有合并进 main，普通删除会被拒绝
  git branch --delete --force "$BRANCH"

  # 推送本身没成功时远端本来就没有这个分支，删除失败可以忽略
  git push origin --delete "$BRANCH" 2> /dev/null \
    || true
}

# 参数必须恰好是一个 X.Y.Z 格式的版本号
if [[ $# -ne 1 ]]; then
  fail "需要恰好一个参数，用法：mise run release X.Y.Z"
fi

if [[ ! "$1" =~ $VERSION_PATTERN ]]; then
  fail "版本号须为 X.Y.Z，三段都是不带前导零的整数，实际为 $1"
fi

# 新版本号，以及对应的发布分支与 tag
readonly VERSION="$1"
readonly BRANCH="release/$VERSION"
readonly TAG="v$VERSION"

# 发布分支要从 main 切出
current_branch="$(git branch --show-current)"

if [[ "$current_branch" != "main" ]]; then
  fail "须在 main 分支上运行，当前分支：${current_branch:-无（游离的 HEAD）}"
fi

# 未提交的改动会混进发布提交
worktree_changes="$(git status --porcelain)"

if [[ -n "$worktree_changes" ]]; then
  fail "工作区有未提交的改动或未跟踪的文件，请先处理"
fi

# 本地 main 须与远端一致：落后会漏掉已合并的改动，超前会把没审过的提交带进发布
if ! git fetch origin; then
  fail "git fetch origin 失败"
fi

local_main="$(git rev-parse main)"
remote_main="$(git rev-parse origin/main)"

if [[ "$local_main" != "$remote_main" ]]; then
  fail "本地 main 与 origin/main 不一致，请先同步"
fi

# 同名 tag 已存在说明这个版本发布过
if remote_has_ref "refs/tags/$TAG"; then
  fail "tag ${TAG} 已存在，这个版本发布过"
fi

# 后面要用 gh 创建 PR
if ! gh auth status > /dev/null; then
  fail "gh 未通过登录检查，请按上面的提示处理后重试"
fi

# origin 须是本仓库：fork 的 PR 拿不到发布所需的写权限，合并后不会发布
# 按 origin 的 URL 查询，有多个 remote 时结果也确定
origin_url="$(git remote get-url origin)"

if ! origin_is_fork="$(gh repo view "$origin_url" --json isFork --jq .isFork)"; then
  fail "查询 origin 对应的 GitHub 仓库失败：${origin_url}"
fi

if [[ "$origin_is_fork" != "false" ]]; then
  fail "origin 须是本仓库，不能是 fork：${origin_url}"
fi

# 本地或远端已有同名分支时不覆盖，交给用户确认后清理
if git show-ref --quiet --verify "refs/heads/$BRANCH"; then
  fail "本地已有分支 ${BRANCH}"
fi

if remote_has_ref "refs/heads/$BRANCH"; then
  fail "远端已有分支 ${BRANCH}"
fi

# 版本号的改动提交在发布分支上，经 PR 合并进 main
git switch --create "$BRANCH"

# 发布流程要求 Info.plist 的两个版本号都等于新版本
for key in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Set :$key $VERSION" "$INFO_PLIST"
done

git add "$INFO_PLIST"

# Info.plist 已是目标版本时（首个版本、发布失败后重发）没有改动，但开 PR 仍需要一个提交
git commit --allow-empty --message "release: $VERSION"

# 推送发布分支，PR 从它发起
git push --set-upstream origin "$BRANCH" || {
  discard_release_branch
  fail "推送 ${BRANCH} 失败"
}

# PR 标题须为 `release: X.Y.Z`，合并后才会触发 .github/workflows/release.yml
pr_url="$(
  gh pr create \
    --base main \
    --head "$BRANCH" \
    --title "release: $VERSION" \
    --body "发布 ${VERSION}：合并后由 GitHub Actions 打包并创建 Release。"
)" || {
  discard_release_branch
  fail "创建 PR 失败"
}

# PR 链接用于等 CI 与合并；发布分支已推送，本地切回 main
echo "已创建 PR：$pr_url"

git switch main

# 发布分支已推送到远端，本地副本没有用处，留着会让重发同一版本时被“本地已有分支”拦住
git branch --delete "$BRANCH"
