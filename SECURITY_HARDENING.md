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

## 保留的官方 / 用户可控外发

- **用户原始订阅源**：本地拉取引擎仅直连用户自己添加的订阅 URL，不经任何第三方中转。
- **本仓库可控源**：`raw.githubusercontent.com/Siu-Leung/ShellCrash`、`cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash`（脚本、自主编译内核、面板、GeoData、规则模板）。
- **用户显式配置的推送渠道**：`api.telegram.org`（自建 Bot）、PushDeer、Pushover、PushPlus、自建 Bark / Gotify / SynoChat。
- **核心运行必需探测**：DoH/DNS、连通性探测（`gstatic.com/generate_204` 等）。

## 开发、同步打包与回归测试

实际安装与在线更新拉取的是仓库根目录的 **`ShellCrash.tar.gz`**。修改 `scripts/` 或 `public/` 后务必执行：

```sh
sh sync_pkg.sh                              # 全量同步源码到 ShellCrash.tar.gz
for t in tests/test_*.sh; do sh "$t"; done  # 运行全部 13 项离线与功能回归测试
```

所有测试脚本均已兼容无 `ripgrep`（自动回退至标准 `grep -E`）的纯 Linux 环境。
