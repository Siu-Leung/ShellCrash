
setproxy(){
    [ -n "$(pidof CrashCore)" ] && {
        [ -n "$authentication" ] && auth="$authentication@" || auth=""
        [ -z "$mix_port" ] && mix_port=7890
        export https_proxy="http://${auth}127.0.0.1:$mix_port"
        export http_proxy="http://${auth}127.0.0.1:$mix_port"
    }
}

wget_proxy() (
    mode=$1
    shift
    # BusyBox 使用 -Y，GNU Wget 和 Wget2 使用长选项控制代理。
    if wget --help 2>&1 | grep -q -- '-Y'; then
        exec wget -Y "$mode" "$@"
    fi
    exec wget "--proxy=$mode" "$@"
)

# wget_nocheck_supported —— 当前 wget 是否支持 --no-check-certificate
# 不能只看帮助文案：Alpine BusyBox 1.37 的 --help 没列这个选项，但实际可用；
# OpenWrt uclient-fetch 帮助里有列。不支持的实现会报 "unrecognized option ... no-check-certificate"。
wget_nocheck_supported() {
    wget --help 2>&1 | grep -q 'no-check-certificate' && return 0
    wget --no-check-certificate --help 2>&1 | grep -qiE 'option[^a-z]*no-check-certificate' && return 1
    return 0
}
