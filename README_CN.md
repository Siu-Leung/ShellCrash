<h1 align="center">ShellCrash（零信任安全加固版）</h1>

<p align="center">
  <a target="_blank" href="https://github.com/MetaCubeX/mihomo/releases">
    <img src="https://img.shields.io/github/release/MetaCubeX/mihomo.svg?style=flat-square&label=Core">
  </a>
  <a target="_blank" href="https://github.com/Siu-Leung/ShellCrash/releases">
    <img src="https://img.shields.io/github/release/Siu-Leung/ShellCrash.svg?style=flat-square&label=ShellCrash&colorB=green">
  </a>
</p>

<p align="center">
  <strong>面向 Linux 与路由器的专业、干净、自主可控的 Mihomo / Sing-Box 代理管理工具</strong>
</p>

<p align="center">
  简体中文 | <a href="README.md">English</a> | <a href="SECURITY_HARDENING.md">安全审计与加固清单</a>
</p>

## 核心特性

- **零信任与去外链**：彻底移除第三方中转服务器、在线订阅转换站、公共推送机器人、外部在线面板与推广引流；所有脚本、规则、面板、数据库与内核均由本仓库自主维护与分发（默认锁定 `dev` 分支，`bin/` 走自主编译的 `update` 分支）。
- **零外泄本地订阅拉取与转换**：订阅链接只直连你自己的原始订阅源，在本机使用纯 POSIX `sh`/`awk`/`base64` 自动识别并解码 Base64、明文 URI 列表（`ss`/`vmess`/`vless`/`trojan`/`hy2`/`tuic`/`anytls` 等）、Clash YAML 与 Sing-Box JSON，本地正则过滤后套用本仓库规则模板生成纯本地 `type: file` / `type: local` 配置。
- **默认安全边界**：安装脚本、下载器、代理客户端与 Bot 默认强制开启 TLS 证书校验；纯净/本机模式（`firewall_area=4`）默认仅绑定 `127.0.0.1`，防止无密码端口暴露在公网；配置写入原子防注入，消除间接变量 `eval`。
- **多内核与全场景 Linux 支持**：支持 Mihomo（Meta）、Sing-Box、Sing-BoxR 内核切换；兼容 Debian/Ubuntu/CentOS/Alpine/Arch 等标准 Linux、OpenWrt、Padavan、华硕/梅林及 Docker 容器。
- **自主供应链构建**：内置 GitHub Actions 工作流（带 `update` 分支并发锁与 rebase 防冲突），可随时直接从 `MetaCubeX/mihomo`、`SagerNet/sing-box`、`reF1nd/sing-box` 官方源码重新交叉编译全架构内核与最新 GeoData/面板。

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

- **Docker**：使用本仓库 `docker/` 目录下的 `Dockerfile` 与 `compose.yml` 自行构建部署。
- **本地离线安装**：从本仓库 `dev` 或 `update` 分支下载 `ShellCrash.tar.gz`，上传至目标设备 `/tmp/` 目录后解压并运行 `init.sh` 完成初始化。

## 快速上手

安装完成后，在终端输入以下命令进入交互菜单：

```sh
crash        # 启动交互管理菜单
crash doctor # 一键环境与安全健康自检（只读）
crash -h     # 查看命令行帮助
```

### 零外泄订阅配置（推荐流程）

1. 进入 `6 配置文件管理 -> a) 添加提供者`，粘贴你的订阅链接（支持 Clash YAML、Base64 通用订阅、明文节点分享链接或本地文件）。
2. 返回 `6 配置文件管理`，选择 **`c) 本地拉取并转换配置文件（零外泄）`**。
3. 可按需设置排除/包含节点正则、切换本地/本仓库规则模板、指定拉取 UA，点击 `1)` 即可在本机完成拉取、解码、过滤与规则合成。
4. 如需自动定时更新，在 `5 定时任务` 中启用 `104 更新订阅并重启` 或 `105 热更新订阅`，后台同样 100% 走本机直拉转换。

### 自主重编内核与资源（供应链清零）

在本仓库 GitHub **Actions** 页面手动触发以下工作流即可全部替换为自己编译的二进制与最新规则库：

- `core_easy_update`：输入 `meta`、`singbox` 或 `singboxr`，从官方源码交叉编译并推送至 `update` 分支。
- `bin_update`：自动更新最新 Zashboard / Metacubexd 面板、GeoIP / GeoSite / `.mrs` / `.srs` 数据库、CA 根证书，并同步 `dev` 分支的 `ShellCrash.tar.gz`。

## 运行依赖

| 组件 | 必要性 | 说明 |
| :--- | :--- | :--- |
| `curl` 或 `wget` | 必须 | 用于安装、本地拉取订阅、更新内核与规则库 |
| `iptables` 或 `nftables` | 重要 | 透明代理必需；缺少时自动降级为纯净/本机模式 |
| `ca-certificates` | 推荐 | 启用严格 TLS 证书校验所需 |
| `crontab` | 可选 | 定时自动更新订阅与内核 |

## 开发、打包与回归测试

详细安全审计与加固记录请参阅 [SECURITY_HARDENING.md](SECURITY_HARDENING.md)。修改 `scripts/` 或 `public/` 源码后，务必同步重建预打包文件并运行全部离线回归测试：

```sh
sh sync_pkg.sh
for t in tests/test_*.sh; do sh "$t"; done
```

## 许可协议

本项目采用 [GNU 通用公共许可证第 3.0 版（GPL-3.0）](LICENSE.txt) 授权。
