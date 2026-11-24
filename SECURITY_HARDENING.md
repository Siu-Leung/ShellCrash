# ShellCrash 零信任安全加固版（Siu-Leung Fork）

基于 `juewuy/ShellCrash`，唯一维护分支为 **`dev`**（二进制与资源分支为自主编译的 **`update`**）。本 fork 以**零信任、去外链、全自主可控、本地优先**为目标，确保安装、更新、订阅拉取转换、规则与面板资源、日志推送及二进制构建全部可控、可审计。

## 全部加固与优化项

| 类别 | 原版行为 | 本加固版实现 |
|---|---|---|
| **订阅拉取与转换** | 在线转换把订阅 URL 发给第三方 `subconverter`（`sub.jwsc`/`v1.mk`），存在订阅泄露风险 | **内置零外泄本地拉取与转换引擎**（`scripts/libs/local_sub_convert.sh`）：仅直连原始订阅源下载到本地，纯 POSIX `sh`/`awk`/`base64` 自动识别并解码 Base64 / 明文 URI / Clash YAML / Sing-Box JSON，本地转义与正则过滤后套用本仓库规则模板生成纯本地 `type: file` / `type: local` 配置，定时更新与热更新均零外泄 |
| **纯净模式网络边界** | `firewall_area=4`（纯净模式）下无防火墙拦截，但仍默认监听 `0.0.0.0:9999` 控制面板与全网卡代理端口且无密码 | 纯净模式下未显式开启 `public_support=ON` 时，Clash/Mihomo 与 Sing-Box 默认仅绑定 `127.0.0.1`（`allow-lan: false`），杜绝公网服务器无密裸奔 |
| **配置与命令注入防护** | `9_upgrade.sh` / `task_cmd.sh` 存在间接变量 `eval`；`set_config.sh` 缺少键名校验与换行过滤；`override.sh` 缺输入校验且含非 POSIX `\s` | 白名单函数 `get_version_var` 消除间接变量 `eval`；`set_config.sh` 严格校验合法标识符、剥离 `\r\n` 并原子替换写回；`override.sh` 增加 `ovr_input_safe` 校验并兼容 BusyBox POSIX 字符类 |
| **TLS 证书校验** | 默认 `skip_cert=ON`；`install.sh` 与 `tools/tg_bot.sh` 硬编码 `-k` / `--no-check-certificate` | 全链路默认强制校验 TLS 证书（`skip_cert=OFF`），开启跳过需二次确认；`install.sh` / `install_en.sh` 仅在显式设置 `SKIP_CERT=1` 时放行 |
| **TG 日志推送 & Bot** | 支持 `publictoken` 经 `tgbot.jwsc.eu.org` 中转；帮助消息含推广返利与上游群链 | 移除公共机器人中转与全部推广/引流链接，仅直连 `api.telegram.org/bot<自建TOKEN>`；`tools/tg_bot.sh` 与 `tools/ShellDDNS.sh` 同步清理外链 |
| **仓库与更新供应链** | 默认拉取上游 `juewuy/ShellCrash`、私人源 `gh.jwsc`/`t.jwsc`、失效 `testingcf.jsdelivr.net`，容器环境与部分菜单切回 `master` | 全仓统一指向 `Siu-Leung/ShellCrash@dev`（`bin/` 走 `update` 分支）与 `cdn.jsdelivr.net`；锁定安装脚本、`init.sh` 容器环境、`9_upgrade.sh` 源切换均指向 `dev`；移除 `bfstart.sh` 外部在线面板 `board.zash.run.place` 跳转 |
| **DNS / Sing-Box 修复** | Sing-Box 私有 DoH 丢 path；`providers_singbox.sh` 将 `domain_resolver` 错误展开为 IP 列表；ECS 未全链路附加 | 完整支持 DoH 私有路径、修正 `"domain_resolver": "dns_proxy_server"` 字面 tag、全链路 ECS 附加、规范 fake-ip 分类转换与 `respect-rules` 可配 |
| **预打包基线与 CI 并发锁** | `ShellCrash.tar.gz` 长期滞后于 `scripts/` 源码；多内核并发编译推送 `update` 分支撞车；`bin_update.yml` 缺写权限且从 `master` 同步旧包 | `sync_pkg.sh` 升级为全量同步 `scripts/`、`public/servers*.list` 与 `version`；`bin_update.yml` 补齐 `write-all` 并从 `dev` 同步包；三大构建工作流加统一 `concurrency` 串行锁与 `git pull --rebase` 重试 |

## 深度安全与逻辑漏洞审计加固（V2 全仓审计）

在既有零信任基线上，对全仓脚本、规则模板、Docker 与 GitHub Actions 工作流完成逐行审计，并修复以下高危/中危安全漏洞与逻辑缺陷：

1. **Telegram Bot 认证绕过、Tar-Slip 与明文降级修复**：
   - `scripts/menus/bot_tg.sh` & `tools/tg_bot.sh`：强制校验 `TG_CHATID` 为非空整数、`TG_TOKEN` 格式合法；`getUpdates` 强制 `limit=1` 并严格解析首条消息的 `chat.id`（优先 `jq`，回退非贪婪匹配），杜绝攻击者在消息正文中伪造 `"id":<chat_id>` 或拼批绕过鉴权；对上传 `.tar.gz` 实施 `_safe_tar_check()` 防 Tar-Slip 路径穿越与符号链接攻击；全部 HTTP 调用移除硬编码 `-k`，统一遵循 fail-closed TLS 与 JSON 转义。
   - `scripts/menus/bot_tg_bind.sh`：校验 Bot Token 格式，修复贪婪正则误抓 `chat_ID`，支持负数群组 ID。
2. **任意命令执行与注入面清零**：
   - `scripts/start.sh` & `scripts/menus/task_cmd.sh`：移除通配符 `*) "$1"` 任意命令执行入口，改为严格命令白名单。
   - `scripts/libs/set_config.sh` + 全部菜单写入点（`2_settings.sh`、`6_core_config.sh`、`7_gateway.sh`、`8_tools.sh`、`9_upgrade.sh`、`dns.sh`、`fw_filter.sh`、`providers.sh`、`subconverter.sh`、`core_tools.sh`）：新增 POSIX 单引号安全写入函数 `setconfig_quote()`，防止 URL 中 `&`/`;`/单引号等字符在 `source ShellCrash.cfg` 时触发命令执行。
   - `scripts/menus/9_upgrade.sh` & `scripts/menus/override.sh`：修复 `awk '{print $'"$num"'}'` 命令注入；`5_task.sh`、`logger.sh`、`providers_*.sh` 以 `ENVIRON` awk 替代高危 `sed "/$var/d"`；`ddns.sh` 过滤 UCI 单引号/换行注入；`install.sh` / `install_en.sh` / `set_profile.sh` 严格校验别名标识符。
3. **全链路 TLS Fail-Closed 与最小暴露面**：
   - `web_get.sh`、`web_get_curlbar.sh`、`web_get_lite.sh`、`web_json.sh`、`local_sub_convert.sh`、`providers_*.sh`、`clash_modify.sh`、`singbox_modify.sh`、`8_tools.sh`、`bin_update.yml`：全部改为仅显式 `skip_cert=ON` 才跳过证书校验；修复 `web_get.sh` 在 curl 8.x 下代理认证/含空格 UA 分词失败问题。
   - 纯净模式（`firewall_area=4` 且 `public_support != ON`）下进一步将 Clash DNS 与 Sing-Box `dns-in` / `redirect-in` / `tproxy-in` 绑定收敛至 `127.0.0.1`；公网防火墙拒接端口扩展覆盖 `$dns_port,$redir_port,$tproxy_port`；修复 `8_tools.sh` `stop_iptables()` 误用 `ip6tables -A` 导致“关闭外网 SSH 反增放行规则”的严重漏洞。
4. **全链路自有仓库供应链与 CI 修复**：
   - `scripts/libs/web_get_bin.sh`：修复新装默认空 `url_id` 导致 `bin/*` 误拉 `@dev` 而非 `@update` 的致命缺陷。
   - `rules/clash_providers/*.yaml` & `rules/singbox_providers/*.json`：100% 规则集 URL 迁至 `Siu-Leung/ShellCrash@update/bin/ruleset/{mrs,srs}/`；同步升级 `bin_update.yml` 每日构建发布全套 `.mrs`/`.srs`（含 `ads`、`applications.list`、`googlefcm`、`steam-cn`）。
   - 修复所有 CI 工作流中 jsDelivr 缓存刷新路径误剥 `bin/`、`core_auto_update.yml` `gz` 构建永不更新 `bin/version`、未失败退出重试、`${{ inputs.* }}` 脚本注入、`write-all` 过宽权限及 `docker.yaml` 指向 `master` 等问题；`docker/compose.yml` 与 `docker/README.md` 改为自建镜像。
5. **关键逻辑与兼容性 Bug 修复**：
   - 修复 `init.sh` 空 `$shtype` 破坏脚本 shebang 与正文、缺少 `version` 写入及 `dns_direct_domains.list` 迁移。
   - 修复 `check_geo.sh` 引号导致 `find` 失败每次启动重复下载 GeoData、`task_cmd.sh` `update_scripts` 无法解析纯文本 `version`、`fw_nftables.sh` `$$vm_ipv4` 笔误、`singbox_modify.sh` 自定义规则 `source_ip_cidr`/`source_port` 字段错误与 `dns_protect=OFF` 失效、`sb_inbounds.sh` 尾部多余逗号、`local_sub_convert.sh` UTF-8 BOM 处理与流式 Base64 解码、`sync_pkg.sh` 干净重建无过期文件残留。

## 保留的官方 / 用户可控外发

- **用户原始订阅源**：本地拉取引擎仅直连用户自己添加的订阅 URL，不经任何第三方中转。
- **本仓库可控源**：`raw.githubusercontent.com/Siu-Leung/ShellCrash`、`cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash`（脚本走 `dev`，自编译内核/面板/GeoData/规则集走 `update`）。
- **用户显式配置的推送渠道**：`api.telegram.org`（自建 Bot）、PushDeer、Pushover、PushPlus（HTTPS）、自建 Bark / Gotify / SynoChat。
- **核心运行必需探测**：DoH/DNS、连通性探测（`gstatic.com/generate_204` 等）。

## 开发、同步打包与回归测试

实际安装与在线更新拉取的是仓库根目录的 **`ShellCrash.tar.gz`**。修改 `scripts/` 或 `public/` 后务必执行：

```sh
sh sync_pkg.sh                              # 干净重建 ShellCrash.tar.gz
for t in tests/test_*.sh; do sh "$t"; done  # 运行全部离线安全与功能回归测试
```

所有测试脚本均已兼容无 `ripgrep`（自动回退至标准 `grep -E`）的纯 Linux 环境。
