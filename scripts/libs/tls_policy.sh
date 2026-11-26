#!/bin/sh
# tls_policy.sh —— 证书校验策略（三类流量分开管理）
#
#   1. 项目文件下载（内核/规则/面板/脚本/TG）：skip_cert
#        OFF  = 严格校验（默认）
#        ON   = 跳过校验（老设备缺 CA 证书时的兜底）
#   2. 订阅拉取（机场订阅 / 直链配置）：sub_tls
#        auto   = 先严格校验，失败后自动跳过证书再拉一次并记日志（默认，和原项目一样"能用"）
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
    webget "$1" "$2" "$3" "$4" skipceroff "$5" && return 0
    [ "$_sw_mode" = "strict" ] && return 1
    # auto：严格校验失败后跳过证书再试一次；只有这次成功才说明是证书问题，才记警告
    if webget "$1" "$2" "$3" "$4" skipcerforce "$5"; then
        if type logger 2>/dev/null | grep -q function; then
            logger "订阅证书校验未通过，已自动跳过证书拉取成功：$(tls_url_host "$2")（如需严格模式请到 功能设置-证书校验 中修改）" 33
        else
            echo "订阅证书校验未通过，已自动跳过证书拉取成功：$(tls_url_host "$2")" >&2
        fi
        return 0
    fi
    return 1
}
