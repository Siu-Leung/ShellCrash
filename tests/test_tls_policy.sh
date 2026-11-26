#!/bin/sh
# 证书策略回归测试（1.9.7-hardened.7 / 独立复测报告 P1-a、P1-b、P2、P3 与 node_tls=skip 补写）
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CRASHDIR="$ROOT/scripts"
cd "$ROOT" || exit 1

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
mkdir -p "$SANDBOX/bin"
ORIG_PATH=$PATH

failures=0
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    failures=$((failures + 1))
}

ckcmd() { command -v "$1" >/dev/null 2>&1; }
pidof() { return 1; }
. "$CRASHDIR/libs/set_proxy.sh"
. "$CRASHDIR/libs/web_get.sh"
. "$CRASHDIR/libs/tls_policy.sh"

echo "== 1. wget_nocheck_supported：按实际能力判断，不只看帮助文案 =="
# kind：listed=帮助里列出（uclient-fetch）；hidden=帮助没列但可用（Alpine BusyBox 1.37）；
#       reject=不支持该选项
cat >"$SANDBOX/bin/wget" <<'EOF'
#!/bin/sh
case "$WG_KIND" in
listed)
    [ "$1" = --help ] && { echo "  --no-check-certificate  Don't validate the server's certificate"; exit 0; }
    ;;
hidden)
    [ "$1" = --help ] && { echo "Usage: wget [-cqS] [--spider] [-O FILE] [-U STR] URL..."; exit 1; }
    [ "$1" = --no-check-certificate ] && [ "$2" = --help ] && { echo "wget: unrecognized option: help" >&2; exit 1; }
    ;;
reject)
    [ "$1" = --help ] && { echo "Usage: wget [-q] [-O FILE] URL"; exit 1; }
    [ "$1" = --no-check-certificate ] && { echo "wget: unrecognized option: no-check-certificate" >&2; exit 1; }
    ;;
esac
exit 1
EOF
chmod +x "$SANDBOX/bin/wget"
PATH="$SANDBOX/bin:$ORIG_PATH"
export WG_KIND
for _k in listed:0 hidden:0 reject:1; do
    WG_KIND=${_k%%:*}
    wget_nocheck_supported
    _rc=$?
    [ "$_rc" = "${_k#*:}" ] && pass "wget($WG_KIND) 判定返回 $_rc" || fail "wget($WG_KIND) 判定返回 $_rc，期望 ${_k#*:}"
done
for _f in scripts/libs/web_get.sh scripts/libs/web_get_lite.sh scripts/libs/web_json.sh scripts/menus/bot_tg.sh; do
    if grep -q "wget --help.*grep -q 'no-check-certificate'" "$_f"; then
        fail "$_f 仍只靠帮助文案判断 --no-check-certificate"
    else
        pass "$_f 不再只靠帮助文案判断"
    fi
done
if grep -q 'no-check-certificate --help' tools/tg_bot.sh; then pass "tools/tg_bot.sh 内联能力探测"; else fail "tools/tg_bot.sh 缺少能力探测"; fi
PATH=$ORIG_PATH

echo "== 2. webget 证书错误分类（只把确认的证书失败写入标记）=="
# curl 分支：wget 没有 show-progress、curl 可用
cat >"$SANDBOX/bin/wget" <<'EOF'
#!/bin/sh
exit 1
EOF
cat >"$SANDBOX/bin/curl" <<'EOF'
#!/bin/sh
[ "$1" = --version ] && { echo "curl 7.88.1"; exit 0; }
echo "$*" >>"$SANDBOX/curl.log"
exit "$CURL_RC"
EOF
chmod +x "$SANDBOX/bin/wget" "$SANDBOX/bin/curl"
PATH="$SANDBOX/bin:$ORIG_PATH"
export SANDBOX CURL_RC
for _c in 60:tls 51:tls 7:none 22:none 28:none; do
    CURL_RC=${_c%%:*}
    rm -f "$SANDBOX/flag"
    WEBGET_TLS_ERRFILE="$SANDBOX/flag" webget "$SANDBOX/out" "https://example.invalid/sub" echooff rediron skipceroff >/dev/null 2>&1
    WEBGET_TLS_ERRFILE=''
    grep -q tls "$SANDBOX/flag" 2>/dev/null && _got=tls || _got=none
    [ "$_got" = "${_c#*:}" ] && pass "curl 退出码 $CURL_RC → $_got" || fail "curl 退出码 $CURL_RC → $_got，期望 ${_c#*:}"
done
rm -f "$SANDBOX/bin/curl"

# GNU wget 分支：退出码 5 = SSL 校验失败
cat >"$SANDBOX/bin/wget" <<'EOF'
#!/bin/sh
[ "$1" = --help ] && { echo "--show-progress"; exit 0; }
exit "$WGET_RC"
EOF
chmod +x "$SANDBOX/bin/wget"
export WGET_RC
for _c in 5:tls 4:none 8:none; do
    WGET_RC=${_c%%:*}
    rm -f "$SANDBOX/flag"
    WEBGET_TLS_ERRFILE="$SANDBOX/flag" webget "$SANDBOX/out" "https://example.invalid/sub" echooff rediron skipceroff >/dev/null 2>&1
    WEBGET_TLS_ERRFILE=''
    grep -q tls "$SANDBOX/flag" 2>/dev/null && _got=tls || _got=none
    [ "$_got" = "${_c#*:}" ] && pass "GNU wget 退出码 $WGET_RC → $_got" || fail "GNU wget 退出码 $WGET_RC → $_got，期望 ${_c#*:}"
done

# BusyBox / uclient 分支：证书失败退出码只有 1，要看报错文字；同时检查 UA 用 -U 传递
# curl 不可用（宿主机自带 curl 也要屏蔽），才会走到第三个分支
printf '#!/bin/sh\nexit 127\n' >"$SANDBOX/bin/curl"
chmod +x "$SANDBOX/bin/curl"
cat >"$SANDBOX/bin/wget" <<'EOF'
#!/bin/sh
if [ "$1" = --help ]; then echo "Usage: wget [-cqS] [-O FILE] [-U STR] [-Y on/off] URL"; exit 1; fi
if [ "$1" = --no-check-certificate ] && [ "$2" = --help ]; then echo "wget: unrecognized option: help" >&2; exit 1; fi
echo "$*" >>"$SANDBOX/bb.log"
case "$BB_ERR" in
cert) echo "ssl_client: certificate verify failed" >&2 ;;
x509) echo "Connection error: Invalid SSL certificate" >&2; exit 5 ;;
http) echo "wget: server returned error: HTTP/1.1 503 Service Unavailable" >&2 ;;
esac
exit 1
EOF
chmod +x "$SANDBOX/bin/wget"
export BB_ERR
for _c in cert:tls x509:tls http:none; do
    BB_ERR=${_c%%:*}
    rm -f "$SANDBOX/flag" "$SANDBOX/bb.log"
    WEBGET_TLS_ERRFILE="$SANDBOX/flag" webget "$SANDBOX/out" "https://example.invalid/sub" echooff rediron skipceroff "clash.meta" >/dev/null 2>&1
    WEBGET_TLS_ERRFILE=''
    grep -q tls "$SANDBOX/flag" 2>/dev/null && _got=tls || _got=none
    [ "$_got" = "${_c#*:}" ] && pass "BusyBox/uclient 报错($BB_ERR) → $_got" || fail "BusyBox/uclient 报错($BB_ERR) → $_got，期望 ${_c#*:}"
done
if grep -q -- '-U clash.meta' "$SANDBOX/bb.log" && [ "$(wc -l <"$SANDBOX/bb.log")" -eq 2 ]; then
    pass "BusyBox 分支通过 -U 传递 UA，并按代理 on/off 各试一次"
else
    fail "BusyBox 分支 UA/重试异常: $(cat "$SANDBOX/bb.log")"
fi
[ ! -e "$SANDBOX/flag.stderr" ] && pass "BusyBox 分支清理暂存的 stderr" || fail "BusyBox 分支残留 stderr 暂存文件"
rm -f "$SANDBOX/bb.log"
BB_ERR=cert
webget "$SANDBOX/out" "https://example.invalid/sub" echooff rediron skipcerforce >/dev/null 2>&1
grep -q -- '--no-check-certificate' "$SANDBOX/bb.log" && pass "BusyBox 帮助未列出时 skipcerforce 仍带 --no-check-certificate" || fail "BusyBox skipcerforce 未带 --no-check-certificate"
rm -f "$SANDBOX/bb.log"
skip_cert=invalid
webget "$SANDBOX/out" "https://example.invalid/sub" echooff rediron >/dev/null 2>&1
grep -q -- '--no-check-certificate' "$SANDBOX/bb.log" && fail "skip_cert=invalid 时项目下载跳过了证书" || pass "skip_cert=invalid 时项目下载仍严格校验"
unset skip_cert
PATH=$ORIG_PATH

echo "== 3. sub_webget：只在确认 HTTPS 证书失败时降级 =="
WG_LOG="$SANDBOX/wg.log"
LOG_LOG="$SANDBOX/logger.log"
logger() { echo "$1" >>"$LOG_LOG"; }
# MOCK_FAIL：tls=证书失败；http=普通 HTTP/网络失败
webget() {
    echo "$5" >>"$WG_LOG"
    [ "$5" = skipcerforce ] && { echo ok >"$1"; return 0; }
    [ "$MOCK_FAIL" = tls ] && [ -n "$WEBGET_TLS_ERRFILE" ] && echo tls >"$WEBGET_TLS_ERRFILE"
    return 1
}
TMPDIR=$SANDBOX
sub_tls=auto
: >"$WG_LOG"; : >"$LOG_LOG"; MOCK_FAIL=http
if ! sub_webget "$SANDBOX/s1" "http://sub.example.invalid/x?token=SECRET" echooff rediron ua &&
    [ "$(tr '\n' ' ' <"$WG_LOG")" = "skipceroff " ] && [ ! -s "$LOG_LOG" ]; then
    pass "http:// 订阅失败：只拉一次，不降级、不记证书日志"
else
    fail "http:// 订阅行为异常: $(cat "$WG_LOG") / $(cat "$LOG_LOG")"
fi
: >"$WG_LOG"; : >"$LOG_LOG"; MOCK_FAIL=http
if ! sub_webget "$SANDBOX/s2" "https://sub.example.invalid/x" echooff rediron ua &&
    [ "$(tr '\n' ' ' <"$WG_LOG")" = "skipceroff " ] && [ ! -s "$LOG_LOG" ]; then
    pass "HTTPS 非证书错误（503/超时）：不降级"
else
    fail "HTTPS 非证书错误被降级: $(cat "$WG_LOG")"
fi
: >"$WG_LOG"; : >"$LOG_LOG"; MOCK_FAIL=tls
if sub_webget "$SANDBOX/s3" "https://u:p@bad.example.invalid:8443/x?token=SECRET" echooff rediron ua &&
    [ "$(tr '\n' ' ' <"$WG_LOG")" = "skipceroff skipcerforce " ] &&
    grep -q 'bad.example.invalid' "$LOG_LOG" && ! grep -q 'SECRET\|u:p' "$LOG_LOG"; then
    pass "HTTPS 证书失败：auto 降级成功并只记录主机名"
else
    fail "HTTPS 证书失败降级异常: $(cat "$WG_LOG") / $(cat "$LOG_LOG")"
fi
ls "$SANDBOX"/.sub_tls_err.* >/dev/null 2>&1 && fail "sub_webget 残留标记文件" || pass "sub_webget 清理标记文件"
: >"$WG_LOG"; sub_tls=strict; MOCK_FAIL=tls
if ! sub_webget "$SANDBOX/s4" "https://bad.example.invalid/x" echooff rediron ua && [ "$(tr '\n' ' ' <"$WG_LOG")" = "skipceroff " ]; then
    pass "strict：证书失败直接拒绝"
else
    fail "strict 行为异常: $(cat "$WG_LOG")"
fi
unset sub_tls MOCK_FAIL
unset -f webget logger
. "$CRASHDIR/libs/web_get.sh"

echo "== 4. node_tls=skip：给没写字段的节点补上跳过证书 =="
cat >"$SANDBOX/proxies.yaml" <<'EOF'
  - {name: f1, type: trojan, server: a.example, port: 443, password: x}
  - {name: f2, type: trojan, server: a.example, port: 443, password: x, skip-cert-verify: true}
  - {name: f3, type: trojan, server: a.example, port: 443, password: x} # 行尾注释
  - name: b1
    type: vless
    server: b.example
    port: 443
    alpn:
      - h2
  - name: b2
    type: trojan
    skip-cert-verify: false
EOF
tls_yaml_force_skip "$SANDBOX/proxies.yaml"
_y="$SANDBOX/proxies.yaml"
grep -q 'name: f1.*password: x, skip-cert-verify: true}' "$_y" && pass "flow 节点追加 skip-cert-verify: true" || fail "flow 节点未补写"
[ "$(grep -c 'name: f2.*skip-cert-verify' "$_y")" = 1 ] && ! grep -q 'name: f2.*skip-cert-verify: true.*skip-cert-verify' "$_y" && pass "已有字段的 flow 节点不重复写" || fail "flow 节点重复写字段"
grep -q 'name: f3, type: trojan, server: a.example, port: 443, password: x} # 行尾注释$' "$_y" && pass "带行尾注释的 flow 节点保持原样（不写坏 YAML）" || fail "带行尾注释的 flow 节点被改动"
sed -n '/name: b1/{n;p;}' "$_y" | grep -q '^    skip-cert-verify: true$' && pass "block 节点按同级缩进插入" || fail "block 节点未正确插入: $(cat "$_y")"
[ "$(awk '/name: b2/,0' "$_y" | grep -c 'skip-cert-verify')" = 1 ] && pass "已有字段的 block 节点不重复写" || fail "block 节点重复写字段"
grep -q '^      - h2$' "$_y" && pass "嵌套列表不受影响" || fail "嵌套列表被改动"
printf -- '- name: z\n  type: trojan\n' >"$SANDBOX/p0.yaml"
tls_yaml_force_skip "$SANDBOX/p0.yaml"
sed -n 2p "$SANDBOX/p0.yaml" | grep -q '^  skip-cert-verify: true$' && pass "零缩进节点正确插入" || fail "零缩进节点处理异常: $(cat "$SANDBOX/p0.yaml")"

cat >"$SANDBOX/outbounds.json" <<'EOF'
{
  "outbounds": [
    {
      "type": "trojan",
      "tag": "t1",
      "tls": {
        "enabled": true,
        "server_name": "a.example"
      }
    },
    {
      "type": "vless",
      "tag": "t2",
      "tls": {
        "enabled": true,
        "insecure": true,
        "utls": {
          "enabled": true
        }
      }
    }
  ]
}
EOF
tls_json_force_insecure "$SANDBOX/outbounds.json"
_j="$SANDBOX/outbounds.json"
[ "$(grep -c '"insecure": true' "$_j")" = 2 ] && pass "Sing-Box tls 块补写 insecure: true（已有的不重复）" || fail "Sing-Box insecure 补写数量异常: $(cat "$_j")"
if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$_j" && pass "补写后仍是合法 JSON" || fail "补写后 JSON 非法"
fi
grep -q 'tls_yaml_force_skip "$TMPDIR"/proxies.yaml' scripts/starts/clash_modify.sh && pass "clash_modify 接入补写" || fail "clash_modify 未接入补写"
grep -q 'tls_json_force_insecure "$TMPDIR"/jsons/outbounds.json' scripts/starts/singbox_modify.sh && pass "singbox_modify 接入补写" || fail "singbox_modify 未接入补写"

echo "== 5. doctor 与下载器共用有效值 =="
DOC="$SANDBOX/doc"
mkdir -p "$DOC/libs" "$DOC/configs"
cp scripts/libs/doctor.sh scripts/libs/tls_policy.sh "$DOC/libs/"
printf 'skip_cert=invalid\nsub_tls=bogus\n' >"$DOC/configs/ShellCrash.cfg"
_out=$(CRASHDIR="$DOC" sh -c '. "$CRASHDIR/libs/doctor.sh"; run_doctor' 2>&1)
echo "$_out" | grep -q 'skip_cert=invalid 不是有效值.*已按严格校验处理' && pass "doctor：skip_cert=invalid 提示按严格处理" || fail "doctor 未正确提示 skip_cert 无效值"
echo "$_out" | grep -q '证书校验已关闭' && fail "doctor 把无效值误报为已关闭校验" || pass "doctor 不再误报校验已关闭"
echo "$_out" | grep -q 'sub_tls=bogus 不是有效值' && pass "doctor：sub_tls 无效值告警" || fail "doctor 未提示 sub_tls 无效值"
printf "skip_cert='ON'\n" >"$DOC/configs/ShellCrash.cfg"
_out=$(CRASHDIR="$DOC" sh -c '. "$CRASHDIR/libs/doctor.sh"; run_doctor' 2>&1)
echo "$_out" | grep -q '节点证书：全部跳过' && pass "doctor：旧配置 skip_cert=ON 节点显示为全部跳过" || fail "doctor 旧配置节点策略显示异常"
[ "$(cat "$DOC/configs/ShellCrash.cfg")" = "skip_cert='ON'" ] && pass "doctor 未改写配置（只读）" || fail "doctor 改写了配置"

echo "== 6. 旧配置切换项目文件开关时节点策略不变 =="
MENU="$SANDBOX/menu"
mkdir -p "$MENU/configs" "$MENU/libs"
cp scripts/libs/tls_policy.sh "$MENU/libs/"
printf 'skip_cert=ON\n' >"$MENU/configs/ShellCrash.cfg"
_out=$(
    CRASHDIR="$MENU"
    unset node_tls sub_tls
    skip_cert=ON
    load_lang() { :; }
    comp_box() { :; }
    content_line() { :; }
    btm_box() { :; }
    msg_alert() { :; }
    errornum() { :; }
    read() {
        while [ $# -gt 1 ]; do shift; done
        command read -r "$1"
    }
    . "$ROOT/scripts/libs/set_config.sh"
    . "$ROOT/scripts/menus/2_settings.sh"
    printf '1\n0\n' | set_tls_policy >/dev/null 2>&1
    cat "$MENU/configs/ShellCrash.cfg"
)
if echo "$_out" | grep -q '^node_tls=skip$' && echo "$_out" | grep -q '^skip_cert=OFF$'; then
    pass "关闭项目文件跳过证书前先固化 node_tls=skip"
else
    fail "菜单切换后配置异常: $_out"
fi

echo "== 7. 升级迁移 =="
if grep -q "skip_cert=\[.\\\\\"\]?ON" scripts/init.sh && grep -q 'setconfig node_tls skip' scripts/init.sh; then
    pass "init.sh 迁移：旧 skip_cert=ON 且无 node_tls 时写入 node_tls=skip"
else
    fail "init.sh 缺少 node_tls 迁移"
fi
MIG="$SANDBOX/mig.cfg"
for _c in "skip_cert=ON:skip" "skip_cert='ON':skip" "skip_cert=OFF:" "skip_cert=ON
node_tls=follow:follow"; do
    printf '%s\n' "${_c%:*}" >"$MIG"
    CFG_PATH=$MIG
    (
        . "$ROOT/scripts/libs/set_config.sh"
        eval "$(sed -n '/^#证书策略迁移/,/^fi$/p' "$ROOT/scripts/init.sh" | sed 's/setconfig node_tls skip/setconfig node_tls skip "$CFG_PATH"/')"
    )
    _got=$(sed -n 's/^node_tls=//p' "$MIG")
    [ "$_got" = "${_c##*:}" ] && pass "迁移 [$(echo "${_c%:*}" | tr '\n' ' ')] → node_tls=${_got:-未写}" || fail "迁移 [${_c%:*}] 得到 node_tls=$_got"
done

echo "== 8. start_wait / _upg_check_service_ready 兼容 BusyBox wget 与 OpenWrt uclient-fetch =="
SW_BIN="$SANDBOX/swbin"
mkdir -p "$SW_BIN"
# 屏蔽宿主机 curl：让 command -v curl 找不到（测试无 curl 的 Alpine/OpenWrt）
for _tool in sh grep sed awk tr od id cat sleep printf mkdir rm cp mv cmp; do
    _tp=$(command -v "$_tool" 2>/dev/null) && [ -x "$_tp" ] && ln -sf "$_tp" "$SW_BIN/$_tool"
done
# BusyBox wget 替身：带 --no-proxy 报错退出；支持 -Y off 与 --header
cat >"$SW_BIN/wget" <<'EOF'
#!/bin/sh
[ "$1" = --help ] && { echo "Usage: wget [-q] [-T SEC] [-Y on/off] [--header STR] [-O FILE] URL"; exit 1; }
for a in "$@"; do
    [ "$a" = --no-proxy ] && { echo "wget: unrecognized option: no-proxy" >&2; exit 1; }
done
echo '{"version":"v1.19.17","proxies":{}}'
exit 0
EOF
chmod +x "$SW_BIN/wget"
_sw_res=$(PATH="$SW_BIN" db_port=9999 secret=s sh -c '. "$1/scripts/libs/start_wait.sh"; echo "$test"' _ "$ROOT")
[ "$_sw_res" = proxies ] && pass "start_wait：无 curl + BusyBox wget（无 --no-proxy）正常通过" || fail "start_wait BusyBox 失败: $_sw_res"

# OpenWrt uclient-fetch 替身：带 --header 报错退出；支持 -Y off；有 secret 时返回 HTTP error 401
cat >"$SW_BIN/wget" <<'EOF'
#!/bin/sh
[ "$1" = --help ] && { echo "Options: -T N  -Y on/off  --no-proxy  --no-check-certificate"; exit 1; }
for a in "$@"; do
    case "$a" in --header*) echo "wget: unrecognized option: $a" >&2; exit 1 ;; esac
done
if [ "$UC_MODE" = 401 ]; then
    echo "HTTP error 401" >&2
    exit 8
fi
echo '{"version":"v1.19.17","proxies":{}}'
exit 0
EOF
chmod +x "$SW_BIN/wget"
_sw_res=$(PATH="$SW_BIN" UC_MODE=401 db_port=9999 secret=s sh -c '. "$1/scripts/libs/start_wait.sh"; echo "$test"' _ "$ROOT")
[ "$_sw_res" = proxies ] && pass "start_wait：无 curl + uclient-fetch（无 --header，有 secret 返回 401）不卡 29 秒" || fail "start_wait uclient 401 失败: $_sw_res"

# 构造 ELF 魔数假 CrashCore 测 _upg_check_service_ready
ELF_DIR="$SANDBOX/elf"
mkdir -p "$ELF_DIR/configs"
printf '\177ELF' >"$ELF_DIR/CrashCore"
printf 'db_port=9999\nsecret=s\n' >"$ELF_DIR/configs/ShellCrash.cfg"
cat >"$SW_BIN/pidof" <<'EOF'
#!/bin/sh
echo 12345
EOF
chmod +x "$SW_BIN/pidof"
PATH="$SW_BIN" UC_MODE=401 CRASHDIR="$ELF_DIR" TMPDIR="$ELF_DIR" USER=nonroot sh -c '. "$1/scripts/libs/set_config.sh"; _upg_check_service_ready' _ "$ROOT" &&
    pass "_upg_check_service_ready：无 curl + uclient-fetch（有 secret 401）判定就绪" ||
    fail "_upg_check_service_ready uclient 401 失败"

echo
if [ "$failures" -gt 0 ]; then
    echo "test_tls_policy: $failures 项失败"
    exit 1
fi
echo "test_tls_policy: 全部通过"
