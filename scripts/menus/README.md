# scripts/menus/ — 交互菜单与远程管理脚本

本目录存放 ShellCrash 各级交互菜单、定时任务调度与自建 Telegram Bot 脚本。

## 开发与安全规范

- 文案统一通过 `scripts/lang/chs/*.lang` 与 `scripts/lang/en/*.lang` 维护，新增或修改键名时需保持中英文键同步。
- 用户输入的 URL、密钥、认证凭据、设备名等配置值写入文件前必须经过校验，并使用 `setconfig_quote` 写入，防止配置文件被 `source` 时触发命令注入。
- 动态文本过滤与字段提取优先使用 `awk -v` / `ENVIRON`，禁止将未校验的用户输入拼接到 `eval`、`sed "/$var/d"` 或 `awk '{print $'"$var"'}'` 中。
- `task_cmd.sh` 仅允许白名单内置任务与三位数字任务 ID，禁止通配符直接执行任意参数。
- Telegram Bot（`bot_tg.sh`）仅直连官方 `api.telegram.org`，必须严格校验数字型 `TG_CHATID`、使用 `limit=1` 拉取并防正文伪造 `chat.id` 及压缩包 Tar-Slip。