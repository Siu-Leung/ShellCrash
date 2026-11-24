. "$CRASHDIR"/libs/set_proxy.sh
#$1:目标地址 $2:json字符串
web_json_post() (
    setproxy
    if curl --version >/dev/null 2>&1; then
        _cert=''
        [ "$skip_cert" = "ON" ] && _cert='-k'
        curl $_cert -fsSl -X POST --connect-timeout 3 --max-time 10 -H "Content-Type: application/json" "$1" -d "$2" >/dev/null 2>&1
    else
        _cert=''
        [ "$skip_cert" = "ON" ] && wget --help 2>&1 | grep -q 'no-check-certificate' && _cert='--no-check-certificate'
        wget_proxy on -q $_cert --timeout=3 --method=POST --header="Content-Type: application/json" --body-data="$2" -O /dev/null "$1" >/dev/null 2>&1
    fi
)
