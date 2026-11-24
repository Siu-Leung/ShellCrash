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

echo '== 12. V3 复核回归（S1/T1/U1/U2/Fake-IP JSON/只读 doctor/CI 门禁）=='
# 12a. S1: 合法 Mihomo 直链 YAML 在 url_type 为空时 check_config 必须返回 0
cat >"$TMP/valid_mihomo.yaml" <<'EOF'
proxies:
  - {name: HK-1, type: vless, server: 1.2.3.4, port: 443}
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-1]
rules:
  - MATCH,PROXY
EOF
if TMPDIR="$TMP" core_config_new="$TMP/valid_mihomo.yaml" url_type="" sh -c 'ckcmd(){ command -v "$1" >/dev/null 2>&1; }; logger(){ :; }; . "$1/scripts/starts/clash_config_check.sh"; check_config' _ "$ROOT"; then
    ok "S1: clash_config_check 对合法 Mihomo 直链(url_type为空)返回 0"
else
    bad "S1: clash_config_check 误拒了合法 Mihomo 直链配置"
fi

# 12b. T1: Telegram 群组操作者 from.id 鉴权
BOT_T1="$TMP/bot_t1.sh"
awk '/^extract_chat_id\(\)/,/^}/ { print } /^extract_from_id\(\)/,/^}/ { print } /^is_authorized_event\(\)/,/^}/ { print }' "$ROOT/scripts/menus/bot_tg.sh" >"$BOT_T1"
PRIV_EV='{"ok":true,"result":[{"update_id":1,"message":{"from":{"id":555},"chat":{"id":555,"type":"private"},"text":"/crash"}}]}'
GRP_MEMBER='{"ok":true,"result":[{"update_id":2,"message":{"from":{"id":999},"chat":{"id":-100123,"type":"supergroup"},"text":"/crash"}}]}'
GRP_ADMIN='{"ok":true,"result":[{"update_id":3,"message":{"from":{"id":888},"chat":{"id":-100123,"type":"supergroup"},"text":"/crash"}}]}'

TG_CHATID="555" TG_ADMIN_IDS="" sh -c ". '$BOT_T1'; is_authorized_event \"\$1\"" _ "$PRIV_EV" \
    && ok "T1: 私聊 chat.id 与 from.id 一致放行" || bad "T1: 私聊合法事件被误拒"
TG_CHATID="-100123" TG_ADMIN_IDS="" sh -c ". '$BOT_T1'; is_authorized_event \"\$1\"" _ "$GRP_ADMIN" \
    && bad "T1: 群组未配置 TG_ADMIN_IDS 时应拒绝管理操作" || ok "T1: 群组未配置 TG_ADMIN_IDS 默认拒绝越权"
TG_CHATID="-100123" TG_ADMIN_IDS="777,888" sh -c ". '$BOT_T1'; is_authorized_event \"\$1\"" _ "$GRP_MEMBER" \
    && bad "T1: 群组非白名单成员应被拒绝" || ok "T1: 群组非白名单成员(999)被拦截"
TG_CHATID="-100123" TG_ADMIN_IDS="777,888" sh -c ". '$BOT_T1'; is_authorized_event \"\$1\"" _ "$GRP_ADMIN" \
    && ok "T1: 群组白名单管理员(888)正常放行" || bad "T1: 群组白名单管理员被误拒"

# 12c. 远端 bin/version 纯数据解析（禁止 source 执行命令）
VER_PWN="$TMP/ver_pwn"
cat >"$TMP/evil_version" <<EOF
meta_v=v1.19.34
singbox_v=v1.12.0; touch $VER_PWN
\$(touch ${VER_PWN}_2)
GeoIP_v=20261124
EOF
_lv_res=$(sh -c ". '$ROOT/scripts/libs/set_config.sh'; meta_v=''; singbox_v=''; GeoIP_v=''; load_version_file '$TMP/evil_version'; printf '%s|%s|%s' \"\$meta_v\" \"\$singbox_v\" \"\$GeoIP_v\"")
if [ "$_lv_res" = "v1.19.34||20261124" ] && [ ! -e "$VER_PWN" ] && [ ! -e "${VER_PWN}_2" ]; then
    ok "load_version_file 纯数据解析正常且彻底免疫命令注入"
else
    bad "load_version_file 解析或防护异常: got='$_lv_res'"
fi

# 12d. Sing-Box Fake-IP：用完整 public/fake_ip_filter.list 生成真实 JSON 并以 python3 解析校验
_fp_json=$(sh -c ". '$ROOT/scripts/starts/singbox_modify.sh' >/dev/null 2>&1 || true; sb_convert_domain_rules '$ROOT/public/fake_ip_filter.list'; printf '{\"domain\":[%s],\"domain_suffix\":[%s],\"domain_regex\":[%s]}' \"\$_fp_domain\" \"\$_fp_suffix\" \"\$_fp_regex\"")
if printf '%s' "$_fp_json" | python3 -c '
import json, sys
obj = json.load(sys.stdin)
assert "music.163.com" in obj["domain"], "missing plain domain"
assert "lan" in obj["domain_suffix"], "missing suffix"
assert "^[^.]+$" in obj["domain_regex"], "missing bare-* single-label regex"
assert ".*" not in obj["domain_regex"], "dangerous catch-all .* present"
assert not any("*" in x for x in obj["domain_suffix"]), "wildcard leaked into domain_suffix"
'
then
    ok "sb_convert_domain_rules 对完整 fake_ip_filter.list 生成 100% 合法 JSON 且裸 * 不吞噬域名"
else
    bad "sb_convert_domain_rules JSON 校验或裸 * 语义失败"
fi

# 12e. systemd ExecStart 无字面 >/dev/null
assert_no "$ROOT/scripts/starts/shellcrash.service" 'ExecStart=.*>/dev/null' 'shellcrash.service ExecStart 无字面 >/dev/null'
assert_no "$ROOT/scripts/start.sh" 'ExecStart=.*>/dev/null' 'start.sh ExecStart 改写无字面 >/dev/null'

# 12f. crash doctor 在缺少配置文件时严格只读（不创建 ShellCrash.cfg / 不执行 init.sh）
DOC_SB="$TMP/doc_ro"
mkdir -p "$DOC_SB/libs" "$DOC_SB/configs"
cp "$ROOT/scripts/menu.sh" "$DOC_SB/"
cp "$ROOT/scripts/libs/doctor.sh" "$DOC_SB/libs/"
printf '#!/bin/sh\ntouch "%s/INIT_RAN"\n' "$DOC_SB" >"$DOC_SB/init.sh"
chmod +x "$DOC_SB/init.sh"
TMPDIR="$TMP/doc_tmp" sh "$DOC_SB/menu.sh" doctor >/dev/null 2>&1 || true
if [ ! -e "$DOC_SB/INIT_RAN" ] && [ ! -e "$DOC_SB/configs/ShellCrash.cfg" ]; then
    ok "crash doctor 在未初始化目录下严格只读（未触发 init.sh）"
else
    bad "crash doctor 产生了写入/初始化副作用"
fi

# 12g. task_cmd.sh 数值任务透传真实失败退出码
T_SB="$TMP/task_rc_sb"
mkdir -p "$T_SB/configs/task" "$T_SB/libs" "$T_SB/menus" "$T_SB/lang/chs" "$T_SB/task"
cp -R "$ROOT/scripts/libs/." "$T_SB/libs/"
cp -R "$ROOT/scripts/menus/." "$T_SB/menus/"
cp -R "$ROOT/scripts/lang/chs/." "$T_SB/lang/chs/"
: >"$T_SB/configs/command.env"
printf 'i18n=chs\n' >"$T_SB/configs/ShellCrash.cfg"
printf '901#false#fail_task\n' >"$T_SB/configs/task/task.user"
if CRASHDIR="$T_SB" TMPDIR="$TMP/task_rc_tmp" sh "$T_SB/menus/task_cmd.sh" 901 >/dev/null 2>&1; then
    bad "task_cmd.sh 数值任务失败时误返回 0"
else
    ok "task_cmd.sh 数值任务正确透传非零失败退出码"
fi

# 12h. 工作流治理与 R3 核验
if [ ! -e "$ROOT/.github/workflows/test.yaml" ] && [ ! -e "$ROOT/.github/workflows/release_new_version.yaml" ] && [ ! -e "$ROOT/.github/workflows/docker_readme_push.yaml" ] && [ -f "$ROOT/.github/workflows/ci.yml" ]; then
    ok "已移除遗留高危/失效工作流并新增 ci.yml 回归门禁"
else
    bad "工作流清理或 ci.yml 缺失"
fi
assert_yes "$ROOT/.github/workflows/core_easy_update.yaml" 'update_singbox_tar:' 'core_easy_update.yaml 含 singbox tar.gz 构建'
assert_yes "$ROOT/.github/workflows/bin_update.yml" 'bin/SHA256SUMS' 'bin_update.yml 生成 bin/SHA256SUMS 清单'
assert_yes "$ROOT/.github/workflows/bin_update.yml" 'ShellCrash@dev/\$\{devf\}' 'bin_update.yml 同步刷新 @dev 脚本包缓存'
assert_no "$ROOT/scripts/menus/9_upgrade.sh" '"4\) Clash"' '9_upgrade.sh 已移除停更的 Clash 旧内核选项'

echo '== 13. V4 实机全量审计复核回归（事务升级/备份恢复/空节点/Sing-BoxR筛选/菜单缺陷）=='
# 13a. setconfig 同值字节幂等性（同版本重装不改写 ShellCrash.cfg 字节与顺序）
CFG13="$TMP/idemp.cfg"
printf '#header\nfoo=bar\nalpha=1\n' >"$CFG13"
_h_before=$(sha256sum "$CFG13" | awk '{print $1}')
sh -c ". '$ROOT/scripts/libs/set_config.sh'; setconfig foo bar '$CFG13'"
_h_after=$(sha256sum "$CFG13" | awk '{print $1}')
[ "$_h_before" = "$_h_after" ] && ok "V4: setconfig 同值写入保持配置文件字节 100% 不变" || bad "V4: setconfig 同值改写了配置文件字节"

# 13b. apply_script_upgrade 故障注入：init.sh exit 34 完整回滚脚本、配置并清理新增文件
UPG_SB="$TMP/upg_sb"
mkdir -p "$UPG_SB/configs" "$UPG_SB/libs" "$UPG_SB/tmp"
printf '#!/bin/sh\necho old_start\n' >"$UPG_SB/start.sh"
printf '#!/bin/sh\necho old_menu\n' >"$UPG_SB/menu.sh"
printf '#!/bin/sh\nexit 0\n' >"$UPG_SB/init.sh"
printf '#!/bin/sh\n:\n' >"$UPG_SB/libs/get_config.sh"
printf 'versionsh_l=1.9.7-hardened.1\ncustom=keepme\n' >"$UPG_SB/configs/ShellCrash.cfg"
chmod +x "$UPG_SB/start.sh" "$UPG_SB/menu.sh" "$UPG_SB/init.sh"
_cfg_hash0=$(sha256sum "$UPG_SB/configs/ShellCrash.cfg" | awk '{print $1}')

# 构造“init.sh 改写配置并 exit 34，且包内含新增文件 extra_new.sh”的测试包
UPG_PKG="$TMP/upg_pkg_src"
mkdir -p "$UPG_PKG/libs"
printf '#!/bin/sh\necho new_start\n' >"$UPG_PKG/start.sh"
printf '#!/bin/sh\necho new_menu\n' >"$UPG_PKG/menu.sh"
printf '#!/bin/sh\necho mutated=1 >> "$CRASHDIR/configs/ShellCrash.cfg"\nexit 34\n' >"$UPG_PKG/init.sh"
printf '#!/bin/sh\n:\n' >"$UPG_PKG/libs/get_config.sh"
printf 'new_extra\n' >"$UPG_PKG/extra_new.sh"
tar -czf "$TMP/init_fail.tar.gz" -C "$UPG_PKG" .

if CRASHDIR="$UPG_SB" TMPDIR="$UPG_SB/tmp" sh -c ". '$ROOT/scripts/libs/set_config.sh'; apply_script_upgrade '$TMP/init_fail.tar.gz'"; then
    bad "V4: init.sh exit 34 时 apply_script_upgrade 不应返回 0"
else
    _cfg_hash1=$(sha256sum "$UPG_SB/configs/ShellCrash.cfg" | awk '{print $1}')
    if [ "$_cfg_hash0" = "$_cfg_hash1" ] && grep -q 'old_start' "$UPG_SB/start.sh" && [ ! -e "$UPG_SB/extra_new.sh" ]; then
        ok "V4: init.sh exit 34 触发完整回滚（配置字节不变、旧脚本恢复、新增文件已清理）"
    else
        bad "V4: init.sh exit 34 回滚不完整"
    fi
fi

# 13c. clash_modify.sh 空 proxies: [] 不生成空 '- ' 项，且 IPv6 DoH 在 YAML flow 列表加单引号
cat >"$TMP/empty_proxies.yaml" <<'EOF'
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies: [DIRECT]
rules:
  - MATCH,PROXY
EOF
sh -c '
    CRASHDIR="$1"
    TMPDIR="$1/tmp_ep"
    BINDIR="$1"
    mkdir -p "$TMPDIR"
    core_config="$2"
    crashcore=meta
    firewall_area=4; public_support=OFF
    dns_mod=mix; dns_protect=ON; dns_respect_rules=ON; hosts_opt=OFF
    dns_nameserver="https://[2001:db8::1]:44443/dns-query, 223.5.5.5"
    dns_proxy_server="https://[2001:db8::2]:44443/dns-query"
    dns_fallback="https://[2001:db8::3]:44443/dns-query"
    mix_port=7890; redir_port=7892; tproxy_port=7893; db_port=9999; dns_port=1053; routing_mark=7894
    . "$3/scripts/starts/clash_modify.sh"
    prepare_clash_base_config
    split_and_customize_yaml_parts
' _ "$TMP" "$TMP/empty_proxies.yaml" "$ROOT" 2>/dev/null
if [ ! -s "$TMP/tmp_ep/proxies.yaml" ] && grep -Fq "'https://[2001:db8::1]:44443/dns-query'" "$TMP/tmp_ep/dns.yaml"; then
    ok "V4: clash_modify.sh 空 proxies: [] 不生成非法空节点且 IPv6 DoH 已加单引号"
else
    bad "V4: clash_modify.sh 空 proxies 或 IPv6 DoH 处理失败"
fi

# 13d. Sing-BoxR include/exclude 置于 urltest 出站而非 providers[]，标准 singbox 明确拒绝，doh:// 归一化为 https
SB13="$TMP/sb13"
mkdir -p "$SB13/configs" "$SB13/libs" "$SB13/providers" "$SB13/rules/singbox_providers" "$SB13/tmp"
cp "$ROOT/scripts/libs/local_sub_convert.sh" "$SB13/libs/"
cp "$ROOT/rules/singbox_providers/ShellCrash_RS_Nano.json" "$SB13/rules/singbox_providers/"
for stub in web_get.sh web_get_bin.sh logger.sh; do printf 'logger(){ :; }\n' >"$SB13/libs/$stub"; done
printf 'ss://YWVzLTI1Ni1nY206cGFzcw@1.2.3.4:8388#KeepNode\nss://YWVzLTI1Ni1nY206cGFzcw@5.6.7.8:8388#DropNode\n' >"$SB13/providers/src.txt"
printf 'provider_temp_singbox=ShellCrash_RS_Nano.json\n' >"$SB13/configs/ShellCrash.cfg"
printf 'sub1 ./providers/src.txt 3 12 auto #Drop #Keep\n' >"$SB13/configs/providers.cfg"

# 标准版 singbox 必须明确返回非零
if CRASHDIR="$SB13" BINDIR="$SB13" TMPDIR="$SB13/tmp" crashcore=singbox LOCAL_SUB_SKIP_CORE_TEST=1 \
   sh -c ". '$SB13/libs/local_sub_convert.sh'; local_build_singbox_config" >/dev/null 2>&1; then
    bad "V4: 标准版 singbox 应拒绝 Sing-BoxR provider 模板合成"
else
    ok "V4: 标准版 singbox 提前拒绝不兼容的 Sing-BoxR provider 模板"
fi

# Sing-BoxR 必须将 include/exclude 写在 outbounds(urltest) 而非 providers[]
if CRASHDIR="$SB13" BINDIR="$SB13" TMPDIR="$SB13/tmp" crashcore=singboxr LOCAL_SUB_SKIP_CORE_TEST=1 \
   sh -c ". '$SB13/libs/local_sub_convert.sh'; rm -rf \"\$TMPDIR/providers\"; local_build_singbox_config" >/dev/null 2>&1; then
    ok "V4: Sing-BoxR 带 include/exclude 本地转换执行成功"
else
    bad "V4: Sing-BoxR 带 include/exclude 本地转换失败"
fi
assert_no "$ROOT/scripts/libs/local_sub_convert.sh" '"exclude":.*\\n.*health_check|"include":.*\\n.*health_check' 'V4: local_sub_convert.sh 不再向 providers[] 写入未知 include/exclude'
assert_yes "$ROOT/scripts/libs/local_sub_convert.sh" 'for _ext in yaml txt json;' 'V4: local_fallback_cached_provider 支持复用 .json 缓存'

_sb_doh=$(sh -c ". '$ROOT/scripts/starts/singbox_modify.sh' >/dev/null 2>&1 || true; parse_singbox_dns 'doh://[2001:db8::1]:44443/dns-query'")
case "$_sb_doh" in
    *'"type": "https"'*'"server": "2001:db8::1"'*'"server_port": 44443'*'"path": "/dns-query"'*)
        ok "V4: parse_singbox_dns 将 doh:// 归一化为 https 并保留 IPv6/端口/path" ;;
    *) bad "V4: parse_singbox_dns 输出异常: $_sb_doh" ;;
esac

# 13e. 备份恢复、面板升级、任务错误码、端口/CIDR 校验与全部菜单缺陷静态核验
assert_yes "$ROOT/scripts/menus/2_settings.sh" 'safe_tar_check "\$BACK_TAR"' 'V4: 设置恢复前先校验备份归档与 ShellCrash.cfg'
assert_yes "$ROOT/scripts/menus/2_settings.sh" '_tp_port=' 'V4: 端口冲突检查覆盖 tproxy_port (redir_port+1)'
assert_yes "$ROOT/scripts/menus/9_upgrade.sh" 'if getscripts; then' 'V4: setscripts 校验 getscripts 返回码，失败不误报成功'
assert_yes "$ROOT/scripts/menus/9_upgrade.sh" 'safe_tar_check "\$_db_tar"' 'V4: 面板安装先暂存校验再替换旧 ui'
assert_no "$ROOT/scripts/menus/9_upgrade.sh" 'UPG_SOURCE_SWITCH_STABLE|UPG_SOURCE_SWITCH_MASTER' 'V4: setserver 已移除误导性 stable/master 菜单项'
assert_yes "$ROOT/scripts/menus/9_upgrade.sh" '_custom_url' 'V4: setserver 自定义源取消不污染会话 update_url'
assert_yes "$ROOT/scripts/menus/8_tools.sh" '_new_device_name' 'V4: device_name 空回车取消不污染会话显示'
assert_yes "$ROOT/scripts/menus/ddns.sh" '\[ "\$num" -eq \$\(\(nr \+ 1\)\) \]' 'V4: ddns.sh 拒绝越界序号'
assert_yes "$ROOT/scripts/menus/dns.sh" 'a\[i\]>255' 'V4: dns.sh 严格校验 IPv4 八位组 0-255'
assert_yes "$ROOT/scripts/menus/dns.sh" 'DNS_FAKEIP_CONFLICT_BLOCK' 'V4: dns.sh 保存前拦截与本机接口重叠的 fake-ip 段'
assert_yes "$ROOT/scripts/menus/task_cmd.sh" 'return "\$_mmdb_fail"' 'V4: task 113 update_mmdb 透传下载失败状态'
assert_yes "$ROOT/scripts/menu.sh" 'MENU_CLI_DOCTOR' 'V4: menu.sh -h doctor 说明已国际化'

for lf in dns.lang menu.lang 2_settings.lang; do
    _miss=$(awk -F= '/^[A-Za-z0-9_]+=/ {k[$1]=1} FILENAME==ARGV[2] && /^[A-Za-z0-9_]+=/ {delete k[$1]} END {for (x in k) print x}' \
        "$ROOT/scripts/lang/chs/$lf" "$ROOT/scripts/lang/en/$lf")
    if [ -z "$_miss" ]; then
        ok "V4: lang/en/$lf 与 lang/chs/$lf 键 100% 同步"
    else
        bad "V4: lang/en/$lf 缺少键: $(echo "$_miss" | tr '\n' ' ')"
    fi
done

# 13f. V4.1 深度自审回归：stop 失败中止升级、SIGKILL .upg_txn 自愈、同版本覆盖配置字节不变、b64json 归一化、POSIX sh 缺失 command.env 兼容
UPG41="$TMP/upg41"
mkdir -p "$UPG41/inst/configs" "$UPG41/inst/libs" "$UPG41/pkg/libs" "$UPG41/tmp"
cp "$ROOT/scripts/libs/set_config.sh" "$UPG41/inst/libs/set_config.sh"
cp "$ROOT/scripts/libs/get_config.sh" "$UPG41/inst/libs/get_config.sh"
cp "$ROOT/scripts/libs/set_config.sh" "$UPG41/pkg/libs/set_config.sh"
cp "$ROOT/scripts/libs/get_config.sh" "$UPG41/pkg/libs/get_config.sh"
cat > "$UPG41/inst/configs/ShellCrash.cfg" <<'EOF'
#ShellCrash配置文件，不明勿动！
versionsh_l=1.9.7-hardened.2
crashcore=meta
my_alias=crash
EOF
printf '1.9.7-hardened.2\n' > "$UPG41/inst/version"
printf '#!/bin/sh\nexit 0\n' > "$UPG41/inst/menu.sh"
printf '#!/bin/sh\nexit 0\n' > "$UPG41/inst/init.sh"
printf '#!/bin/sh\n[ "$1" = "stop" ] && exit 19\nexit 0\n' > "$UPG41/inst/start.sh"
chmod +x "$UPG41/inst/start.sh" "$UPG41/inst/menu.sh" "$UPG41/inst/init.sh"

printf '1.9.7-hardened.2\n' > "$UPG41/pkg/version"
printf '#!/bin/sh\n# new\nexit 0\n' > "$UPG41/pkg/menu.sh"
printf '#!/bin/sh\nexit 0\n' > "$UPG41/pkg/init.sh"
printf '#!/bin/sh\nexit 0\n' > "$UPG41/pkg/start.sh"
printf 'extra\n' > "$UPG41/pkg/brand_new.txt"
tar -czf "$UPG41/pkg.tar.gz" -C "$UPG41/pkg" .

_sha_pre=$(sha256sum "$UPG41/inst/configs/ShellCrash.cfg" | awk '{print $1}')
if CRASHDIR="$UPG41/inst" TMPDIR="$UPG41/tmp" sh -c ". '$UPG41/inst/libs/set_config.sh'; apply_script_upgrade '$UPG41/pkg.tar.gz'" >/dev/null 2>&1; then
    bad "V4.1: start.sh stop 返回非零时 apply_script_upgrade 应立即中止"
else
    _sha_post=$(sha256sum "$UPG41/inst/configs/ShellCrash.cfg" | awk '{print $1}')
    if [ "$_sha_pre" = "$_sha_post" ] && [ ! -e "$UPG41/inst/brand_new.txt" ] && ! grep -q '# new' "$UPG41/inst/menu.sh"; then
        ok "V4.1: start.sh stop 失败时立即中止切换且旧文件与配置 100% 未动"
    else
        bad "V4.1: start.sh stop 失败后仍污染了现有目录"
    fi
fi

# 同版本正常覆盖：修复 start.sh stop=0，使用真实 init.sh 验证 ShellCrash.cfg 字节完全不变
cp "$ROOT/scripts/init.sh" "$UPG41/pkg/init.sh"
cp "$ROOT/scripts/libs/set_profile.sh" "$UPG41/pkg/libs/set_profile.sh"
mkdir -p "$UPG41/inst/starts" "$UPG41/pkg/starts" "$UPG41/pkg/menus"
for f in bfstart.sh afstart.sh fw_stop.sh fw_ipv6_watch.sh; do printf '#!/bin/sh\nexit 0\n' > "$UPG41/pkg/starts/$f"; done
for f in task_cmd.sh bot_tg.sh; do printf '#!/bin/sh\nexit 0\n' > "$UPG41/pkg/menus/$f"; done
printf '#!/bin/sh\nexit 0\n' > "$UPG41/inst/start.sh"
chmod +x "$UPG41/inst/start.sh"
cat > "$UPG41/inst/configs/ShellCrash.cfg" <<'EOF'
#ShellCrash配置文件，不明勿动！
versionsh_l=1.9.7-hardened.2
start_old=ON
firewall_mod=nftables
crashcore=meta
my_alias=crash
EOF
_sha_same_pre=$(sha256sum "$UPG41/inst/configs/ShellCrash.cfg" | awk '{print $1}')
tar -czf "$UPG41/same.tar.gz" -C "$UPG41/pkg" .
if CRASHDIR="$UPG41/inst" TMPDIR="$UPG41/tmp" sh -c ". '$UPG41/inst/libs/set_config.sh'; apply_script_upgrade '$UPG41/same.tar.gz'" >/dev/null 2>&1; then
    _sha_same_post=$(sha256sum "$UPG41/inst/configs/ShellCrash.cfg" | awk '{print $1}')
    if [ "$_sha_same_pre" = "$_sha_same_post" ]; then
        ok "V4.1: 同版本覆盖升级后 ShellCrash.cfg SHA-256 字节 100% 不变"
    else
        bad "V4.1: 同版本覆盖升级改写了 ShellCrash.cfg ($_sha_same_pre != $_sha_same_post)"
    fi
else
    bad "V4.1: 同版本覆盖升级执行失败"
fi

# 模拟 SIGKILL 中断遗留 .upg_txn/pending，下次加载 get_config.sh 自动自愈
mkdir -p "$UPG41/inst/.upg_txn/bak/configs"
cp -f "$UPG41/inst/configs/ShellCrash.cfg" "$UPG41/inst/.upg_txn/bak/configs/ShellCrash.cfg"
printf 'versionsh_l=corrupted-half-upgrade\n' > "$UPG41/inst/configs/ShellCrash.cfg"
printf 'orphan_new_file.txt\n' > "$UPG41/inst/.upg_txn/newlist"
printf 'leftover\n' > "$UPG41/inst/orphan_new_file.txt"
printf '0\n' > "$UPG41/inst/.upg_txn/was_running"
: > "$UPG41/inst/.upg_txn/pending"
# 同时故意删除 command.env 验证 POSIX sh 下 get_config.sh 不因缺失 command.env 退出
rm -f "$UPG41/inst/configs/command.env"
if CRASHDIR="$UPG41/inst" sh -c ". '$UPG41/inst/libs/get_config.sh'" >/dev/null 2>&1; then
    _sha_rec=$(sha256sum "$UPG41/inst/configs/ShellCrash.cfg" | awk '{print $1}')
    if [ "$_sha_rec" = "$_sha_same_pre" ] && [ ! -e "$UPG41/inst/orphan_new_file.txt" ] && [ ! -d "$UPG41/inst/.upg_txn" ]; then
        ok "V4.1: SIGKILL 遗留 .upg_txn 在下次加载 get_config.sh 时自动字节级回滚自愈（且缺失 command.env 不中断 POSIX sh）"
    else
        bad "V4.1: .upg_txn 自愈后文件或配置未完全恢复"
    fi
else
    bad "V4.1: get_config.sh 在缺失 command.env 或执行 .upg_txn 自愈时异常退出"
fi

# b64json 订阅归一化核验
printf '%s' '{"outbounds":[{"type":"socks","tag":"N1","server":"198.51.100.9","server_port":1080}]}' | base64 | tr -d '\n' > "$UPG41/b64json.raw"
if CRASHDIR="$SB13" TMPDIR="$UPG41/tmp" sh -c ". '$ROOT/scripts/libs/local_sub_convert.sh'; local_normalize_sub_file '$UPG41/b64json.raw' '$UPG41/out_sub' && [ \"\$LOCAL_SUB_FMT\" = 'json' ] && [ -s '$UPG41/out_sub.json' ]" >/dev/null 2>&1; then
    ok "V4.1: local_normalize_sub_file 正确识别并解码 Base64 封装的 Sing-Box JSON (b64json)"
else
    bad "V4.1: local_normalize_sub_file 未能识别 b64json"
fi

echo '== 14. V5 真实 systemd 验收复现问题回归（运行态升级防自回滚 / 单元 ExecStart / 旧版 107 恢复 / 快速启动）=='

# 14a. 运行态升级：新 start.sh 与无环境变量的 systemd 钩子（env -i 加载 get_config.sh）均不得将正在进行的升级误判为中断回滚
V5="$TMP/v5_run_upg"
mkdir -p "$V5/inst/configs" "$V5/inst/libs" "$V5/inst/starts" "$V5/pkg/libs" "$V5/pkg/starts" "$V5/pkg/menus" "$V5/tmp" "$V5/bin"
cp "$ROOT/scripts/libs/set_config.sh" "$V5/inst/libs/set_config.sh"
cp "$ROOT/scripts/libs/get_config.sh" "$V5/inst/libs/get_config.sh"
cp "$ROOT/scripts/libs/set_profile.sh" "$V5/inst/libs/set_profile.sh"
cp "$ROOT/scripts/libs/set_config.sh" "$V5/pkg/libs/set_config.sh"
cp "$ROOT/scripts/libs/get_config.sh" "$V5/pkg/libs/get_config.sh"
cp "$ROOT/scripts/libs/set_profile.sh" "$V5/pkg/libs/set_profile.sh"
cp "$ROOT/scripts/init.sh" "$V5/pkg/init.sh"
cp "$ROOT/scripts/init.sh" "$V5/inst/init.sh"
for f in bfstart.sh afstart.sh fw_stop.sh fw_ipv6_watch.sh; do printf '#!/bin/sh\nexit 0\n' > "$V5/pkg/starts/$f"; done
for f in task_cmd.sh bot_tg.sh; do printf '#!/bin/sh\nexit 0\n' > "$V5/pkg/menus/$f"; done

# 伪造 pidof 基于状态文件判断 CrashCore 运行态，同时放置可执行 $TMPDIR/CrashCore 以触发真实存活校验
cat > "$V5/bin/pidof" <<EOF
#!/bin/sh
[ "\$1" = "CrashCore" ] && [ -f "$V5/tmp/core.alive" ] && { echo 42424; exit 0; }
exit 1
EOF
printf '#!/bin/sh\nexit 0\n' > "$V5/tmp/CrashCore"
chmod +x "$V5/bin/pidof" "$V5/tmp/CrashCore"
: > "$V5/tmp/core.alive"

cat > "$V5/inst/configs/ShellCrash.cfg" <<'EOF'
#ShellCrash配置文件，不明勿动！
versionsh_l=1.9.7-hardened.2-audit-before
start_old=ON
firewall_mod=nftables
crashcore=meta
my_alias=crash
EOF
printf '1.9.7-hardened.2-audit-before\n' > "$V5/inst/version"
printf '#!/bin/sh\n# old-menu\nexit 0\n' > "$V5/inst/menu.sh"
cat > "$V5/inst/start.sh" <<EOF
#!/bin/sh
# old-start
. "\$CRASHDIR/libs/get_config.sh"
[ "\$1" = "stop" ] && rm -f "$V5/tmp/core.alive"
[ "\$1" = "start" ] && : > "$V5/tmp/core.alive"
exit 0
EOF
chmod +x "$V5/inst/start.sh" "$V5/inst/menu.sh" "$V5/inst/init.sh"

printf '1.9.7-hardened.3\n' > "$V5/pkg/version"
printf '#!/bin/sh\n# new-menu-v3\nexit 0\n' > "$V5/pkg/menu.sh"
cat > "$V5/pkg/start.sh" <<EOF
#!/bin/sh
# new-start-v3
. "\$CRASHDIR/libs/get_config.sh"
if [ "\$1" = "start" ]; then
    # 模拟 systemd PID 1 通过 D-Bus 在完全清洁环境中执行 ExecStartPre/Post (bfstart/afstart 加载 get_config.sh)
    env -i PATH="\$PATH" CRASHDIR="\$CRASHDIR" sh -c '. "\$CRASHDIR/libs/get_config.sh"' || exit 1
    : > "$V5/tmp/core.alive"
fi
[ "\$1" = "stop" ] && rm -f "$V5/tmp/core.alive"
exit 0
EOF
chmod +x "$V5/pkg/start.sh" "$V5/pkg/menu.sh" "$V5/pkg/init.sh"
tar -czf "$V5/upg_v3.tar.gz" -C "$V5/pkg" .

if PATH="$V5/bin:$PATH" CRASHDIR="$V5/inst" TMPDIR="$V5/tmp" sh -c ". '$V5/inst/libs/set_config.sh'; apply_script_upgrade '$V5/upg_v3.tar.gz'"; then
    _v_after=$(tr -d '\r\n ' < "$V5/inst/version")
    if [ "$_v_after" = "1.9.7-hardened.3" ] && \
       grep -q '^versionsh_l=1.9.7-hardened.3$' "$V5/inst/configs/ShellCrash.cfg" && \
       grep -q '# new-start-v3' "$V5/inst/start.sh" && \
       [ ! -e "$V5/inst/.upg_txn" ] && [ -f "$V5/tmp/core.alive" ]; then
        ok "V5: 运行态升级不再被自身或 systemd 清洁环境钩子误回滚，版本与 start.sh 真实更新且核心恢复运行"
    else
        bad "V5: 运行态升级返回 0 但状态不符 (version=$_v_after)"
    fi
else
    bad "V5: 正常运行态升级返回非零"
fi

# 14b. 运行态升级后核心未存活（即使 start.sh 退出 0）：必须判定失败、完整回滚并返回非零
printf '1.9.7-hardened.4-broken\n' > "$V5/pkg/version"
cat > "$V5/pkg/start.sh" <<EOF
#!/bin/sh
# broken-start-no-core
. "\$CRASHDIR/libs/get_config.sh"
rm -f "$V5/tmp/core.alive"
exit 0
EOF
tar -czf "$V5/upg_broken.tar.gz" -C "$V5/pkg" .
if PATH="$V5/bin:$PATH" CRASHDIR="$V5/inst" TMPDIR="$V5/tmp" sh -c ". '$V5/inst/libs/set_config.sh'; apply_script_upgrade '$V5/upg_broken.tar.gz'" >/dev/null 2>&1; then
    bad "V5: 新版启动后核心未存活却仍返回 0"
else
    _v_rb=$(tr -d '\r\n ' < "$V5/inst/version")
    if [ "$_v_rb" = "1.9.7-hardened.3" ] && grep -q '# new-start-v3' "$V5/inst/start.sh" && [ -f "$V5/tmp/core.alive" ]; then
        ok "V5: 新版启动后核心未存活时返回非零并完整回滚至上一可用版本且恢复运行"
    else
        bad "V5: 核心未存活回滚后状态异常 (version=$_v_rb)"
    fi
fi

# 14c. systemd 单元默认路径与 init.sh 展开命令校验
assert_yes "$ROOT/scripts/starts/shellcrash.service" '^ExecStart=/tmp/ShellCrash/CrashCore -d /etc/ShellCrash -f /tmp/ShellCrash/config\.yaml$' 'V5: shellcrash.service 默认 ExecStart 指向 /tmp/ShellCrash/CrashCore 与 Mihomo 参数'
assert_yes "$ROOT/scripts/init.sh" '_installed_systemd_unit=' 'V5: init.sh 在解析 TMPDIR/BINDIR 后同步改写 systemd 单元 ExecStart 并执行 daemon-reload'

# 14d. 旧版 107 风格（1.9.6alpha1 菜单直接 source init.sh 且 $PID 非空）升级后自动恢复运行
V5_107="$TMP/v5_legacy107"
mkdir -p "$V5_107/configs" "$V5_107/task"
cp -a "$ROOT/scripts"/. "$V5_107/"
cp "$ROOT/version" "$V5_107/version"
cat > "$V5_107/configs/ShellCrash.cfg" <<'EOF'
#ShellCrash配置文件，不明勿动！
versionsh_l=1.9.6alpha1
crashcore=meta
start_old=ON
firewall_mod=nftables
my_alias=crash
EOF
printf 'BINDIR=%s\nTMPDIR=%s/tmp\nCOMMAND="old"\n' "$V5_107" "$V5_107" > "$V5_107/configs/command.env"
cat > "$V5_107/start.sh" <<EOF
#!/bin/sh
[ "\$1" = "start" ] && : > "$V5_107/restarted.ok"
exit 0
EOF
chmod +x "$V5_107/start.sh"
if CRASHDIR="$V5_107" __IS_MODULE_9_UPGRADE_LOADED=1 PID=9876 sh -c '. "$CRASHDIR/init.sh" >/dev/null'; then
    if [ -f "$V5_107/configs/directories.env" ] && [ -f "$V5_107/restarted.ok" ]; then
        ok "V5: 旧版 1.9.6alpha1 (107 布局) 运行态 source init.sh 升级后自动迁移目录并拉起服务"
    else
        bad "V5: 旧版 1.9.6alpha1 升级后未迁移 directories.env 或未自动重启服务"
    fi
else
    bad "V5: 旧版 1.9.6alpha1 升级执行 init.sh 返回非零"
fi

# 14e. 仅 lo 网卡环境 getlanip 零等待返回 + 后台日志任务关闭继承管道不阻塞调用者
V5_FAST="$TMP/v5_fast"
mkdir -p "$V5_FAST/bin" "$V5_FAST/tmp"
cat > "$V5_FAST/bin/ip" <<'EOF'
#!/bin/sh
case "$*" in
    "-o link show"*) echo "1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000" ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$V5_FAST/bin/ip"
_t0=$(date +%s)
_out=$(PATH="$V5_FAST/bin:$PATH" CRASHDIR="$ROOT/scripts" TMPDIR="$V5_FAST/tmp" sh -c '
    . "$CRASHDIR/libs/logger.sh"
    . "$CRASHDIR/starts/fw_getlanip.sh"
    getlanip
    { sleep 5; logger "bg-done"; } >/dev/null 2>&1 </dev/null &
    printf "%s" "$host_ipv4"
')
_t1=$(date +%s)
if [ $((_t1 - _t0)) -le 2 ] && [ -n "$_out" ]; then
    ok "V5: 仅 lo 环境 getlanip 与后台延迟日志耗时 $((_t1 - _t0))s 立即返回，不再阻塞 25s"
else
    bad "V5: getlanip 或后台任务耗时过长 ($((_t1 - _t0))s)"
fi

for lf in 9_upgrade.lang; do
    _miss=$(awk -F= '/^[A-Za-z0-9_]+=/ {k[$1]=1} FILENAME==ARGV[2] && /^[A-Za-z0-9_]+=/ {delete k[$1]} END {for (x in k) print x}' \
        "$ROOT/scripts/lang/chs/$lf" "$ROOT/scripts/lang/en/$lf")
    if [ -z "$_miss" ]; then
        ok "V5: lang/en/$lf 与 lang/chs/$lf 键 100% 同步"
    else
        bad "V5: lang/en/$lf 缺少键: $(echo "$_miss" | tr '\n' ' ')"
    fi
done

echo '== 15. V6 复测阻断项与静态审查补充项回归（V4->V6 运行态升级 / 回滚快照保全 / 引号 Sing-Box / ELF API 健康检查）=='

# 15a. 精确复现原版 V4 (1.9.7-hardened.2: 写 0 字节空 pending 且无 _SC_UPG_ACTIVE) 在运行态升级到 V6 (1.9.7-hardened.4)
V6="$TMP/v6_from_v4"
mkdir -p "$V6/inst/configs" "$V6/inst/libs" "$V6/inst/starts" "$V6/pkg/libs" "$V6/pkg/starts" "$V6/pkg/menus" "$V6/tmp" "$V6/bin"
cp "$ROOT/scripts/libs/get_config.sh" "$V6/inst/libs/get_config.sh"
cp "$ROOT/scripts/libs/set_profile.sh" "$V6/inst/libs/set_profile.sh"
cp "$ROOT/scripts/libs/set_config.sh" "$V6/pkg/libs/set_config.sh"
cp "$ROOT/scripts/libs/get_config.sh" "$V6/pkg/libs/get_config.sh"
cp "$ROOT/scripts/libs/set_profile.sh" "$V6/pkg/libs/set_profile.sh"
cp "$ROOT/scripts/init.sh" "$V6/pkg/init.sh"
for f in bfstart.sh afstart.sh fw_stop.sh fw_ipv6_watch.sh; do printf '#!/bin/sh\nexit 0\n' > "$V6/pkg/starts/$f"; done
for f in task_cmd.sh bot_tg.sh; do printf '#!/bin/sh\nexit 0\n' > "$V6/pkg/menus/$f"; done

# 构造精确复刻 V4 (56a9ce6) 的 set_config.sh：写 0 字节空 pending、不设 _SC_UPG_ACTIVE、子 shell 调 init.sh 再调 start.sh start
cat > "$V6/inst/libs/set_config.sh" <<'EOF'
safe_tar_check() { tar -tzf "$1" >/dev/null 2>&1; }
recover_interrupted_upgrade() {
    _riu_txn="$CRASHDIR/.upg_txn"
    [ -f "$_riu_txn/pending" ] || return 0
    if [ -d "$_riu_txn/bak" ]; then
        ( cd "$_riu_txn/bak" && find . -type f | sed 's|^\./||' ) | while IFS= read -r _rel; do
            [ -n "$_rel" ] || continue
            mkdir -p "$CRASHDIR/$(dirname "$_rel")"
            cp -f "$_riu_txn/bak/$_rel" "$CRASHDIR/$_rel" 2>/dev/null
        done
    fi
    _riu_run=$(cat "$_riu_txn/was_running" 2>/dev/null)
    rm -rf "$_riu_txn"
    [ "$_riu_run" = "1" ] && "$CRASHDIR"/start.sh start >/dev/null 2>&1 || true
    return 0
}
apply_script_upgrade() {
    _asu_tar="$1"
    _asu_stage="$TMPDIR/upg_stage.$$"
    _asu_txn="$CRASHDIR/.upg_txn"
    _asu_bak="$_asu_txn/bak"
    _asu_list="$_asu_txn/newlist"
    rm -rf "$_asu_stage" "$_asu_txn"
    mkdir -p "$_asu_stage" "$_asu_bak" || return 1
    tar -zxf "$_asu_tar" -C "$_asu_stage" || return 1
    _asu_was_running=0
    [ -n "$(pidof CrashCore 2>/dev/null)" ] && _asu_was_running=1
    printf '%s\n' "$_asu_was_running" >"$_asu_txn/was_running"
    "$CRASHDIR"/start.sh stop >/dev/null 2>&1 || return 1
    ( cd "$_asu_stage" && find . -type f | sed 's|^\./||' ) >"$_asu_list"
    while IFS= read -r _rel; do
        [ -n "$_rel" ] && [ -e "$CRASHDIR/$_rel" ] && mkdir -p "$_asu_bak/$(dirname "$_rel")" && cp -f "$CRASHDIR/$_rel" "$_asu_bak/$_rel"
    done <"$_asu_list"
    for _cfg in configs/ShellCrash.cfg configs/command.env configs/directories.env; do
        [ -f "$CRASHDIR/$_cfg" ] && mkdir -p "$_asu_bak/configs" && cp -f "$CRASHDIR/$_cfg" "$_asu_bak/$_cfg"
    done
    : >"$_asu_txn/pending"
    _asu_ok=0
    if cp -af "$_asu_stage"/. "$CRASHDIR"/ 2>/dev/null && \
       ( CRASHDIR="$CRASHDIR" sh "$CRASHDIR"/init.sh >/dev/null ) && \
       { [ "$_asu_was_running" = 0 ] || "$CRASHDIR"/start.sh start >/dev/null 2>&1; }; then
        _asu_ok=1
    fi
    if [ "$_asu_ok" = 1 ]; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 0
    fi
    recover_interrupted_upgrade
    return 1
}
EOF

cat > "$V6/bin/pidof" <<EOF
#!/bin/sh
[ "\$1" = "CrashCore" ] && [ -f "$V6/tmp/core.alive" ] && { echo 51515; exit 0; }
exit 1
EOF
chmod +x "$V6/bin/pidof"
: > "$V6/tmp/core.alive"

cat > "$V6/inst/configs/ShellCrash.cfg" <<'EOF'
#ShellCrash配置文件，不明勿动！
versionsh_l=1.9.7-hardened.2
start_old=ON
firewall_mod=nftables
crashcore=meta
my_alias=crash
EOF
printf '1.9.7-hardened.2\n' > "$V6/inst/version"
printf '#!/bin/sh\nexit 0\n' > "$V6/inst/menu.sh"
printf '#!/bin/sh\nexit 0\n' > "$V6/inst/init.sh"
cat > "$V6/inst/start.sh" <<EOF
#!/bin/sh
# v4-old-start
. "\$CRASHDIR/libs/get_config.sh"
[ "\$1" = "stop" ] && rm -f "$V6/tmp/core.alive"
[ "\$1" = "start" ] && : > "$V6/tmp/core.alive"
exit 0
EOF
chmod +x "$V6/inst/start.sh" "$V6/inst/menu.sh" "$V6/inst/init.sh"

printf '1.9.7-hardened.4\n' > "$V6/pkg/version"
printf '#!/bin/sh\nexit 0\n' > "$V6/pkg/menu.sh"
cat > "$V6/pkg/start.sh" <<EOF
#!/bin/sh
# v6-new-start
. "\$CRASHDIR/libs/get_config.sh"
if [ "\$1" = "start" ]; then
    env -i PATH="\$PATH" CRASHDIR="\$CRASHDIR" sh -c '. "\$CRASHDIR/libs/get_config.sh"' || exit 1
    : > "$V6/tmp/core.alive"
fi
[ "\$1" = "stop" ] && rm -f "$V6/tmp/core.alive"
exit 0
EOF
chmod +x "$V6/pkg/start.sh" "$V6/pkg/menu.sh" "$V6/pkg/init.sh"
tar -czf "$V6/v6_pkg.tar.gz" -C "$V6/pkg" .

if PATH="$V6/bin:$PATH" CRASHDIR="$V6/inst" TMPDIR="$V6/tmp" sh -c ". '$V6/inst/libs/set_config.sh'; apply_script_upgrade '$V6/v6_pkg.tar.gz'"; then
    _v6_obs=$(tr -d '\r\n ' < "$V6/inst/version")
    if [ "$_v6_obs" = "1.9.7-hardened.4" ] && \
       grep -q '^versionsh_l=1.9.7-hardened.4$' "$V6/inst/configs/ShellCrash.cfg" && \
       grep -q '# v6-new-start' "$V6/inst/start.sh" && \
       [ ! -e "$V6/inst/.upg_txn" ] && [ -f "$V6/tmp/core.alive" ]; then
        ok "V6: 原版 V4 (1.9.7-hardened.2 空 pending) 运行态直升 1.9.7-hardened.4 落盘成功且不再静默回滚"
    else
        bad "V6: V4->V6 运行态升级后版本或文件未落盘 (version=$_v6_obs)"
    fi
else
    bad "V6: V4->V6 运行态升级返回非零"
fi

# 15b. 回滚阶段若旧服务重启也失败：必须保留 .upg_txn/bak 恢复资料（转为 rollback_failed）并返回非零
V6_RB="$TMP/v6_rb_keep"
mkdir -p "$V6_RB/inst/.upg_txn/bak/configs" "$V6_RB/inst/configs" "$V6_RB/inst/libs" "$V6_RB/tmp"
cp "$ROOT/scripts/libs/set_config.sh" "$V6_RB/inst/libs/set_config.sh"
printf 'versionsh_l=1.9.7-hardened.3\n' > "$V6_RB/inst/.upg_txn/bak/configs/ShellCrash.cfg"
printf 'versionsh_l=broken\n' > "$V6_RB/inst/configs/ShellCrash.cfg"
printf '1\n' > "$V6_RB/inst/.upg_txn/was_running"
printf '99999999\n' > "$V6_RB/inst/.upg_txn/pending"
printf '#!/bin/sh\nexit 55\n' > "$V6_RB/inst/start.sh"
chmod +x "$V6_RB/inst/start.sh"
if CRASHDIR="$V6_RB/inst" TMPDIR="$V6_RB/tmp" sh -c ". '$V6_RB/inst/libs/set_config.sh'; recover_interrupted_upgrade" >/dev/null 2>&1; then
    bad "V6: 回滚阶段重启失败时 recover_interrupted_upgrade 不应返回 0"
else
    if [ -f "$V6_RB/inst/.upg_txn/bak/configs/ShellCrash.cfg" ] && \
       [ -f "$V6_RB/inst/.upg_txn/rollback_failed" ] && \
       [ ! -f "$V6_RB/inst/.upg_txn/pending" ]; then
        ok "V6: 回滚恢复失败时返回非零并完整保留 .upg_txn/bak 快照资料（标记 rollback_failed）"
    else
        bad "V6: 回滚失败时误删了 .upg_txn/bak 恢复资料"
    fi
fi

# 15c. 带单引号/双引号的 crashcore='singboxr' 与旧版 clashcore='singbox' 在 init.sh 中均正确生成 sing-box 启动参数
for _sb_line in "crashcore='singboxr'" 'crashcore="singbox"' "clashcore='singboxr'"; do
    V6_SB="$TMP/v6_sb_$(echo "$_sb_line" | tr -dc 'a-z')"
    mkdir -p "$V6_SB/configs"
    cp -a "$ROOT/scripts"/. "$V6_SB/"
    cp "$ROOT/version" "$V6_SB/version"
    printf '#ShellCrash配置文件，不明勿动！\n%s\nstart_old=ON\nfirewall_mod=nftables\nmy_alias=crash\n' "$_sb_line" > "$V6_SB/configs/ShellCrash.cfg"
    CRASHDIR="$V6_SB" sh "$V6_SB/init.sh" >/dev/null 2>&1
    if grep -q 'CrashCore run -D \$BINDIR -C \$TMPDIR/jsons' "$V6_SB/configs/command.env"; then
        ok "V6: init.sh 正确识别 $_sb_line 并生成 Sing-Box 启动命令"
    else
        bad "V6: init.sh 未识别 $_sb_line ($(cat "$V6_SB/configs/command.env" 2>/dev/null))"
    fi
done

# 15d. 真实 ELF 核心存在但控制器 API 未响应时，_upg_check_service_ready 必须判定失败
V6_ELF="$TMP/v6_elf_api"
mkdir -p "$V6_ELF/inst/configs" "$V6_ELF/tmp" "$V6_ELF/bin"
printf 'db_port=59991\n' > "$V6_ELF/inst/configs/ShellCrash.cfg"
printf '\177ELFfakebinary' > "$V6_ELF/tmp/CrashCore"
printf '#!/bin/sh\necho 12345\nexit 0\n' > "$V6_ELF/bin/pidof"
# 用快速返回非零的 curl 替身模拟控制器端口未监听，使 8 次重试快速失败? 这里只用 1 次? 不，直接让 wget/curl 返回失败则循环 8s，改用 sleep 替身瞬时完成！
printf '#!/bin/sh\nexit 0\n' > "$V6_ELF/bin/sleep"
printf '#!/bin/sh\nexit 7\n' > "$V6_ELF/bin/curl"
chmod +x "$V6_ELF/bin/pidof" "$V6_ELF/bin/sleep" "$V6_ELF/bin/curl"
if PATH="$V6_ELF/bin:$PATH" CRASHDIR="$V6_ELF/inst" TMPDIR="$V6_ELF/tmp" sh -c ". '$ROOT/scripts/libs/set_config.sh'; _upg_check_service_ready" >/dev/null 2>&1; then
    bad "V6: 真实 ELF 核心控制器 API 无响应时 _upg_check_service_ready 不应返回 0"
else
    ok "V6: 真实 ELF 核心进程存活但控制器 API 未响应时准确拦截并返回非零"
fi

echo ''
if [ "$FAIL" -eq 0 ]; then
    printf '\033[32mV2/V3/V4/V5/V6 全面安全、逻辑与真实 systemd 验收回归测试全部通过\033[0m\n'
else
    printf '\033[31mV2/V3/V4/V5/V6 审计回归测试失败 %d 项\033[0m\n' "$FAIL"
    exit 1
fi
