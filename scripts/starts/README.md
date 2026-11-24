# scripts/starts/ — 启动生命周期、配置合成与防火墙脚本

本目录存放内核启动前后钩子、Clash / Sing-Box 配置修饰、GeoData 检查以及 `iptables` / `nftables` 防火墙规则脚本。

## 开发与安全规范

- 本目录脚本面向非交互后台执行，日志文案尽量通过对应 `lang/` 资源或 `logger` 输出，不依赖终端交互。
- **纯净模式收敛**：当 `firewall_area=4` 且 `public_support != ON` 时，Clash DNS / 控制面板及 Sing-Box 全部入站必须仅监听 `127.0.0.1`。
- **公网防火墙防护**：`fw_iptables.sh` 与 `fw_nftables.sh` 的公网拦截集需同步覆盖混合代理、Web 面板、DNS 及透明代理端口，并在 `fw_stop.sh` 中对等清理。
- **TLS 默认校验**：`clash_modify.sh` 与 `singbox_modify.sh` 对 `skip-cert-verify` / `insecure` 采用 fail-closed 策略，仅当显式 `skip_cert=ON` 时关闭校验。
- **配置转义**：向 YAML/JSON 写入用户认证、密钥及自定义规则时必须做好反斜杠、引号转义与字段类型校验。