#!/usr/bin/env bash
# GH Actions 专用: 用 GITEE_TOKEN 走 git plumbing 把 data/blocklist.bin 推到 Gitee dist 分支。
# 为什么不用 contents API: 1MB 的 base64 JSON PUT 在跨境链路上实测超时(Urllib 60s);
# git push 分块传输稳定。凭据虽内嵌在远程 URL, 但 GH Actions 会把 secrets 在日志里
# 自动打码(***), 且 git push -q 不回显 URL —— 双保险。
# 环境变量: GITEE_TOKEN 必填(Gitee 私人令牌, projects 权限)
set -euo pipefail
cd "$(dirname "$0")/.."
: "${GITEE_TOKEN:?需要 GITEE_TOKEN 环境变量}"
OWNER_REPO="${1:-hewmbj/esp32-c3-adblock-cn}"
URL="https://hewmbj:${GITEE_TOKEN}@gitee.com/${OWNER_REPO}.git"

git config user.name  "blocklist-bot"
git config user.email "blocklist-bot@users.noreply.gitee.com"

SIZE=$(stat -c%s data/blocklist.bin 2>/dev/null || stat -f%z data/blocklist.bin)
MSG="blocklist (CI) $(date -u +%F) — $((SIZE/5)) entries"

BLOB=$(git hash-object -w data/blocklist.bin)
TREE=$(printf '100644 blob %s\tblocklist.bin\n' "$BLOB" | git mktree)
PARENT=""
if git fetch -q "$URL" dist 2>/dev/null; then PARENT=$(git rev-parse FETCH_HEAD); fi
if [ -n "$PARENT" ]; then
  NEW=$(git commit-tree "$TREE" -p "$PARENT" -m "$MSG")
else
  NEW=$(git commit-tree "$TREE" -m "$MSG")
fi
git push -q "$URL" "$NEW:refs/heads/dist"
echo "[publish] dist @ ${NEW:0:12} ($((SIZE/5)) entries)"
