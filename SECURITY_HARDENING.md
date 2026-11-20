# ShellCrash 零信任安全加固版（Siu-Leung Fork）

基于 `juewuy/ShellCrash`，唯一维护分支为 **`dev`**。本 fork 以**零信任、去外链、全自主可控、本地优先**为目标，让安装、更新、订阅拉取转换、规则与面板资源、日志推送全部只走用户自己配置的端点或本仓库可控源。

## 全部加固与优化项

| 类别 | 原版行为 | 本加固版实现 |
|---|---|---|
| **订阅拉取与转换** | 在线转换把订阅 URL 发给第三方 `subconverter`（`sub.jwsc`/`v1.mk`），存在订阅泄露风险 | **内置零外泄本地拉取与转换引擎**（`scripts/libs/local_sub_convert.sh`）：直连原始订阅源下载到本地，纯 POSIX sh/awk/base64 自动识别并解码 Base64 / 明文 URI / Clash YAML / Sing-Box JSON，本地正则过滤后套用本仓库规则模板生成纯本地 `type: file` / `type: local` 配置，定时更新与热更新均零外泄 |
| **TG 日志推送 & Bot** | 支持 `publictoken` 经 `tgbot.jwsc.eu.org` 中转；帮助消息含推广返利与上游群链 | 移除公共机器人中转与全部推广/引流链接，仅直连 `api.telegram.org/bot<自建TOKEN>`；`tools/tg_bot.sh` 同步清理外链并默认校验证书 |
| **仓库与更新供应链** | 默认拉取上游 `juewuy/ShellCrash`、私人中转源 `gh.jwsc`/`t.jwsc`、失效 `testingcf.jsdelivr.net`，容器环境默认 `master` | 全仓统一指向 `Siu-Leung/ShellCrash@dev`（`bin/` 走 `update` 分支）与 `cdn.jsdelivr.net`；锁定安装脚本、`init.sh` 容器环境、`9_upgrade.sh` 源切换均指向 `dev`；移除 `bfstart.sh` 第三方在线面板 `board.zash.run.place` 跳转 |
| **TLS 证书校验** | 默认 `skip_cert=ON`；`install.sh` 硬编码 `curl -k` / `--no-check-certificate` | 默认强制校验 TLS 证书（`skip_cert=OFF`），开启跳过需二次确认；`install.sh` / `install_en.sh` 默认开启证书校验（仅 `SKIP_CERT=1` 显式放行） |
| **命令注入与输入校验** | `9_upgrade.sh` / `task_cmd.sh` 存在间接变量 `eval`；`override.sh` 缺少输入校验且含非 POSIX `\s` | 白名单函数 `get_version_var` 消除间接变量 `eval`；`override.sh` 增加 `ovr_input_safe` 输入校验并全面兼容 BusyBox POSIX 字符类 |
| **DNS / Fake-IP 加固** | Sing-Box 私有 DoH 路径解析丢 path；ECS 未全链路附加；fake-ip 通配符转换不完整 | 完整支持 DoH 私有路径、全链路 ECS 附加、规范 `domain`/`domain_suffix`/`domain_regex` 分类转换与 `respect-rules` 可配 |
| **预打包基线统一** | `ShellCrash.tar.gz` 长期滞后于 `scripts/` 源码（10 个核心脚本不同步） | `sync_pkg.sh` 升级为全量同步 `scripts/`、`public/servers*.list` 与 `version`，源码与安装包 100% 一致 |

## 保留的官方 / 用户可控外发

- **用户原始订阅源**：本地拉取引擎仅直连用户自己添加的订阅 URL，不经任何第三方中转。
- **本仓库可控源**：`raw.githubusercontent.com/Siu-Leung/ShellCrash`、`cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash`（脚本、内核、面板、GeoData、规则模板）。
- **用户显式配置的推送渠道**：`api.telegram.org`（自建 Bot）、PushDeer、Pushover、PushPlus、自建 Bark / Gotify / SynoChat。
- **核心运行必需探测**：DoH/DNS、连通性探测（`gstatic.com/generate_204` 等）。

## 开发、同步打包与回归测试

实际安装与在线更新拉取的是仓库根目录的 **`ShellCrash.tar.gz`**。修改 `scripts/` 或 `public/` 后务必执行：

```sh
sh sync_pkg.sh                         # 全量同步源码到 ShellCrash.tar.gz
for t in tests/test_*.sh; do sh "$t"; done   # 运行全部离线与功能回归测试
```

所有测试脚本均已兼容无 `ripgrep`（自动回退至标准 `grep -E`）的纯 Linux 环境。
