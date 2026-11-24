# ShellCrash（自建安全加固版 Docker 镜像）

用于在容器环境中独立运行 **ShellCrash（零信任安全加固版）**，支持 **HTTP / SOCKS 代理** 与 **旁路由透明代理** 两种部署模式。

本镜像完全基于本仓库（`Siu-Leung/ShellCrash` `dev` 分支）根目录的 `Dockerfile` 自主构建（保留原作者 Juewuy 的 GPL-3.0 版权署名），不依赖任何第三方预编译 Docker 镜像。

------

## Build（本地构建镜像）

克隆本仓库 `dev` 分支并在仓库根目录执行：

```shell
git clone -b dev https://github.com/Siu-Leung/ShellCrash.git
cd ShellCrash
docker build -t shellcrash:local .
```

------

## Quick Start（最小化运行）

仅启用 HTTP(S) / SOCKS5 代理与 Web 面板功能，默认仅绑定宿主机回环地址 `127.0.0.1`（Mix 代理端口 `7890`，面板端口 `9999`），避免未设密码暴露到公网：

```shell
docker run -d \
  --name shellcrash \
  -p 127.0.0.1:7890:7890 \
  -p 127.0.0.1:9999:9999 \
  shellcrash:local
```

------

## Container Management（容器管理）

首次部署完成后，请进入容器完成初始化配置（导入订阅、启用本地转换、设置面板密码及启动内核服务），后续也可通过同一命令进入管理界面：

```shell
docker exec -it shellcrash sh -l
```

------

## Advanced Usage（旁路由 / 透明代理）

适用于旁路由、软路由或需要透明代理的部署场景，需提前创建 `macvlan` 网络（不推荐使用容器的 `host` 模式）。

### 1. 创建 macvlan 网络

请根据实际局域网网段与物理网卡名称调整参数（若已创建可跳过）：

```shell
docker network create \
  --driver macvlan \
  --subnet 192.168.31.0/24 \
  --gateway 192.168.31.1 \
  -o parent=eth0 \
  macvlan_lan
```

### 2. 启动容器（旁路由模式）

```shell
docker run -d \
  --name shellcrash \
  --network macvlan_lan \
  --ip 192.168.31.222 \
  --cap-add NET_ADMIN \
  --cap-add NET_RAW \
  --cap-add SYS_ADMIN \
  --sysctl net.ipv4.ip_forward=1 \
  --device /dev/net/tun:/dev/net/tun \
  --restart unless-stopped \
  shellcrash:local
```

### 3. 配置局域网设备

将需要代理设备的 IPv4 网关与 DNS 指向容器 IP（例如 `192.168.31.222`）。

> 注意：旁路由模式若未启用 IPv6 代理，请关闭局域网 IPv6 分配或主路由 IPv6 转发，以免流量经 IPv6 绕过旁路由。

------

## Persistent Configuration（持久化配置，推荐）

使用 Docker 命名卷持久化 ShellCrash 配置与规则目录（可加到上方 `docker run` 参数中）：

```shell
  -v shellcrash_configs:/etc/ShellCrash/configs \
  -v shellcrash_yamls:/etc/ShellCrash/yamls \
  -v shellcrash_jsons:/etc/ShellCrash/jsons \
```

------

## Compose Deployment（Docker Compose 本地构建部署）

由于 `docker/compose.yml` 采用 `build: ..` 从本仓库根目录自主构建镜像，请先克隆仓库再启动服务：

### 1. 克隆本仓库 `dev` 分支

```shell
git clone -b dev https://github.com/Siu-Leung/ShellCrash.git
cd ShellCrash
```

### 2. 按需修改 `docker/compose.yml`

根据你的实际网卡名、网段与固定 IP 编辑 `docker/compose.yml`：

```shell
vi docker/compose.yml
```

### 3. 构建并后台运行

```shell
docker compose -f docker/compose.yml up -d --build
```

------

## Delete（移除容器与数据卷）

### Docker 移除容器与卷

```shell
docker rm -f shellcrash
docker volume rm shellcrash_configs shellcrash_yamls shellcrash_jsons
```

### Compose 移除容器与卷

```shell
docker compose -f docker/compose.yml down -v
```

## Notes

- 容器内公网防火墙无法替代宿主机防火墙；若将 `7890` / `9999` 映射到非 `127.0.0.1` 地址，请务必在菜单中设置混合端口认证与面板密钥，并做好宿主机防火墙规则。
- 旁路由模式需要宿主机内核支持 `/dev/net/tun`。
- `macvlan` 模式下宿主机默认无法直接访问容器 IP。
- 容器内脚本更新与资源下载均默认走本仓库（`dev` / `update`）并强制严格 TLS 证书校验。
