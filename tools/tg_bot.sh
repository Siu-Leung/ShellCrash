#!/bin/sh

. "${CRASHDIR}"/libs/get_config.sh
. "${CRASHDIR}"/libs/set_config.sh
. "${CRASHDIR}"/libs/set_proxy.sh
. "${CRASHDIR}"/libs/logger.sh
OFFSET=0
API="https://api.telegram.org/bot$TGBOT_TOKEN"
[ -z "$TMPDIR" ] && TMPDIR=/tmp/ShellCrash
mkdir -p "$TMPDIR"
STATE_FILE="$TMPDIR/tgbot_state"
LOGFILE="$TMPDIR/tgbot.log"

### --- 基础函数 --- ###
webget() (
	setproxy
	cert_flag=""
	[ "$skip_cert" = "ON" ] && cert_flag="-k"
	if curl --version >/dev/null 2>&1; then
		curl $cert_flag -fsSl --connect-timeout 3 --max-time "${2:-35}" "$1" 2>/dev/null
	else
		wcert=""
		[ "$skip_cert" = "ON" ] && wget --help 2>&1 | grep -q 'no-check-certificate' && wcert="--no-check-certificate"
		wget_proxy on -q $wcert --timeout="${2:-35}" -O - "$1"
	fi
)
webpost() (
	setproxy
	cert_flag=""
	[ "$skip_cert" = "ON" ] && cert_flag="-k"
	if curl --version >/dev/null 2>&1; then
		curl $cert_flag -fsSl -X POST --connect-timeout 3 --max-time 10 -H "Content-Type: application/json; charset=utf-8" "$1" -d "$2" >/dev/null 2>&1
	else
		wcert=""
		[ "$skip_cert" = "ON" ] && wget --help 2>&1 | grep -q 'no-check-certificate' && wcert="--no-check-certificate"
		wget_proxy on -q $wcert --timeout=5 --method=POST --header="Content-Type: application/json; charset=utf-8" --body-data="$2" -O /dev/null "$1" >/dev/null 2>&1
	fi
)
send_msg() {
    _esc_text=$(json_escape "$1")
	webpost "$API/sendMessage" "{\"chat_id\":\"$TGBOT_CHATID\",\"text\":\"$_esc_text\",\"parse_mode\":\"Markdown\"}"
}
send_help(){
    TEXT=$(cat <<EOF
ShellCrash Telegram 机器人命令：
/crash - 呼出控制菜单
/help - 查看帮助
EOF
)
	send_msg "$TEXT"
}
send_menu() {
	#获取运行状态
	PID=$(pidof CrashCore | awk '{print $NF}')
	if [ -n "$PID" ]; then
		run=正在运行
		VmRSS=$(awk '/^VmRSS:/ {printf "%.2f MB\n", $2/1000}' "/proc/$PID/status" 2>/dev/null)
		start_time=$(cat "$TMPDIR/crash_start_time" 2>/dev/null)
		if [ -n "$start_time" ]; then
			time=$(($(date +%s) - start_time))
			day=$((time / 86400))
			[ "$day" = "0" ] && day='' || day="$day天"
			time=$(date -u -d @"${time}" +%H小时%M分%S秒)
		fi
		corename=$(echo "$crashcore" | sed 's/singboxr/SingBoxR/' | sed 's/singbox/SingBox/' | sed 's/clash/Clash/' | sed 's/meta/Mihomo/')
	else
		run=未运行
	fi
    TEXT=$(cat <<EOF
*欢迎使用ShellCrash！*                版本：$versionsh_l
$corename服务$run               【*$redir_mod*】
内存占用：$VmRSS                    已运行：$day$time
请选择操作：
EOF
)
    _esc_text=$(json_escape "$TEXT")
    MENU=$(cat <<'EOF'
{
  "inline_keyboard":[
    [
      {"text":"▶ 启用劫持","callback_data":"start_redir"},
      {"text":"■ 纯净模式","callback_data":"stop_redir"},
      {"text":"🔄 重启内核","callback_data":"restart"}
    ],
    [
      {"text":"🌀 热更新订阅","callback_data":"refresh"},
      {"text":"📝 添加订阅","callback_data":"set_sub"}
    ]
  ]
}
EOF
)
	webpost "$API/sendMessage" "{\"chat_id\":\"$TGBOT_CHATID\",\"text\":\"$_esc_text\",\"parse_mode\":\"Markdown\",\"reply_markup\":$MENU}"
}

### --- 具体操作函数 --- ###
do_start_fw() {
	[ -z "$redir_mod_bf" ] && redir_mod_bf='Redir'
	[ -z "$firewall_area_bf" ] && firewall_area_bf='1'
	redir_mod=$redir_mod_bf
	firewall_area=$firewall_area_bf
	setconfig redir_mod "$redir_mod"
	setconfig firewall_area "$firewall_area"
	"$CRASHDIR"/start.sh start_firewall
    echo "ShellCrash 透明路由*$redir_mod_bf*已启用！" > "$LOGFILE"
}
do_stop_fw() {
	redir_mod_bf=$redir_mod
	[ "$firewall_area" != "4" ] && firewall_area_bf=$firewall_area
	firewall_area=4
	setconfig firewall_area 4
	"$CRASHDIR"/start.sh stop_firewall
    echo "ShellCrash 已切换到纯净模式！" > "$LOGFILE"
}
do_restart() {
    "$CRASHDIR"/start.sh restart
    echo "ShellCrash 服务已重启！" > "$LOGFILE"
}
do_refresh() {
    "$CRASHDIR"/task/task.sh hotupdate
	echo "ShellCrash 已完成热更新订阅！" > "$LOGFILE"
}
do_set_sub() {
    #echo "$1" "$2" >> "$CRASHDIR"/configs/providers.cfg
    echo "错误，还未完成的功能！" > "$LOGFILE"
}

extract_chat_id() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -r '.result[0] | (.message.chat.id // .callback_query.message.chat.id // empty)' 2>/dev/null
	else
		printf '%s' "$1" | grep -oE '"chat":[[:space:]]*\{[[:space:]]*"id":[[:space:]]*-?[0-9]+' | head -n 1 | grep -oE -- '-?[0-9]+$'
	fi
}

extract_from_id() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -r '.result[0] | (.callback_query.from.id // .message.from.id // empty)' 2>/dev/null
	else
		printf '%s' "$1" | grep -oE '"from":[[:space:]]*\{[[:space:]]*"id":[[:space:]]*[0-9]+' | head -n 1 | grep -oE '[0-9]+$'
	fi
}

is_authorized_event() {
	_ev_chat=$(extract_chat_id "$1")
	_ev_from=$(extract_from_id "$1")
	[ -n "$TGBOT_CHATID" ] && [ "$_ev_chat" = "$TGBOT_CHATID" ] || return 1
	case "$TGBOT_CHATID" in
		-*)
			_admins="${TGBOT_ADMIN_IDS:-$TG_ADMIN_IDS}"
			[ -n "$_admins" ] && [ -n "$_ev_from" ] || return 1
			case ",$(printf '%s' "$_admins" | tr ' ;' ',,')," in
				*",${_ev_from},"*) return 0 ;;
				*) return 1 ;;
			esac
			;;
		*)
			[ -z "$_ev_from" ] || [ "$_ev_from" = "$TGBOT_CHATID" ] || return 1
			return 0
			;;
	esac
}

### --- 轮询主进程 --- ###
polling(){
	case "$TGBOT_CHATID" in
		'' | *[!0-9-]*) echo "Invalid or empty TGBOT_CHATID, aborting." >&2; exit 1 ;;
	esac
	[ -z "$TGBOT_TOKEN" ] && { echo "Empty TGBOT_TOKEN, aborting." >&2; exit 1; }
	while true; do
		UPDATES=$(webget "$API/getUpdates?timeout=25&limit=1&offset=$OFFSET" 35)

		echo "$UPDATES" | grep -q '"update_id"' || {
			sleep 10
			continue
		}

		OFFSET=$(echo "$UPDATES" | grep -o '"update_id":[0-9]*' | head -n1 | cut -d: -f2)
		case "$OFFSET" in
			'' | *[!0-9]*) sleep 5; continue ;;
		esac
		OFFSET=$((OFFSET + 1))

		### --- 严格校验 ChatID 与操作者 from.id（杜绝群成员越权控制） --- ###
		is_authorized_event "$UPDATES" || continue

		### --- 处理按钮事件 --- ###
		CALLBACK=$(echo "$UPDATES" | grep -o '"data":"[^"]*"' | head -n1 | sed 's/.*:"//;s/"$//')

		case "$CALLBACK" in
			"start_redir")
				if [ "$firewall_area" = '4' ];then
					do_start_fw
					send_msg  "已切换到$redir_mod_bf！"
				else
					send_msg  "当前已经是$redir_mod！"
				fi
				send_menu 
				continue
				;;
			"stop_redir")
				if [ "$firewall_area" != '4' ];then
					do_stop_fw
					send_msg  "已切换到纯净模式"
				else
					send_msg  "当前已经是纯净模式！"
				fi
				send_menu 
				continue
				;;
			"restart")
				do_restart
				send_msg  "🔄 服务已重启"
				sleep 10
				send_menu 
				continue
				;;
			"refresh")
				do_refresh
				send_msg  "🌀 刷新完成：
$(cat "$LOGFILE" 2>/dev/null)"
				send_menu 
				continue
				;;
			"set_sub")
				echo "await_sub" > "$STATE_FILE"
				send_msg  "✏ 请输入新的订阅链接："
				continue
				;;
		esac


		### --- 处理订阅输入 --- ###
		TEXT=$(echo "$UPDATES" | grep -o '"text":"[^"]*"' | tail -n1 | sed 's/.*"text":"//;s/"$//')

		if [ "$(cat "$STATE_FILE" 2>/dev/null)" = "await_sub" ]; then
			echo "" > "$STATE_FILE"
			do_set_sub "$TEXT"
			send_msg  "订阅更新完成：
$(cat "$LOGFILE" 2>/dev/null)"
			send_menu 
			continue
		fi


		### 处理命令 ###
		case "$TEXT" in
		/crash)
			send_menu
		;;
		/help)
			send_help
		;;
		esac

	done
}

### --- 初始设置 --- ###
set_botmenu(){
	webpost "https://api.telegram.org/bot$TOKEN/setMyCommands" '{"commands":[{"command":"crash","description":"呼出ShellCrash菜单"},{"command":"help","description":"查看帮助"}]}'
}
set_token(){
	echo -----------------------------------------------
	echo -e "请先通过 \033[32;4mhttps://t.me/BotFather\033[0m 申请TG机器人并获取其\033[36mAPI TOKEN\033[0m"
	echo -----------------------------------------------
	read -r -p "请输入你获取到的API TOKEN > " TOKEN
	if ! printf '%s' "$TOKEN" | grep -qE '^[0-9]+:[A-Za-z0-9_-]{20,}$'; then
		echo -e "\033[31mAPI TOKEN 格式无效！\033[0m"
		return 1
	fi
	echo -----------------------------------------------
	echo -e "请向\033[32m你申请的机器人\033[31m而不是BotFather\033[0m，发送任意几条消息！"
	echo -----------------------------------------------
	read -r -p "我已经发送完成(1/0) > " res
	if [ "$res" = 1 ]; then
		url_tg="https://api.telegram.org/bot${TOKEN}/getUpdates"
		chat=$(webget "$url_tg" 15 | tail -n 1)
		[ -n "$chat" ] && chat_ID=$(printf '%s' "$chat" | grep -oE '"chat":[[:space:]]*\{[[:space:]]*"id":[[:space:]]*-?[0-9]+' | tail -n 1 | grep -oE -- '-?[0-9]+$')
		[ -z "$chat_ID" ] && {
			echo -e "\033[31m无法获取对话ID，请确认使用的不是已经被绑定的机器人，或手动输入ChatID！\033[0m"
			echo -e "通常访问 $url_tg 即可看到ChatID，也可以尝试其他方法\033[0m"
			read -r -p "请手动输入ChatID > " chat_ID
		}
		if printf '%s' "$chat_ID" | grep -qE '^-?[0-9]{5,}$'; then
			TGBOT_TOKEN=$TOKEN
			setconfig_quote TGBOT_TOKEN "$TOKEN"
			setconfig TGBOT_CHATID "$chat_ID"
			set_botmenu
			echo -e "\033[32m已完成Telegram机器人设置！\033[0m"
		else
			echo -e "\033[31m无法获取有效对话ID，请重新配置！\033[0m"
		fi
	fi
}

case "$1" in
init)
	set_token
;;
*)
	polling
;;
esac
