#!/bin/sh
# 把源码 scripts/ public/ tools/ 的改动同步进预打包 ShellCrash.tar.gz
# 包内是扁平化结构：scripts/libs/x.sh -> libs/x.sh, scripts/lang/... -> lang/..., public/servers.list -> servers.list
# 注意：包内 menus/bot_tg.sh 原本与源码有 1 行差异（wget_proxy -> wget -Y），需保留包内基线，只做我们的加固替换。
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
cp public/servers.list               "$STAGE/servers.list"
cp public/servers_chs.list           "$STAGE/servers_chs.list"
cp public/servers_en.list            "$STAGE/servers_en.list"

# bot_tg.sh 包内基线不同：先在包内副本上直接做与源码相同的加固文本替换（不整体覆盖）
python3 - "$STAGE/menus/bot_tg.sh" <<'PY'
import sys
p=sys.argv[1]
s=open(p,encoding='utf-8').read()
old='''$BOT_TG_HELP_COFFEE
https://juewuy.github.io/yOF4Yf06Q/
$BOT_TG_HELP_AIRPORT
https://dler.pro/auth/register?affid=89698
https://pub.bigmeok.me?code=2PuWY9I7
EOF'''
new='EOF'
if old in s:
    open(p,'w',encoding='utf-8').write(s.replace(old,new))
    print('bot_tg.sh: promo block removed')
else:
    print('bot_tg.sh: promo block already absent (idempotent)')
PY

# tools/tg_bot.sh 不在包内（独立工具），无需同步

# 重新打包（保持与原包一致的相对路径条目，无 ./ 前缀、无隐藏文件丢失）
( cd "$STAGE" && find . -mindepth 1 | sed 's#^\./##' | sort | tar --no-recursion -czf "$OLDPWD/ShellCrash.tar.gz" -T - )
rm -rf "$STAGE"
echo "ShellCrash.tar.gz rebuilt:"
tar -tzf ShellCrash.tar.gz | wc -l
