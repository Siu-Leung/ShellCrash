#!/bin/sh
# tests/real_core_matrix.sh — Real-binary config & subscription validation matrix
# Usage: sh tests/real_core_matrix.sh /path/to/real_cores
# Expects:
#   $1/meta/CrashCore
#   $1/singbox/CrashCore
#   $1/singboxr/CrashCore
#   $1/geo/Country.mmdb, cn.mrs, cn.srs, cnip.srs

REPO=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CORES="${1:-}"

if [ -z "$CORES" ] || [ ! -x "$CORES/meta/CrashCore" ] || [ ! -x "$CORES/singbox/CrashCore" ] || [ ! -x "$CORES/singboxr/CrashCore" ]; then
    echo "Usage: sh tests/real_core_matrix.sh <real_cores_dir>" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo "=== Core Versions ==="
"$CORES/meta/CrashCore" -v || exit 1
"$CORES/singbox/CrashCore" version | head -n 1 || exit 1
"$CORES/singboxr/CrashCore" version | head -n 1 || exit 1

setup_sandbox() {
    _sb="$1"
    _core="$2"
    rm -rf "$_sb"
    mkdir -p "$_sb/crash" "$_sb/tmp"
    cp -a "$REPO/scripts"/. "$_sb/crash/"
    cp -a "$REPO/public"/. "$_sb/crash/configs/" 2>/dev/null || true
    cp -a "$REPO/rules" "$_sb/crash/rules" 2>/dev/null || true
    mkdir -p "$_sb/crash/configs" "$_sb/crash/yamls" "$_sb/crash/jsons" "$_sb/crash/providers" "$_sb/crash/ruleset/mrs" "$_sb/crash/ruleset/srs"
    cp -f "$REPO/public/fake_ip_filter.list" "$_sb/crash/configs/fake_ip_filter.list"
    cp -f "$REPO/public/servers.list" "$_sb/crash/configs/servers_chs.list" 2>/dev/null || true
    cp -f "$CORES/geo/Country.mmdb" "$_sb/crash/Country.mmdb"
    cp -f "$CORES/geo/cn.mrs" "$_sb/crash/ruleset/cn.mrs"
    cp -f "$CORES/geo/cn.srs" "$_sb/crash/ruleset/cn.srs"
    cp -f "$CORES/geo/cnip.srs" "$_sb/crash/ruleset/cnip.srs"
    cp -f "$CORES/$_core/CrashCore" "$_sb/tmp/CrashCore"
    chmod +x "$_sb/tmp/CrashCore"
    cat > "$_sb/crash/configs/directories.env" <<EOF
TMPDIR=$_sb/tmp
BINDIR=$_sb/crash
EOF
    cat > "$_sb/crash/configs/ShellCrash.cfg" <<EOF
#ShellCrash配置文件，不明勿动！
crashcore=$_core
authentication=''
skip_cert=OFF
EOF
}

echo "=== 1. Mihomo: empty proxies: [] + DIRECT across all DNS modes + IPv6 DoH ==="
for dmod in mix fake-ip route redir_host; do
    SB="$WORK/meta_empty_$dmod"
    setup_sandbox "$SB" meta
    cat >> "$SB/crash/configs/ShellCrash.cfg" <<EOF
dns_mod=$dmod
dns_nameserver='https://[2001:db8::2]:8443/dns-query, 223.5.5.5'
dns_fallback='https://[2001:db8::1]:44443/dns-query, 1.1.1.1'
dns_resolver='223.5.5.5, 2400:3200::1'
ipv6_dns=ON
EOF
    cat > "$SB/crash/yamls/config.yaml" <<'EOF'
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,PROXY
EOF
    (
        export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
        . "$CRASHDIR/libs/get_config.sh"
        . "$CRASHDIR/libs/set_config.sh"
        . "$CRASHDIR/libs/logger.sh"
        . "$CRASHDIR/libs/check_target.sh"
        . "$CRASHDIR/starts/clash_modify.sh"
        modify_yaml || exit 1
        "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$TMPDIR/config.yaml" >/dev/null || exit 1
    ) || exit 1
    echo "  PASS meta empty-proxies dns_mod=$dmod"
done

echo "=== 2. Mihomo: local_sub_convert (URI + YAML + include/exclude) ==="
SB="$WORK/meta_sub"
setup_sandbox "$SB" meta
mkdir -p "$SB/subs"
for _r in "$REPO"/rules/clash_providers/*.yaml; do
    for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.mrs' "$_r" 2>/dev/null | sort -u); do
        cp -f "$CORES/geo/cn.mrs" "$SB/crash/$_rf"
    done
done
cat > "$SB/subs/uri.txt" <<'EOF'
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@198.51.100.10:8388#HK-Node-01
trojan://secretpass@198.51.100.11:443?sni=example.com#SG-Node-02
vless://11111111-2222-3333-4444-555555555555@198.51.100.12:443?encryption=none&security=tls&sni=example.com&type=ws&host=example.com&path=%2Fws#AD-Spam-Node
EOF
cat > "$SB/subs/clash.yaml" <<'EOF'
proxies:
  - name: JP-YAML-Node
    type: socks5
    server: 198.51.100.25
    port: 1080
EOF
cat > "$SB/crash/configs/providers.cfg" <<'EOF'
sub_uri https://sub.invalid/uri 3 12 clash.meta #AD-Spam #HK|SG|JP
sub_yaml https://sub.invalid/yaml 3 12 clash.meta
EOF
B64_JSON=$(printf '%s' '{"outbounds":[{"type":"socks","tag":"JP-B64JSON","server":"198.51.100.20","server_port":1080}]}' | base64 | tr -d '\n')

(
    export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
    . "$CRASHDIR/libs/get_config.sh"
    . "$CRASHDIR/libs/set_config.sh"
    . "$CRASHDIR/libs/logger.sh"
    . "$CRASHDIR/libs/check_target.sh"
    . "$CRASHDIR/libs/local_sub_convert.sh"
    webget() {
        case "$2" in
            https://sub.invalid/uri) cp -f "$SB/subs/uri.txt" "$1"; return 0 ;;
            https://sub.invalid/yaml) cp -f "$SB/subs/clash.yaml" "$1"; return 0 ;;
            *) return 1 ;;
        esac
    }
    get_bin() {
        if [ -f "$REPO/$2" ]; then cp -f "$REPO/$2" "$1"; return 0; fi
        return 1
    }
    include="HK|SG|JP"
    exclude="AD-Spam"
    local_build_clash_config || exit 1
    . "$CRASHDIR/starts/clash_modify.sh"
    dns_mod=mix
    modify_yaml || exit 1
    "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$TMPDIR/config.yaml" >/dev/null || exit 1
) || exit 1
echo "  PASS meta local_sub_convert + URI + YAML + include/exclude"

echo "=== 3. Mihomo: broken base config fails modify_yaml (non-zero) ==="
SB="$WORK/meta_broken"
setup_sandbox "$SB" meta
cat > "$SB/crash/yamls/config.yaml" <<'EOF'
proxies:
  - name: bad
    type: nonexistent_proto_xyz
    server: 198.51.100.1
    port: 443
proxy-groups:
  - name: PROXY
    type: select
    proxies: [bad]
rules:
  - MATCH,PROXY
EOF
if (
    export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
    . "$CRASHDIR/libs/get_config.sh"
    . "$CRASHDIR/libs/set_config.sh"
    . "$CRASHDIR/libs/logger.sh"
    . "$CRASHDIR/libs/check_target.sh"
    . "$CRASHDIR/starts/clash_modify.sh"
    modify_yaml >/dev/null 2>&1
); then
    echo "  FAIL: meta broken base config unexpectedly succeeded" >&2
    exit 1
fi
echo "  PASS meta broken base config returned non-zero"

echo "=== 4. Sing-BoxR: local_sub_convert (none / include / exclude / both / b64json) + all DNS modes ==="
for filter_case in none inc exc both; do
    SB="$WORK/sbr_$filter_case"
    setup_sandbox "$SB" singboxr
    mkdir -p "$SB/subs"
    for _r in "$REPO"/rules/singbox_providers/*.json; do
        for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.srs' "$_r" 2>/dev/null | sort -u); do
            cp -f "$CORES/geo/cn.srs" "$SB/crash/$_rf"
        done
    done
    cat > "$SB/subs/uri.txt" <<'EOF'
ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@198.51.100.10:8388#HK-Node-01
trojan://secretpass@198.51.100.11:443?sni=example.com#SG-Node-02
EOF
    printf '%s\n' "$B64_JSON" > "$SB/subs/b64json.txt"
    cat > "$SB/crash/configs/providers.cfg" <<'EOF'
sub_uri https://sub.invalid/uri 3 12 sing-box
sub_b64json https://sub.invalid/b64json 3 12 sing-box
EOF
    (
        export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
        . "$CRASHDIR/libs/get_config.sh"
        . "$CRASHDIR/libs/set_config.sh"
        . "$CRASHDIR/libs/logger.sh"
        . "$CRASHDIR/libs/check_target.sh"
        . "$CRASHDIR/libs/local_sub_convert.sh"
        webget() {
            case "$2" in
                https://sub.invalid/uri) cp -f "$SB/subs/uri.txt" "$1"; return 0 ;;
                https://sub.invalid/b64json) cp -f "$SB/subs/b64json.txt" "$1"; return 0 ;;
                *) return 1 ;;
            esac
        }
        get_bin() {
            if [ -f "$REPO/$2" ]; then cp -f "$REPO/$2" "$1"; return 0; fi
            return 1
        }
        include=""; exclude=""
        case "$filter_case" in
            inc)  include="HK|JP" ;;
            exc)  exclude="SG" ;;
            both) include="HK|SG|JP"; exclude="SG" ;;
        esac
        local_build_singbox_config >/dev/null || exit 1
        for dmod in mix fake-ip route redir_host; do
            dns_mod="$dmod"
            dns_nameserver='doh://[2001:db8::2]:8443/dns-query, 223.5.5.5'
            dns_fallback='dot://1.1.1.1:853, https://[2001:db8::1]:44443/dns-query'
            dns_resolver='223.5.5.5, 2400:3200::1'
            rm -rf "$TMPDIR/jsons" && mkdir -p "$TMPDIR/jsons"
            . "$CRASHDIR/starts/singbox_modify.sh"
            modify_json || exit 1
            "$TMPDIR/CrashCore" check -D "$BINDIR" -C "$TMPDIR/jsons" || exit 1
        done
    ) || exit 1
    echo "  PASS singboxr filter_case=$filter_case across all 4 DNS modes"
done

echo "=== 5. Sing-BoxR: .json cached provider fallback when network fails ==="
SB="$WORK/sbr_json_cache"
setup_sandbox "$SB" singboxr
for _r in "$REPO"/rules/singbox_providers/*.json; do
    for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.srs' "$_r" 2>/dev/null | sort -u); do
        cp -f "$CORES/geo/cn.srs" "$SB/crash/$_rf"
    done
done
cat > "$SB/crash/providers/sub_1.json" <<'EOF'
{"outbounds":[{"type":"socks","tag":"Cached-JSON-Node","server":"198.51.100.30","server_port":1080}]}
EOF
cat > "$SB/crash/configs/providers.cfg" <<'EOF'
sub_1 https://offline.invalid/sub 3 12 sing-box
EOF
(
    export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
    . "$CRASHDIR/libs/get_config.sh"
    . "$CRASHDIR/libs/set_config.sh"
    . "$CRASHDIR/libs/logger.sh"
    . "$CRASHDIR/libs/check_target.sh"
    . "$CRASHDIR/libs/local_sub_convert.sh"
    webget() { return 1; }
    get_bin() {
        if [ -f "$REPO/$2" ]; then cp -f "$REPO/$2" "$1"; return 0; fi
        return 1
    }
    local_build_singbox_config >/dev/null || exit 1
    rm -rf "$TMPDIR/jsons" && mkdir -p "$TMPDIR/jsons"
    . "$CRASHDIR/starts/singbox_modify.sh"
    dns_mod=mix
    modify_json || exit 1
    "$TMPDIR/CrashCore" check -D "$BINDIR" -C "$TMPDIR/jsons" || exit 1
) || exit 1
echo "  PASS singboxr .json cached provider fallback"

echo "=== 6. Stock Sing-Box: native JSON + all 4 DNS modes (incl. fake-ip filter list & doh://) + reject singboxr provider build ==="
SB="$WORK/sb_stock"
setup_sandbox "$SB" singbox
cat > "$SB/crash/jsons/config.json" <<'EOF'
{
  "outbounds": [
    {
      "type": "socks",
      "tag": "Node-1",
      "server": "198.51.100.50",
      "server_port": 1080
    },
    {
      "type": "selector",
      "tag": "PROXY",
      "outbounds": ["Node-1", "DIRECT"]
    }
  ],
  "route": {
    "rules": [],
    "final": "PROXY"
  }
}
EOF
(
    export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
    . "$CRASHDIR/libs/get_config.sh"
    . "$CRASHDIR/libs/set_config.sh"
    . "$CRASHDIR/libs/logger.sh"
    . "$CRASHDIR/libs/check_target.sh"
    . "$CRASHDIR/libs/local_sub_convert.sh"
    if local_build_singbox_config >/dev/null 2>&1; then
        echo "  FAIL: stock singbox should reject singboxr provider generation" >&2
        exit 1
    fi
    for dmod in mix fake-ip route redir_host; do
        dns_mod="$dmod"
        dns_nameserver='doh://223.5.5.5/dns-query'
        dns_fallback='https://[2001:db8::1]:44443/dns-query'
        dns_resolver='223.5.5.5'
        rm -rf "$TMPDIR/jsons" && mkdir -p "$TMPDIR/jsons"
        . "$CRASHDIR/starts/singbox_modify.sh"
        modify_json || exit 1
        "$TMPDIR/CrashCore" check -D "$BINDIR" -C "$TMPDIR/jsons" || exit 1
    done
) || exit 1
echo "  PASS stock singbox all 4 DNS modes + singboxr provider rejection"

echo "ALL REAL-BINARY CHECKS PASSED!"
