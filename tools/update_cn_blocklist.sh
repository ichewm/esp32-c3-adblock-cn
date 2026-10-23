#!/usr/bin/env bash
# 中国区规则一键更新：下载国内为主的规则源 -> 合并去重构建 blocklist.bin -> 校验大小
# 用法:
#   tools/update_cn_blocklist.sh                 # 只构建 data/blocklist.bin
#   tools/update_cn_blocklist.sh 192.168.1.50    # 构建后直接推送到设备 (dashboard 上传)
#
# 规则源策略（中国优先）:
#   - anti-AD:   国内主力聚合列表（本身已合并大量国内外源，日更，国内直连可下载）
#   - yhosts:    国内补充
#   - EasyList China: 国内补充，只取 DNS 可表达的 ||domain^ 规则
#   - StevenBlack: 国外基线（广告+恶意软件）。不要国外规则就注释掉这一行。
# 下载用 python urllib（本地/CI 都不依赖 curl）；需要代理的机器走 https_proxy 环境变量。
set -euo pipefail
cd "$(dirname "$0")/.."


# 0x120000 = 1,179,648B LittleFS 分区；留余量后的安全上限（与 CI 同比例）
MAX_BYTES=930000

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 多镜像候选：本地（有代理）首个即中；Gitee Go 云节点在国内，raw.githubusercontent
# 不通时会超时切到 jsdelivr / gh 代理镜像（实测两者内容一致）。
python3 - "$TMP" <<'EOF'
import pathlib, socket, sys, urllib.request
socket.setdefaulttimeout(25)
SOURCES = [
    ("antiad.txt", ["https://anti-ad.net/domains.txt"]),
    ("yhosts.txt", [
        "https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts",
        "https://cdn.jsdelivr.net/gh/VeleSila/yhosts@master/hosts",
        "https://ghfast.top/https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts"]),
    ("easylistchina.txt", [
        "https://easylist-downloads.adblockplus.org/easylistchina.txt",
        "https://raw.githubusercontent.com/easylist/easylistchina/master/easylistchina.txt",
        "https://cdn.jsdelivr.net/gh/easylist/easylistchina@master/easylistchina.txt"]),
    ("sb.txt", [
        "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts",
        "https://cdn.jsdelivr.net/gh/StevenBlack/hosts@master/hosts",
        "https://ghfast.top/https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"]),
]
dest_dir = pathlib.Path(sys.argv[1])
for name, candidates in SOURCES:
    for url in candidates:
        try:
            urllib.request.urlretrieve(url, dest_dir / name)
            print(f'下载: {url} ({(dest_dir / name).stat().st_size} B)')
            break
        except Exception as e:
            print(f'  !! {url} 失败: {e}')
    else:
        raise SystemExit(f'!! 所有镜像均失败: {name}')
EOF

python3 tools/build_blocklist.py data/blocklist.bin "$TMP"/*

SIZE=$(stat -f%z data/blocklist.bin 2>/dev/null || stat -c%s data/blocklist.bin)
if [ "$SIZE" -gt "$MAX_BYTES" ]; then
  echo "错误: blocklist.bin ($SIZE B) 超过分区安全上限 ($MAX_BYTES B)，未部署。请删减源后重试。" >&2
  exit 1
fi
echo "✓ 大小校验通过: $SIZE / $MAX_BYTES 字节 ($(( SIZE * 100 / MAX_BYTES ))% 预算)"

# 可选：直接推送到已部署的设备（等价于 dashboard 的 Blocklist -> Upload）
if [ "${1:-}" != "" ]; then
  IP="$1"
  PW=$(sed -n 's/.*WEB_PASS = "\([^"]*\)".*/\1/p' src/secrets.h)
  USER=$(sed -n 's/.*WEB_USER = "\([^"]*\)".*/\1/p' src/secrets.h)
  echo "推送到设备 http://$IP/upload ..."
  python3 - "$USER" "$PW" "$IP" <<'EOF'
import base64, json, sys, urllib.request, uuid
user, pw, ip = sys.argv[1:4]
bin_ = open('data/blocklist.bin', 'rb').read()
boundary = uuid.uuid4().hex
body = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; '
        f'filename="blocklist.bin"\r\nContent-Type: application/octet-stream\r\n\r\n'
        ).encode() + bin_ + f'\r\n--{boundary}--\r\n'.encode()
req = urllib.request.Request(
    f'http://{ip}/upload', data=body, method='POST',
    headers={'Content-Type': f'multipart/form-data; boundary={boundary}',
             'Authorization': 'Basic ' + base64.b64encode(f'{user}:{pw}'.encode()).decode(),
             'X-Requested-With': 'c3-adblock'})
print('设备响应:', urllib.request.urlopen(req, timeout=120).read().decode())
EOF
fi
