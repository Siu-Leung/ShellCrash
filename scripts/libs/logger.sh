
[ -n "$__IS_LIB_LOGGER" ] && return
__IS_LIB_LOGGER=1

#日志工具
. "$CRASHDIR"/libs/web_json.sh
# JSON 字符串转义（转义 \、"、回车、换行、制表符，防止日志含特殊字符破坏 JSON 或注入字段）
json_escape() {
    printf '%s' "$1" | awk '
        BEGIN { ORS="" }
        {
            gsub(/\\/, "\\\\")
            gsub(/"/, "\\\"")
            gsub(/\r/, "\\r")
            gsub(/\t/, "\\t")
            if (NR > 1) printf "\\n"
            printf "%s", $0
        }
    '
}

#$1日志内容$2显示颜色$3是否推送$4是否覆盖上一条
logger() {
    _log_dir="${TMPDIR:-/tmp/ShellCrash}"
    mkdir -p "$_log_dir"
    _log_file="$_log_dir/ShellCrash.log"
    [ -n "$2" -a "$2" != 0 ] && printf "\033[%sm%s\033[0m\n" "$2" "$1"
    log_text="$(date "+%G-%m-%d_%H:%M:%S")~$1"
    if [ "$4" = on ] && [ -f "$_log_file" ]; then
        _log_tmp="$_log_file.tmp.$$"
        _LOG_PAT="$1" awk 'index($0, ENVIRON["_LOG_PAT"]) == 0' "$_log_file" >"$_log_tmp" && mv -f "$_log_tmp" "$_log_file"
        rm -f "$_log_tmp"
    fi
    printf '%s\n' "$log_text" >>"$_log_file"
    [ "$(wc -l <"$_log_file" 2>/dev/null || echo 0)" -gt 199 ] && sed -i '1,20d' "$_log_file"
    #推送远程日志
    [ "$3" != off ] && {
        [ -n "$device_name" ] && log_text="$log_text($device_name)"
        _log_esc=$(json_escape "$log_text")
        # 安全加固：仅使用用户自建 Telegram Bot（api.telegram.org），移除第三方公共机器人中转
        case "$push_TG" in
        '' | publictoken) : ;;
        *)
            url="https://api.telegram.org/bot${push_TG}/sendMessage"
            content="{\"chat_id\":\"$(json_escape "${chat_ID}")\",\"text\":\"${_log_esc}\"}"
            web_json_post "$url" "$content" &
            ;;
        esac
        [ -n "$push_bark" ] && {
            url="${push_bark}"
            content="{\"body\":\"${_log_esc}\",\"title\":\"ShellCrash_log\",\"level\":\"passive\",\"badge\":\"1\"}"
            web_json_post "$url" "$content" &
        }
        [ -n "$push_Deer" ] && {
            url="${push_Deer_url%/}"
            url="${url:-https://api2.pushdeer.com}/message/push"
            content="{\"pushkey\":\"$(json_escape "${push_Deer}")\",\"text\":\"${_log_esc}\"}"
            web_json_post "$url" "$content" &
        }
        [ -n "$push_Po" ] && {
            url="https://api.pushover.net/1/messages.json"
            content="{\"token\":\"$(json_escape "${push_Po}")\",\"user\":\"$(json_escape "${push_Po_key}")\",\"title\":\"ShellCrash_log\",\"message\":\"${_log_esc}\"}"
            web_json_post "$url" "$content" &
        }
        [ -n "$push_PP" ] && {
            url="https://www.pushplus.plus/send"
            content="{\"token\":\"$(json_escape "${push_PP}")\",\"title\":\"ShellCrash_log\",\"content\":\"${_log_esc}\"}"
            web_json_post "$url" "$content" &
        }
        [ -n "$push_Gotify" ] && {
            url="${push_Gotify}"
            content="{\"title\":\"ShellCrash_log\",\"message\":\"${_log_esc}\",\"priority\":5}"
            web_json_post "$url" "$content" &
        }
        [ -n "$push_SynoChat" ] && {
            url="${push_ChatURL}/webapi/entry.cgi?api=SYNO.Chat.External&method=chatbot&version=2&token=${push_ChatTOKEN}"
            content="payload={\"text\":\"${_log_esc}\", \"user_ids\":[${push_ChatUSERID}]}"
            web_json_post "$url" "$content" &
        }
    } >/dev/null 2>&1 </dev/null &
}
