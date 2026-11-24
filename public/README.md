## ShellCrash 公共配置列表目录

本目录维护 ShellCrash（`Siu-Leung/ShellCrash`）使用的内置公共列表文件（打包时自动同步至 `ShellCrash.tar.gz`，不含本 `README.md`）：

- `servers.list` / `servers_chs.list` / `servers_en.list`：本仓库脚本更新源（`dev`）与二进制资源源（`update`）列表；原第三方在线订阅转换服务器条目（`512-519`）已全部注释禁用，订阅转换统一走本地引擎。
- `fake_ip_filter.list`：Fake-IP 过滤域名列表。
- `dns_direct_domains.list`：默认直连 DNS 域名列表（避免国内域名经代理 DNS 解析）。
- `task_chs.list` / `task_en.list`：内置定时任务定义列表（中 / 英文）。

修改约定：

- 严格遵循各列表字段格式，使用 `LF` 换行符及 `UTF-8` 编码。
- 请保留文件末尾空行；禁止添加未经审计的第三方中转域名或订阅转换服务。
- 修改本目录文件后，请执行 `sh sync_pkg.sh` 重建 `ShellCrash.tar.gz` 并运行全部离线回归测试。
