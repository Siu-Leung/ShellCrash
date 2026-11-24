# scripts/libs/ — 内置基础工具库

本目录存放 ShellCrash 内置核心工具脚本（POSIX `sh` / BusyBox `ash` 兼容）。

## 开发规范

- 引用方式必须为：

```sh
. "$CRASHDIR"/libs/xxx.sh
```

- 退出函数必须使用 `return x`，严禁使用 `exit x` 中断调用方脚本。
- 工具库函数原则上不应直接向终端输出交互文案（除日志库 `logger.sh` 与诊断库 `doctor.sh` 外）。
- **配置防注入**：写入用户输入类配置必须使用 `set_config.sh` 提供的 `setconfig_quote`，普通受控键值使用 `setconfig`（内置键名标识符校验、`\r\n` 剥离与原子替换写入）。
- **TLS 校验（Fail-Closed）**：`web_get.sh`、`web_get_lite.sh`、`web_get_curlbar.sh`、`web_json.sh`、`local_sub_convert.sh` 均默认强制校验证书，仅当显式 `skip_cert=ON` 时跳过。
- **仓库分支分流**：`web_get_bin.sh` 自动将 `bin/*` 路由至 `Siu-Leung/ShellCrash@update`，将 `public/*` 与 `rules/*` 路由至 `Siu-Leung/ShellCrash@dev`（同时兼容首次安装 `url_id` 为空的场景）。
- **子 Shell 隔离与下载约定**：
  - `webget`、`web_get_lite` 与 `web_json_post` 在子 Shell 中执行，临时代理和内部变量不会污染调用方环境。
  - `webget` 成功返回 `0`，失败统一返回 `1`（不透传 wget 的 `4`/`8` 等退出码）；使用 `curl` 下载时，仅当退出码为 `0` 且 HTTP 状态码为 `200` 才算成功。失败时仅清理本次新建的普通文件，不会删除既有文件、符号链接或 `/dev/null`。

## 离线回归测试

在仓库根目录运行全套回归测试：

```sh
for t in tests/test_*.sh tests/clash_geodata.sh; do sh "$t" || exit 1; done
```