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
# Resolve before constructing links inside a separate temporary directory.
[ -n "$CORES" ] && CORES=$(CDPATH= cd -- "$CORES" 2>/dev/null && pwd -P)

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

if [ ! -f "$CORES/geo/Country.mmdb" ] || [ ! -f "$CORES/geo/cn.mrs" ] || [ ! -f "$CORES/geo/cn.srs" ] || [ ! -f "$CORES/geo/cnip.srs" ]; then
    echo "  [INFO] $CORES/geo/* incomplete; skipping optional local geodata staging"
fi

copy_geo_if_present() {
    [ -f "$1" ] && cp -f "$1" "$2" || true
}

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
    copy_geo_if_present "$CORES/geo/Country.mmdb" "$_sb/crash/Country.mmdb"
    copy_geo_if_present "$CORES/geo/cn.mrs" "$_sb/crash/ruleset/cn.mrs"
    copy_geo_if_present "$CORES/geo/cn.srs" "$_sb/crash/ruleset/cn.srs"
    copy_geo_if_present "$CORES/geo/cnip.srs" "$_sb/crash/ruleset/cnip.srs"
    ln -sf "$CORES/$_core/CrashCore" "$_sb/tmp/CrashCore"
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
    rm -rf "$SB"
    echo "  PASS meta empty-proxies dns_mod=$dmod"
done

echo "=== 2. Mihomo: local_sub_convert (URI + YAML + include/exclude) ==="
SB="$WORK/meta_sub"
setup_sandbox "$SB" meta
mkdir -p "$SB/subs"
for _r in "$REPO"/rules/clash_providers/*.yaml; do
    for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.mrs' "$_r" 2>/dev/null | sort -u); do
        copy_geo_if_present "$CORES/geo/cn.mrs" "$SB/crash/$_rf"
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
rm -rf "$SB"
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
rm -rf "$SB"
echo "  PASS meta broken base config returned non-zero"

echo "=== 4. Sing-BoxR: local_sub_convert (none / include / exclude / both / b64json) + all DNS modes ==="
for filter_case in none inc exc both; do
    SB="$WORK/sbr_$filter_case"
    setup_sandbox "$SB" singboxr
    mkdir -p "$SB/subs"
    for _r in "$REPO"/rules/singbox_providers/*.json; do
        for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.srs' "$_r" 2>/dev/null | sort -u); do
            copy_geo_if_present "$CORES/geo/cn.srs" "$SB/crash/$_rf"
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
    rm -rf "$SB"
    echo "  PASS singboxr filter_case=$filter_case across all 4 DNS modes"
done

echo "=== 5. Sing-BoxR: .json cached provider fallback when network fails ==="
SB="$WORK/sbr_json_cache"
setup_sandbox "$SB" singboxr
for _r in "$REPO"/rules/singbox_providers/*.json; do
    for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.srs' "$_r" 2>/dev/null | sort -u); do
        copy_geo_if_present "$CORES/geo/cn.srs" "$SB/crash/$_rf"
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
rm -rf "$SB"
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

echo "=== 7. node_tls=skip/verify: provider override_tls / skip-cert-verify 被真实内核接受 ==="
for _nt in skip verify; do
    [ "$_nt" = skip ] && _want=true || _want=false
    # Mihomo
    SB="$WORK/meta_nodetls_$_nt"
    setup_sandbox "$SB" meta
    mkdir -p "$SB/subs"
    for _r in "$REPO"/rules/clash_providers/*.yaml; do
        for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.mrs' "$_r" 2>/dev/null | sort -u); do
            copy_geo_if_present "$CORES/geo/cn.mrs" "$SB/crash/$_rf"
        done
    done
    printf 'trojan://secretpass@198.51.100.11:443?sni=example.com#SG-Node-02\n' >"$SB/subs/uri.txt"
    printf 'sub_uri https://sub.invalid/uri 3 12 clash.meta\n' >"$SB/crash/configs/providers.cfg"
    printf 'node_tls=%s\n' "$_nt" >>"$SB/crash/configs/ShellCrash.cfg"
    (
        export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
        . "$CRASHDIR/libs/get_config.sh"
        . "$CRASHDIR/libs/set_config.sh"
        . "$CRASHDIR/libs/logger.sh"
        . "$CRASHDIR/libs/check_target.sh"
        . "$CRASHDIR/libs/local_sub_convert.sh"
        webget() { cp -f "$SB/subs/uri.txt" "$1"; }
        get_bin() { [ -f "$REPO/$2" ] && cp -f "$REPO/$2" "$1"; }
        local_build_clash_config >/dev/null || exit 1
        grep -q "skip-cert-verify: $_want" "$CRASHDIR/yamls/config.yaml" || { echo "  FAIL meta node_tls=$_nt override missing" >&2; exit 1; }
        . "$CRASHDIR/starts/clash_modify.sh"
        dns_mod=mix
        modify_yaml >/dev/null || exit 1
        "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$TMPDIR/config.yaml" >/dev/null || exit 1
    ) || exit 1
    rm -rf "$SB"
    # Sing-BoxR
    SB="$WORK/sbr_nodetls_$_nt"
    setup_sandbox "$SB" singboxr
    mkdir -p "$SB/subs"
    for _r in "$REPO"/rules/singbox_providers/*.json; do
        for _rf in $(grep -oE 'ruleset/[^"[:space:]]+\.srs' "$_r" 2>/dev/null | sort -u); do
            copy_geo_if_present "$CORES/geo/cn.srs" "$SB/crash/$_rf"
        done
    done
    printf 'trojan://secretpass@198.51.100.11:443?sni=example.com#SG-Node-02\n' >"$SB/subs/uri.txt"
    printf 'sub_uri https://sub.invalid/uri 3 12 sing-box\n' >"$SB/crash/configs/providers.cfg"
    printf 'node_tls=%s\n' "$_nt" >>"$SB/crash/configs/ShellCrash.cfg"
    (
        export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
        . "$CRASHDIR/libs/get_config.sh"
        . "$CRASHDIR/libs/set_config.sh"
        . "$CRASHDIR/libs/logger.sh"
        . "$CRASHDIR/libs/check_target.sh"
        . "$CRASHDIR/libs/local_sub_convert.sh"
        webget() { cp -f "$SB/subs/uri.txt" "$1"; }
        get_bin() { [ -f "$REPO/$2" ] && cp -f "$REPO/$2" "$1"; }
        local_build_singbox_config >/dev/null || exit 1
        grep -q "\"insecure\": $_want" "$CRASHDIR/jsons/config.json" || { echo "  FAIL singboxr node_tls=$_nt override_tls missing" >&2; exit 1; }
        dns_mod=mix
        rm -rf "$TMPDIR/jsons" && mkdir -p "$TMPDIR/jsons"
        . "$CRASHDIR/starts/singbox_modify.sh"
        modify_json >/dev/null || exit 1
        "$TMPDIR/CrashCore" check -D "$BINDIR" -C "$TMPDIR/jsons" || exit 1
    ) || exit 1
    rm -rf "$SB"
    echo "  PASS meta + singboxr node_tls=$_nt"
done

echo "=== 8. node_tls=skip: 原生直链配置里没写 skip-cert-verify / insecure 的节点也被补上，且真实内核接受 ==="
for _nt in skip follow; do
    # Mihomo 原生配置：flow + block 两种节点，都没写 skip-cert-verify
    SB="$WORK/meta_native_$_nt"
    setup_sandbox "$SB" meta
    printf 'node_tls=%s\n' "$_nt" >>"$SB/crash/configs/ShellCrash.cfg"
    cat >"$SB/crash/yamls/config.yaml" <<'EOF'
proxies:
  - {name: N-flow, type: trojan, server: 198.51.100.21, port: 443, password: p, sni: example.com}
  - name: N-block
    type: vless
    server: 198.51.100.22
    port: 443
    uuid: 0b5c7a5e-5d7e-4b8f-9b1f-0d6c3b7f2a11
    tls: true
    servername: example.com
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - N-flow
      - N-block
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
        dns_mod=mix
        modify_yaml >/dev/null || exit 1
        _n=$(grep -c 'skip-cert-verify: true' "$TMPDIR/config.yaml")
        if [ "$_nt" = skip ]; then
            [ "$_n" -ge 2 ] || { echo "  FAIL meta native node_tls=skip filled $_n/2" >&2; exit 1; }
        else
            [ "$_n" = 0 ] || { echo "  FAIL meta native node_tls=follow modified nodes" >&2; exit 1; }
        fi
        "$TMPDIR/CrashCore" -t -d "$BINDIR" -f "$TMPDIR/config.yaml" >/dev/null || exit 1
    ) || exit 1
    rm -rf "$SB"
    # Stock Sing-Box 原生配置：tls 块没写 insecure
    SB="$WORK/sb_native_$_nt"
    setup_sandbox "$SB" singbox
    printf 'node_tls=%s\n' "$_nt" >>"$SB/crash/configs/ShellCrash.cfg"
    cat >"$SB/crash/jsons/config.json" <<'EOF'
{
  "outbounds": [
    {
      "type": "trojan",
      "tag": "N-1",
      "server": "198.51.100.31",
      "server_port": 443,
      "password": "p",
      "tls": { "enabled": true, "server_name": "example.com" }
    },
    { "type": "selector", "tag": "PROXY", "outbounds": ["N-1", "DIRECT"] }
  ],
  "route": { "rules": [], "final": "PROXY" }
}
EOF
    (
        export CRASHDIR="$SB/crash" TMPDIR="$SB/tmp" BINDIR="$SB/crash"
        . "$CRASHDIR/libs/get_config.sh"
        . "$CRASHDIR/libs/set_config.sh"
        . "$CRASHDIR/libs/logger.sh"
        . "$CRASHDIR/libs/check_target.sh"
        dns_mod=mix
        rm -rf "$TMPDIR/jsons" && mkdir -p "$TMPDIR/jsons"
        . "$CRASHDIR/starts/singbox_modify.sh"
        modify_json >/dev/null || exit 1
        if [ "$_nt" = skip ]; then
            grep -q '"insecure": true' "$TMPDIR/jsons/outbounds.json" || { echo "  FAIL singbox native node_tls=skip insecure missing" >&2; exit 1; }
        else
            ! grep -q '"insecure": true' "$TMPDIR/jsons/outbounds.json" || { echo "  FAIL singbox native node_tls=follow modified" >&2; exit 1; }
        fi
        "$TMPDIR/CrashCore" check -D "$BINDIR" -C "$TMPDIR/jsons" || exit 1
    ) || exit 1
    rm -rf "$SB"
    echo "  PASS meta + singbox native node_tls=$_nt"
done

echo "ALL REAL-BINARY CHECKS PASSED!"
