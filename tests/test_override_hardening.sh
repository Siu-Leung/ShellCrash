#!/bin/sh
# override 覆写引擎加固离线回归：验证输入校验函数 + 静态断言，不联网、不改真实环境
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo '== 1. ovr_input_safe 输入校验 =='
# 只抽取函数定义单独 source，提供提示变量桩与 msg_alert 桩
TMPD=$(mktemp -d)
awk '/^ovr_input_safe\(\)/{p=1} p{print} p&&/^}/{exit}' "$ROOT/scripts/menus/override.sh" >"$TMPD/fn.sh"
printf 'OVR_INPUT_INVALID="invalid"\nOVR_INPUT_EMPTY="empty"\nmsg_alert(){ :; }\n' >"$TMPD/pre.sh"
. "$TMPD/pre.sh"
. "$TMPD/fn.sh"

ovr_input_safe 'DOMAIN-SUFFIX,example.com,DIRECT' >/dev/null 2>&1 && ok "合法规则接受" || bad "合法规则被误拒"
ovr_input_safe 'name: test, server: 1.1.1.1, port: 12345' >/dev/null 2>&1 && ok "合法节点接受" || bad "合法节点被误拒"
ovr_input_safe 'bad"quote' >/dev/null 2>&1 && bad "双引号未拦截" || ok "双引号拦截"
ovr_input_safe "bad'quote" >/dev/null 2>&1 && bad "单引号未拦截" || ok "单引号拦截"
ovr_input_safe 'bad$var' >/dev/null 2>&1 && bad '$未拦截' || ok '$拦截'
ovr_input_safe 'bad`tick' >/dev/null 2>&1 && bad "反引号未拦截" || ok "反引号拦截"
ovr_input_safe 'bad\slash' >/dev/null 2>&1 && bad "反斜杠未拦截" || ok "反斜杠拦截"
ovr_input_safe '' >/dev/null 2>&1 && bad "空值未拦截" || ok "空值拦截"
ovr_input_safe "$(printf 'a\tb')" >/dev/null 2>&1 && bad "控制字符未拦截" || ok "控制字符拦截"
rm -rf "$TMPD"

echo '== 2. 三处输入点已接入校验 =='
rg -q 'ovr_input_safe "\$rule_state_set"' "$ROOT/scripts/menus/override.sh" && ok "规则内容校验已接入" || bad "规则内容校验缺失"
rg -q 'ovr_input_safe "\$new_group_name"' "$ROOT/scripts/menus/override.sh" && ok "策略组名校验已接入" || bad "策略组名校验缺失"
rg -q 'ovr_input_safe "\$proxy_state_set"' "$ROOT/scripts/menus/override.sh" && ok "节点内容校验已接入" || bad "节点内容校验缺失"

echo '== 3. 修正 D: \s 已全部替换为 POSIX 字符类 =='
# 只查真正的 sed -i 命令行（排除注释行）里是否还有 \s
_sed_bad=$(rg --no-heading '^\s*[^#]*sed -i' "$ROOT/scripts/menus/override.sh" | rg '\\s' || true)
if [ -n "$_sed_bad" ]; then bad "sed -i 仍存在 \\s 用法: $_sed_bad"; else ok "sed -i 中无 \\s（busybox 兼容）"; fi
_n=$(rg -c '\[\[:space:\]\]' "$ROOT/scripts/menus/override.sh")
[ "$_n" -ge 3 ] && ok "[[:space:]] 使用 $_n 处" || bad "POSIX 字符类不足"

echo '== 4. 修正 B: 累加器已重置 =='
_n=$(rg -c 'unset rule_group_add  # 安全加固' "$ROOT/scripts/menus/override.sh")
[ "$_n" -ge 2 ] && ok "两处累加器均有清空($_n)" || bad "累加器清空不足($_n)"

echo '== 5. 修正 A: 示例文本一致 =='
rg -q 'name: test, server: 192.168.1.1' "$ROOT/scripts/menus/override.sh" && ok "示例已去括号/引号" || bad "示例仍带括号/引号"
# 语言标签存在
for L in chs en; do
  rg -q 'OVR_INPUT_INVALID' "$ROOT/scripts/lang/$L/override.lang" && ok "$L 提示标签存在" || bad "$L 提示标签缺失"
done

echo '== 6. shell 语法 =='
sh -n "$ROOT/scripts/menus/override.sh" && ok "sh -n override.sh" || bad "sh -n"

echo ''
[ "$FAIL" -eq 0 ] && echo '\033[32m全部通过\033[0m' || { echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; }
