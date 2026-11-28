
#
put_save() ( #推送面板选择；子 shell 避免污染调用者变量
    request_type=${3:-PUT}
    [ -r "$CRASHDIR/libs/panel_http.sh" ] || return 1
    . "$CRASHDIR/libs/panel_http.sh"
    _panel_local_url "$1" || return 1
    case ${secret:-} in *"$(printf '\r')"*|*'
'*) return 1;; esac
    if curl --version >/dev/null 2>&1; then
        _ps_status=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" \
            curl -q -fsS --noproxy '*' --connect-timeout 3 --max-time 10 -X "$request_type" -H "Authorization: Bearer ${secret:-}" -H "Content-Type:application/json" "$1" -d "$2" -o /dev/null -w '%{http_code}' 2>/dev/null) || return 1
        case $_ps_status in 2[0-9][0-9]) return 0;; *) return 1;; esac
    elif command -v wget >/dev/null 2>&1; then
        _ps_help=$(wget --help 2>&1)
        case $_ps_help in *-Y*) _ps_np='-Y off';; *) _ps_np='--no-proxy';; esac
        if printf '%s\n' "$_ps_help" | grep -q -- '--method' &&
           printf '%s\n' "$_ps_help" | grep -q -- '--body-data' &&
           printf '%s\n' "$_ps_help" | grep -q -- '--header' &&
           printf '%s\n' "$_ps_help" | grep -q -- '--max-redirect'; then
            http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" \
                wget -q $_ps_np -T 5 --max-redirect=0 --method="$request_type" --header="Authorization: Bearer ${secret:-}" --header="Content-Type:application/json" --body-data="$2" -O /dev/null "$1" >/dev/null 2>&1
        else
            # 旧 uclient-fetch/BusyBox wget 无 PUT 时，回退仅允许本机 HTTP。
            [ -r "$CRASHDIR/libs/panel_http.sh" ] || return 1
            . "$CRASHDIR/libs/panel_http.sh"
            _panel_nc_request "$request_type" "$1" "$2" >/dev/null
        fi
    else
        return 1
    fi
)
web_restore() { #还原面板选择；任意请求失败时返回非零，但继续处理其余组
    local _wr_result
    _wr_result=0
    [ -s "$CRASHDIR"/configs/web_save ] || return 0
    while IFS=, read -r group_name now_name || [ -n "$group_name" ]; do
        [ -z "$group_name" ] && continue
        group_name=$(printf '%s' "$group_name" | sed 's/ /%20/g')
        now_esc=$(printf '%s' "$now_name" | sed 's/\\/\\\\/g; s/"/\\"/g')
        put_save "http://127.0.0.1:${db_port}/proxies/${group_name}" "{\"name\":\"${now_esc}\"}" || _wr_result=1
    done <"$CRASHDIR"/configs/web_save
    return "$_wr_result"
}
