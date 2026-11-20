#!/bin/sh
# 安全加固版离线回归：只做静态断言，不联网、不改动真实环境
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }
assert_no(){ # $1=file $2=pattern $3=desc
    if rg -q "$2" "$1" 2>/dev/null; then bad "$3 — 仍含 [$2]"; else ok "$3"; fi
}
assert_yes(){
    if rg -q "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 — 缺少 [$2]"; fi
}

echo '== 1. 源码树：无第三方中转/推广/转换站硬编码 =='
for f in scripts/libs/logger.sh scripts/menus/bot_tg_bind.sh scripts/menus/bot_tg.sh \
         scripts/menus/8_tools.sh scripts/menus/7_gateway.sh scripts/menus/6_core_config.sh \
         README.md README_CN.md; do
    assert_no "$ROOT/$f" 'tgbot\.jwsc\.eu\.org|dler\.pro/auth/register|pub\.bigmeok\.me|https://sub\.jwsc\.eu\.org|https://api\.v1\.mk|https://url\.v1\.mk' "$(basename "$f") 无第三方外发 URL"
done
# servers 列表：只校验生效行（非 # 注释）
for f in servers.list servers_chs.list servers_en.list; do
    if rg -q '^[^#[:space:]].*(jwsc\.eu\.org|v1\.mk)' "$ROOT/public/$f" 2>/dev/null; then
        bad "$f 仍有生效的第三方源"
    else ok "$f 无生效的第三方源"; fi
done

echo '== 2. 加固标记存在 =='
assert_yes "$ROOT/scripts/libs/logger.sh" 'api\.telegram\.org/bot\$\{push_TG\}/sendMessage' 'logger 保留官方 TG API'
assert_yes "$ROOT/scripts/menus/6_core_config.sh" 'CORECFG_SUBCONV_DISABLED' '在线转换入口已禁用并提示'

echo '== 3. shell 语法校验（busybox sh -n）=='
for f in scripts/libs/logger.sh scripts/menus/bot_tg_bind.sh scripts/menus/8_tools.sh \
         scripts/menus/7_gateway.sh scripts/menus/6_core_config.sh; do
    if sh -n "$ROOT/$f" 2>/dev/null; then ok "sh -n $(basename "$f")"; else bad "sh -n $(basename "$f")"; fi
done

echo '== 4. 预打包 tar.gz 与源码同步 =='
TMP=$(mktemp -d); tar -xzf "$ROOT/ShellCrash.tar.gz" -C "$TMP"
assert_no "$TMP/libs/logger.sh" 'tgbot\.jwsc\.eu\.org' '包内 logger 无 publictoken 中转'
assert_no "$TMP/menus/bot_tg.sh" 'dler\.pro|bigmeok' '包内 bot_tg 无推广链接'
assert_no "$TMP/menus/bot_tg_bind.sh" 'tgbot\.jwsc\.eu\.org' '包内 bot_tg_bind 无公共机器人中转'
assert_yes "$TMP/menus/6_core_config.sh" 'CORECFG_SUBCONV_DISABLED' '包内在线转换已禁用'
for f in libs/logger.sh menus/bot_tg_bind.sh menus/8_tools.sh menus/7_gateway.sh menus/6_core_config.sh; do
    if sh -n "$TMP/$f" 2>/dev/null; then ok "包内 sh -n $f"; else bad "包内 sh -n $f"; fi
done
rm -rf "$TMP"

echo '== 5. servers 列表第三方源已注释（不生效）=='
for f in servers.list servers_chs.list servers_en.list; do
    TMP2=$(mktemp -d); tar -xzf "$ROOT/ShellCrash.tar.gz" -C "$TMP2" "$f"
    if rg -q '^([0-9]+).*(jwsc|v1\.mk)' "$TMP2/$f" 2>/dev/null; then bad "包内 $f 仍有生效的第三方源"; else ok "包内 $f 第三方源已全部注释"; fi
    rm -rf "$TMP2"
done

echo ''
if [ "$FAIL" -eq 0 ]; then echo '\033[32m全部通过\033[0m'; else echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; fi
