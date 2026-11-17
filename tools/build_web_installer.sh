#!/usr/bin/env bash
# 重建浏览器一键安装器物料（docs/*.bin + manifest.json）。
#
# 为什么需要: 安装器物料是预构建二进制，固件/分区表一变就会过期 —— 2026-07 首次
# 添加安装器后分区表改了 3 轮，docs/ 里的 bin 一直是老分区表 + 无认证版本的固件，
# 浏览器刷出来的设备 /upload /update 等端点全部裸奔（详见 CHINA.md「浏览器一键安装器」）。
# 规则: 每次改 main.cpp / page.h / partitions.csv 后，重跑本脚本并提交产物。
#
# 用法: tools/build_web_installer.sh    （需要 pio；产物写入 docs/ 并覆盖旧文件）
set -euo pipefail
cd "$(dirname "$0")/.."

pio run -e c3               # firmware.bin / bootloader.bin / partitions.bin
pio run -e c3 -t buildfs    # littlefs.bin（data/ 目录打包成镜像）

B=.pio/build/c3
for f in bootloader.bin partitions.bin firmware.bin littlefs.bin; do
  test -s "$B/$f" || { echo "错误: $B/$f 不存在" >&2; exit 1; }
  cp "$B/$f" "docs/$f"
done
# C3 构建不产生 boot_app0.bin（那是经典 ESP32 双核的 otadata 引导镜像），
# esp32-c3 的 manifest 不需要它 —— 历史上遗留的旧文件直接删掉，避免误用。
rm -f docs/boot_app0.bin

# manifest.json 的偏移直接从刚构建的 partitions.bin 解析，不手抄
# （手抄 0x2B0000 的旧分区值正是上一版安装器物料腐化的根因之一）。
python3 - "$B/partitions.bin" <<'EOF'
import json, struct, sys

parts = {}
data = open(sys.argv[1], 'rb').read()
for i in range(0, len(data), 32):
    e = data[i:i + 32]
    if e[:2] != b'\xaaP':
        continue
    ptype, sub = e[2], e[3]
    off, size = struct.unpack('<II', e[4:12])
    label = e[12:28].rstrip(b'\x00').decode()
    parts[label] = (ptype, sub, off, size)

app0, spiffs = parts['app0'], parts['spiffs']
assert app0[0] == 0, f"app0 不是 app 类型: {app0}"
assert spiffs[0] == 1, f"spiffs 不是 data 类型: {spiffs}"
assert app0[2] + app0[3] <= spiffs[2], "app0 与 spiffs 重叠?!"

manifest = {
    "name": "C3 AdBlocker (CN)",
    "version": "2.0.0",
    "new_install_prompt_erase": True,
    "builds": [{
        "chipFamily": "ESP32-C3",
        "parts": [
            {"path": "bootloader.bin", "offset": 0},
            {"path": "partitions.bin", "offset": 32768},
            {"path": "firmware.bin",   "offset": app0[2]},
            {"path": "littlefs.bin",   "offset": spiffs[2]},
        ],
    }],
}
with open('docs/manifest.json', 'w') as f:
    json.dump(manifest, f, indent=2)
    f.write('\n')
print(f"manifest.json: firmware @ {app0[2]:#x} (slot {app0[3]:#x}B), "
      f"littlefs @ {spiffs[2]:#x} ({spiffs[3]:#x}B)")
EOF

echo "✓ docs/ 安装器物料已重建（记得连同代码一起提交）"
