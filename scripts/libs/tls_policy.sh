#!/bin/sh
# tls_policy.sh —— 证书校验策略（三类流量分开管理）
#
#   1. 项目文件下载（内核/规则/面板/脚本/TG）：skip_cert
#        OFF  = 严格校验（默认）
#        ON   = 跳过校验（老设备缺 CA 证书时的兜底）
#   2. 订阅拉取（机场订阅 / 直链配置）：sub_tls
#        auto   = 先严格校验；只有确认是 HTTPS 证书校验失败时才跳过证书再拉一次并记日志
#                 （默认，和原项目一样"能用"）；普通网络/HTTP 错误不降级
#        strict = 只严格校验，证书不对就失败（保留上次缓存）
#        skip   = 始终跳过证书
#   3. 节点自身 TLS（skip-cert-verify / insecure）：node_tls
#        follow = 跟随订阅，订阅里写什么就是什么，脚本不改（默认）
#        skip   = 强制所有节点跳过证书（原项目默认行为）
#        verify = 强制所有节点校验证书
#
# 兼容：老配置里只保存了 skip_cert=ON（原项目默认 ON）时，node_tls 未设置则视为 skip，
#       保证升级后节点行为不变。

[ -n "$__IS_LIB_TLS_POLICY_LOADED" ] && return 0
__IS_LIB_TLS_POLICY_LOADED=1

# 回显 follow / skip / verify
tls_node_mode() {
    case "$node_tls" in
    follow | skip | verify) echo "$node_tls" ;;
    *) [ "$skip_cert" = "ON" ] && echo skip || echo follow ;;
    esac
}

# 回显 auto / strict / skip
tls_sub_mode() {
    case "$sub_tls" in
    auto | strict | skip) echo "$sub_tls" ;;
    *) echo auto ;;
    esac
}

# tls_yaml_force_skip <proxies.yaml> —— node_tls=skip 时给 Clash 原生节点补上 skip-cert-verify: true
# 已有 false 的由调用方先替换为 true；这里只处理"完全没写这个字段"的节点：
#   - 单行 flow 节点：  - {name: a, type: trojan, ...}  → 在末尾 } 前追加
#   - 多行 block 节点：  - name: a  → 在该节点第一行后插入一行（缩进与同级键一致）
tls_yaml_force_skip() {
    [ -s "$1" ] || return 0
    awk '
    function flush(   i, has, ind) {
        if (n == 0) return
        has = 0
        for (i = 1; i <= n; i++) if (buf[i] ~ /skip-cert-verify:/) has = 1
        print buf[1]
        if (!has) {
            ind = keyind
            if (ind == "") { ind = entind "  " }
            print ind "skip-cert-verify: true"
        }
        for (i = 2; i <= n; i++) print buf[i]
        n = 0; keyind = ""
    }
    {
        line = $0
        if (!haveent && match(line, /^[ \t]*- /)) { entind = substr(line, 1, RLENGTH - 2); haveent = 1 }
        if (haveent && substr(line, 1, length(entind) + 2) == entind "- ") {
            flush()
            rest = substr(line, length(entind) + 3)
            if (rest ~ /^\{/) {
                # 只改能确定结尾的单行 flow；带行尾注释或跨行的 flow 保持原样，避免写坏 YAML
                if (rest ~ /^\{.*\}[ \t]*$/ && rest !~ /skip-cert-verify:/) sub(/\}[ \t]*$/, ", skip-cert-verify: true}", line)
                print line
                next
            }
            n = 1; buf[1] = line
            next
        }
        if (n > 0) {
            n++; buf[n] = line
            if (keyind == "" && match(line, /^[ \t]+[^ \t#]/)) keyind = substr(line, 1, RLENGTH - 1)
            next
        }
        print line
    }
    END { flush() }
    ' "$1" >"$1.tlstmp" && mv -f "$1.tlstmp" "$1"
}

# tls_json_force_insecure <outbounds.json> —— node_tls=skip 时给 Sing-Box 节点的 tls 对象补上 "insecure": true
# 依赖 CrashCore format 的标准缩进输出（format 会省略值为 false 的 insecure，所以只能补写）
tls_json_force_insecure() {
    [ -s "$1" ] || return 0
    awk '
    function flush(   i, has) {
        has = 0
        for (i = 2; i <= n; i++) if (substr(buf[i], 1, length(ind) + 2) == ind "  " && buf[i] ~ /^[ \t]*"insecure":/) has = 1
        print buf[1]
        if (!has) print ind "  \"insecure\": true,"
        for (i = 2; i <= n; i++) print buf[i]
        n = 0; intls = 0
    }
    {
        if (!intls && match($0, /^[ \t]*"tls": \{[ \t]*$/)) {
            intls = 1; n = 1; buf[1] = $0
            match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH)
            next
        }
        if (intls) {
            n++; buf[n] = $0
            if ($0 ~ ("^" ind "\\}")) flush()
            next
        }
        print
    }
    END { if (intls) for (i = 1; i <= n; i++) print buf[i] }
    ' "$1" >"$1.tlstmp" && mv -f "$1.tlstmp" "$1"
}

# 只取主机名用于日志，避免把订阅 token 写进日志
tls_url_host() {
    printf '%s\n' "$1" | sed -E 's|^[A-Za-z][A-Za-z0-9+.-]*://||; s|^[^/@]*@||; s|[/?#].*$||; s|:[0-9]+$||' | head -n 1
}

# sub_webget —— 按 sub_tls 策略拉取订阅
# 参数同 webget，但没有第 5 个证书参数：$1=目标 $2=URL $3=echo $4=redir $5=UA
# 依赖：调用方已加载 web_get.sh（webget）与 logger.sh（logger）
sub_webget() {
    _sw_mode=$(tls_sub_mode)
    if [ "$_sw_mode" = "skip" ]; then
        webget "$1" "$2" "$3" "$4" skipcerforce "$5"
        return $?
    fi
    # 非 HTTPS 没有证书可言：只做一次普通拉取，不存在"降级"
    case "$2" in
    [Hh][Tt][Tt][Pp][Ss]://*) ;;
    *)
        webget "$1" "$2" "$3" "$4" skipceroff "$5"
        return $?
        ;;
    esac
    _sw_flag="${TMPDIR:-/tmp}/.sub_tls_err.$$"
    rm -f "$_sw_flag" "$_sw_flag.stderr"
    WEBGET_TLS_ERRFILE="$_sw_flag"
    webget "$1" "$2" "$3" "$4" skipceroff "$5"
    _sw_rc=$?
    WEBGET_TLS_ERRFILE=''
    _sw_tls=''
    grep -q tls "$_sw_flag" 2>/dev/null && _sw_tls=1
    rm -f "$_sw_flag" "$_sw_flag.stderr"
    [ "$_sw_rc" = 0 ] && return 0
    [ "$_sw_mode" = "strict" ] && return 1
    # auto：只有确认是证书校验失败才跳过证书重试；超时、DNS、HTTP 4xx/5xx 等直接按失败处理
    [ -n "$_sw_tls" ] || return 1
    if webget "$1" "$2" "$3" "$4" skipcerforce "$5"; then
        _sw_msg="订阅 HTTPS 证书校验失败，已按自动模式跳过证书拉取成功：$(tls_url_host "$2")（如需严格模式请到 功能设置-证书校验 中修改）"
        if type logger 2>/dev/null | grep -q function; then
            logger "$_sw_msg" 33
        else
            echo "$_sw_msg" >&2
        fi
        return 0
    fi
    return 1
}
