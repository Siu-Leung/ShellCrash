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
gen_random() {
    if ckcmd openssl; then
        openssl rand --base64 "$1" | tr -d '\r\n'
    elif ckcmd base64; then
        dd if=/dev/urandom bs=1 count="$1" 2>/dev/null | base64 | tr -d '\r\n'
    elif busybox base64 --help >/dev/null 2>&1; then
        dd if=/dev/urandom bs=1 count="$1" 2>/dev/null | busybox base64 | tr -d '\r\n'
    elif ckcmd ucode; then
        ucode -e 'import * as fs from "fs"; let f = fs.open("/dev/urandom", "r"); let s = f ? f.read(+ARGV[0]) : null; if (!s) exit(1); print(b64enc(s));' -- "$1" 2>/dev/null
    elif ckcmd uuencode; then
        dd if=/dev/urandom bs=1 count="$1" 2>/dev/null | uuencode -m - | sed -n '2p' | tr -d '\r\n'
    elif ckcmd hexdump; then
        dd if=/dev/urandom bs=1 count="$1" 2>/dev/null | hexdump -v -e '1/1 "%02x"' | _b64_enc_hex
    elif ckcmd od; then
        dd if=/dev/urandom bs=1 count="$1" 2>/dev/null | od -An -tx1 -v | _b64_enc_hex
    else
        return 1
    fi
}
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