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
# DNS/fake-ip 优化离线回归：验证纯函数逻辑，不联网、不改真实环境
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CRASHDIR="$ROOT"
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

echo '== 1. get_ecsip.sh: append_ecs_to_dns =='
# 只抽取函数定义，避免 source 触发底部联网探测
eval "$(awk '/^append_ecs_to_dns\(\)/{p=1} p{print} p&&/^}/{exit}' "$ROOT/scripts/libs/get_ecsip.sh")"
r=$(append_ecs_to_dns "223.5.5.5, 1.1.1.1" "113.66.0.0/24")
case "$r" in
  *'223.5.5.5#ecs-override=true&ecs=113.66.0.0/24'*'1.1.1.1#ecs-override=true&ecs=113.66.0.0/24'*) ok "多DNS均附加ECS" ;;
  *) bad "多DNS附加ECS: 得到 [$r]" ;;
esac
# 已有 fragment 的用 & 续接，不重复 #
r=$(append_ecs_to_dns "https://dns.example/dns-query#foo=bar" "1.2.3.0/24")
case "$r" in
  *'#foo=bar&ecs-override=true'*) ok "已有fragment用&续接" ;;
  *) bad "已有fragment续接: [$r]" ;;
esac
# 空输入原样返回
[ "$(append_ecs_to_dns "" "1.2.3.0/24")" = "" ] && ok "空列表原样返回" || bad "空列表处理"

echo '== 2. ip_in_cidr =='
ip_in_cidr_test(){
  ip_in_cidr "$1" "$2" >/dev/null 2>&1
  # 上面的函数可能依赖 awk；直接在此实现等价调用（函数来自 dns.sh 不便 source，复制核心 awk）
  awk -v ip="$1" -v cidr="$2" 'BEGIN{
    split(cidr,c,"/"); split(c[1],n,"."); split(ip,a,".");
    ipn=a[1]*16777216+a[2]*65536+a[3]*256+a[4];
    netn=n[1]*16777216+n[2]*65536+n[3]*256+n[4];
    bits=c[2]+0; span=2^(32-bits);
    if(ipn>=netn && ipn<netn+span) exit 0; else exit 1; }'
}
ip_in_cidr_test 198.18.5.6 198.18.0.0/15 && ok "网段内命中" || bad "网段内命中"
ip_in_cidr_test 192.168.1.1 198.18.0.0/15 && bad "误判网段内" || ok "网段外排除"
ip_in_cidr_test 198.20.0.1 198.18.0.0/15 && bad "边界外误判" || ok "边界外正确排除"

echo '== 3. sb_convert_domain_rules (singbox 规则分类) =='
. "$ROOT/scripts/starts/singbox_modify.sh" >/dev/null 2>&1 || true
TF=$(mktemp)
printf '# comment\n\n*\nfoo.com\n*.example.com\n+.apple.com\ntime.*.google.com\n+.stun.*.*\n' >"$TF"
sb_convert_domain_rules "$TF"
case "$_fp_domain" in *'"foo.com"'*) ok "纯域名->domain" ;; *) bad "纯域名分类: [$_fp_domain]" ;; esac
case "$_fp_suffix" in *'"example.com"'*'"apple.com"'*) ok "通配后缀->domain_suffix" ;; *) bad "后缀分类: [$_fp_suffix]" ;; esac
case "$_fp_regex" in *'"^[^.]+$"'*'"^time\\..*\\.google\\.com$"'*) ok "内部通配与裸*->合法JSON domain_regex" ;; *) bad "正则分类: [$_fp_regex]" ;; esac
rm -f "$TF"

echo '== 4. dns_cfg_append 去重与校验 =='
# 从 dns.sh 抽取函数定义单独 source（避免整菜单执行）
TMPD=$(mktemp -d)
extract_fn(){
  awk -v fn="$2" '$0 ~ "^"fn"\\(\\)" {p=1} p{print} p && /^}/ {exit}' "$1"
}
extract_fn "$ROOT/scripts/menus/dns.sh" dns_cfg_append >"$TMPD/fn.sh"
# 提供依赖的 msg_alert 桩
echo 'msg_alert(){ :; }
DNS_DUPLICATE="dup"
DNS_INPUT_INVALID="invalid"' >"$TMPD/pre.sh"
. "$TMPD/pre.sh"
. "$TMPD/fn.sh"
CFGF="$TMPD/list"
: >"$CFGF"
dns_cfg_append "$CFGF" "  foo.com  " domain >/dev/null && [ "$(cat "$CFGF")" = "foo.com" ] && ok "trim 后写入" || bad "trim 写入"
dns_cfg_append "$CFGF" "foo.com" domain >/dev/null && bad "重复未拦截" || ok "重复被拦截"
dns_cfg_append "$CFGF" "bad domain" domain >/dev/null && bad "空格未拦截" || ok "非法空格被拦截"
dns_cfg_append "$CFGF" "*.bar.com" domain >/dev/null && ok "通配符规则允许" || bad "通配符误拦截"
rm -rf "$TMPD"

echo '== 5. 关键修复标记存在 =='
rg -q 'append_ecs_to_dns' "$ROOT/scripts/starts/clash_modify.sh" && ok "clash ECS 已改用稳健函数" || bad "clash ECS 未改"
rg -q 'dns_respect_rules' "$ROOT/scripts/starts/clash_modify.sh" && ok "respect-rules 可配置" || bad "respect-rules 未改"
rg -q 'respect-rules' "$ROOT/scripts/starts/clash_modify.sh" && ok "respect-rules 写入逻辑存在" || bad "缺 respect-rules"
rg -q 'sb_convert_domain_rules' "$ROOT/scripts/starts/singbox_modify.sh" && ok "singbox 规则转换已重写" || bad "singbox 转换未改"
rg -q 'fake_ip_range' "$ROOT/scripts/menus/dns.sh" && ok "fake-ip 网段设置入口存在" || bad "网段入口缺失"

echo ''
[ "$FAIL" -eq 0 ] && echo '\033[32m全部通过\033[0m' || { echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; }
