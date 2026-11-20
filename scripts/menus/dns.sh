#!/bin/sh
# Copyright (C) Juewuy

[ -n "$__IS_MODULE_DNS_LOADED" ] && return
__IS_MODULE_DNS_LOADED=1

load_lang dns

# 安全加固：向配置文件追加一条规则/域名，先 trim、去空、去重、校验基本合法性。
# $1=目标文件  $2=输入内容  $3=类型(domain|rule)
# 返回 0=已追加  1=重复/无效
dns_cfg_append() {
    _dc_file="$1"
    _dc_val=$(printf '%s' "$2" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$_dc_val" ] && return 1
    # 域名字段不允许出现裸空格或逗号（会破坏 YAML/JSON），规则字段允许通配符但不允许空白
    if printf '%s' "$_dc_val" | grep -qE '[[:space:],"]'; then
        msg_alert "\033[31m$DNS_INPUT_INVALID\033[0m"
        return 1
    fi
    # 去重：整行精确匹配（忽略注释行）
    if [ -f "$_dc_file" ] && grep -qxF "$_dc_val" "$_dc_file"; then
        msg_alert "\033[33m$DNS_DUPLICATE\033[0m"
        return 1
    fi
    printf '%s\n' "$_dc_val" >>"$_dc_file" && return 0
    return 1
}

# 安全加固：判断 IPv4 地址是否落在 CIDR 网段内（用数值范围比较，不依赖 awk 位运算）
ip_in_cidr() {
    awk -v ip="$1" -v cidr="$2" 'BEGIN{
        split(cidr,c,"/"); split(c[1],n,"."); split(ip,a,".");
        ipn=a[1]*16777216+a[2]*65536+a[3]*256+a[4];
        netn=n[1]*16777216+n[2]*65536+n[3]*256+n[4];
        bits=c[2]+0;
        span=2^(32-bits);
        if(ipn>=netn && ipn<netn+span) exit 0; else exit 1;
    }'
}

# 安全加固：查看/修改 fake-ip 网段，附本地网段冲突检测
fake_ip_range() {
    while true; do
        comp_box "\033[32m$DNS_FAKEIP_RANGE\033[0m" \
            "\033[36mIPv4: $fakeip4\033[0m" \
            "\033[36mIPv6: $fakeip6\033[0m"
        _conflict=''
        for _lip in $(ip -4 -o addr 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | sort -u); do
            ip_in_cidr "$_lip" "$fakeip4" && _conflict="$_conflict $_lip"
        done
        [ -n "$_conflict" ] && content_line "\033[31m警告：本地地址 $_conflict 与 fake-ip 段重叠，可能导致路由异常！\033[0m" \
            || content_line "\033[32m未发现本地网段冲突\033[0m"
        content_line "\033[33m修改后需重启服务，防火墙规则会自动采用新段。\033[0m"
        btm_box "1) 修改 IPv4 fake-ip 段" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " _n
        case "$_n" in
        "" | 0) break ;;
        1)
            read -r -p "输入新 IPv4 CIDR（如 198.18.0.0/15）> " _new
            case "$_new" in
            */*) ;;
            *) msg_alert "\033[31m格式错误：需 CIDR 形式\033[0m"; continue ;;
            esac
            _ip=${_new%/*}; _bits=${_new#*/}
            echo "$_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || { msg_alert "\033[31m非法 IPv4\033[0m"; continue; }
            [ "$_bits" -ge 8 ] 2>/dev/null && [ "$_bits" -le 30 ] || { msg_alert "\033[31m掩码需在 8-30 之间\033[0m"; continue; }
            fakeip4="$_new"
            setconfig fakeip4 "'$fakeip4'"
            msg_alert "\033[32mfakeip4 已设为 $fakeip4，请重启服务\033[0m"
            ;;
        *) errornum ;;
        esac
    done
}

# DNS 模式设置
set_dns_mod() {
    while true; do
        [ -z "$hosts_opt" ] && hosts_opt=ON
        [ -z "$dns_protect" ] && dns_protect=ON
        [ -z "$ecs_subnet" ] && ecs_subnet=OFF
        comp_box "$DNS_CURRENT_MODE\033[47;30m $dns_mod \033[0m" \
            "\033[33m$DNS_RESTART_NOTICE\033[0m"
        content_line "1) $DNS_SET_TO MIX$COMMON_MOD：\t\033[32m$DNS_MODE_MIX_DESC\033[0m"
        content_line "2) $DNS_SET_TO Route$COMMON_MOD：\t\033[32m$DNS_MODE_ROUTE_DESC\033[0m"
        content_line "3) $DNS_SET_TO Redir$COMMON_MOD：\t\033[33m$DNS_MODE_REDIR_DESC\033[0m"
        content_line ""
        content_line "4) $DNS_MENU_PROTECT：\t \033[36m$dns_protect\033[0m\t$DNS_PROTECT_DESC"
        content_line "5) $DNS_MENU_HOSTS：\t \033[36m$hosts_opt\033[0m\t$DNS_HOSTS_DESC"
        content_line "6) $DNS_MENU_ECS：\t \033[36m$ecs_subnet\033[0m\t$DNS_ECS_DESC"
        content_line "7) $DNS_MENU_REDIR：\033[36m$dns_redir_port\033[0m\t$DNS_REDIR_PORT_DESC"
        [ "$dns_mod" = "mix" ] &&
            content_line "8) \033[33m$DNS_FAKEIP_MENU\033[0m"
        content_line "9) \033[36m$DNS_ADV_MENU\033[0m"
        content_line "b) \033[36m$DNS_FAKEIP_RANGE\033[0m"
        [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ] &&
            content_line "a) \033[32m$DNS_DIRECT_MENU\033[0m"
        content_line ""
        content_line "0) $COMMON_BACK"
        separator_line "="
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1 | 2)
            if echo "$crashcore" | grep -q 'singbox' || [ "$crashcore" = meta ]; then
                [ "$num" = 1 ] && dns_mod=mix || dns_mod=route
                setconfig dns_mod "$dns_mod"
                msg_alert "\033[36m$DNS_SET_OK：$dns_mod\033[0m"
            else
                msg_alert "\033[31m$DNS_CORE_UNSUPPORTED\033[0m"
            fi
            ;;
        3)
            dns_mod=redir_host
            setconfig dns_mod "$dns_mod"
            msg_alert "\033[36m$DNS_SET_OK：$dns_mod\033[0m"
            ;;
        4)
            if [ "$dns_protect" = ON ]; then
                dns_protect=OFF
            else
                dns_protect=ON
            fi
            setconfig dns_protect "$dns_protect"
            common_success
            ;;
        5)
            if [ "$hosts_opt" = ON ]; then
                hosts_opt=OFF
            else
                hosts_opt=ON
            fi
            setconfig hosts_opt "$hosts_opt"
            common_success
            ;;
        6)
            if [ "$ecs_subnet" = ON ]; then
                ecs_subnet=OFF
            else
                ecs_subnet=ON
            fi
            setconfig ecs_subnet "$ecs_subnet"
            common_success
            ;;
        7)
            while true; do
                comp_box "\033[31m$DNS_REDIR_WARN\033[0m" \
                    "\033[33m$DNS_REDIR_HINT 127.0.0.1:$dns_port\033[0m" \
                    "" \
                    "\033[36m$DNS_INPUT_REDIR_PORT\033[0m" \
                    "$DNS_INPUT_REDIR_RESET" \
                    "$DNS_INPUT_REDIR_BACK"
                read -r -p "$DNS_INPUT> " num
                case "$num" in
                0)
                    break
                    ;;
                r)
                    dns_redir_port="$dns_port"
                    setconfig dns_redir_port
                    common_success
                    break
                    ;;
                *)
                    if [ "$num" -ge 1 ] && [ "$num" -lt 65535 ]; then
                        if netstat -ntul 2>/dev/null | grep -q ":$num " || ss -ntul 2>/dev/null | grep -q ":$num "; then
                            dns_redir_port="$num"
                            setconfig dns_redir_port "$dns_redir_port"
                            common_success
                            break
                        else
                            msg_alert "\033[33m$DNS_REDIR_NO_SERVICE\033[0m"
                        fi
                    else
                        errornum
                    fi
                    ;;
                esac
            done
            ;;
        8)
            fake_ip_filter
            ;;
        9)
            set_dns_adv
            ;;
        b)
            fake_ip_range
            ;;
        a)
            if [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ]; then
                dns_direct_domains
            else
                msg_alert "\033[33m直连域名功能仅在 mix/route 模式下可用！\033[0m"
            fi
            ;;
        *)
            errornum
            ;;
        esac
    done
}

fake_ip_filter() {
    while true; do
        comp_box "\033[32m$DNS_FAKEIP_DESC\033[0m" \
            "\033[31m$DNS_FAKEIP_TIP\033[0m" \
            "\033[36m$DNS_FAKEIP_EXAMPLE\033[0m"
        if [ -s "$CRASHDIR/configs/fake_ip_filter" ]; then
            content_line "\033[33m$DNS_FAKEIP_EXIST\033[0m"
            content_line ""
            awk '{print NR") "$1}' "$CRASHDIR/configs/fake_ip_filter" |
                while IFS= read -r line; do
                    content_line "$line"
                done
        else
            content_line "\033[33m$DNS_FAKEIP_EMPTY\033[0m"
        fi
        btm_box "" \
            "0) $COMMON_BACK"
        read -r -p "$DNS_FAKEIP_EDIT> " input
        case "$input" in
        "" | 0)
            break
            ;;
        *)
            if [ "$input" -ge 1 ] 2>/dev/null; then
                if sed -i "${input}d" "$CRASHDIR/configs/fake_ip_filter"; then
                    msg_alert "\033[32m$DNS_REMOVE_OK\033[0m"
                else
                    msg_alert "\033[31m$DNS_REMOVE_FAIL\033[0m"
                fi
            else
                comp_box "$DNS_CONFIRM_ADD\033[32m$input\033[0m"
                btm_box "1) $DNS_CONFIRM_OK" \
                    "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT>" res
                if [ "$res" = 1 ]; then
                    if dns_cfg_append "$CRASHDIR/configs/fake_ip_filter" "$input" rule; then
                        msg_alert "\033[32m$DNS_ADD_OK\033[0m"
                    else
                        msg_alert "\033[31m$DNS_ADD_FAIL\033[0m"
                    fi
                else
                    break
                fi
            fi
            ;;
        esac
    done
}

# 直连域名管理
dns_direct_domains() {
    while true; do
        comp_box "\033[32m$DNS_DIRECT_DESC\033[0m" \
            "\033[36m$DNS_DIRECT_TIP\033[0m" \
            "$DNS_DIRECT_EXAMPLE"
        if [ -s "$CRASHDIR/configs/dns_direct_domains" ]; then
            content_line "\033[33m$DNS_DIRECT_EXIST\033[0m"
            content_line ""
            awk '{print NR") "$1}' "$CRASHDIR/configs/dns_direct_domains" |
                while IFS= read -r line; do
                    content_line "$line"
                done
        else
            content_line "\033[33m$DNS_DIRECT_EMPTY\033[0m"
        fi
        btm_box "" \
            "a) $DNS_DIRECT_ADD_LAN" \
            "r) $DNS_DIRECT_LOAD_PRESET" \
            "t) $DNS_DIRECT_TEST" \
            "0) $COMMON_BACK"
        read -r -p "$DNS_DIRECT_EDIT> " input
        case "$input" in
        "" | 0)
            break
            ;;
        a)
            comp_box "$DNS_DIRECT_INPUT_HINT"
            btm_box "1) $DNS_CONFIRM_OK" \
                "0) $COMMON_BACK"
            read -r -p "$DNS_INPUT> " domain
            case "$domain" in
            0)
                continue
                ;;
            *)
                if dns_cfg_append "$CRASHDIR/configs/dns_direct_domains" "$domain" domain; then
                    msg_alert "\033[32m$DNS_ADD_OK\033[0m"
                else
                    msg_alert "\033[31m$DNS_ADD_FAIL\033[0m"
                fi
                ;;
            esac
            ;;
        r)
            if [ -s "$CRASHDIR/public/dns_direct_domains.list" ]; then
                # 安全加固：预设合并时去重，不重复写入已存在的域名
                _added=0
                while IFS= read -r _pd || [ -n "$_pd" ]; do
                    case "$_pd" in '' | \#*) continue ;; esac
                    dns_cfg_append "$CRASHDIR/configs/dns_direct_domains" "$_pd" domain >/dev/null 2>&1 && _added=$((_added + 1))
                done <"$CRASHDIR/public/dns_direct_domains.list"
                msg_alert "\033[32m$DNS_DIRECT_LOAD_OK (+$_added)\033[0m"
            else
                msg_alert "\033[31m预设文件不存在！\033[0m"
            fi
            ;;
        t)
            comp_box "$DNS_DIRECT_TEST_INPUT"
            btm_box "1) $DNS_CONFIRM_OK" \
                "0) $COMMON_BACK"
            read -r -p "$DNS_INPUT> " test_domain
            case "$test_domain" in
            0)
                continue
                ;;
            *)
                # 安全加固：优先用 nslookup；精简系统无 nslookup 时用内核 DNS API(Clash/Mihomo) 兜底
                if command -v nslookup >/dev/null 2>&1; then
                    result=$(nslookup "$test_domain" 127.0.0.1:$dns_port 2>&1 || echo "解析失败")
                elif command -v dig >/dev/null 2>&1; then
                    result=$(dig +short +time=2 "@127.0.0.1" -p "$dns_port" "$test_domain" 2>&1 || echo "解析失败")
                else
                    # 通过 mihomo/clash external-controller 的 /dns/query 接口查询
                    [ -z "$secret" ] && secret=$(grep -E '^secret=' "$CRASHDIR/configs/ShellCrash.cfg" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d "'\"")
                    _dns_json=$(printf '{"host":"%s","type":"A"}' "$test_domain")
                    if command -v curl >/dev/null 2>&1; then
                        result=$(curl -s --connect-timeout 3 -H "Authorization: Bearer $secret" -H 'Content-Type: application/json' -X POST "http://127.0.0.1:$db_port/dns/query" -d "$_dns_json" 2>&1)
                    elif command -v wget >/dev/null 2>&1; then
                        result=$(wget -q --timeout=3 --header="Authorization: Bearer $secret" --header='Content-Type: application/json' --method=POST --body-data="$_dns_json" -O - "http://127.0.0.1:$db_port/dns/query" 2>&1)
                    else
                        result="无可用 DNS 查询工具（nslookup/dig/curl/wget 均缺失）"
                    fi
                    [ -z "$result" ] && result="查询无响应（确认内核已启动且 dns.enable=true）"
                fi
                comp_box "$DNS_DIRECT_TEST_RESULT" \
                    "$result"
                # 判断是否在直连列表中
                if [ -f "$CRASHDIR/configs/dns_direct_domains" ] && grep -qF "$test_domain" "$CRASHDIR/configs/dns_direct_domains"; then
                    content_line "\033[32m$DNS_DIRECT_TEST_IN_LIST\033[0m"
                else
                    content_line "\033[33m$DNS_DIRECT_TEST_NOT_IN_LIST\033[0m"
                fi
                btm_box "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT> " res
                ;;
            esac
            ;;
        *)
            if [ "$input" -ge 1 ] 2>/dev/null; then
                if sed -i "${input}d" "$CRASHDIR/configs/dns_direct_domains"; then
                    msg_alert "\033[32m$DNS_REMOVE_OK\033[0m"
                else
                    msg_alert "\033[31m$DNS_REMOVE_FAIL\033[0m"
                fi
            fi
            ;;
        esac
    done
}

# DNS详细设置
set_dns_adv() {
    [ -z "$dns_failover" ] && dns_failover=OFF
    while true; do
        comp_box "\033[31m$DNS_ADV_SINGBOX_LIMIT\033[0m" \
            "$DNS_ADV_SPLIT" \
            "\033[33m$DNS_ADV_CERT\033[0m" \
            "" \
            "DIRECT-DNS：" \
            "\033[32m$dns_nameserver\033[0m" \
            "" \
            "PROXY-DNS：" \
            "\033[36m$dns_fallback\033[0m" \
            "" \
            "RESOLVER-DNS：" \
            "\033[33m$dns_resolver\033[0m" \
            "" \
            "PROXY-SERVER-DNS：" \
            "\033[33m$dns_proxy_server\033[0m" \
            ""
        btm_box "1) $DNS_ADV_EDIT_DIRECT" \
            "2) $DNS_ADV_EDIT_PROXY" \
            "3) $DNS_ADV_EDIT_RESOLVER" \
			"4) $DNS_ADV_EDIT_PROXY_SERVER" \
            "5) \033[32m$DNS_ADV_AUTO_ENCRYPT\033[0m" \
            "6) $DNS_ADV_FAILOVER：\t\033[36m$dns_failover\033[0m" \
            "7) $DNS_RESPECT_RULES：\t\033[36m$dns_respect_rules\033[0m" \
            "9) \033[33m$DNS_ADV_RESET\033[0m" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            comp_box "$DNS_NOW\033[32m$dns_nameserver\033[0m"
            btm_box "\033[36m$DNS_INPUT_NEW\033[0m" \
                "$DNS_INPUT_RESET" \
                "$DNS_INPUT_REDIR_BACK"
            read -r -p "$DNS_INPUT> " res
            case "$res" in
            0)
                continue
                ;;
            r)
                dns_nameserver="127.0.0.1"
                setconfig dns_nameserver "'$dns_nameserver'"
                common_success
                ;;
            *)
                dns_nameserver=$(echo "$res" | sed 's#|#,\ #g')
                if [ -n "$dns_nameserver" ]; then
                    setconfig dns_nameserver "'$dns_nameserver'"
                    common_success
                else
                    common_failed
                fi
                ;;
            esac
            ;;
        2)
            comp_box "$DNS_NOW\033[32m$dns_fallback\033[0m"
            btm_box "\033[36m$DNS_INPUT_NEW\033[0m" \
                "$DNS_INPUT_RESET" \
                "$DNS_INPUT_REDIR_BACK"
            read -r -p "$DNS_INPUT> " res
            case "$res" in
            0)
                continue
                ;;
            r)
                dns_fallback="1.1.1.1, 8.8.8.8"
                setconfig dns_fallback "'$dns_fallback'"
                common_success
                ;;
            *)
                dns_fallback=$(echo "$res" | sed 's#|#,\ #g')
                if [ -n "$dns_fallback" ]; then
                    setconfig dns_fallback "'$dns_fallback'"
                    common_success
                else
                    common_failed
                fi
                ;;
            esac
            ;;
        3)
            comp_box "$DNS_NOW\033[32m$dns_resolver\033[0m"
            btm_box "\033[36m$DNS_INPUT_NEW\033[0m" \
                "$DNS_INPUT_RESET" \
                "$DNS_INPUT_REDIR_BACK"
            separator_line "="
            read -r -p "$DNS_INPUT> " res
            case "$res" in
            0)
                continue
                ;;
            "r")
                dns_resolver="223.5.5.5, 2400:3200::1"
                setconfig dns_resolver "'$dns_resolver'"
                common_success
                ;;
            *)
                if echo "$res" | grep -qE '://.*::'; then
                    msg_alert "\033[31m$DNS_IPV6_NOT_SUPPORT\033[0m"
                else
                    dns_resolver=$(echo "$res" | sed 's#|#,\ #g')
                    setconfig dns_resolver "'$dns_resolver'"
                    msg_alert "\033[32m$COMMON_SUCCESS\033[0m"
                fi
                ;;
            esac
            ;;
        4)
            comp_box "$DNS_NOW\033[32m$dns_proxy_server\033[0m"
            btm_box "\033[36m$DNS_INPUT_NEW\033[0m" \
                "$DNS_INPUT_RESET" \
                "$DNS_INPUT_REDIR_BACK"
            separator_line "="
            read -r -p "$DNS_INPUT> " res
            case "$res" in
            0)
                continue
                ;;
            "r")
                dns_proxy_server="$dns_resolver"
                setconfig dns_proxy_server "'$dns_proxy_server'"
                common_success
                ;;
            *)
                if echo "$res" | grep -qE '://.*::'; then
                    msg_alert "\033[31m$DNS_IPV6_NOT_SUPPORT\033[0m"
                else
                    dns_proxy_server=$(echo "$res" | sed 's#|#,\ #g')
                    setconfig dns_proxy_server "'$dns_proxy_server'"
                    msg_alert "\033[32m$COMMON_SUCCESS\033[0m"
                fi
                ;;
            esac
            ;;
		5)
            line_break
            separator_line "="
            if echo "$crashcore" | grep -qE 'meta|singbox'; then
                dns_nameserver='https://dns.alidns.com/dns-query, https://doh.pub/dns-query'
                dns_fallback='https://cloudflare-dns.com/dns-query, https://dns.google/dns-query, https://doh.opendns.com/dns-query'
                dns_resolver='https://223.5.5.5/dns-query, 2400:3200::1'
                setconfig dns_nameserver "'$dns_nameserver'"
                setconfig dns_fallback "'$dns_fallback'"
                setconfig dns_resolver "'$dns_resolver'"
                content_line "\033[32m$DNS_ENCRYPT_OK\033[0m"
            else
                content_line "\033[31m$DNS_CORE_REQUIRE\033[0m"
            fi
            separator_line "="
            ;;
        6)
            [ "$dns_failover" = "ON" ] && dns_failover=OFF || dns_failover=ON
            setconfig dns_failover "$dns_failover"
            if [ "$dns_failover" = "ON" ]; then
                msg_alert "\033[33m$DNS_ADV_FAILOVER_TIP\033[0m"
            else
                common_success
            fi
            ;;
        7)
            # 安全加固：切换 respect-rules，仅 meta 内核有意义
            if echo "$crashcore" | grep -q 'meta'; then
                [ "$dns_respect_rules" = "ON" ] && dns_respect_rules=OFF || dns_respect_rules=ON
                setconfig dns_respect_rules "$dns_respect_rules"
                msg_alert "\033[36m$DNS_RESPECT_RULES: $dns_respect_rules\033[0m"
            else
                msg_alert "\033[33m$DNS_CORE_UNSUPPORTED\033[0m"
            fi
            ;;
        9)
            setconfig dns_nameserver
            setconfig dns_fallback
            setconfig dns_resolver
            setconfig dns_failover
            setconfig dns_respect_rules
            . "$CRASHDIR/libs/get_config.sh"
            common_success
            ;;
        *)
            errornum
            ;;
        esac
    done
}
