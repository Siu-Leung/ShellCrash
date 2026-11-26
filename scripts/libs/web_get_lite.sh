. "$CRASHDIR"/libs/set_proxy.sh
#$1:目标地址 $2:禁用proxy $3:可选读取超时秒数(默认10)
web_get_lite() (
    [ -z "$2" ] && setproxy
    _timeout="${3:-10}"
    if curl --version >/dev/null 2>&1; then
        _cert=''
        [ "$skip_cert" = "ON" ] && _cert='-k'
        curl $_cert -sSl --connect-timeout 3 --max-time "$_timeout" "$1" 2>/dev/null
    else
        _cert=''
        [ "$skip_cert" = "ON" ] && wget_nocheck_supported && _cert='--no-check-certificate'
        [ -z "$2" ] && _wproxy=on || _wproxy=off
        wget_proxy "$_wproxy" -q $_cert --timeout="$_timeout" -O - "$1"
    fi
)
