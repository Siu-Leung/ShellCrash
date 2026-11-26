#!/bin/sh
# 全平台兼容与测试夹具可移植性回归测试（1.9.7-hardened.8）
# 覆盖：原生 OpenWrt (无 base64/openssl/od、uclient-fetch、procd)、Alpine (BusyBox wget、OpenRC)、
#       CentOS 7 旧版 GNU wget (无 --show-progress)、dash 下 MIPS 大小端识别、自定义 TMPDIR
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CRASHDIR="$ROOT/scripts"
cd "$ROOT" || exit 1

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

failures=0
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
    printf '  [FAIL] %s\n' "$1" >&2
    failures=$((failures + 1))
}

echo "== 1. 原生 OpenWrt / 极简 BusyBox 无 base64/openssl 时的 Base64 编解码兜底 =="
NOB64_BIN="$SANDBOX/nob64_bin"
mkdir -p "$NOB64_BIN"
# 只链接基础 POSIX 工具（故意不放 base64、openssl、ucode、uuencode）
for _t in sh sed awk tr wc grep head tail cat cp mv rm mkdir chmod dd hexdump od cmp printf; do
    _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -sf "$_p" "$NOB64_BIN/$_t"
done
# 构造带中文节点名、URL-safe 字符(-/_)且省略末尾 = padding 的真实分享链接订阅
RAW_SUB=$(printf 'trojan://p@ss-w_rd@example.com:443?sni=a.example#香港-IPLC-01\nvless://11111111-2222-3333-4444-555555555555@example.org:8443#日本节点02\n')
printf '%s' "$RAW_SUB" >"$SANDBOX/exp.sub"
# 用宿主机生成 URL-safe 无 padding Base64 输入
B64_URLSAFE=$(base64 <"$SANDBOX/exp.sub" | tr -d '\r\n=' | tr '+/' '-_')
printf '%s\n' "$B64_URLSAFE" >"$SANDBOX/in.b64"

cat >"$NOB64_BIN/busybox" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$NOB64_BIN/busybox"

if PATH="$NOB64_BIN" CRASHDIR="$CRASHDIR" sh -c '
    . "$CRASHDIR/libs/local_sub_convert.sh"
    local_b64_decode "$1" "$2"
' _ "$SANDBOX/in.b64" "$SANDBOX/out.sub" && cmp -s "$SANDBOX/exp.sub" "$SANDBOX/out.sub"; then
    pass "local_b64_decode：无 base64/openssl/ucode 时 sed+awk 准确解码 URL-safe 无 padding 中文订阅"
else
    fail "local_b64_decode 纯 awk 兜底解码失败"
fi

# 测试 gen_base64（含以 -n 开头的字符串，防 dash echo -n 陷阱）与 gen_random
_enc_exp=$(printf '%s' '-n ss2022:pass' | base64 | tr -d '\r\n')
_enc_got=$(PATH="$NOB64_BIN" sh -c '
    ckcmd() { command -v "$1" >/dev/null 2>&1; }
    . "$1/scripts/libs/gen_base64.sh"
    gen_base64 "-n ss2022:pass"
' _ "$ROOT")
[ "$_enc_got" = "$_enc_exp" ] && pass "gen_base64：无 base64/openssl 且输入以 -n 开头时编码完全一致" || fail "gen_base64 兜底异常: got=$_enc_got want=$_enc_exp"

_rnd_got=$(PATH="$NOB64_BIN" sh -c '
    ckcmd() { command -v "$1" >/dev/null 2>&1; }
    . "$1/scripts/libs/gen_base64.sh"
    gen_random 16
' _ "$ROOT")
[ "${#_rnd_got}" = 24 ] && pass "gen_random：无 openssl/base64 时生成 16 字节(24 字符 Base64)随机密钥" || fail "gen_random 长度异常: $_rnd_got"

echo "== 2. install.sh / install_en.sh 全平台 wget 兼容 =="
INST_BIN="$SANDBOX/inst_bin"
mkdir -p "$INST_BIN"
for _t in sh grep sed awk tr head cat rm mkdir mktemp; do
    _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -sf "$_p" "$INST_BIN/$_t"
done
# 抽取 install.sh 与 install_en.sh 的 ckcmd + webget 函数独立测试
for _inst in install.sh install_en.sh; do
    sed -n '/^ckcmd()/,/^error_down()/p' "$ROOT/$_inst" | sed '$d' >"$SANDBOX/${_inst}.fn"
    # (a) Alpine BusyBox wget：--version 失败，--help 不列 no-check-certificate，但实际支持
    cat >"$INST_BIN/wget" <<'EOF'
#!/bin/sh
[ "$1" = --version ] && exit 1
[ "$1" = --help ] && { echo "Usage: wget [-q] [-T SEC] [-O FILE] URL"; exit 1; }
[ "$1" = --no-check-certificate ] && [ "$2" = --help ] && { echo "wget: unrecognized option: help" >&2; exit 1; }
echo "$*" >"$WLOG"
out=""
while [ $# -gt 0 ]; do [ "$1" = -O ] && out=$2; shift; done
[ -n "$out" ] && echo ok >"$out"
exit 0
EOF
    chmod +x "$INST_BIN/wget"
    WLOG="$SANDBOX/w.log" PATH="$INST_BIN" SKIP_CERT=1 sh -c '. "$1"; webget "$2" https://example.invalid/x echooff; [ "$result" = 200 ]' _ "$SANDBOX/${_inst}.fn" "$SANDBOX/io" &&
        grep -q -- '--no-check-certificate' "$SANDBOX/w.log" &&
        pass "$_inst：Alpine BusyBox wget + SKIP_CERT=1 正确附带 --no-check-certificate" ||
        fail "$_inst Alpine BusyBox SKIP_CERT=1 失败: $(cat "$SANDBOX/w.log" 2>/dev/null)"

    WLOG="$SANDBOX/w.log" PATH="$INST_BIN" sh -c '. "$1"; webget "$2" https://example.invalid/x echooff; [ "$result" = 200 ]' _ "$SANDBOX/${_inst}.fn" "$SANDBOX/io" &&
        ! grep -q -- '--no-check-certificate' "$SANDBOX/w.log" &&
        pass "$_inst：默认不带 --no-check-certificate（严格校验）" ||
        fail "$_inst 默认未严格校验"

    # (b) CentOS 7 旧版 GNU wget：--version 成功，但 --help 不含 --show-progress，传 --show-progress 会报错退出
    cat >"$INST_BIN/wget" <<'EOF'
#!/bin/sh
[ "$1" = --version ] && { echo "GNU Wget 1.14"; exit 0; }
[ "$1" = --help ] && { echo "GNU Wget 1.14, --no-check-certificate --max-redirect"; exit 0; }
for a in "$@"; do
    [ "$a" = --show-progress ] && { echo "wget: unrecognized option '--show-progress'" >&2; exit 2; }
done
out=""
while [ $# -gt 0 ]; do [ "$1" = -O ] && out=$2; shift; done
[ -n "$out" ] && echo ok >"$out"
exit 0
EOF
    chmod +x "$INST_BIN/wget"
    PATH="$INST_BIN" sh -c '. "$1"; webget "$2" https://example.invalid/x; [ "$result" = 200 ]' _ "$SANDBOX/${_inst}.fn" "$SANDBOX/io" &&
        pass "$_inst：旧版 GNU wget 1.14（无 --show-progress）不传不兼容参数正常下载" ||
        fail "$_inst 旧版 GNU wget 1.14 下载失败"
done

echo "== 3. OpenWrt procd / Alpine OpenRC 启动顺序与 7 字段 passwd =="
# 校验 shellcrash.procd 与 shellcrash.openrc 先跑 bfstart.sh 再判定 shellcrash:x:0:7890
for _f in scripts/starts/shellcrash.procd scripts/starts/shellcrash.openrc; do
    _bf_ln=$(grep -n '^[^#]*starts/bfstart\.sh' "$_f" | head -n 1 | cut -d: -f1)
    _ug_ln=$(grep -n '^[^#]*shellcrash:x:0:7890.*/etc/passwd' "$_f" | head -n 1 | cut -d: -f1)
    if [ -n "$_bf_ln" ] && [ -n "$_ug_ln" ] && [ "$_bf_ln" -lt "$_ug_ln" ]; then
        pass "$_f：先执行 bfstart.sh 再读取 shellcrash:x:0:7890（防首次本机代理回环）"
    else
        fail "$_f：shellcrash 用户判定仍在 bfstart.sh 之前 ($_bf_ln vs $_ug_ln)"
    fi
done
grep -q 'shellcrash:x:0:7890::/home/shellcrash:/bin/sh' scripts/starts/bfstart.sh &&
    pass "bfstart.sh：无 useradd 系统写入标准 7 字段 /etc/passwd 条目" ||
    fail "bfstart.sh：passwd 字段数不规范"
grep -q 'afstart\.sh >/dev/null 2>&1 </dev/null &' scripts/starts/shellcrash.openrc &&
    pass "shellcrash.openrc：后台 afstart.sh 关闭标准流防 rc-service 挂起" ||
    fail "shellcrash.openrc：后台 afstart.sh 未关闭标准流"
[ "$(grep -c 'sed -i "s%/etc/ShellCrash%\$CRASHDIR%g" /etc/init.d/shellcrash' scripts/init.sh)" -ge 2 ] &&
    pass "init.sh：procd 与 OpenRC 安装时均替换实际 CRASHDIR 路径" ||
    fail "init.sh：procd/OpenRC 未替换 CRASHDIR"

echo "== 4. 原生 OpenWrt 无 od 时 _upg_check_service_ready 仍识别 ELF 二进制 =="
NOOD_BIN="$SANDBOX/nood_bin"
mkdir -p "$NOOD_BIN" "$SANDBOX/elf_dir/configs"
for _t in sh dd grep sed awk tr id cat sleep printf mkdir rm cp mv cmp; do
    _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -sf "$_p" "$NOOD_BIN/$_t"
done
printf '#!/bin/sh\necho 23456\n' >"$NOOD_BIN/pidof"
# 放入一个拒绝连接的 wget：若 ELF 被正确识别，_upg_check_service_ready 必须因控制器未就绪返回非零！
cat >"$NOOD_BIN/wget" <<'EOF'
#!/bin/sh
[ "$1" = --help ] && { echo "Options: -T N -Y on/off --no-check-certificate"; exit 1; }
echo "Connection error: Connection failed" >&2
exit 4
EOF
chmod +x "$NOOD_BIN/pidof" "$NOOD_BIN/wget"
printf '\177ELFfake' >"$SANDBOX/elf_dir/CrashCore"
printf 'db_port=19999\n' >"$SANDBOX/elf_dir/configs/ShellCrash.cfg"
# 改小重试上限加速断言：把 <= 8 临时映射为 <= 1 验证 ELF 分支确实被触发
sed 's/"\$_try" -le 8/"$_try" -le 1/' "$ROOT/scripts/libs/set_config.sh" >"$SANDBOX/set_config_fast.sh"
if PATH="$NOOD_BIN" CRASHDIR="$SANDBOX/elf_dir" TMPDIR="$SANDBOX/elf_dir" USER=nonroot \
    sh -c '. "$1"; _upg_check_service_ready' _ "$SANDBOX/set_config_fast.sh" >/dev/null 2>&1; then
    fail "无 od 时 _upg_check_service_ready 漏掉了 ELF 控制器就绪核验"
else
    pass "无 od（仅 dd）时 _upg_check_service_ready 准确识别 ELF 并执行控制器核验"
fi

echo "== 5. check_cpucore 在 dash / 无 hexdump 下的 MIPS 大小端判定 =="
MIPS_BIN="$SANDBOX/mips_bin"
mkdir -p "$MIPS_BIN"
for _t in sh grep sed awk tr od dd printf; do
    _p=$(command -v "$_t" 2>/dev/null) && [ -x "$_p" ] && ln -sf "$_p" "$MIPS_BIN/$_t"
done
cat >"$MIPS_BIN/uname" <<'EOF'
#!/bin/sh
echo "Linux $FAKE_ARCH"
EOF
chmod +x "$MIPS_BIN/uname"
_got_le=$(PATH="$MIPS_BIN" FAKE_ARCH=mipsel sh -c 'setconfig(){ echo "$2"; }; . "$1/scripts/libs/check_cpucore.sh"; check_cpucore' _ "$ROOT")
[ "$_got_le" = "mipsle-softfloat" ] && pass "check_cpucore：mipsel → mipsle-softfloat" || fail "check_cpucore mipsel 异常: $_got_le"
# 在小端宿主机上模拟 uname 返回泛化的 "Linux mips" 且无 hexdump，验证 od 分支不因 echo -n 误判
_got_od=$(PATH="$MIPS_BIN" FAKE_ARCH=mips sh -c 'setconfig(){ echo "$2"; }; . "$1/scripts/libs/check_cpucore.sh"; check_cpucore' _ "$ROOT")
[ "$_got_od" = "mipsle-softfloat" ] && pass "check_cpucore：无 hexdump 时 od 分支正确识别当前小端字节序" || fail "check_cpucore od 分支异常: $_got_od"

echo "== 6. 自定义非 /tmp TMPDIR 下运行 test_webget_curl_exit.sh =="
CUST_TMP="$SANDBOX/custom_app_cache"
mkdir -p "$CUST_TMP"
if TMPDIR="$CUST_TMP" sh "$ROOT/tests/test_webget_curl_exit.sh" >/dev/null 2>&1; then
    pass "test_webget_curl_exit.sh：在自定义 TMPDIR 下通过"
else
    fail "test_webget_curl_exit.sh：在自定义 TMPDIR 下失败"
fi

echo
if [ "$failures" -gt 0 ]; then
    echo "test_cross_platform: $failures 项失败"
    exit 1
fi
echo "test_cross_platform: 全部通过"
