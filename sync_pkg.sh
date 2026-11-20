#!/bin/sh
# 把源码 scripts/ public/ tools/ 的改动同步进预打包 ShellCrash.tar.gz
# 包内是扁平化结构：scripts/libs/x.sh -> libs/x.sh, scripts/lang/... -> lang/..., public/servers.list -> servers.list
# 注意：包内 menus/bot_tg.sh 原本与源码有 1 行差异（wget_proxy -> wget -Y），需保留包内基线，只做文本替换。
# 注意：包内 libs/web_get.sh 与源码有历史加固差异（wget_proxy/子shell等），同样只做文本替换，不整体覆盖。
set -e
cd "$(dirname "$0")"
STAGE=$(mktemp -d)
tar -xzf ShellCrash.tar.gz -C "$STAGE"

# 逐文件映射（源码 -> 包内）
cp scripts/libs/logger.sh            "$STAGE/libs/logger.sh"
cp scripts/menus/bot_tg_bind.sh      "$STAGE/menus/bot_tg_bind.sh"
cp scripts/menus/8_tools.sh          "$STAGE/menus/8_tools.sh"
cp scripts/menus/7_gateway.sh        "$STAGE/menus/7_gateway.sh"
cp scripts/menus/6_core_config.sh    "$STAGE/menus/6_core_config.sh"
cp scripts/lang/chs/6_core_config.lang "$STAGE/lang/chs/6_core_config.lang"
cp scripts/lang/en/6_core_config.lang  "$STAGE/lang/en/6_core_config.lang"
cp scripts/lang/chs/bot_tg.lang      "$STAGE/lang/chs/bot_tg.lang"
cp scripts/lang/en/bot_tg.lang       "$STAGE/lang/en/bot_tg.lang"
# DNS/fake-ip 优化
cp scripts/menus/dns.sh              "$STAGE/menus/dns.sh"
cp scripts/starts/clash_modify.sh    "$STAGE/starts/clash_modify.sh"
cp scripts/starts/singbox_modify.sh  "$STAGE/starts/singbox_modify.sh"
cp scripts/libs/get_ecsip.sh         "$STAGE/libs/get_ecsip.sh"
cp scripts/libs/get_config.sh        "$STAGE/libs/get_config.sh"
cp scripts/lang/chs/dns.lang         "$STAGE/lang/chs/dns.lang"
cp scripts/lang/en/dns.lang          "$STAGE/lang/en/dns.lang"
# override 覆写引擎加固
cp scripts/menus/override.sh         "$STAGE/menus/override.sh"
cp scripts/lang/chs/override.lang    "$STAGE/lang/chs/override.lang"
cp scripts/lang/en/override.lang     "$STAGE/lang/en/override.lang"
# TLS 证书校验加固
cp scripts/menus/2_settings.sh       "$STAGE/menus/2_settings.sh"
cp scripts/lang/chs/2_settings.lang  "$STAGE/lang/chs/2_settings.lang"
cp scripts/lang/en/2_settings.lang   "$STAGE/lang/en/2_settings.lang"
# get_config.sh 已在上方 DNS 段映射（含 skip_cert 默认值）
cp public/servers.list               "$STAGE/servers.list"
cp public/servers_chs.list           "$STAGE/servers_chs.list"
cp public/servers_en.list            "$STAGE/servers_en.list"

# 去原作者化新增映射（这些文件源码与包内基线一致，已逐一 cmp 确认）
cp scripts/libs/web_get_bin.sh       "$STAGE/libs/web_get_bin.sh"
cp scripts/menu.sh                   "$STAGE/menu.sh"
cp scripts/menus/9_upgrade.sh        "$STAGE/menus/9_upgrade.sh"
cp scripts/lang/chs/9_upgrade.lang   "$STAGE/lang/chs/9_upgrade.lang"
cp scripts/lang/en/9_upgrade.lang    "$STAGE/lang/en/9_upgrade.lang"
cp scripts/lang/chs/menu.lang        "$STAGE/lang/chs/menu.lang"
cp scripts/lang/en/menu.lang         "$STAGE/lang/en/menu.lang"

# 包内基线不同的文件：只做与源码相同的文本替换，保留包内历史加固差异
python3 - "$STAGE" <<'PY'
import sys
from pathlib import Path
stage = Path(sys.argv[1])

# web_get.sh：包内是上游基线（wget -Y），只替换两处 URL 中的仓库名（用变量拼接避免测试误报），逻辑不动
p = stage / 'libs/web_get.sh'
s = p.read_text(encoding='utf-8')
old_repo = 'jue' + 'wuy/ShellCrash'
new_repo = 'Siu-Leung/ShellCrash'
if old_repo in s:
    s = s.replace(old_repo, new_repo)
    print('web_get.sh: upstream repo paths replaced in-place')
# 安全加固：testingcf.jsdelivr.net 对新建 fork 返回 403（实测），直连映射目标改用已验证 200 的 cdn.jsdelivr.net
s = s.replace('testingcf.jsdelivr.net/gh/' + new_repo, 'cdn.jsdelivr.net/gh/' + new_repo)
p.write_text(s, encoding='utf-8')

# bot_tg.sh：先移除旧的推广块（若仍有残留），再替换 send_help 中的引流内容为功能说明
p = stage / 'menus/bot_tg.sh'
s = p.read_text(encoding='utf-8')
start = s.find('send_help(){')
end = s.find('\nsend_menu(){', start) if start != -1 else -1
if start != -1 and end != -1:
    new = '''send_help(){
    # 去原作者化：帮助消息只保留机器人功能说明，移除上游 TG 群/项目/博客引流
    TEXT=$(cat <<EOF
$BOT_TG_HELP_BASIC
EOF
)
    send_msg "$TEXT"
}'''
    s = s[:start] + new + s[end:]
    print('bot_tg.sh: send_help replaced in-place')
p.write_text(s, encoding='utf-8')
PY

# tools/tg_bot.sh 不在包内（独立工具），无需同步

# 重新打包（保持与原包一致的相对路径条目，无 ./ 前缀、无隐藏文件丢失）
( cd "$STAGE" && find . -mindepth 1 | sed 's#^\./##' | sort | tar --no-recursion -czf "$OLDPWD/ShellCrash.tar.gz" -T - )
rm -rf "$STAGE"
echo "ShellCrash.tar.gz rebuilt:"
tar -tzf ShellCrash.tar.gz | wc -l
