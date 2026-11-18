# 中国区部署说明 (China deployment)

这是 [M-Abozaid/esp32-c3-adblock](https://github.com/M-Abozaid/esp32-c3-adblock) 的中国区本地化分支。
上游请参考根目录 [README.md](../README.md)。

## 本分支的改动

| 文件 | 改动 | 原因 |
|---|---|---|
| `partitions.csv` | 固件槽 0x150000→0x180000，规则分区 0x150000→0xF0000（@0x310000） | 上游在新版 arduino-esp32 下编译超分区（issue #48）；0x160000 槽仍装不下实际 ~1.5MB 镜像，最终 0x180000 槽 + 锁 espressif32@6.9.0（详见 partitions.csv 头注释） |
| `src/main.cpp` | 上游 DNS: Quad9 `9.9.9.9` → 阿里 `223.5.5.5` | Quad9 在国内延迟高且易被污染；想换 DNSPod 改回 `119,29,29,29` |
| `src/main.cpp` | 转发上游: 明文 UDP → **DoH 加密**（RFC 8484，GlobalSign R5 根证书校验，失败自动降级 UDP） | 明文 UDP:53 的应答可被链路注入污染 |
| `tools/update_cn_blocklist.sh` | 新增：中国优先规则一键构建/推送 | 上游默认列表偏欧美 |
| `.github/workflows/blocklist-cn.yml` | 新增：每周一自动重建中国区列表并发布 release | 规则保鲜 |

## 规则策略（中国优先）

| 规则源 | DNS 可用条目 | 国内直连 | 说明 |
|---|---|---|---|
| [anti-AD](https://anti-ad.net/domains.txt) | ~111k | ✅ 日更 | 国内主力聚合列表（源头在 [privacy-protection-tools/anti-AD](https://github.com/privacy-protection-tools/anti-AD)） |
| [yhosts](https://github.com/VeleSila/yhosts) | ~6k | ❌ 需代理 | 国内补充 |
| [EasyList China](https://easylist-downloads.adblockplus.org/easylistchina.txt) | ~8k | ❌ 需代理 | 只取 `||domain^` 规则，页面元素规则 DNS 用不上 |
| [StevenBlack](https://github.com/StevenBlack/hosts) | ~47k 净增 | ❌ 需代理 | 国外基线（走代理浏览外网时用）；**纯国内就注释掉** |

合并去重后 **~161k 条 / ~807KB / 0 哈希碰撞**，分区容量约 186k 条。
neohosts 已停更（404），AdGuard 中文过滤器对 DNS 无价值，均不采用。

## 托管与更新（Gitee 为主）

本分支以 [Gitee](https://gitee.com) 为主阵地（国内直连、CI/规则分发都可达），
GitHub 可选作镜像。

1. **局域网直推（最快）**：在有代理的电脑上 `tools/update_cn_blocklist.sh <设备IP>`，
   一条命令完成 下载→构建→推送（走 dashboard 的 `/upload`，Basic Auth + CSRF 头）。
2. **设备定时自拉（全自动，走 Gitee）**：
   ```bash
   # 首次：在 Gitee 建好仓库后
   git remote add gitee https://gitee.com/hewmbj/esp32-c3-adblock-cn.git
   git push -u gitee main
   tools/publish_gitee.sh        # 构建列表并推到 blocklist 分支
   ```
   然后在设备 dashboard → Remote auto-update 填
   `https://gitee.com/hewmbj/esp32-c3-adblock-cn/raw/dist/blocklist.bin`，
   间隔建议 168 小时。Mac 上可加 cron 每周自动跑 `publish_gitee.sh`。
   实测 Gitee raw 链路匿名可下载（302 到签名 URL，固件已开重定向跟随）；
   **不要用 Gitee release 附件**（防盗链可能要求登录，固件无法登录）；
   也**不要用 GitHub release 地址**（大陆基本拉不动）。
3. **手动上传**：dashboard → Blocklist → Upload。

## CI（GitHub Actions 每周定时重建 → 推 Gitee）

构建平面在 GitHub（免费、Secrets 机制可靠），分发平面在 Gitee（设备拉取快）。
已配置：`.github/workflows/blocklist-cn.yml`，每周一 06:00（北京时间；GitHub
调度队列带延迟，实测晚 3.5 小时左右）自动下载规则源 → 构建 → 推送 Gitee dist
分支 → 发 GitHub release 备份；设备在每周一 12:00（本地 NTP 时钟）拉取，
给构建链留 6 小时余量。

唯一前置条件（一次性）：在 GitHub 仓库 Settings → Secrets → Actions 添加
`GITEE_PUSH_TOKEN` = Gitee 私人令牌（projects 权限）。

手动触发：
`gh workflow run blocklist-cn.yml --repo ichewm/esp32-c3-adblock-cn`。

为什么不用 Gitee Go（国内 CI）：实测其「通用变量」对文件式 .workflow
流水线不生效（环境变量注入与 `${}` 文本替换均无效），无法安全地携带
推送令牌；且构建节点在国内百度云，拉不动 GitHub 规则源。
注：固件已把 Gitee raw 地址和 168 小时间隔烧录为默认值 —— 刷完即自动每周拉取，
无需任何 dashboard 配置；手动设置过 Remote auto-update 的设备会覆盖默认值。

## 浏览器一键安装器（docs/）

`docs/` 里的 `*.bin + manifest.json` 是 esp-web-tools 浏览器安装器的预构建物料，
**固件或分区表一变就会过期**（历史上分区表改了三轮而物料没重建，导致安装器刷出
旧分区表 + 无认证固件）。规则：改 `main.cpp` / `page.h` / `partitions.csv` 后重跑

```bash
tools/build_web_installer.sh      # 重建 docs/*.bin + manifest.json（偏移从 partitions.bin 解析生成）
```

并把产物随代码一起提交；CI（build.yml → web-installer job）每次 push 也会构建一份
新鲜物料作为 artifact 供直接下载。

## 墓园模式（fw cn-2.3.0+）

遥测采集端不再回 `0.0.0.0`（连接拒绝 → SDK 退避重试耗电），而是回答**设备自身 IP**，
SDK 连到我们的 ：80 会收到秒回的 `204 No Content`——上报方认为成功，安静闭嘴。
清单来自独立数据仓库 [cn-telemetry-collectors](https://github.com/ichewm/cn-telemetry-collectors)
（每条带双源共证或探测指纹证据，每周自动重验证，曾一天抓获两个指纹反转）。
固件侧为编译期内置（`tools/sync_telemetry.sh` 重新生成 `src/telemetry_list.h`），
清单变化跟随固件 OTA；白名单优先级仍高于墓园。

## 部署

```bash
cp src/secrets.example.h src/secrets.h   # 填 WiFi(可选)和 WEB_PASS/OTA_PASS(必填)
tools/update_cn_blocklist.sh             # 生成 data/blocklist.bin (~800KB)
pio run -e c3 -t upload && pio run -e c3 -t uploadfs
```

验证：`dig @<设备IP> ad.toutiao.com` → `0.0.0.0`；`dig @<设备IP> baidu.com` → 真实 IP。
无问题后，在路由器把 DHCP 下发的 DNS 指到设备 IP（设备 IP 先在路由器里做静态绑定）。

## 已知限制（DNS 拦截的边界，与上游一致）

- **同一域名混合内容无法区分**：抖音/微信朋友圈信息流、B 站/爱优腾贴片、CDN 同域广告
  —— DNS 层无解（Pi-hole 同样无解），需端上方案（如 AdGuard 本地 VPN 模式）叠加。
- **HTTPDNS 绕过**：淘宝/抖音等部分请求走内置 HTTPDNS，不经过本设备。
- **误杀排查**：某 APP 打不开时先在 dashboard 看 allowed/blocked 计数，用 `/pause` 暂停
  全局拦截做对照；确认误杀后点查询记录里的 **allow** 按钮一键放行（运行时白名单：自动定位到
  实际被拦的父域、覆盖其全部子域、优先级高于一切拦截源、flash 持久化）。
- 设备是全网 DNS 单点：路由器侧建议保留一个备用 DNS（如 223.5.5.5），设备挂了只退化为不拦截。
