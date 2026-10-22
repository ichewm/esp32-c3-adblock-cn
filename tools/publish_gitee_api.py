#!/usr/bin/env python3
"""CI 用：把 data/blocklist.bin 通过 Gitee contents API 发布到 dist 分支。

为什么不用 git push：CI 里 git 远程 URL 若内嵌 token，push 的
"To https://user:TOKEN@gitee.com/..." 输出会把 token 泄进公开构建日志；
API 方式 token 只进 Authorization header，不落日志。

用法: GITEE_TOKEN=xxx python3 tools/publish_gitee_api.py [owner/repo]
环境: GITEE_TOKEN 必填（仓库「管理→环境变量设置」里配置，私人令牌需 projects 权限）
"""
import base64
import json
import os
import sys
import urllib.request

OWNER_REPO = sys.argv[1] if len(sys.argv) > 1 else "hewmbj/esp32-c3-adblock-cn"
# token 来源优先级: PUSH_TOKEN_FILE(文本替换写入的临时文件, CI) > PUSH_TOKEN > GITEE_TOKEN(环境变量)
TOKEN = ""
tf = os.environ.get("PUSH_TOKEN_FILE")
if tf and os.path.exists(tf):
    content = open(tf).read().strip()
    if content and "${" not in content:  # 未被替换的模板则忽略
        TOKEN = content
TOKEN = TOKEN or (os.environ.get("PUSH_TOKEN") or os.environ.get("GITEE_TOKEN") or "").strip()
if not TOKEN:
    print("PUSH_TOKEN 未生效：检查仓库「管理 → 流水线 → 通用变量」里的 PUSH_TOKEN（私人令牌，需 projects 权限）")
    sys.exit(1)

api = f"https://gitee.com/api/v5/repos/{OWNER_REPO}/contents/blocklist.bin"


def req(url, method="GET", payload=None):
    r = urllib.request.Request(
        url, method=method,
        data=json.dumps(payload).encode() if payload else None,
        headers={"Authorization": f"token {TOKEN}", "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=60) as resp:
        return json.loads(resp.read() or b"{}")


entries = os.path.getsize("data/blocklist.bin") // 5
msg = f"blocklist (CI) {__import__('datetime').date.today()} — {entries} entries"

sha = None
try:  # 已有文件则拿到 sha 才能更新；分支/文件不存在则创建
    sha = req(f"{api}?ref=dist")["sha"]
except Exception:
    pass

out = req(api, "PUT", {
    "content": base64.b64encode(open("data/blocklist.bin", "rb").read()).decode(),
    "branch": "dist", "sha": sha, "message": msg,
})
print(f"[publish] dist @ {out.get('commit', {}).get('sha', '?')[:12]} ({entries} entries)")
