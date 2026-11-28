#生成指定位数的加密秘钥，符合ss2022协议
_b64_enc_hex() {
    LC_ALL=C awk '
        BEGIN { b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" }
        { gsub(/[^0-9A-Fa-f]/, ""); hex = hex $0 }
        END {
            n = int(length(hex) / 2)
            # BusyBox awk 不一定开启非十进制字符串自动转换，用逐半字节算值最稳
            for (i = 0; i < n; i++) {
                h1 = index("0123456789abcdef", tolower(substr(hex, i * 2 + 1, 1))) - 1
                h2 = index("0123456789abcdef", tolower(substr(hex, i * 2 + 2, 1))) - 1
                bytes[i] = h1 * 16 + h2
            }
            out = ""
            for (i = 0; i < n; i += 3) {
                b0 = bytes[i]
                b1 = (i + 1 < n) ? bytes[i + 1] : 0
                b2 = (i + 2 < n) ? bytes[i + 2] : 0
                out = out substr(b64, int(b0 / 4) + 1, 1)
                out = out substr(b64, (b0 % 4) * 16 + int(b1 / 16) + 1, 1)
                out = out ((i + 1 < n) ? substr(b64, (b1 % 16) * 4 + int(b2 / 64) + 1, 1) : "=")
                out = out ((i + 2 < n) ? substr(b64, (b2 % 64) + 1, 1) : "=")
            }
            printf "%s", out
        }
    '
}
# $1 是随机字节数（正十进制整数），不是输出字符数。
# 使用私有临时目录逐阶段检查，避免 POSIX 管道只返回最后一段的状态。
gen_random() (
    _gr_n=$1
    case $_gr_n in ''|*[!0-9]*) return 1 ;; esac
    while [ "${_gr_n#0}" != "$_gr_n" ]; do _gr_n=${_gr_n#0}; done
    # 避免 32 位 shell 算术溢出；AWK 兜底的内存随请求线性增长。
    case $_gr_n in ''|?????????*) return 1 ;; esac
    umask 077
    _gr_try=0
    while :; do
        _gr_dir=${TMPDIR:-/tmp}/shellcrash-random.$$.${_gr_try}
        if mkdir "$_gr_dir" 2>/dev/null; then break; fi
        _gr_try=$(( _gr_try + 1 ))
        [ "$_gr_try" -lt 32 ] || return 1
    done
    trap 'rm -rf "$_gr_dir"' 0
    trap 'exit 1' 1 2 3 15
    if ckcmd openssl; then
        openssl rand -base64 "$_gr_n" >"$_gr_dir/encoded" 2>/dev/null || return 1
    elif ckcmd ucode && ! ckcmd base64 && ! busybox base64 --help >/dev/null 2>&1 &&
         ucode -e 'import * as fs from "fs"; if (type(fs.open) != "function") exit(1);' >/dev/null 2>&1; then
        ucode -e 'import * as fs from "fs"; let f = fs.open("/dev/urandom", "r"); let n = +ARGV[0]; let s = f ? f.read(n) : null; if (s === null || length(s) != n) exit(1); print(b64enc(s));' -- "$_gr_n" >"$_gr_dir/encoded" 2>/dev/null || return 1
    else
        dd if=/dev/urandom of="$_gr_dir/raw" bs=1 count="$_gr_n" 2>/dev/null || return 1
        [ "$(wc -c <"$_gr_dir/raw")" -eq "$_gr_n" ] || return 1
        if ckcmd base64; then
            base64 <"$_gr_dir/raw" >"$_gr_dir/encoded" || return 1
        elif busybox base64 --help >/dev/null 2>&1; then
            busybox base64 <"$_gr_dir/raw" >"$_gr_dir/encoded" || return 1
        elif ckcmd uuencode; then
            uuencode -m - <"$_gr_dir/raw" >"$_gr_dir/uu" || return 1
            sed '1d; /^====$/d; /^end$/d' "$_gr_dir/uu" >"$_gr_dir/encoded" || return 1
        elif ckcmd hexdump; then
            hexdump -v -e '1/1 "%02x"' <"$_gr_dir/raw" >"$_gr_dir/hex" || return 1
            _b64_enc_hex <"$_gr_dir/hex" >"$_gr_dir/encoded" || return 1
        elif ckcmd od; then
            od -An -tx1 -v <"$_gr_dir/raw" >"$_gr_dir/hex" || return 1
            _b64_enc_hex <"$_gr_dir/hex" >"$_gr_dir/encoded" || return 1
        else
            return 1
        fi
    fi
    tr -d '\r\n' <"$_gr_dir/encoded" >"$_gr_dir/result" || return 1
    _gr_len=$(wc -c <"$_gr_dir/result") || return 1
    [ "$_gr_len" -eq $(( (_gr_n + 2) / 3 * 4 )) ] || return 1
    [ "$(LC_ALL=C tr -d 'A-Za-z0-9+/=' <"$_gr_dir/result" | wc -c)" -eq 0 ] || return 1
    _gr_pad=$(LC_ALL=C tr -cd '=' <"$_gr_dir/result" | wc -c) || return 1
    [ "$_gr_pad" -eq $(( (3 - _gr_n % 3) % 3 )) ] || return 1
    LC_ALL=C grep -q '=[^=]' "$_gr_dir/result" && return 1
    cat "$_gr_dir/result"
)
#对指定字符串进行base64转码
gen_base64() {
    if ckcmd base64; then
        printf '%s' "$1" | base64 | tr -d '\r\n'
    elif busybox base64 --help >/dev/null 2>&1; then
        printf '%s' "$1" | busybox base64 | tr -d '\r\n'
    elif ckcmd openssl; then
        printf '%s' "$1" | openssl base64 -A | tr -d '\r\n'
    elif ckcmd ucode; then
        ucode -e 'print(b64enc(ARGV[0]));' -- "$1" 2>/dev/null
    elif ckcmd hexdump; then
        printf '%s' "$1" | hexdump -v -e '1/1 "%02x"' | _b64_enc_hex
    elif ckcmd od; then
        printf '%s' "$1" | od -An -tx1 -v | _b64_enc_hex
    else
        return 1
    fi
}