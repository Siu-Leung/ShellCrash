#!/bin/sh
# 兼容未安装 ripgrep 的纯 Linux 环境：无 rg 时自动回退到 POSIX grep
if ! command -v rg >/dev/null 2>&1; then
    rg() {
        _q=""; _F=""; _c=""; _n=""; _i=""; _pat=""
        while [ $# -gt 0 ]; do
            case "$1" in
                -q) _q="-q"; shift ;;
                -F) _F="-F"; shift ;;
                -c) _c="-c"; shift ;;
                -n) _n="-n"; shift ;;
                -i) _i="-i"; shift ;;
                -g) shift 2 ;;
                --glob=*) shift ;;
                -e) shift; _pat="$1"; shift ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        if [ -z "$_pat" ] && [ $# -gt 0 ]; then _pat="$1"; shift; fi
        _mode="-E"; [ -n "$_F" ] && _mode="-F"
        _rec=""
        for _p in "$@"; do [ -d "$_p" ] && _rec="-r"; done
        grep $_rec $_mode $_q $_c $_n $_i -- "$_pat" "$@"
    }
fi
# eval 注入面消除离线回归：验证 get_version_var 白名单函数 + 三处 eval 已替换
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo '== 1. get_version_var 白名单函数行为 =='
TMPD=$(mktemp -d)
awk '/^get_version_var\(\)/{p=1} p{print} p&&/^}/{exit}' "$ROOT/scripts/libs/get_config.sh" >"$TMPD/fn.sh"
. "$TMPD/fn.sh"
meta_v='1.9.6alpha1'; Country_v='20240101'; cn_ip_v='v2'; singbox_v='1.14.4'
[ "$(get_version_var meta_v)" = '1.9.6alpha1' ] && ok "内核版本 meta_v 读取正确" || bad "meta_v 读取错误"
[ "$(get_version_var Country_v)" = '20240101' ] && ok "数据库版本 Country_v 读取正确" || bad "Country_v 读取错误"
[ "$(get_version_var cn_ip_v)" = 'v2' ] && ok "geo_v(cn_ip_v) 读取正确" || bad "cn_ip_v 读取错误"
[ "$(get_version_var singbox_v)" = '1.14.4' ] && ok "singbox_v 读取正确" || bad "singbox_v 读取错误"

echo '== 2. 注入防护 =='
[ -z "$(get_version_var 'meta_v; touch /tmp/__pwn_eval__')" ] && ok "命令注入串返回空" || bad "注入串未拦截"
[ ! -e /tmp/__pwn_eval__ ] && ok "注入未产生副作用" || { bad "注入产生了文件"; rm -f /tmp/__pwn_eval__; }
[ -z "$(get_version_var '$(touch /tmp/__pwn_eval2__)')" ] && ok "子命令替换串返回空" || bad "子命令替换未拦截"
[ ! -e /tmp/__pwn_eval2__ ] && ok "子命令替换未执行" || { bad "子命令替换执行了"; rm -f /tmp/__pwn_eval2__; }
# 函数体内不应含 eval
if awk '/^get_version_var\(\)/{p=1} p{print} p&&/^}/{exit}' "$ROOT/scripts/libs/get_config.sh" | rg -q '^[^#]*\beval\b'; then
    bad "get_version_var 内部仍含 eval"
else ok "get_version_var 完全无 eval"; fi
rm -rf "$TMPD"

echo '== 3. 三处间接变量 eval 已替换 =='
rg -q 'core_v_new=\$\(get_version_var "\$\{crashcore\}_v"\)' "$ROOT/scripts/menus/9_upgrade.sh" && ok "9_upgrade 内核版本已改白名单" || bad "9_upgrade 未改"
rg -q 'crash_v_new=\$\(get_version_var "\$\{crashcore\}_v"\)' "$ROOT/scripts/menus/task_cmd.sh" && ok "task_cmd 内核版本已改白名单" || bad "task_cmd 内核版本未改"
rg -q 'geo_v_now=\$\(get_version_var "\$geo_v"\)' "$ROOT/scripts/menus/task_cmd.sh" && ok "task_cmd 数据库版本已改白名单" || bad "task_cmd 数据库版本未改"
# 确认间接变量 eval 不再存在（eval $task_command 是用户自定义任务，允许保留）
_left=$(rg --no-heading '^\s*[^#]*(eval echo .*\$|eval \$\{|eval "printf)' "$ROOT/scripts/menus/9_upgrade.sh" "$ROOT/scripts/menus/task_cmd.sh" || true)
[ -z "$_left" ] && ok "无间接变量 eval 残留" || bad "仍有间接变量 eval: $_left"

echo '== 4. 白名单覆盖实际 geo_v 值 =='
for v in Country_v cn_mini_v cn_ip_v cn_ipv6_v GeoSite_v geosite_v geoip_v geoip_cn_v geosite_cn_v; do
    awk '/^get_version_var\(\)/{p=1} p{print} p&&/^}/{exit}' "$ROOT/scripts/libs/get_config.sh" | rg -q "^\s+$v\)" && ok "白名单含 $v" || bad "白名单缺 $v"
done

echo '== 5. shell 语法 =='
for f in scripts/libs/get_config.sh scripts/menus/9_upgrade.sh scripts/menus/task_cmd.sh; do
    sh -n "$ROOT/$f" && ok "sh -n $(basename "$f")" || bad "sh -n $(basename "$f")"
done

echo ''
[ "$FAIL" -eq 0 ] && echo '\033[32m全部通过\033[0m' || { echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; }
