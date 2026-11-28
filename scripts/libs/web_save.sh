get_save() { #获取面板信息并内部处理所有异常
	local response exit_code _ws_help _ws_np
	[ -r "$CRASHDIR/libs/panel_http.sh" ] || return 1
	. "$CRASHDIR/libs/panel_http.sh"
	_panel_local_url "$1" || return 1
	case ${secret:-} in *"$(printf '\r')"*|*'
'*) return 1;; esac
	if curl --version >/dev/null 2>&1; then
		response=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" curl -q -sf --noproxy '*' --connect-timeout 2 --max-time 5 -H "Authorization: Bearer ${secret:-}" -H "Content-Type:application/json" -w '\n%{http_code}' "$1" 2>/dev/null)
		exit_code=$?
		case $response in *'
'2[0-9][0-9]) response=${response%???}; response=${response%?};; *) return 1;; esac
	elif command -v wget >/dev/null 2>&1; then
		_ws_help=$(wget --help 2>&1)
		case $_ws_help in *-Y*) _ws_np='-Y off';; *) _ws_np='--no-proxy';; esac
		if printf '%s\n' "$_ws_help" | grep -q -- '--header' &&
		   printf '%s\n' "$_ws_help" | grep -q -- '--max-redirect'; then
			response=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" wget -q -T 3 $_ws_np --max-redirect=0 --header="Authorization: Bearer ${secret:-}" --header="Content-Type:application/json" -O - "$1" 2>/dev/null)
			exit_code=$?
		elif command -v ucode >/dev/null 2>&1 && command -v busybox >/dev/null 2>&1 &&
		     [ -r "$CRASHDIR/libs/panel_response.uc" ] &&
		     ucode -e 'import { stdin } from "fs";' >/dev/null 2>&1; then
			# 优先用受限本机管道回退（OpenWrt 默认 uclient-fetch 无 --header 且可严格禁跳转）。
			response=$(_panel_nc_request GET "$1" '')
			exit_code=$?
		elif printf '%s\n' "$_ws_help" | grep -q -- '--header'; then
			# 极简 BusyBox 环境无 curl/ucode 时保留原生 wget --header 兼容（与 .8 一致）。
			response=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" wget -q -T 3 $_ws_np --header="Authorization: Bearer ${secret:-}" --header="Content-Type:application/json" -O - "$1" 2>/dev/null)
			exit_code=$?
		else
			return 1
		fi
	else
		return 1
	fi
	[ "$exit_code" -eq 0 ] && [ -n "$response" ] && [ "$response" != "{}" ] || return 1
	printf '%s\n' "$response"
}

web_save() { #最小化保存面板节点选择
	#使用get_save获取面板节点设置，失败自动退出
	response=$(get_save "http://127.0.0.1:${db_port}/proxies") || return 1

	echo "$response" | sed 's/{}//g' | sed 's/:{/\
/g' | grep -aE '"Selector"' >"$TMPDIR"/web_proxies

	>"$TMPDIR"/web_save
	[ -s "$TMPDIR"/web_proxies ] && while read line; do
		def=$(echo "$line" | grep -oE '"all".*",' | awk -F "[\"]" '{print $4}')
		now=$(echo "$line" | grep -oE '"now".*",' | awk -F "[\"]" '{print $4}')
		[ "$def" != "$now" ] && {
			name=$(echo "$line" | grep -oE '"name".*",' | awk -F "[\"]" '{print $4}')
			echo "${name},${now}" >>"$TMPDIR"/web_save
		}
	done <"$TMPDIR"/web_proxies
	rm -f "$TMPDIR"/web_proxies
	. "$CRASHDIR"/libs/compare.sh && compare "$TMPDIR"/web_save "$CRASHDIR"/configs/web_save
	[ "$?" = 0 ] && rm -f "$TMPDIR"/web_save || mv -f "$TMPDIR"/web_save "$CRASHDIR"/configs/web_save
}
