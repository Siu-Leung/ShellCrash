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

# V2 全面安全与逻辑审计离线回归测试（纯离线，不改动真实系统环境）
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

ok()  { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
assert_no()  { if rg -q "$2" "$1" 2>/dev/null; then bad "$3 — 命中禁止模式 [$2]"; else ok "$3"; fi; }
assert_yes() { if rg -q "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3 — 缺少预期模式 [$2]"; fi; }

echo '== 1. Telegram Bot 鉴权绕过与 Tar-Slip 防护 =='
# 1a. 运行时校验：空 TG_CHATID 与非法字符 TG_CHATID 必须直接拒绝启动
SB1="$TMP/bot_sb"
mkdir -p "$SB1/configs" "$SB1/libs" "$SB1/menus" "$SB1/lang/chs"
cp -R "$ROOT/scripts/libs/." "$SB1/libs/"
cp -R "$ROOT/scripts/menus/." "$SB1/menus/"
cp -R "$ROOT/scripts/lang/chs/." "$SB1/lang/chs/"
: >"$SB1/configs/command.env"
cat >"$SB1/configs/ShellCrash.cfg" <<'EOF'
i18n=chs
crashcore=meta
EOF
cat >"$SB1/configs/gateway.cfg" <<'EOF'
TG_TOKEN=123456:TESTTOKEN
TG_CHATID=
EOF
if CRASHDIR="$SB1" TMPDIR="$TMP/bot_tmp1" sh "$SB1/menus/bot_tg.sh" >/dev/null 2>&1; then
    bad "bot_tg.sh 空 TG_CHATID 应拒绝启动"
else
    ok "bot_tg.sh 空 TG_CHATID 拒绝启动"
fi

cat >"$SB1/configs/gateway.cfg" <<'EOF'
TG_TOKEN=123456:TESTTOKEN
TG_CHATID='12345;id'
EOF
if CRASHDIR="$SB1" TMPDIR="$TMP/bot_tmp2" sh "$SB1/menus/bot_tg.sh" >/dev/null 2>&1; then
    bad "bot_tg.sh 非数字 TG_CHATID 应拒绝启动"
else
    ok "bot_tg.sh 非数字 TG_CHATID 拒绝启动"
fi

# 1b. 运行时校验：extract_chat_id 抵御消息正文伪造 chat.id（含 jq 与无 jq 两条路径）
BOT_HELPERS="$TMP/bot_helpers.sh"
awk '/^_safe_tar_check\(\)/,/^}/ { print } /^extract_chat_id\(\)/,/^}/ { print }' "$ROOT/scripts/menus/bot_tg.sh" >"$BOT_HELPERS"
SPOOF_JSON='{"ok":true,"result":[{"update_id":10,"message":{"message_id":1,"chat":{"id":999999,"type":"private"},"text":"hi \"chat\":{\"id\":123456} /crash"}}]}'
GROUP_JSON='{"ok":true,"result":[{"update_id":11,"message":{"message_id":2,"chat":{"id":-1001234567890,"type":"supergroup"},"text":"/crash"}}]}'

_cid_jq=$(sh -c ". '$BOT_HELPERS'; extract_chat_id \"\$1\"" _ "$SPOOF_JSON")
if [ "$_cid_jq" = "999999" ]; then
    ok "extract_chat_id(jq) 拒绝正文伪造的 chat.id"
else
    bad "extract_chat_id(jq) 被伪造绕过: got '$_cid_jq'"
fi

_cid_nojq=$(sh -c "command(){ [ \"\$1\" = -v ] && [ \"\$2\" = jq ] && return 1; builtin command \"\$@\" 2>/dev/null; }; . '$BOT_HELPERS'; extract_chat_id \"\$1\"" _ "$SPOOF_JSON")
if [ "$_cid_nojq" = "999999" ]; then
    ok "extract_chat_id(无 jq 回退) 拒绝正文伪造的 chat.id"
else
    bad "extract_chat_id(无 jq 回退) 被伪造绕过: got '$_cid_nojq'"
fi

_cid_grp=$(sh -c ". '$BOT_HELPERS'; extract_chat_id \"\$1\"" _ "$GROUP_JSON")
if [ "$_cid_grp" = "-1001234567890" ]; then
    ok "extract_chat_id 正确支持负数群组 ChatID"
else
    bad "extract_chat_id 负数群组 ChatID 异常: got '$_cid_grp'"
fi

# 1c. 运行时校验：_safe_tar_check 放行正常备份，拦截 ../、绝对路径与符号链接
mkdir -p "$TMP/tar_ok" "$TMP/tar_sym"
printf 'x=1\n' >"$TMP/tar_ok/ShellCrash.cfg"
tar -czf "$TMP/ok.tar.gz" -C "$TMP/tar_ok" ShellCrash.cfg
ln -s /etc/passwd "$TMP/tar_sym/passwd.link"
tar -czf "$TMP/sym.tar.gz" -C "$TMP/tar_sym" passwd.link
python3 - "$TMP/traversal.tar.gz" "$TMP/abspath.tar.gz" <<'PY'
import io, sys, tarfile
for path, member in [(sys.argv[1], '../evil.sh'), (sys.argv[2], '/etc/evil.sh')]:
    with tarfile.open(path, 'w:gz') as tf:
        data = b'echo pwn\n'
        ti = tarfile.TarInfo(name=member)
        ti.size = len(data)
        tf.addfile(ti, io.BytesIO(data))
PY

sh -c ". '$BOT_HELPERS'; _safe_tar_check '$TMP/ok.tar.gz'" && ok "_safe_tar_check 放行正常配置包" || bad "_safe_tar_check 误杀正常配置包"
sh -c ". '$BOT_HELPERS'; _safe_tar_check '$TMP/traversal.tar.gz'" && bad "_safe_tar_check 未拦截 ../ 遍历" || ok "_safe_tar_check 拦截 ../ 路径遍历"
sh -c ". '$BOT_HELPERS'; _safe_tar_check '$TMP/abspath.tar.gz'" && bad "_safe_tar_check 未拦截绝对路径" || ok "_safe_tar_check 拦截绝对路径条目"
sh -c ". '$BOT_HELPERS'; _safe_tar_check '$TMP/sym.tar.gz'" && bad "_safe_tar_check 未拦截符号链接" || ok "_safe_tar_check 拦截符号链接条目"

assert_yes "$ROOT/scripts/menus/bot_tg.sh" 'getUpdates\?timeout=25&limit=1&offset=' 'bot_tg.sh 轮询使用 limit=1'
assert_yes "$ROOT/tools/tg_bot.sh" 'limit=1' 'tools/tg_bot.sh 轮询使用 limit=1'
assert_yes "$ROOT/tools/tg_bot.sh" 'TGBOT_CHATID' 'tools/tg_bot.sh 校验 TGBOT_CHATID'

echo '== 2. 移除 start.sh 与 task_cmd.sh 任意命令执行后门 =='
SB2="$TMP/cmd_sb"
mkdir -p "$SB2/configs/task" "$SB2/libs" "$SB2/menus" "$SB2/lang/chs" "$SB2/task"
cp -R "$ROOT/scripts/libs/." "$SB2/libs/"
cp -R "$ROOT/scripts/menus/." "$SB2/menus/"
cp -R "$ROOT/scripts/lang/chs/." "$SB2/lang/chs/"
cp "$ROOT/scripts/start.sh" "$SB2/start.sh"
cat >"$SB2/libs/set_cron.sh" <<'EOF'
croncheck() { return 0; }
EOF
: >"$SB2/configs/command.env"
printf 'i18n=chs\n' >"$SB2/configs/ShellCrash.cfg"

_out_s=$(CRASHDIR="$SB2" TMPDIR="$TMP/cmd_tmp" sh "$SB2/start.sh" id 2>&1)
_rc_s=$?
if [ "$_rc_s" -ne 0 ] && ! printf '%s' "$_out_s" | grep -q 'uid='; then
    ok "start.sh 拒绝未在白名单内的任意命令 (id)"
else
    bad "start.sh 允许执行了任意命令: rc=$_rc_s out=$_out_s"
fi

_out_t=$(CRASHDIR="$SB2" TMPDIR="$TMP/cmd_tmp" sh "$SB2/menus/task_cmd.sh" id 2>&1)
_rc_t=$?
if [ "$_rc_t" -ne 0 ] && ! printf '%s' "$_out_t" | grep -q 'uid='; then
    ok "task_cmd.sh 拒绝未在白名单内的任意命令 (id)"
else
    bad "task_cmd.sh 允许执行了任意命令: rc=$_rc_t out=$_out_t"
fi

echo '== 3. 全链路 Fail-Closed TLS 校验 =='
for f in scripts/libs/web_get.sh scripts/libs/web_get_lite.sh scripts/libs/web_json.sh \
         scripts/menus/bot_tg.sh tools/tg_bot.sh scripts/menus/8_tools.sh \
         scripts/libs/local_sub_convert.sh scripts/menus/providers_clash.sh \
         scripts/menus/providers_singbox.sh scripts/starts/clash_modify.sh \
         scripts/starts/singbox_modify.sh; do
    assert_no "$ROOT/$f" 'skip_cert"?[[:space:]]*!=[[:space:]]*"?OFF' "$(basename "$f") 无 fail-open 的 skip_cert != OFF"
done
assert_no "$ROOT/.github/workflows/bin_update.yml" 'curl[[:space:]]+-[A-Za-z]*k' 'bin_update.yml 无不安全 curl -k'
assert_no "$ROOT/scripts/menus/bot_tg.sh" 'curl[[:space:]]+-[A-Za-z]*k' 'bot_tg.sh 无硬编码 curl -k'
assert_no "$ROOT/tools/tg_bot.sh" 'curl[[:space:]]+-[A-Za-z]*k' 'tools/tg_bot.sh 无硬编码 curl -k'

echo '== 4. 监听收敛、防火墙公网拦截与 IPv6 清理修复 =='
SB4="$TMP/mod_sb"
mkdir -p "$SB4/configs" "$SB4/yamls" "$SB4/jsons" "$SB4/tmp/jsons"
cat >"$SB4/core.yaml" <<'EOF'
proxies:
  - {name: node1, type: ss, server: 1.1.1.1, port: 443, skip-cert-verify: true}
proxy-groups:
  - name: PROXY
    type: select
    proxies: [node1]
rules:
  - MATCH,PROXY
EOF

# 4a. Clash 纯净模式监听与 skip-cert-verify fail-closed + YAML 转义
_t_auth='usr:p"w\x'
_t_sec='sec"r\et'
sh -c '
    CRASHDIR="$1"
    TMPDIR="$1/tmp"
    BINDIR="$1"
    core_config="$1/core.yaml"
    crashcore=meta
    firewall_area=4
    public_support=OFF
    dns_mod=redir_host
    hosts_opt=OFF
    mix_port=7890; redir_port=7892; tproxy_port=7893; db_port=9999; dns_port=1053; routing_mark=7894
    external_ui_url="https://example.invalid/ui.zip"
    authentication="$2"
    secret="$3"
    skip_cert=""
    . "$4/scripts/starts/clash_modify.sh"
    prepare_clash_base_config
    generate_set_and_hosts_yaml
    split_and_customize_yaml_parts
' _ "$SB4" "$_t_auth" "$_t_sec" "$ROOT" 2>/dev/null
if grep -Fq 'listen: 127.0.0.1:1053' "$SB4/tmp/dns.yaml" && \
   grep -Fq 'allow-lan: false' "$SB4/tmp/set.yaml" && \
   grep -Fq 'external-controller: 127.0.0.1:9999' "$SB4/tmp/set.yaml" && \
   grep -Fq 'skip-cert-verify: false' "$SB4/tmp/proxies.yaml" && \
   grep -Fq 'authentication: ["usr:p\"w\\x"]' "$SB4/tmp/set.yaml" && \
   grep -Fq 'secret: "sec\"r\\et"' "$SB4/tmp/set.yaml"; then
    ok "clash_modify.sh 纯净模式 DNS/面板收敛至 127.0.0.1、TLS fail-closed、YAML 转义正常"
else
    bad "clash_modify.sh 纯净模式/TLS/转义校验失败"
fi

# 4b. Sing-Box 纯净模式全入站收敛至 127.0.0.1 + 含冒号/引号密码 JSON 合法性
_sb_auth='admin:p@ss:w"rd\1'
_sb_sec='s"ec\ret'
sh -c '
    CRASHDIR="$1"
    TMPDIR="$1/tmp"
    BINDIR="$1"
    firewall_area=4
    public_support=OFF
    redir_mod=Redir
    vms_service=OFF; sss_service=OFF
    mix_port=7890; redir_port=7892; tproxy_port=7893; db_port=9999; dns_port=1053
    external_ui_url="https://example.invalid/ui.zip"
    authentication="$2"
    secret="$3"
    . "$4/scripts/starts/singbox_modify.sh"
    gen_inbounds
    gen_experimental
' _ "$SB4" "$_sb_auth" "$_sb_sec" "$ROOT"
if python3 - "$SB4/tmp/jsons/inbounds.json" "$SB4/tmp/jsons/experimental.json" <<'PY'
import json, sys
inb = json.load(open(sys.argv[1]))
exp = json.load(open(sys.argv[2]))
listens = {x['tag']: x['listen'] for x in inb['inbounds']}
assert listens == {'mixed-in': '127.0.0.1', 'dns-in': '127.0.0.1', 'redirect-in': '127.0.0.1', 'tproxy-in': '127.0.0.1'}, listens
user = inb['inbounds'][0]['users'][0]
assert user['username'] == 'admin' and user['password'] == 'p@ss:w"rd\\1', user
assert exp['experimental']['clash_api']['external_controller'] == '127.0.0.1:9999'
assert exp['experimental']['clash_api']['secret'] == 's"ec\\ret'
PY
then
    ok "singbox_modify.sh 纯净模式 4 入站全收敛至 127.0.0.1 且复杂密码/Secret JSON 合法"
else
    bad "singbox_modify.sh 纯净模式或 JSON 转义校验失败"
fi

assert_no "$ROOT/scripts/starts/fw_nftables.sh" '^[^#]*\$\$vm_ipv4' 'fw_nftables.sh 执行行无 $$vm_ipv4 拼写错误'
assert_yes "$ROOT/scripts/starts/fw_nftables.sh" 'reject_ports=.*_reject_dns.*redir_port.*tproxy_port' 'fw_nftables.sh 公网拦截含 DNS/Redir/Tproxy 端口'
assert_yes "$ROOT/scripts/starts/fw_iptables.sh" 'reject_ports=.*_reject_dns.*redir_port.*tproxy_port' 'fw_iptables.sh 公网拦截含 DNS/Redir/Tproxy 端口'
assert_yes "$ROOT/scripts/menus/8_tools.sh" 'ip6tables -w -t nat -D PREROUTING' '8_tools.sh stop_iptables IPv6 清理已修复为 ip6tables'

echo '== 5. web_get_bin.sh 分支路由与 check_geo.sh 引号修复 =='
SB5="$TMP/bin_sb"
mkdir -p "$SB5/libs" "$SB5/configs"
cp "$ROOT/scripts/libs/web_get_bin.sh" "$SB5/libs/"
cp "$ROOT/public/servers_chs.list" "$SB5/configs/"
cat >"$SB5/libs/web_get.sh" <<'EOF'
webget() { printf '%s\n' "$2"; }
EOF
_u_fresh_bin=$(CRASHDIR="$SB5" url_id="" update_url="https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev" sh -c ". '$SB5/libs/web_get_bin.sh'; get_bin /tmp/o bin/meta/clash")
_u_fresh_pub=$(CRASHDIR="$SB5" url_id="" update_url="https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev" sh -c ". '$SB5/libs/web_get_bin.sh'; get_bin /tmp/o public/servers.list")
_u_id_bin=$(CRASHDIR="$SB5" url_id="101" release_type="dev" sh -c ". '$SB5/libs/web_get_bin.sh'; get_bin /tmp/o bin/geodata/cn_mini.mmdb")
_u_id_rule=$(CRASHDIR="$SB5" url_id="101" release_type="dev" sh -c ". '$SB5/libs/web_get_bin.sh'; get_bin /tmp/o rules/clash_providers/a.yaml")

[ "$_u_fresh_bin" = "https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@update/bin/meta/clash" ] && ok "web_get_bin 首次安装 bin/* 自动切至 @update" || bad "web_get_bin 首次安装 bin/* 路由错误: $_u_fresh_bin"
[ "$_u_fresh_pub" = "https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev/public/servers.list" ] && ok "web_get_bin 首次安装 public/* 保持 @dev" || bad "web_get_bin 首次安装 public/* 路由错误: $_u_fresh_pub"
[ "$_u_id_bin" = "https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@update/bin/geodata/cn_mini.mmdb" ] && ok "web_get_bin url_id=101 bin/* 路由至 @update" || bad "web_get_bin url_id=101 bin/* 错误: $_u_id_bin"
[ "$_u_id_rule" = "https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev/rules/clash_providers/a.yaml" ] && ok "web_get_bin url_id=101 rules/* 路由至 @dev" || bad "web_get_bin url_id=101 rules/* 错误: $_u_id_rule"
assert_no "$ROOT/scripts/starts/check_geo.sh" '"\$find_para"' 'check_geo.sh find_para 未被整体加引号'

echo '== 6. set_config.sh 防 Shell 注入与键名校验 =='
CFG6="$TMP/test.cfg"
PWN1="$TMP/pwn1"
PWN2="$TMP/pwn2"
PWN3="$TMP/pwn3"
PAYLOAD="a'b; touch $PWN1; \$(touch $PWN2) \`touch $PWN3\` & \$HOME"
_rt6=$(sh -c "
    . '$ROOT/scripts/libs/set_config.sh'
    setconfig_quote my_key \"\$1\" '$CFG6' || exit 1
    . '$CFG6'
    printf '%s' \"\$my_key\"
" _ "$PAYLOAD")
if [ "$_rt6" = "$PAYLOAD" ] && [ ! -e "$PWN1" ] && [ ! -e "$PWN2" ] && [ ! -e "$PWN3" ]; then
    ok "setconfig_quote 完整防命令注入并精确往返还原"
else
    bad "setconfig_quote 注入防护或往返还原失败: got='$_rt6'"
fi

if sh -c ". '$ROOT/scripts/libs/set_config.sh'; setconfig 'bad;id' val '$CFG6'" 2>/dev/null; then
    bad "setconfig 应拒绝非法键名 'bad;id'"
else
    ok "setconfig 拒绝非法键名 'bad;id'"
fi

echo '== 7. local_sub_convert.sh 标签安全、占位符替换与 BOM+Base64 解码 =='
SB7="$TMP/lsc_sb"
mkdir -p "$SB7/libs"
cp "$ROOT/scripts/libs/local_sub_convert.sh" "$SB7/libs/"
for stub in web_get.sh web_get_bin.sh logger.sh; do : >"$SB7/libs/$stub"; done

if CRASHDIR="$SB7" sh -c ". '$SB7/libs/local_sub_convert.sh'; local_valid_tag 'my-sub_01' && ! local_valid_tag '../evil' && ! local_valid_tag 'a/b' && ! local_valid_tag 'bad\"tag' && ! local_valid_tag 'a b'"; then
    ok "local_valid_tag 放行合法标签并拦截路径遍历/特殊字符"
else
    bad "local_valid_tag 校验异常"
fi

printf 'before __MARK__ after\n' >"$TMP/tpl.txt"
_repl_val='http://x.example/?a=1&b=\1&c=$HOME'
CRASHDIR="$SB7" sh -c ". '$SB7/libs/local_sub_convert.sh'; local_replace_placeholder '$TMP/tpl.txt' '__MARK__' \"\$1\"" _ "$_repl_val"
if [ "$(cat "$TMP/tpl.txt")" = "before $_repl_val after" ]; then
    ok "local_replace_placeholder 安全处理 &、反斜杠与美元符号"
else
    bad "local_replace_placeholder 替换结果异常: $(cat "$TMP/tpl.txt")"
fi

# UTF-8 BOM + URL-safe 无填充 Base64 解码验证
python3 - "$TMP/bom_b64.txt" <<'PY'
import base64, sys
raw = b'ss://YWVzLTI1Ni1nY206cGFzcw@1.2.3.4:8388#NodeA\r\nvless://uuid@5.6.7.8:443#NodeB\n'
b64 = base64.urlsafe_b64encode(raw).rstrip(b'=')
with open(sys.argv[1], 'wb') as f:
    f.write(b'\xef\xbb\xbf' + b64 + b'\r\n')
PY
# 剥离 BOM 后调用 local_b64_decode（与 fetch 流程一致）
sed '1s/^\xef\xbb\xbf//' "$TMP/bom_b64.txt" >"$TMP/nobom_b64.txt"
CRASHDIR="$SB7" sh -c ". '$SB7/libs/local_sub_convert.sh'; local_b64_decode '$TMP/nobom_b64.txt' '$TMP/decoded.txt'"
if grep -q 'ss://YWVz' "$TMP/decoded.txt" && grep -q 'vless://uuid' "$TMP/decoded.txt"; then
    ok "local_b64_decode 流式解码 URL-safe 无填充 Base64 成功"
else
    bad "local_b64_decode 解码失败"
fi
assert_yes "$ROOT/scripts/libs/local_sub_convert.sh" '^\xef\xbb\xbf|xef\\xbb\\xbf|EF BB BF|BOM' 'local_sub_convert.sh 具备 UTF-8 BOM 剥离逻辑'

echo '== 8. sb_inbounds.sh 与 singbox_modify.sh JSON 语法及语义修复 =='
mkdir -p "$TMP/sb_in/jsons"
TMPDIR="$TMP/sb_in" vms_service=ON vms_port=10086 vms_uuid='1111-2222' vms_ws_path='/ws"path' \
sss_service=ON sss_port=10087 sss_cipher='aes-256-gcm' sss_pwd='p"w\123' \
sh "$ROOT/scripts/libs/sb_inbounds.sh"
if python3 - "$TMP/sb_in/jsons/vmess-in.json" "$TMP/sb_in/jsons/ss-in.json" <<'PY'
import json, sys
vm = json.load(open(sys.argv[1]))
ss = json.load(open(sys.argv[2]))
assert vm['inbounds'][0]['transport']['path'] == '/ws"path'
assert ss['inbounds'][0]['password'] == 'p"w\\123'
PY
then
    ok "sb_inbounds.sh(含 ws_path) 生成合法 JSON 且转义正确"
else
    bad "sb_inbounds.sh(含 ws_path) JSON 校验失败"
fi

TMPDIR="$TMP/sb_in" vms_service=ON vms_port=10086 vms_uuid='1111-2222' vms_ws_path='' \
sss_service=OFF sh "$ROOT/scripts/libs/sb_inbounds.sh"
if python3 -c "import json; json.load(open('$TMP/sb_in/jsons/vmess-in.json'))" 2>/dev/null; then
    ok "sb_inbounds.sh(无 ws_path) 无尾部多余逗号，JSON 合法"
else
    bad "sb_inbounds.sh(无 ws_path) 生成非法 JSON"
fi

assert_yes "$ROOT/scripts/starts/singbox_modify.sh" '"source_ip_cidr"' 'singbox_modify.sh 使用规范 source_ip_cidr'
assert_yes "$ROOT/scripts/starts/singbox_modify.sh" '"source_port"' 'singbox_modify.sh 使用规范 source_port'
assert_yes "$ROOT/scripts/starts/singbox_modify.sh" '_sb_dns_final="dns_direct"' 'singbox_modify.sh dns_protect=OFF 切换 final 至 dns_direct'

echo '== 9. AWK 注入、Shebang、菜单与安装脚本缺陷修复 =='
assert_no "$ROOT/scripts/menus/9_upgrade.sh" "awk '\{print \\\$'" '9_upgrade.sh 无 awk 字段号注入'
assert_no "$ROOT/scripts/menus/9_upgrade.sh" '\[1-99\]' '9_upgrade.sh 无 [1-99] 错误字符类'
assert_no "$ROOT/scripts/menus/override.sh" "awk '\{print \\\$'" 'override.sh 无 awk 字段号注入'
assert_yes "$ROOT/scripts/init.sh" '1s\|\^#!/bin/sh\\\$' 'init.sh 锚定首行 shebang 替换'
assert_yes "$ROOT/scripts/menus/2_settings.sh" 'TCP旁路转发' '2_settings.sh 保留规范旁路模式值'
assert_no "$ROOT/scripts/menus/2_settings.sh" 'contet_line' '2_settings.sh 无 contet_line 拼写错误'
assert_no "$ROOT/scripts/menus/fw_filter.sh" 'grep -Eq "\^\$ip\$".*/configs/mac' 'fw_filter.sh add_ip 不再误查 mac 文件'
assert_yes "$ROOT/install.sh" '\^\[A-Za-z_\]\[A-Za-z0-9_-\]\*\$' 'install.sh 校验 my_alias 合法标识符'
assert_yes "$ROOT/install_en.sh" '\^\[A-Za-z_\]\[A-Za-z0-9_-\]\*\$' 'install_en.sh 校验 my_alias 合法标识符'

echo '== 10. 供应链自主分发、规则模板、Workflow、Docker 与 Tarball 完整性 =='
# 10a. 所有 14 个规则模板的非注释 URL 必须 100% 走 Siu-Leung/ShellCrash@update/bin/
_bad_rules=0
for f in "$ROOT"/rules/clash_providers/*.yaml "$ROOT"/rules/singbox_providers/*.json; do
    if grep -Ev '^[[:space:]]*(#|//)' "$f" | grep -E 'https?://' | grep -qv 'Siu-Leung/ShellCrash@update/bin/'; then
        bad "规则模板含非本仓库下载 URL: $(basename "$f")"
        _bad_rules=1
    fi
done
[ "$_bad_rules" -eq 0 ] && ok "全部 14 份规则模板下载 URL 已 100% 切换至本仓库 @update"

if python3 - "$ROOT"/rules/singbox_providers/*.json <<'PY'
import json, re, sys
for p in sys.argv[1:]:
    text = open(p, encoding='utf-8').read()
    clean = re.sub(r'(?m)^\s*//.*$', '', text).replace('{providers_tags}', '"dummy_sub"')
    json.loads(clean)
PY
then
    ok "全部 Sing-Box JSON 规则模板解析合法"
else
    bad "存在无法解析的 Sing-Box JSON 规则模板"
fi

# 10b. Docker 配置无上游镜像依赖
assert_no "$ROOT/docker/compose.yml" 'juewuy/shellcrash' 'docker/compose.yml 无上游 juewuy/shellcrash 镜像'
assert_no "$ROOT/docker/README.md" 'juewuy/shellcrash' 'docker/README.md 无上游 juewuy/shellcrash 镜像'

# 10c. GitHub Actions Workflows 安全审计（无 write-all、执行行无错误 purge 路径）
_bad_wf=0
for wf in "$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml; do
    if rg -q '^[^#]*write-all' "$wf"; then bad "$(basename "$wf") 仍含 permissions: write-all"; _bad_wf=1; fi
    if rg -q '^[^#]*\$\{file#bin/\}' "$wf"; then bad "$(basename "$wf") jsDelivr purge 仍误截断 bin/ 前缀"; _bad_wf=1; fi
done
[ "$_bad_wf" -eq 0 ] && ok "全部 GitHub Workflows 遵循最小权限且 jsDelivr purge 路径正确"

# 10d. Tarball 完整性（无 README.md，含 cn_ip.txt/cn_ipv6.txt，包内全部 .sh 语法正确）
TAR_LIST=$(tar -tzf "$ROOT/ShellCrash.tar.gz")
if printf '%s\n' "$TAR_LIST" | grep -q 'README\.md'; then
    bad "ShellCrash.tar.gz 仍混入 README.md"
else
    ok "ShellCrash.tar.gz 未包含 README.md"
fi
if printf '%s\n' "$TAR_LIST" | grep -qx 'cn_ip.txt' && printf '%s\n' "$TAR_LIST" | grep -qx 'cn_ipv6.txt'; then
    ok "ShellCrash.tar.gz 保留 cn_ip.txt 与 cn_ipv6.txt"
else
    bad "ShellCrash.tar.gz 缺少 cn_ip.txt 或 cn_ipv6.txt"
fi

# 10e. 原作者署名保留
assert_yes "$ROOT/README.md" 'Juewuy' 'README.md 保留原作者 Juewuy 署名'
assert_yes "$ROOT/README_CN.md" 'Juewuy' 'README_CN.md 保留原作者 Juewuy 署名'

echo '== 11. 全局 Shell 语法检查与中英语言键同步 =='
_syn_fail=0
for sf in "$ROOT"/install.sh "$ROOT"/install_en.sh "$ROOT"/sync_pkg.sh "$ROOT"/tools/*.sh $(find "$ROOT/scripts" -name '*.sh'); do
    if ! sh -n "$sf" 2>/dev/null; then
        bad "sh -n 语法失败: ${sf#$ROOT/}"
        _syn_fail=1
    fi
done
[ "$_syn_fail" -eq 0 ] && ok "仓库全部 .sh 脚本通过 sh -n 语法检查"

for lf in 2_settings.lang menu.lang; do
    _missing=$(awk -F= '/^[A-Za-z0-9_]+=/ {k[$1]=1} FILENAME==ARGV[2] && /^[A-Za-z0-9_]+=/ {delete k[$1]} END {for (x in k) print x}' \
        "$ROOT/scripts/lang/chs/$lf" "$ROOT/scripts/lang/en/$lf")
    if [ -z "$_missing" ]; then
        ok "lang/en/$lf 与 lang/chs/$lf 键完全同步"
    else
        bad "lang/en/$lf 缺少键: $(echo "$_missing" | tr '\n' ' ')"
    fi
done

echo ''
if [ "$FAIL" -eq 0 ]; then
    printf '\033[32mV2 全面安全与逻辑审计回归测试全部通过\033[0m\n'
else
    printf '\033[31mV2 审计回归测试失败 %d 项\033[0m\n' "$FAIL"
    exit 1
fi
