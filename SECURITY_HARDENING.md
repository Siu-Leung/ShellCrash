# ShellCrash 零信任安全架构与全仓审计说明

本项目（`Siu-Leung/ShellCrash`）基于原作者 **Juewuy** 的开源 GPL-3.0 项目 ShellCrash 独立演进并完成全面安全重构。唯一代码主分支为 **`dev`**，二进制与静态资源分发分支为自主构建的 **`update`**。项目以**零信任、去外链、全自主可控、本地优先**为核心设计原则，确保安装、更新、订阅拉取转换、规则与面板资源、通知控制及二进制构建全部可控、可审计。

## 核心架构加固总览

| 类别 | 原有风险 / 行为 | 当前项目实现 |
|---|---|---|
| **订阅拉取与转换** | 在线转换把订阅 URL 发给第三方 `subconverter`（`sub.jwsc`/`v1.mk`），存在订阅泄露风险 | **内置零外泄本地拉取与转换引擎**（`scripts/libs/local_sub_convert.sh`）：仅直连原始订阅源下载到本地，纯 POSIX `sh`/`awk`/`base64` 处理 UTF-8 BOM 与流式 Base64 解码，识别明文 URI / Clash YAML / Sing-Box JSON，本地转义与正则过滤后套用本仓库规则模板生成纯本地 `type: file` / `type: local` 配置，定时更新与热更新均零外泄 |
| **纯净模式与公网防火墙** | `firewall_area=4`（纯净模式）下无防火墙拦截，但仍监听全网卡控制面板、DNS 与透明代理端口且无密码；公网拦截遗漏 DNS/Redir/Tproxy 端口 | 纯净模式下未显式开启 `public_support=ON` 时，Clash DNS / 控制面板及 Sing-Box 全部 4 个入站（`mixed-in`/`dns-in`/`redirect-in`/`tproxy-in`）默认仅绑定 `127.0.0.1`（`allow-lan: false`）；公网防火墙同步拦截代理、面板、DNS 与透明代理端口；`crash doctor` 纳入回环监听巡检 |
| **配置与命令注入防护** | `start.sh`/`task_cmd.sh` 存在通配符 `*) "$1"` 任意命令执行；`9_upgrade.sh`/`task_cmd.sh`/`override.sh` 存在间接变量 `eval` 与 `awk` 字段拼接注入；`set_config.sh` 缺引号转义与键名校验 | 移除全部通配符命令执行改为严格白名单；`get_version_var` 消除间接 `eval`；`set_config.sh` 新增 `quote_cfg_val`/`setconfig_quote`（POSIX 单引号转义 + 标识符校验 + 原子写入），覆盖全菜单与安装脚本；`awk` 统一改用 `-v`/`ENVIRON` 传参 |
| **TLS 证书校验（Fail-Closed）** | 默认 `skip_cert=ON`；多处脚本与 CI 硬编码 `-k` / `--no-check-certificate` 或使用 fail-open 判断 `!= OFF` | 全链路默认强制严格校验 TLS 证书（`skip_cert=OFF`，仅显式 `skip_cert=ON` 时跳过）；`install.sh`/`install_en.sh` 仅在显式设置 `SKIP_CERT=1` 时放行；PushPlus 与 DDNS 升级为 HTTPS；CI 流水线移除 `-k` |
| **自建 Telegram Bot 与推送** | 支持公共机器人中转；`bot_tg.sh` 缺 `TG_CHATID` 启动校验、未限 `limit=1` 且贪婪提取 `"id"` 可被正文伪造绕过；配置恢复未防 Tar-Slip；`tools/tg_bot.sh` 无 ChatID 校验 | 移除公共机器人中转与全部推广/引流链接，仅直连 `api.telegram.org/bot<自建TOKEN>`；强制数字型 `TG_CHATID`（含负数群组）与非空 `TG_TOKEN`；固定 `limit=1` 并严格提取消息头 `chat.id`；`_safe_tar_check` 拦截 `../`、绝对路径、符号链接、硬链接及设备节点 |
| **全链路自主供应链** | 依赖外部下载源、第三方规则集仓库、上游 Docker 镜像；新装空 `url_id` 时 `bin/*` 误拉 `@dev`；CI 过宽 `write-all` 权限与 `${file#bin/}` 缓存刷新失效 | 全仓统一指向 `Siu-Leung/ShellCrash`（脚本走 `dev`，内核/面板/GeoData/规则集走 `update`）；`web_get_bin.sh` 修复新装分支分流；全部 14 份规则模板与 6 个面板 URL 迁至本仓库 `@update`；Docker 改为本地自建 `shellcrash:local`；CI 全部收敛为最小权限并修复缓存刷新、版本更新与输入隔离 |
| **DNS / Sing-Box 与逻辑修复** | Sing-Box 私有 DoH 丢 path、`dns_protect=OFF` 未改 `dns.json` `final`、`source_ip`/`source_port` 字段不规范、密码含 `:` 被截断、`sb_inbounds.sh` 尾部多余逗号；`8_tools.sh` `stop_iptables` 误用 `iptables` 清理 IPv6；`fw_nftables.sh` `$$vm_ipv4` 笔误 | 逐项修复上述 JSON/YAML 语法与转义、IPv6 防火墙清理、`check_geo.sh` `find` 引号、`init.sh` shebang 锚定、`fw_filter.sh` `add_ip` 目标文件、`9_upgrade.sh` 退出码与正则等全部缺陷 |
| **干净打包与离线测试** | 预打包 `ShellCrash.tar.gz` 混入 `README.md` 且容易残留过期文件 | 重写 `sync_pkg.sh` 从零干净构建 `ShellCrash.tar.gz`（保留 `cn_ip.txt`/`cn_ipv6.txt`，剔除 `README.md`）；配套 15 套离线回归测试覆盖全部安全与逻辑不变量 |

## V2 全仓逐行深度审计记录

1. **Telegram Bot 认证绕过与 Tar-Slip 防护**：
   - `scripts/menus/bot_tg.sh` & `tools/tg_bot.sh`：启动校验 `TG_CHATID` 为非空整数（含负数群组）及非空 `TG_TOKEN`；`getUpdates` 强制 `limit=1`，通过 `extract_chat_id()`（优先 `jq`，无 `jq` 回退匹配正文前首个 `"chat":{"id":...}`）防止正文伪造 `"id"` 或多条更新错位越权；`_safe_tar_check()` 检查 `tar -tzf` 与 `tar -tvzf`，拦截绝对路径、`../` 路径穿越及符号链接/硬链接/设备节点；全部请求移除硬编码 `-k` 并统一做 JSON 转义。
   - `scripts/menus/bot_tg_bind.sh`：校验 Bot Token 格式，修复贪婪正则误抓 `chat_ID`，支持负数群组 ID。
2. **任意命令执行与注入面清零**：
   - `scripts/start.sh` & `scripts/menus/task_cmd.sh`：彻底删除通配符 `*) "$1"` 任意命令执行入口，改为严格命令白名单（`start.sh` 补齐 `start_firewall` 合法动作）。
   - `scripts/libs/set_config.sh` + 全部菜单写入点（`2_settings.sh`、`6_core_config.sh`、`7_gateway.sh`、`8_tools.sh`、`9_upgrade.sh`、`dns.sh`、`fw_filter.sh`、`providers.sh`、`subconverter.sh`、`core_tools.sh`）：采用 POSIX 单引号安全写入函数 `setconfig_quote()`，防止 URL/密码中 `&`/`;`/单引号/`$(...)` 在 `source ShellCrash.cfg` 时触发命令执行。
   - `scripts/menus/9_upgrade.sh` & `scripts/menus/override.sh`：修复 `awk '{print $'"$num"'}'` 命令注入；`5_task.sh`、`logger.sh`、`providers_*.sh` 以 `ENVIRON` awk 替代高危 `sed "/$var/d"`；`ddns.sh` 过滤 UCI 引号/换行注入；`install.sh` / `install_en.sh` / `set_profile.sh` 严格校验 `my_alias` 标识符。
3. **全链路 TLS Fail-Closed 与网络边界加固**：
   - `web_get.sh`、`web_get_curlbar.sh`、`web_get_lite.sh`、`web_json.sh`、`local_sub_convert.sh`、`providers_*.sh`、`clash_modify.sh`、`singbox_modify.sh`、`8_tools.sh`、`bin_update.yml`：全部统一为仅显式 `skip_cert=ON` 才跳过证书校验；修复 `web_get.sh` 在 curl 8.x 下代理认证/含空格 UA 分词失败及重试直连残留代理环境变量问题。
   - 纯净模式（`firewall_area=4` 且 `public_support != ON`）下将 Clash DNS 与 Sing-Box `dns-in` / `redirect-in` / `tproxy-in` 均收敛至 `127.0.0.1`；公网防火墙拦截端口扩展覆盖 `$dns_port,$redir_port,$tproxy_port`（带 `set -u` 安全回退）；修复 `8_tools.sh` `stop_iptables()` 清理 IPv6 SSH 转发规则时误用 `iptables` 而非 `ip6tables` 的漏洞。
4. **全链路自有仓库供应链与 CI 修复**：
   - `scripts/libs/web_get_bin.sh`：修复新装默认空 `url_id` 导致 `bin/*` 误拉 `@dev` 而非 `@update` 的缺陷。
   - `rules/clash_providers/*.yaml` & `rules/singbox_providers/*.json`：14 份规则模板下载 URL 100% 迁至 `Siu-Leung/ShellCrash@update/bin/ruleset/{mrs,srs}/`（保留 Nano 模板的 `bin/geodata/`）；`bin_update.yml` 每日构建发布全套 `.mrs`（含 `applications.list`、`ads.mrs`、`googlefcm.mrs`、`steam-cn.mrs`）与 `.srs`。
   - 全部 6 个 GitHub Actions 工作流收敛为最小权限（移除 `write-all`）、将 `${{ inputs.* }}` 改经 `env:` 隔离防脚本注入、修复 jsDelivr 缓存刷新误剥 `bin/` 前缀、修复 `core_auto_update.yml` `gz` 构建漏写 `bin/version`、三次推送失败显式报错，并将 `docker.yaml` 触发分支切至 `dev`；`docker/compose.yml` 与 `docker/README.md` 改为本地自建镜像。
5. **关键逻辑与兼容性 Bug 修复**：
   - 修复 `init.sh` 空 `$shtype` 破坏脚本 shebang 与正文、缺 `version` 读取及 `dns_direct_domains.list` 迁移。
   - 修复 `check_geo.sh` 误引号 `"$find_para"` 导致每次启动重复下载 GeoData、`task_cmd.sh` `update_scripts` 无法解析纯文本 `version`、`fw_nftables.sh` `$$vm_ipv4` 笔误、`fw_filter.sh` `add_ip` 误查 `mac` 文件、`singbox_modify.sh` 与 `clash_modify.sh` 认证/密钥转义及 `dns_protect=OFF` 失效、`sb_inbounds.sh` 尾部多余逗号、`local_sub_convert.sh` UTF-8 BOM 剥离与流式 Base64 解码、`2_settings.lang` / `menu.lang` 英文缺失键同步。

## V3 复核与发布门禁加固（对应第三方复核清单）

1. **修复有效 Mihomo 直链订阅误拒（S1）**：`clash_config_check.sh` 与 `singbox_config_check.sh` 函数末尾显式 `return 0`，杜绝未设 `url_type` 时被误判校验失败；`core_config.sh` 修正备份替换判断逻辑，仅在落盘成功后提示成功。
2. **Telegram 群组操作者鉴权（T1）**：`bot_tg.sh` 与 `tools/tg_bot.sh` 新增 `extract_from_id()` 与 `is_authorized_event()`——私聊模式同时核验 `chat.id` 与 `from.id`，群组模式（负数 `TG_CHATID`）必须显式配置 `TG_ADMIN_IDS` 管理员白名单，否则默认拒绝一切群组管理操作。
3. **升级事务化与内核回滚（U1 / U2 / 信任边界）**：
   - `set_config.sh` 新增纯数据解析函数 `load_version_file()`（彻底替代对远端下载 `bin/version` 的直接 `source`）及 `safe_tar_check()`、`ensure_safe_tmpdir()`。
   - `9_upgrade.sh` 与 `task_cmd.sh` 脚本升级改为“先暂存校验 Tar-Slip 与关键脚本语法 -> 备份现用脚本 -> 切换并校验 -> 失败自动回滚并恢复服务运行态”。
   - `core_tools.sh` 与 `task_cmd.sh` 内核升级改为先验候选二进制与现用配置、备份旧归档至 `$TMPDIR/core_bak`，启动失败时调用 `core_rollback()` 自动回滚。
4. **运行态细节修复**：
   - `shellcrash.service` 与 `start.sh` 移除 systemd `ExecStart` 中会被当字面参数传入的 `>/dev/null`（由 `StandardOutput=null` 接管）。
   - `singbox_modify.sh` `sb_convert_domain_rules()` 修复裸 `*` 误转为 `.*` 破坏 Fake-IP 的缺陷（改为 `^[^.]+$` 匹配单标签主机名），并统一做合法 JSON 双反斜杠转义及 `+.stun.*.*` 混合通配转换。
   - `local_sub_convert.sh` 改为暂存目录拉取并校验通过后再原子提交 `$CRASHDIR/providers/`，单源临时拉取失败自动保留上次有效缓存并告警。
   - `menu.sh` 将 `crash doctor` 提前到 `get_config.sh` 之前执行以确保严格只读；`task_cmd.sh` 数值任务透传真实退出码；`9_upgrade.sh` 移除已下线的 `Clash` 旧内核菜单项。
5. **发布门禁与 CI 治理（R1 / R2 / R3 / D1）**：
   - 版本号推进至 `1.9.7-hardened.1`，`bin_update.yml` 同步清理旧 `clash_v=`、生成 `bin/SHA256SUMS` 并同时刷新 `@dev` 与 `@update` 的 jsDelivr 缓存。
   - 删除含注入风险或失效的 `test.yaml`、`release_new_version.yaml`、`docker_readme_push.yaml`；`core_easy_update.yaml` 补齐 `singbox` 的 `tar.gz` 构建；`update_singbox_core.yaml` 按实际检出 ref 记录版本；将推送锁下沉至 `push_to_git` 作业级消除嵌套并发死锁风险；`docker.yaml` 在未配置 Docker Hub Secrets 时降级为本地构建校验；新增 `ci.yml` 在每次推送 `dev` 时自动运行 POSIX `sh` / BusyBox `ash` 语法检查、全套离线回归测试与 `ShellCrash.tar.gz` 字节一致性核验。
   - 明确区分 **CI 构建时取材上游**（MetaCubeX、SagerNet、reF1nd、DustinWin、Zephyruso、Alpine/s6）与 **运行时本仓库分发**（`Siu-Leung/ShellCrash@dev` & `@update`）。

## V4 实机与全量故障注入复核修复（`1.9.7-hardened.2`）

1. **损坏备份恢复保护（`2_settings.sh`）**：先以 `safe_tar_check` 校验并在隔离暂存目录解包核验 `ShellCrash.cfg`，通过后才备份并切换现用配置，杜绝损坏备份清空配置却误报“已还原”。
2. **统一事务化脚本升级与字节幂等配置（`set_config.sh` / `init.sh` / `9_upgrade.sh` / `task_cmd.sh` / `core_tools.sh`）**：
   - `setconfig` 在键值已唯一存在且完全一致时零改写返回，`init.sh` 保留已有配置字段，确保同版本重装/覆盖时 `ShellCrash.cfg` 字节 100% 不变。
   - 新增统一事务升级函数 `apply_script_upgrade()`：子 Shell 运行 `init.sh` 捕获 `exit`、安装 `INT/TERM` 回滚陷阱、校验 `start.sh stop/start` 状态、失败时字节级还原旧脚本与旧配置并清理全部新增残留文件。
   - `setscripts()` 严格检查 `getscripts` 返回值不再误报成功；`getdb()`/`dbdir()`/`setdb()` 先暂存校验面板压缩包再原子替换；任务 `111`/`112`/`113` 均在版本或 Geo 下载失败时返回非零。
3. **内核配置与 Sing-BoxR 兼容性修复（`clash_modify.sh` / `local_sub_convert.sh` / `providers_singbox.sh` / `singbox_modify.sh`）**：
   - `clash_modify.sh` 修复 `proxies: []` 误生成空 `- ` 节点导致 Mihomo 启动报 `proxy 0: missing type` 的缺陷，并对 YAML flow DNS 列表加单引号兼容 `https://[IPv6]:port` DoH。
   - `local_sub_convert.sh` & `providers_singbox.sh` 将 Sing-BoxR 节点 `include`/`exclude` 筛选移至 `urltest` 出站对象（修复 `providers[0].include/exclude: unknown field`）；对标准版 `singbox` 提前明确提示不支持 Sing-BoxR provider 模板；`local_fallback_cached_provider` 扩展支持 `.json` 缓存；合并后额外运行 `CrashCore check` 校验；`singbox_modify.sh` 将 `doh://`/`dot://` 归一化为 `https`/`tls`。
4. **菜单校验与本地化修复（`dns.sh` / `2_settings.sh` / `7_gateway.sh` / `8_tools.sh` / `9_upgrade.sh` / `ddns.sh` / `menu.sh`）**：
   - `dns.sh` 严格校验 IPv4 八位组 `0-255`、保存前拦截与本机接口重叠的 Fake-IP 网段并补齐全套英文翻译。
   - `2_settings.sh` 端口冲突检查覆盖 `tproxy_port`（`redir_port+1`）并修复非法语言/布局选项行为；`7_gateway.sh` 取消关闭 WAN 防火墙不再写盘；`ddns.sh` 拒绝越界序号；`8_tools.sh` / `9_upgrade.sh` 取消输入不再污染会话变量并移除误导性 `stable`/`master` 选项；`menu.sh` 补齐 `crash doctor` 英文帮助说明。

## 允许的外发通信范围

- **用户原始订阅源**：本地拉取引擎仅直连用户自己配置的订阅 URL，绝不发送给任何第三方转换服务。
- **本仓库可控源**：`raw.githubusercontent.com/Siu-Leung/ShellCrash`、`cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash`（脚本走 `dev`，自编译内核/面板/GeoData/规则集走 `update`）。
- **用户显式配置的推送渠道**：`api.telegram.org`（自建 Bot）、PushDeer、Pushover、PushPlus（HTTPS）、自建 Bark / Gotify / SynoChat。
- **核心运行必需探测**：DoH/DNS 与连通性探测（`gstatic.com/generate_204` 等）。

## 开发、同步打包与离线回归测试

实际安装与在线更新拉取的是仓库根目录的 **`ShellCrash.tar.gz`**。修改 `scripts/`、`public/` 或 `rules/` 后务必执行：

```sh
sh sync_pkg.sh                                                       # 干净重建 ShellCrash.tar.gz
for t in tests/test_*.sh tests/clash_geodata.sh; do sh "$t" || exit 1; done  # 运行全部 15 套离线回归测试
```

所有测试脚本均兼容无 `ripgrep`（自动回退至标准 `grep -E`）的纯 Linux 环境。
