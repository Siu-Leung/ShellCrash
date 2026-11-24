
bar_max=42 #进度条长度

curl_fsize(){ # 获取文件大小
    fsize_raw=0
    _cf_flag='-sIL'
    [ -z "$redirect" ] && _cf_flag='-sI'
    header=$(curl $_cf_flag $certificate --connect-timeout 2 "$url")
    # 代理容错
    [ -z "$header" ] && { export https_proxy="" http_proxy="" HTTPS_PROXY="" HTTP_PROXY=""; header=$(curl $_cf_flag $certificate --connect-timeout 2 "$url"); }
    # 提取大小 (优先 Content-Length，其次 ETag)
    fsize_raw=$(echo "$header" | grep -i 'Content-Length' | tail -n 1 | awk '{print $2}' | tr -d '\r' | awk '{print int($1)}')
    if [ -z "$fsize_raw" ] || [ "$fsize_raw" -eq 0 ]; then
        etag=$(echo "$header" | grep -i 'etag' | tail -n 1 | cut -d '"' -f2 | cut -d '-' -f1)
        case "$etag" in
            '' | *[!0-9A-Fa-f]*) ;;
            *) fsize_raw=$(printf "%d" "0x$etag" 2>/dev/null) ;;
        esac
    fi
}

execute_curl(){ # 手搓curl进度条
    _ec_path="$1"
    _ec_url="$2"
    _ec_total="$3"
    _ec_ua="$4"
    _ec_auth_hdr="$5"
    _ec_redir="$6"
    _ec_cert="$7"
    _ec_res=$(mktemp "${TMPDIR:-/tmp}/webget_res.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/webget_res.$$")
    rm -f "$_ec_res"
    # 后台静默下载，状态码写入独立临时文件（避免 /tmp/webget_res 并发竞争与符号链接劫持）
    (
        set -- -s $_ec_redir $_ec_cert -w '%{http_code}'
        [ -n "$_ec_ua" ] && set -- "$@" --user-agent "$_ec_ua"
        [ -n "$_ec_auth_hdr" ] && set -- "$@" --proxy-header "$_ec_auth_hdr"
        curl "$@" "$_ec_url" -o "$_ec_path"
    ) >"$_ec_res" &
    _ec_pid=$!

    _ec_fs=""
    # 循环监控
    while kill -0 "$_ec_pid" 2>/dev/null; do
        if [ -f "$_ec_path" ]; then
            _ec_curr=$(wc -c < "$_ec_path")
            _ec_pct=$(awk -v c="$_ec_curr" -v t="$_ec_total" 'BEGIN {p=(t>0 ? c*100/t : 0); if(p>100)p=100; printf "%.1f", p}')
            _ec_num=$(awk -v p="$_ec_pct" -v w="$bar_max" 'BEGIN {printf "%d", p*w/100}')
            _ec_bar=$(printf "%${_ec_num}s" | tr ' ' '#')
            _ec_spcn=$((bar_max - _ec_num))
            _ec_spc=""
            [ "$_ec_spcn" -gt 0 ] && _ec_spc=$(printf "%${_ec_spcn}s")
            _ec_size=$(( _ec_total * 100 / 1048576 ))
            _ec_fs="$((_ec_size / 100)).$((_ec_size % 100)) MB"
            printf "\r\033[2K%s%s %6s%%(%s)" "$_ec_bar" "$_ec_spc" "$_ec_pct" "$_ec_fs" >&2
        fi
        usleep 200000 2>/dev/null || sleep 1
    done
    wait "$_ec_pid" #取回后台curl的退出码，传输中断时状态码仍可能是200
    _ec_rc=$?
    _ec_code=$(cat "$_ec_res" 2>/dev/null)
    rm -f "$_ec_res"
    if [ "$_ec_rc" = 0 ] && { [ "$_ec_code" = "200" ] || [ "$_ec_code" = "206" ]; }; then
        _ec_full=$(printf "%${bar_max}s" | tr ' ' '#')
        printf "\r\033[2K%s 100.0%%(%s)\n" "$_ec_full" "$_ec_fs" >&2
    else
        printf "\r\033[2K" >&2 #失败文件由webget按规则统一清理
    fi
    echo "$_ec_code"
    return "$_ec_rc"
}