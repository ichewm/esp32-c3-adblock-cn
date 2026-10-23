#!/usr/bin/env bash
# 构建中国区 blocklist 并发布到 Gitee 仓库的专用 dist 分支。
#
# 为什么用 raw 链路而不是 release 附件:
#   - 实测 https://gitee.com/<user>/<repo>/raw/<branch>/<file> 匿名 GET 可下载
#     (302 到 raw.giteeusercontent.com 的签名 URL，固件 fetchBlocklist 已开重定向跟随)
#   - release 附件匿名下载不可靠(防盗链可能要求登录)，固件只会简单 GET，无法登录
#
# 用法:
#   git remote add gitee https://gitee.com/hewmbj/esp32-c3-adblock-cn.git   # 首次
#   tools/publish_gitee.sh                       # 构建 + 推送 blocklist 分支
#   tools/publish_gitee.sh https://gitee.com/u/r.git  # 没配 remote 时直接传 URL
#
# 之后在设备 dashboard -> Remote auto-update 填:
#   https://gitee.com/hewmbj/esp32-c3-adblock-cn/raw/dist/blocklist.bin
#   建议间隔 168 小时(每周)。Mac 本地也可加 cron 每周自动跑本脚本。
set -euo pipefail
cd "$(dirname "$0")/.."

REMOTE="${GITEE_REMOTE:-gitee}"
if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  if [ "${1:-}" != "" ]; then
    git remote add "$REMOTE" "$1"
  else
    echo "错误: 没有 git remote '$REMOTE'。先执行:" >&2
    echo "  git remote add gitee https://gitee.com/<你的用户名>/<仓库名>.git" >&2
    exit 1
  fi
fi

# 1) 构建中国区列表 (不带参数 = 只构建 data/blocklist.bin)
tools/update_cn_blocklist.sh

SIZE=$(stat -f%z data/blocklist.bin 2>/dev/null || stat -c%s data/blocklist.bin)
ENTRIES=$(( SIZE / 5 ))
MSG="blocklist $(date -u +%F) — ${ENTRIES} entries"

# 2) 用 git plumbing 提交到孤儿分支 blocklist (只含 blocklist.bin，不碰工作区、不污染 main 历史)
BLOB=$(git hash-object -w data/blocklist.bin)
TREE=$(printf '100644 blob %s\tblocklist.bin\n' "$BLOB" | git mktree)
if git fetch -q "$REMOTE" dist 2>/dev/null && git rev-parse -q --verify FETCH_HEAD >/dev/null 2>&1; then
  PARENT=$(git rev-parse FETCH_HEAD)  # 远端 dist 头优先（CI 可能已推过，避免 non-fast-forward）
elif git show-ref --verify --quiet refs/heads/dist; then
  PARENT=$(git rev-parse refs/heads/dist)
else
  PARENT=""
fi
if [ -n "$PARENT" ]; then
  NEW=$(git commit-tree "$TREE" -p "$PARENT" -m "$MSG")
else
  NEW=$(git commit-tree "$TREE" -m "$MSG")
fi
git update-ref refs/heads/dist "$NEW"

# 3) 推送
git push "$REMOTE" refs/heads/dist:refs/heads/dist

# 4) 打印设备自更新 URL
RURL=$(git remote get-url "$REMOTE")
case "$RURL" in
  *.git) RURL="${RURL%.git}" ;;
esac
echo
echo "✓ 已发布。设备 Remote auto-update 填这个 URL (建议间隔 168 小时):"
echo "  ${RURL}/raw/dist/blocklist.bin"
