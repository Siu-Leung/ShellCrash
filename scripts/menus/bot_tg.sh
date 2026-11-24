#!/bin/sh

[ -z "$CRASHDIR" ] && CRASHDIR=$( cd $(dirname $0);cd ..;pwd)
. "$CRASHDIR"/libs/get_config.sh
. "$CRASHDIR"/libs/web_json.sh
. "$CRASHDIR"/libs/set_config.sh
. "$CRASHDIR"/libs/web_get_lite.sh
. "$CRASHDIR"/libs/logger.sh
. "$CRASHDIR"/libs/i18n.sh
. "$CRASHDIR"/menus/running_status.sh
[ -f "$CRASHDIR"/configs/gateway.cfg ] && . "$CRASHDIR"/configs/gateway.cfg

load_lang bot_tg

[ -z "$TMPDIR" ] && TMPDIR='/tmp/ShellCrash'
mkdir -p "$TMPDIR"
# 安全加固：未绑定合法自建 Bot Token 或 ChatID 时拒绝启动轮询，杜绝空 ChatID 绕过鉴权
case "$TG_CHATID" in
    '' | *[!0-9-]*) echo "Invalid or empty TG_CHATID, aborting bot_tg." >&2; exit 1 ;;
esac
[ -z "$TG_TOKEN" ] && { echo "Empty TG_TOKEN, aborting bot_tg." >&2; exit 1; }

API="https://api.telegram.org/bot$TG_TOKEN"
STATE_FILE="$TMPDIR/tgbot_state"
LOGFILE="$TMPDIR/tgbot.log"
OFFSET=0
FILE_TYPE=""
echo "$crashcore" | grep -q 'singbox' && config_type=json || config_type=yaml

### --- 基础函数 --- ###
web_download() (
    setproxy
    if curl --version >/dev/null 2>&1; then
        _cert=''
        [ "$skip_cert" = "ON" ] && _cert='-k'
        curl $_cert -fsSl --connect-timeout 5 --max-time 120 "$1" -o "$2"
    else
        _cert=''
        [ "$skip_cert" = "ON" ] && wget --help 2>&1 | grep -q 'no-check-certificate' && _cert='--no-check-certificate'
        wget_proxy on -q $_cert --timeout=30 -O "$2" "$1"
    fi
)
web_upload() (
    setproxy
    _cert=''
    [ "$skip_cert" = "ON" ] && _cert='-k'
    curl $_cert -sSfl -X POST --connect-timeout 20 --max-time 60 "$API/sendDocument" -F "chat_id=$TG_CHATID" -F "document=@$1" >/dev/null
)
send_msg(){
    _esc_text=$(json_escape "$1")
    web_json_post "$API/sendMessage" "{\"chat_id\":\"$TG_CHATID\",\"text\":\"$_esc_text\",\"parse_mode\":\"Markdown\"}"
}
send_plain_msg(){
    _esc_text=$(json_escape "$1")
    web_json_post "$API/sendMessage" "{\"chat_id\":\"$TG_CHATID\",\"text\":\"$_esc_text\"}"
}
send_help(){
    # 去原作者化：帮助消息只保留机器人功能说明，移除上游 TG 群/项目/博客引流
    TEXT=$(cat <<EOF
$BOT_TG_HELP_BASIC
EOF
)
    send_msg "$TEXT"
}
send_menu(){
    #获取运行状态
    PID=$(pidof CrashCore | awk '{print $NF}')
    if [ -n "$PID" ]; then
        run="$BOT_TG_RUN_ON"
        running_status
    else
        run="$BOT_TG_RUN_OFF"
    fi
    corename=$(echo "$crashcore" | sed 's/singboxr/SingBoxR/' | sed 's/singbox/SingBox/' | sed 's/clash/Clash/' | sed 's/meta/Mihomo/')
    TEXT=$(cat <<EOF
*$BOT_TG_WELCOME*_${versionsh_l}_
$corename$BOT_TG_SERVICE$run
【*$redir_mod*】$BOT_TG_MEM_USED$VmRSS
$BOT_TG_RUNNING_TIME$day$time
$BOT_TG_SELECT_ACTION
EOF
)
    _esc_text=$(json_escape "$TEXT")
    MENU=$(cat <<EOF
{
  "inline_keyboard":[
    [
      {"text":"$BOT_TG_BTN_START","callback_data":"start_redir"},
      {"text":"$BOT_TG_BTN_PURE","callback_data":"stop_redir"},
      {"text":"$BOT_TG_BTN_RESTART","callback_data":"restart"}
    ],
    [
      {"text":"$BOT_TG_BTN_LOG","callback_data":"readlog"},
      {"text":"$BOT_TG_BTN_TRANSFER","callback_data":"transport"}
    ]
  ]
}
EOF
)
    web_json_post "$API/sendMessage" "{\"chat_id\":\"$TG_CHATID\",\"text\":\"$_esc_text\",\"parse_mode\":\"Markdown\",\"reply_markup\":$MENU}"
}
### --- 文件传输 --- ###
send_transport_menu(){ 
    TEXT="$BOT_TG_SELECT_FILE"
    if echo "$crashcore" | grep -q 'singbox';then
        config_type=json
    else
        config_type=yaml
    fi

    if curl -h >/dev/null 2>&1;then
        CURL_KB=$(cat <<EOF
    [
      {"text":"$BOT_TG_BTN_GET_LOG","callback_data":"ts_get_log"},
      {"text":"$BOT_TG_BTN_GET_BAK","callback_data":"ts_get_bak"},
      {"text":"$BOT_TG_BTN_GET_CFG","callback_data":"ts_get_ccf"}
    ],
EOF
)
    else
        CURL_KB="[{\"text\":\"$BOT_TG_NO_CURL\",\"callback_data\":\"noop\"}],"
    fi
    MENU=$(cat <<EOF
{
  "inline_keyboard":[
    $CURL_KB
    [
      {"text":"$BOT_TG_BTN_UP_CORE","callback_data":"ts_up_core"},
      {"text":"$BOT_TG_BTN_UP_BAK","callback_data":"ts_up_bak"},
      {"text":"$BOT_TG_BTN_UP_CFG","callback_data":"ts_up_ccf"}
    ]
  ]
}
EOF
)
    _esc_text=$(json_escape "$TEXT")
    web_json_post "$API/sendMessage" "{\"chat_id\":\"$TG_CHATID\",\"text\":\"$_esc_text\",\"parse_mode\":\"Markdown\",\"reply_markup\":$MENU}"

}
# 校验压缩包内无绝对路径、../ 路径遍历及符号链接/硬链接/设备节点（防 Tar Slip）
_safe_tar_check() {
    _entries=$(tar -tzf "$1" 2>/dev/null) || return 1
    [ -n "$_entries" ] || return 1
    printf '%s\n' "$_entries" | grep -Eq '(^/|^\.\./|/\.\./|/\.\.$|^\.\.$)' && return 1
    _listing=$(tar -tvzf "$1" 2>/dev/null) || return 1
    printf '%s\n' "$_listing" | grep -Eq '^[lhcb]' && return 1
    return 0
}
process_file(){
    echo "$crashcore" | grep -q 'singbox' && config_type=json || config_type=yaml
    case "$FILE_TYPE" in
        1)
            . "$CRASHDIR"/libs/core_tools.sh
            core_check "$TMPDIR/$FILE_NAME" && res="$BOT_TG_UPLOAD_OK" || res="$BOT_TG_UPLOAD_FAIL"
            send_msg "$BOT_TG_CORE_UPDATE$res"
            sleep 2
            "$CRASHDIR"/start.sh start
        ;;
        2)
            if _safe_tar_check "$TMPDIR/$FILE_NAME" && tar -zxf "$TMPDIR/$FILE_NAME" -C "$CRASHDIR"/configs; then
                res="$BOT_TG_CFG_RESTORED"
            else
                res="$BOT_TG_RESTORE_FAIL"
            fi
            send_msg "$res"
        ;;
        3)
            mkdir -p "$CRASHDIR/${config_type}s"
            mv -f "$TMPDIR/$FILE_NAME" "$CRASHDIR/${config_type}s/$FILE_NAME" && res="$BOT_TG_CFG_UPLOADED" || res="$BOT_TG_UPLOAD_FAIL2"
            send_msg "$res"
        ;;
        *)
            send_msg "$BOT_TG_FILE_FORMAT_FAIL"
        ;;
    esac
    FILE_TYPE=""
    rm -f "$TMPDIR/$FILE_NAME"
    send_menu
}
download_file(){
    _raw_name=$(echo "$UPDATES" | sed 's/"callback_query".*//g' | grep -o '"file_name":"[^"]*"' | head -n1 | sed 's/.*:"//;s/"$//')
    # 安全加固：仅允许纯文件名（禁止 /、..、空格与特殊字符），防止路径遍历写入任意目录
    FILE_NAME=$(printf '%s' "$_raw_name" | sed 's|.*/||' | grep -E '^[A-Za-z0-9._-]+\.(tar\.gz|gz|upx|json|yaml)$')
    case "$FILE_NAME" in *..* ) FILE_NAME="" ;; esac
    if [ -n "$FILE_NAME" ] && [ -n "$FILE_TYPE" ];then
        FILE_PATH=$(web_get_lite "$API/getFile?file_id=$FILE_ID" "" 15 | grep -o '"file_path":"[^"]*"' | head -n1 | sed 's/.*:"//;s/"$//')
        case "$FILE_PATH" in '' | *..* | /*) FILE_PATH="" ;; esac
        if [ -n "$FILE_PATH" ]; then
            API_FILE="https://api.telegram.org/file/bot$TG_TOKEN"
            web_download "$API_FILE/$FILE_PATH" "$TMPDIR/$FILE_NAME"
            if [ "$?" = 0 ];then
                process_file
            else
                rm -f "$TMPDIR/$FILE_NAME"
                send_msg "$BOT_TG_NET_UPLOAD_FAIL"
            fi
        else
            send_msg "$BOT_TG_NET_UPLOAD_FAIL"
        fi
    else
        send_msg "$BOT_TG_FILE_FORMAT_FAIL"
    fi
}
### --- 具体操作函数 --- ###
do_start_fw(){
    [ -z "$redir_mod_bf" ] && redir_mod_bf='Redir'
    [ -z "$firewall_area_bf" ] && firewall_area_bf='1'
    redir_mod=$redir_mod_bf
    firewall_area=$firewall_area_bf
    setconfig redir_mod "$redir_mod"
    setconfig firewall_area "$firewall_area"
    "$CRASHDIR"/start.sh start_firewall
    echo "$BOT_TG_FW_ENABLED*$redir_mod_bf*$BOT_TG_FW_ENABLED_SUFFIX" > "$LOGFILE"
}
do_stop_fw(){
    redir_mod_bf=$redir_mod
    [ "$firewall_area" != "4" ] && firewall_area_bf=$firewall_area
    firewall_area=4
    setconfig firewall_area 4
    "$CRASHDIR"/start.sh stop_firewall
    echo "$BOT_TG_SWITCH_PURE" > "$LOGFILE"
}
do_restart(){
    "$CRASHDIR"/start.sh restart
    echo "$BOT_TG_SERVICE_RESTARTED" > "$LOGFILE"
}
do_set_sub(){
    #echo "$1" "$2" >> "$CRASHDIR"/configs/providers.cfg
    echo "$BOT_TG_UNFINISHED" > "$LOGFILE"

}
transport(){ #文件传输
    case "$CALLBACK" in
        "ts_get_log")
            web_upload "$TMPDIR"/ShellCrash.log
            send_menu 
        ;;
        "ts_get_bak")
            now=$(date +%Y%m%d_%H%M%S)
            FILE="$TMPDIR/configs_$now.tar.gz"
            tar -zcf "$FILE" -C "$CRASHDIR/configs/" .
            web_upload "$FILE"
            rm -rf "$FILE"
            send_menu 
        ;;
        "ts_get_ccf")
            FILE="$TMPDIR/$config_type.tar.gz"
            tar -zcf "$FILE" -C "$CRASHDIR/${config_type}s/" .
            web_upload "$FILE"
            rm -rf "$FILE"
            send_menu 
        ;;
        "ts_up_core")
            FILE_TYPE=1
            send_msg  "$BOT_TG_SEND_CORE ${corename} $BOT_TG_SEND_CORE_SUFFIX"
        ;;
        "ts_up_bak")
            FILE_TYPE=2
            send_msg  "$BOT_TG_SEND_BAK"
        ;;
        "ts_up_ccf")
            FILE_TYPE=3
            send_msg  "$BOT_TG_SEND_CFG .${config_type} $BOT_TG_SEND_CFG_SUFFIX"
        ;;
    esac
}

# 安全加固：提取单条更新(limit=1)的首个 chat.id（位于用户可控 text/file_name 之前，防止消息正文伪造 "id":xxx 绕过鉴权）
extract_chat_id() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -r '.result[0] | (.message.chat.id // .callback_query.message.chat.id // empty)' 2>/dev/null
    else
        printf '%s' "$1" | grep -oE '"chat":[[:space:]]*\{[[:space:]]*"id":[[:space:]]*-?[0-9]+' | head -n 1 | grep -oE -- '-?[0-9]+$'
    fi
}

### --- 轮询主进程 --- ###
polling(){
    while true; do
        # limit=1 确保每次只处理一条更新，彻底杜绝多条更新中 CHATID 与 CALLBACK/FILE_ID 错位导致的越权执行
        UPDATES=$(web_get_lite "$API/getUpdates?timeout=25&limit=1&offset=$OFFSET" "" 35)

        echo "$UPDATES" | grep -q '"update_id"' || {
            sleep 10 #防止网络不佳时疯狂请求
            continue
        }
        
        OFFSET=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | head -n1 | cut -d: -f2)
        case "$OFFSET" in
            '' | *[!0-9]*) sleep 5; continue ;;
        esac
        OFFSET=$((OFFSET + 1))
        
        ### --- 严格校验 ChatID --- ###
        CHATID=$(extract_chat_id "$UPDATES")
        [ -n "$TG_CHATID" ] && [ "$CHATID" = "$TG_CHATID" ] || continue
        
        ### --- 处理按钮事件 --- ###
        CALLBACK=$(echo "$UPDATES" | grep -o '"data":"[^"]*"' | head -n1 | sed 's/.*:"//;s/"$//')
        FILE_ID=$(echo "$UPDATES" | sed 's/"callback_query".*//g' | grep -o '"file_id":"[^"]*"' | head -n1 | sed 's/.*:"//;s/"$//')
        
        [ -n "$FILE_ID" ] && {
            download_file
            continue
        }
        [ -n "$CALLBACK" ] && case "$CALLBACK" in
            "start_redir")
                if [ "$firewall_area" = 4 ];then
                    do_start_fw
                    send_msg  "$BOT_TG_SWITCH_TO$redir_mod_bf！"
                else
                    send_msg  "$BOT_TG_ALREADY$redir_mod！"
                fi
                send_menu 
                continue
            ;;
            "stop_redir")
                if [ "$firewall_area" != 4 ];then
                    do_stop_fw
                    send_msg  "$BOT_TG_SWITCH_PURE"
                else
                    send_msg  "$BOT_TG_ALREADY_PURE"
                fi
                send_menu 
                continue
            ;;
            "restart")
                do_restart
                send_msg  "$BOT_TG_SERVICE_RESTARTED_SHORT"
                sleep 10
                send_menu 
                continue
            ;;
            "readlog")
                _log_body=$(grep -v "$BOT_TG_TASK_WORD" "$TMPDIR/ShellCrash.log" 2>/dev/null | tail -n 20)
                send_plain_msg "$BOT_TG_LOG_CONTENT
$_log_body"
                sleep 3
                send_menu 
                continue
            ;;
            "transport")
                send_transport_menu
                continue
            ;;
            "set_sub")
                echo "await_sub" > "$STATE_FILE"
                send_msg  "$BOT_TG_INPUT_SUB"
                continue
            ;;
            ts_*)
                transport
                continue
            ;;
        esac


        ### --- 处理订阅输入 --- ###
        TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | tail -n1 | sed 's/.*"text":"//;s/"$//')

        if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "await_sub" ]; then
            echo "" > "$STATE_FILE"
            do_set_sub "$TEXT"
            send_plain_msg "$BOT_TG_SUB_UPDATED
$(cat "$LOGFILE" 2>/dev/null)"
            send_menu 
            continue
        fi


        ### 处理命令 ###
        case "$TEXT" in
        /crash)
            send_menu
        ;;
        /"$my_alias")
            send_menu
        ;;
        /help)
            send_help
        ;;
        esac

    done
}

[ "$TG_menupush" = ON ] && send_menu

polling

