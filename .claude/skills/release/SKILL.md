---
name: release
description: 发布 Flotilla 的新版本：用 `mise run release` 开 release PR，等 CI 通过后合并，再等 GitHub Actions 创建 GitHub Release。
when_to_use: 用户要发布新版本时，例如“发布 1.2.0”“发个 1.2.0”“release 1.2.0”。
argument-hint: "[X.Y.Z]"
allowed-tools:
  - Bash(mise run release *)
  - Bash(gh pr checks *)
  - Bash(gh pr merge *)
  - Bash(gh pr view *)
  - Bash(gh run list *)
  - Bash(gh run watch *)
  - Bash(gh release view *)
  - Bash(sleep *)
---

# 发布新版本

调用时带的参数：$ARGUMENTS

## 总则

- 全程用中文，称呼用户为“陛下”
- 每一步的结果都如实报告：失败就说失败，不略过，不说成成功
- 等 CI、等发布都要一段时间，可能超过单条命令的超时上限
  - 等待类命令放到后台运行
  - 不因为命令超时就判定失败

## 1. 确定版本号

- 从用户的话或上面的参数里取版本号，格式为 `X.Y.Z`
- 没有给出版本号时，问用户要；不自行推断“下一个版本”

## 2. 开 release PR

```bash
mise run release <版本号>
```

- 失败：把脚本的报错原样告诉用户，停止
- 成功：输出里“已创建 PR：”后面是 PR 链接，链接末尾的数字是 PR 编号

## 3. 等 CI

```bash
gh pr checks <PR 编号> --watch
```

- 刚开的 PR 可能还没登记检查，报 `no checks reported` 时等几十秒再运行
- CI 失败：报告失败的检查项与链接，停止，不合并

## 4. 合并

- CI 通过后，问用户一次是否合并
  - 用户一开始就说了“直接合并”“不用问”之类的话，就不问
- 用户同意后合并：

```bash
gh pr merge <PR 编号> --merge --delete-branch
```

## 5. 等发布

合并后，release workflow 会对这个 PR 运行一次。先取 PR 最后一个提交的 SHA：

```bash
gh pr view <PR 编号> --json headRefOid --jq .headRefOid
```

再按这个 SHA 找到这次运行：

```bash
gh run list --workflow release.yml --commit <提交 SHA> --json databaseId,url
```

- 列表为空说明运行还没登记，等几秒再查
- 找到后等它结束：

```bash
gh run watch <运行 ID> --exit-status
```

## 6. 报告结果

成功：取 Release 链接给用户。

```bash
gh release view v<版本号> --json url --jq .url
```

失败：给出 Actions 运行链接，并说明：

- PR 已合并，但没有发布
- 修好失败原因后，再说一次“发布 <版本号>”即可重发
