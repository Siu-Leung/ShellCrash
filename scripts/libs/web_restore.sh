
#
put_save() { #推送面板选择
    [ -z "$3" ] && request_type=PUT || request_type=$3
    if curl --version >/dev/null 2>&1; then
        http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" \
            curl -fsS --noproxy '*' --connect-timeout 3 --max-time 10 -X "$request_type" -H "Authorization: Bearer $secret" -H "Content-Type:application/json" "$1" -d "$2" >/dev/null
    elif wget --help 2>&1 | grep -q -- '--method'; then
        http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
            wget -q --no-proxy -T 5 --method="$request_type" --header="Authorization: Bearer $secret" --header="Content-Type:application/json" --body-data="$2" -O /dev/null "$1" >/dev/null
    fi
}
web_restore() { #还原面板选择
    [ -s "$CRASHDIR"/configs/web_save ] || return 0
    while IFS=, read -r group_name now_name || [ -n "$group_name" ]; do
        [ -z "$group_name" ] && continue
        group_name=$(printf '%s' "$group_name" | sed 's/ /%20/g')
        now_esc=$(printf '%s' "$now_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
        put_save "http://127.0.0.1:${db_port}/proxies/${group_name}" "{\"name\":\"${now_esc}\"}"
    done <"$CRASHDIR"/configs/web_save
}
