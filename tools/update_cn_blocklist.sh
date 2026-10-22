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
# 注: GitHub 源在国内直连不稳；本机有代理时 curl 自动走 https_proxy。
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCES=(
  "https://anti-ad.net/domains.txt"
  "https://raw.githubusercontent.com/VeleSila/yhosts/master/hosts"
  "https://easylist-downloads.adblockplus.org/easylistchina.txt"
  "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
)

# 0x120000 = 1,179,648B LittleFS 分区；留余量后的安全上限（与 CI 同比例）
MAX_BYTES=1100000

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FILES=()
for url in "${SOURCES[@]}"; do
  f="$TMP/$(basename "$url")"
  echo "下载: $url"
  curl -sLf --retry 3 --max-time 120 -o "$f" "$url"
  FILES+=("$f")
done

python3 tools/build_blocklist.py data/blocklist.bin "${FILES[@]}"

SIZE=$(stat -f%z data/blocklist.bin 2>/dev/null || stat -c%s data/blocklist.bin)
if [ "$SIZE" -gt "$MAX_BYTES" ]; then
  echo "错误: blocklist.bin ($SIZE B) 超过分区安全上限 ($MAX_BYTES B)，未部署。请删减源后重试。" >&2
  exit 1
fi
echo "✓ 大校验通过: $SIZE / $MAX_BYTES 字节 ($(( SIZE * 100 / MAX_BYTES ))% 预算)"

# 可选：直接推送到已部署的设备（等价于 dashboard 的 Blocklist -> Upload）
if [ "${1:-}" != "" ]; then
  IP="$1"
  PW=$(sed -n 's/.*WEB_PASS = "\([^"]*\)".*/\1/p' src/secrets.h)
  USER=$(sed -n 's/.*WEB_USER = "\([^"]*\)".*/\1/p' src/secrets.h)
  echo "推送到设备 http://$IP/upload ..."
  curl -s -u "$USER:$PW" -H "X-Requested-With: c3-adblock" \
       -F "file=@data/blocklist.bin" "http://$IP/upload" && echo
fi
