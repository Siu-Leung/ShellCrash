# ShellCrash 安全加固版（Siu fork）

基于 `juewuy/ShellCrash`，分支 `dev`。这一 fork 的目标是**去除第三方中转与推广外发**，
让日志推送、订阅获取、软件更新只走用户自己配置的端点或官方源。

## 改了什么

| 项 | 原版行为 | 加固后 |
|---|---|---|
| TG 日志推送 | 支持 `publictoken`，日志经 `tgbot.jwsc.eu.org` 公共机器人中转 | **移除公共机器人**，只走 `api.telegram.org/bot<自建TOKEN>` |
| 配置文件菜单 | 在线转换把订阅链接拼进第三方子converter（`sub.jwsc` / `api.v1.mk` / `url.v1.mk`） | **禁用在线转换入口**，保留「在线获取（不转换）」和原生 HTTP provider |
| 更新/规则源列表 | 内置 `gh.jwsc`、`t.jwsc`、`sub.jwsc`、`api.v1.mk` 等第三方源 | 全部注释停用，仅保留 GitHub / jsDelivr 官方源与公开规则模板 |
| TG 帮助信息 | 内置机场推广、打赏返利链接（`dler.pro`、`bigmeok`） | 删除 |
| 安装文档 | README 示例含作者私人源 `gh.jwsc` | 删除，仅留官方 GitHub / jsDelivr |

## 保留的官方/用户可控外发

- `api.telegram.org`：用户自建 Bot 推送（配置 `push_TG` 才启用）
- `api2.pushdeer.com` / `pushover.net` / `pushplus` / 自建 Bark、Gotify、SynoChat：用户显式配置的推送渠道
- `raw.githubusercontent.com` / `github.com` / `testingcf.jsdelivr.net` / `cdn.jsdelivr.net`：脚本与内核更新、规则模板
- `web_get.sh` 里 `gh.jwsc` → `raw.githubusercontent` 的映射仅为兼容旧配置字符串的**重定向映射**，不主动外发，保留
- DNS / 连通性探测（gstatic、baidu、ipinfo 等）：核心功能所需

## 重要：改哪里才生效

实际安装与在线更新下载的是仓库根目录的 **`ShellCrash.tar.gz`**（扁平化脚本包），
不是 `scripts/` 源码目录。本 fork 两边已同步修改；若以后改源码，务必执行：

```sh
sh sync_pkg.sh          # 把 scripts/ public/ 改动同步进 ShellCrash.tar.gz
sh tests/test_security_hardening.sh   # 离线回归
```

## 回归

`tests/test_security_hardening.sh` 做静态断言：无第三方外发 URL、加固标记存在、
`sh -n` 语法校验、包与源码同步、第三方源全部停用。纯离线，不改真实环境。

## 已知边界

- 只静态审计脚本，未做动态抓包；不过外发点均为硬编码 URL，改动即生效。
- 上游更新会覆盖加固：更新脚本会从官方源拉新 `ShellCrash.tar.gz`。**不要在本 fork 实例里点「更新脚本」**，
  需要新版本时在本 fork 合入上游改动后重新生成加固包。
- 用户手动往配置里填第三方转换 URL 的行为不在本 fork 控制范围。
