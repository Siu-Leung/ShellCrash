<h1 align="center">ShellCrash（零信任安全加固版）</h1>

<p align="center">
  <a target="_blank" href="https://github.com/MetaCubeX/mihomo/releases">
    <img src="https://img.shields.io/github/release/MetaCubeX/mihomo.svg?style=flat-square&label=Mihomo">
  </a>
  <a target="_blank" href="https://github.com/SagerNet/sing-box/releases">
    <img src="https://img.shields.io/github/release/SagerNet/sing-box.svg?style=flat-square&label=Sing-Box">
  </a>
  <a target="_blank" href="https://github.com/Siu-Leung/ShellCrash/commits/dev">
    <img src="https://img.shields.io/github/last-commit/Siu-Leung/ShellCrash/dev?style=flat-square&label=Dev&color=green">
  </a>
</p>

<p align="center">
  <strong>独立维护、零信任、全链路自主分发的 Linux / 路由器 Mihomo &amp; Sing-Box 管理项目</strong>
</p>

<p align="center">
  简体中文 | <a href="README.md">English</a> | <a href="SECURITY_HARDENING.md">安全审计与加固清单</a> | <a href="docker/README.md">Docker 部署</a>
</p>

## 项目定位与分支架构

本项目是面向 Linux 服务器与路由器的独立零信任安全加固版本，所有脚本、规则、面板、GeoData 与自编译内核均由本仓库自主构建与分发，不依赖任何第三方下载源、在线订阅转换站或公共中转机器人。

| 分支 / 路径 | 用途 | 内容说明 |
| :--- | :--- | :--- |
| **`dev` 分支** | 脚本与源码主分支 | 安装脚本（`install.sh` / `install_en.sh`）、全套 Shell 脚本（`scripts/`、`tools/`）、规则模板（`rules/`）、列表配置（`public/`）、Docker 构建文件与预打包 `ShellCrash.tar.gz` |
| **`update` 分支** | 二进制与静态资源分发分支 | 自编译全架构内核（`bin/meta/`、`bin/singbox/`、`bin/singboxr/`）、Web 面板（`bin/dashboard/`）、GeoIP/GeoSite（`bin/geodata/`）、全套规则集（`bin/ruleset/mrs/`、`bin/ruleset/srs/`）与 CA 证书 |

## 核心特性

- **运行时全链路自有分发**：彻底移除第三方中转源、在线订阅转换站、公共推送机器人、外部在线面板与上游 Docker 镜像依赖。运行时安装、脚本更新（`dev` 分支）以及内核、规则集、面板、GeoData（`update` 分支）均由本仓库直接分发；上游项目（MetaCubeX、SagerNet、reF1nd、DustinWin、Zephyruso、Alpine/s6 等）仅作为 GitHub Actions 构建时的源码与静态资源取材来源。
- **零外泄本地订阅拉取与转换**：订阅链接只直连你自己的原始订阅源，在本机使用纯 POSIX `sh`/`awk`/`base64` 自动识别并处理 UTF-8 BOM、流式 Base64 解码、明文 URI 列表（`ss`/`ssr`/`vmess`/`vless`/`trojan`/`hy2`/`tuic`/`anytls`/`wireguard` 等）、Clash YAML 与 Sing-Box JSON，经暂存校验后原子切换本地 `type: file` / `type: local` 配置（单源临时失败自动保留上次有效缓存）。
- **默认安全边界（Fail-Closed）**：
  - 安装脚本、下载库、内核配置、本地订阅转换、Telegram Bot 与 CI 流水线默认强制开启严格 TLS 证书校验（`skip_cert=OFF`，仅显式 `skip_cert=ON` 才放行）。
  - 纯净/本机模式（`firewall_area=4` 且未开启公网访问）下，Clash DNS / 控制面板及 Sing-Box 全部 4 个入站均默认收敛至 `127.0.0.1`；公网防火墙同时拦截代理端口、面板端口、DNS 端口与透明代理端口。
  - 远端 `bin/version` 清单采用白名单纯数据解析（禁止 `source` 执行）；脚本与内核升级均采用暂存校验 + 失败自动回滚；配置写入使用 `setconfig_quote`，消除间接 `eval`、`awk` 注入与通配符任意命令执行。
- **自建 Telegram Bot 严格鉴权**：仅直连官方 `api.telegram.org`，默认仅私聊生效（同时核验 `chat.id` 与 `from.id`）；群组模式（负数 `TG_CHATID`）必须显式配置 `TG_ADMIN_IDS` 管理员用户白名单方可控制，杜绝群内普通成员越权；配置恢复压缩包内置 Tar-Slip 与符号链接/硬链接拦截。
- **多内核与全场景 Linux 支持**：支持 Mihomo（Meta）、Sing-Box、Sing-BoxR 内核切换；兼容 Debian/Ubuntu/CentOS/Alpine/Arch 等标准 Linux、OpenWrt、Padavan、华硕/梅林及自建 Docker 容器。
- **自动化回归 CI 与自主构建**：内置最小权限 GitHub Actions 工作流——`ci.yml` 在每次推送 `dev` 时自动校验 POSIX `sh` / BusyBox `ash` 语法、运行全套离线回归测试并校验 `ShellCrash.tar.gz` 字节一致性；`core_easy_update` / `core_auto_update` / `bin_update` 自动构建并附带 `bin/SHA256SUMS` 与双分支 CDN 缓存刷新。

## 安装指南

> [!IMPORTANT]
> 请以 `root` 用户执行安装。以下命令默认开启严格的 TLS 证书校验（仅在缺少根证书的老旧设备上，才建议临时通过 `SKIP_CERT=1` 放行）。

### 标准 Linux / 路由器一键安装

**通过 jsDelivr CDN 源（推荐）：**

```sh
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && sh -c "$(curl -fsSL $url/install.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

**通过 GitHub Raw 直连源（海外服务器或已有代理环境）：**

```sh
export url='https://raw.githubusercontent.com/Siu-Leung/ShellCrash/dev' \
  && sh -c "$(curl -fsSL $url/install.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

**使用 `wget` 安装：**

```sh
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && wget -q -O /tmp/install.sh "$url/install.sh" \
  && sh /tmp/install.sh \
  && . /etc/profile >/dev/null 2>&1
```

### Alpine Linux 虚拟机

```sh
apk add --no-cache curl wget openrc ca-certificates tzdata nftables iproute2 dcron
export url='https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev' \
  && sh -c "$(curl -fsSL $url/install.sh)" \
  && . /etc/profile >/dev/null 2>&1
```

### Docker 与离线安装

- **Docker**：克隆本仓库 `dev` 分支后使用本地 `Dockerfile` 与 `docker/compose.yml` 自构建运行，详见 [docker/README.md](docker/README.md)。
- **本地离线安装**：从本仓库 `dev` 或 `update` 分支下载 `ShellCrash.tar.gz`，上传至目标设备 `/tmp/` 目录后解压并运行 `init.sh` 完成初始化。

## 快速上手

安装完成后，在终端输入以下命令进入管理界面：

```sh
crash        # 启动交互管理菜单
crash doctor # 一键环境与安全健康自检（只读）
crash -h     # 查看命令行帮助
```

### 零外泄订阅配置（推荐流程）

1. 进入 `6 配置文件管理 -> a) 添加提供者`，粘贴你的原始订阅链接（支持 Clash YAML、Base64 通用订阅、明文节点分享链接或本地文件）。
2. 返回 `6 配置文件管理`，选择 **`c) 本地拉取并转换配置文件（零外泄）`**。
3. 可按需设置排除/包含节点正则、切换本仓库规则模板、指定拉取 UA，点击 `1)` 即可在本机完成拉取、解码、过滤与规则合成。
4. 如需自动定时更新，在 `5 定时任务` 中启用 `104 更新订阅并重启` 或 `105 热更新订阅`，后台同样 100% 走本机直拉转换。

### 自建 Telegram Bot 绑定

1. 向 Telegram 官方 `@BotFather` 申请你自己的 Bot Token。
2. 在菜单中进入 `7 网关与远程管理 -> Telegram 机器人`（或日志推送配置），填入自建 Bot Token 并按提示完成个人/群组 ChatID 绑定。
3. 所有通知与控制指令均直连 `api.telegram.org`，不经任何第三方中转服务。

### 自主编译内核与更新资源

在本仓库 GitHub **Actions** 页面手动触发以下工作流即可全部使用自有构建产物：

- `core_easy_update`：输入 `meta`、`singbox` 或 `singboxr`，从官方源码交叉编译全架构二进制并推送至 `update` 分支。
- `bin_update`：自动更新最新 Zashboard / Metacubexd 等 Web 面板、GeoIP / GeoSite、全套 `.mrs` / `.srs` 规则集（发布至 `update` 分支 `bin/ruleset/{mrs,srs}/`）、CA 根证书，并同步 `dev` 分支的 `ShellCrash.tar.gz`。

## 运行依赖

| 组件 | 必要性 | 说明 |
| :--- | :--- | :--- |
| `curl` 或 `wget` | 必须 | 用于安装、本地拉取订阅、更新内核与规则库 |
| `iptables` 或 `nftables` | 重要 | 透明代理必需；缺少时自动降级为纯净/本机模式 |
| `ca-certificates` | 推荐 | 启用严格 TLS 证书校验所需 |
| `crontab` | 可选 | 定时自动更新订阅与内核 |

## 开发、打包与离线回归测试

完整安全审计与架构加固明细请参阅 [SECURITY_HARDENING.md](SECURITY_HARDENING.md)。修改 `scripts/`、`public/` 或 `rules/` 源码后，请同步干净重建预打包文件并运行全部 16 套离线回归测试：

```sh
sh sync_pkg.sh
for t in tests/test_*.sh tests/clash_geodata.sh; do sh "$t" || exit 1; done
```

## 致谢与许可协议

本项目在原作者 **Juewuy** 开源的 ShellCrash 基础上独立演进，完成了全面安全审计、零信任架构重构与全链路自主分发改造；保留全部原作者版权署名，移除了对原托管下载源、镜像与第三方中转服务的依赖。

本项目采用 [GNU 通用公共许可证第 3.0 版（GPL-3.0）](LICENSE.txt) 授权。
