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

合并去重后 **~161k 条 / ~807KB / 0 哈希碰撞**，分区容量约 220k 条（余量 ~35%）。
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

## CI（Gitee Go 每周定时重建）

仓库已内置 `.workflow/blocklist-weekly.yml`（每周二 10:00 定时重建并推 dist 分支）。
首次使用需在网页上做两个一次性操作：

1. **开通 Gitee Go**（免费赠 200 分钟/仓库，永久有效；未开通时报「构建时长余额不足」）：
   打开 `https://gitee.com/hewmbj/esp32-c3-adblock-cn/gitee_go` 点「开通」。
2. **配置推送令牌**：仓库「管理」→「环境变量设置」，添加 `GITEE_TOKEN` =
   你的 Gitee 私人令牌（需 projects 权限），供流水线把新列表推回 dist 分支。

之后可手动触发验证：
`gitee pipeline run -R hewmbj/esp32-c3-adblock-cn --ref main --file blocklist-weekly.yml`。
不想用 CI 的话，本地 crontab 跑 `tools/publish_gitee.sh` 效果相同（全程已验证）。

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
