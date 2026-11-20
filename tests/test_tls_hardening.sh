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
# TLS 证书校验加固离线回归：验证默认严格校验 + 安全警告，不联网、不改真实环境
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo '== 1. 默认值为严格校验(OFF) =='
rg -q '^\[ -z "\$skip_cert" \] && skip_cert=OFF' "$ROOT/scripts/libs/get_config.sh" && ok "get_config 默认 OFF" || bad "get_config 默认非 OFF"
rg -q '\[ -z "\$skip_cert" \] && skip_cert=OFF' "$ROOT/scripts/menus/2_settings.sh" && ok "2_settings 默认 OFF" || bad "2_settings 默认非 OFF"

echo '== 2. web_get 依据 skip_cert 决定证书参数（保持兼容）=='
rg -q 'skipceroff.*skip_cert.*OFF' "$ROOT/scripts/libs/web_get.sh" && ok "curl/wget 严格分支判定存在" || bad "证书判定缺失"
# 确认严格模式分支(certificate='')与跳过分支(certificate='-k'/'--no-check-certificate')成对存在
_n_strict=$(rg -c "certificate=''" "$ROOT/scripts/libs/web_get.sh")
_n_skip=$(rg -c "certificate='(-k|--no-check-certificate)'" "$ROOT/scripts/libs/web_get.sh")
[ "$_n_strict" -ge 2 ] && ok "严格分支存在($_n_strict 处)" || bad "严格分支缺失"
[ "$_n_skip" -ge 2 ] && ok "跳过分支仍受控($_n_skip 处)" || bad "跳过分支缺失"

echo '== 3. 开启跳过证书前的安全警告与二次确认 =='
rg -q 'SET_SKIP_CERT_WARN' "$ROOT/scripts/menus/2_settings.sh" && ok "菜单引用安全警告" || bad "菜单未引用警告"
rg -q 'read -r -p "\$COMMON_INPUT> " confirm' "$ROOT/scripts/menus/2_settings.sh" && ok "存在二次确认读取" || bad "无二次确认"
rg -q '\[ "\$confirm" != 1 \] && continue' "$ROOT/scripts/menus/2_settings.sh" && ok "未确认则跳过开启" || bad "未确认仍会开启"
for L in chs en; do
  rg -q 'SET_SKIP_CERT_WARN' "$ROOT/scripts/lang/$L/2_settings.lang" && ok "$L 警告标签存在" || bad "$L 警告标签缺失"
done

echo '== 4. 注释规范（改动点标注原因）=='
rg -q '安全加固.*TLS|中间人' "$ROOT/scripts/libs/get_config.sh" && ok "get_config 有加固说明" || bad "get_config 缺说明"

echo '== 5. shell 语法 =='
for f in scripts/libs/get_config.sh scripts/menus/2_settings.sh scripts/libs/web_get.sh; do
  sh -n "$ROOT/$f" && ok "sh -n $(basename "$f")" || bad "sh -n $(basename "$f")"
done

echo ''
[ "$FAIL" -eq 0 ] && echo '\033[32m全部通过\033[0m' || { echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; }
