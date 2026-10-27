# 中国区部署说明 (China deployment)

这是 [M-Abozaid/esp32-c3-adblock](https://github.com/M-Abozaid/esp32-c3-adblock) 的中国区本地化分支。
上游请参考根目录 [README.md](../README.md)。

## 本分支的改动

| 文件 | 改动 | 原因 |
|---|---|---|
| `partitions.csv` | 固件槽 0x150000→0x160000，规则分区 0x150000→0x120000 | 上游在新版 arduino-esp32 下编译超分区（issue #48） |
| `src/main.cpp` | 上游 DNS: Quad9 `9.9.9.9` → 阿里 `223.5.5.5` | Quad9 在国内延迟高且易被污染；想换 DNSPod 改回 `119,29,29,29` |
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
已配置：`.github/workflows/blocklist-cn.yml`，每周一 13:23（北京时间）自动
下载规则源 → 构建 → 推送 Gitee dist 分支 → 发 GitHub release 备份。

唯一前置条件（一次性）：在 GitHub 仓库 Settings → Secrets → Actions 添加
`GITEE_PUSH_TOKEN` = Gitee 私人令牌（projects 权限）。

手动触发：
`gh workflow run blocklist-cn.yml --repo ichewm/esp32-c3-adblock-cn`。

为什么不用 Gitee Go（国内 CI）：实测其「通用变量」对文件式 .workflow
流水线不生效（环境变量注入与 `${}` 文本替换均无效），无法安全地携带
推送令牌；且构建节点在国内百度云，拉不动 GitHub 规则源。
注：固件已把 Gitee raw 地址和 168 小时间隔烧录为默认值 —— 刷完即自动每周拉取，
无需任何 dashboard 配置；手动设置过 Remote auto-update 的设备会覆盖默认值。

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
  全局拦截做对照；确认误杀的域名在上游列表里，本分支暂无运行时白名单（规划中）。
- 设备是全网 DNS 单点：路由器侧建议保留一个备用 DNS（如 223.5.5.5），设备挂了只退化为不拦截。
