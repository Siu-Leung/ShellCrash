#!/bin/sh
# Copyright (C) Juewuy

#修饰singbox配置文件

# 安全加固/修正：解析 DNS server 字符串为 sing-box 1.14+ DNS server JSON 字段片段。
# 用途：把 ShellCrash 的 DNS 配置项（逗号分隔列表的第一项）转换为 sing-box 所需 JSON 键值。
# 参数：$1 DNS server 字符串，支持:
#       - 纯 IP / 域名（默认 udp，端口 53）
#       - [IPv6]:port 形式（含方括号的 IPv6 字面量）
#       - scheme://host[:port][/path] 形式（udp/tcp/doh/https/dot/tls）
# 返回：echo 一段带尾逗号的 JSON 字段：'"type": ..., "server": ..., "server_port": ..., ["path": ...,"]'
# 设计说明/边界条件：
#   1. DoH(https) 的 path 必须保留：sing-box 用 "path" 字段承载 /dns-query/<uuid> 这类私有长路径，
#      原实现把 /path 丢弃，且 port 得到 "port/path" 非数字，导致私有 DoH 完全不可用。
#   2. scheme:// 后的 host:port/path 需先剥离 path 再解析端口；IPv6 用 [..]:port 单独处理。
#   3. type 保留原值（doh/https/dot/tls 等）：sing-box 1.14+ 使用 https/tls 类型名，
#      ShellCrash 配置里常见 doh/dot 别名，这里由内核/配置侧保证一致，不在本函数改名。
#   4. 输出为 JSON 字段片段（含尾逗号），调用方直接嵌入 JSON 对象。
parse_singbox_dns() { #dns转换工具
    first_dns=$(printf '%s\n' "$1" | cut -d',' -f1 | cut -d' ' -f1)
    type=""
    server=""
    port=""
    path=""
    case "$first_dns" in
        *://*)
            type="${first_dns%%://*}"
            tmp="${first_dns#*://}"
            # 修正：scheme:// 之后的部分可能含 /path，先切出 path（含前导 /），只用 host[:port] 解析端口
            case "$tmp" in
                */*) path="/${tmp#*/}"; tmp="${tmp%%/*}" ;;
            esac
            ;;
        *)
            type="udp"
            tmp="$first_dns"
            ;;
    esac
    case "$tmp" in
        \[*\]*)
            # IPv6 字面量：[2001:db8::1]:53 —— 去掉方括号取 server，取 ] 后冒号后为端口
            server="${tmp%%]*}"
            server="${server#[}"
            port="${tmp#*\]}"
            port="${port#:}"
            ;;
        *)
            # 域名或 IPv4：按首个 ':' 或 '/' 切分（path 已在上一步剥离）
            server="${tmp%%[:/]*}"
            port="${tmp#*:}"
            [ "$port" = "$tmp" ] && port=""
            ;;
    esac
    if [ -z "$port" ] || printf '%s' "$port" | grep -q '[^0-9]'; then
        # 修正：端口非纯数字（如旧逻辑把 "44443/dns-query/x" 当作端口）时按缺省端口处理
        port=""
    fi
    if [ -z "$port" ]; then
        case "$type" in
            udp|tcp) port=53 ;;
            doh|https) port=443 ;;
            dot|tls) port=853 ;;
            *) port=53 ;;
        esac
    fi
    # 输出：path 仅在有路径时输出，符合 sing-box 1.14+ https DNS server 语法
    if [ -n "$path" ]; then
        echo '"type": "'"$type"'", "server": "'"$server"'", "server_port": '"$port"', "path": "'"$path"'",'
    else
        echo '"type": "'"$type"'", "server": "'"$server"'", "server_port": '"$port"','
    fi
}

# 安全加固：把 ShellCrash 的通配符规则文件正确转换为 sing-box 的 domain/domain_suffix/domain_regex 规则。
# 输入行约定：纯域名 -> domain；*.example.com / +.example.com -> domain_suffix；含内部 * 的 -> domain_regex；
# '#' 开头或空行忽略。输出三个全局变量：_fp_domain / _fp_suffix / _fp_regex（逗号分隔的 JSON 字符串片段）。
sb_convert_domain_rules() {
    _fp_domain=''; _fp_suffix=''; _fp_regex=''
    for _fp_file in "$@"; do
        [ -f "$_fp_file" ] || continue
        while IFS= read -r _fp_line || [ -n "$_fp_line" ]; do
            _fp_line=$(printf '%s' "$_fp_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            case "$_fp_line" in '' | \#*) continue ;; esac
            case "$_fp_line" in
                '*.'* | '+.'*)
                    # 后缀通配：去掉前缀符号
                    _fp_v=${_fp_line#[*+].}
                    [ -n "$_fp_v" ] && _fp_suffix="$_fp_suffix\"$_fp_v\", "
                    ;;
                *'*'*)
                    # 内部通配：转正则，先转义点，再把 * 换成 .*
                    _fp_v=$(printf '%s' "$_fp_line" | sed 's/\./\\./g; s/\*/.*/g')
                    [ -n "$_fp_v" ] && _fp_regex="$_fp_regex\"$_fp_v\", "
                    ;;
                *)
                    # 纯域名（含 geosite:xxx / rule-set:xxx 这类保留原样由内核解析）
                    _fp_domain="$_fp_domain\"$_fp_line\", "
                    ;;
            esac
        done <"$_fp_file"
    done
    _fp_domain=${_fp_domain%, }; _fp_suffix=${_fp_suffix%, }; _fp_regex=${_fp_regex%, }
}

extract_base_jsons() { #提取配置文件以获得outbounds.json,providers.json及route.json
    "$TMPDIR"/CrashCore format -c $core_config >"$TMPDIR"/format.json
    echo '{' >"$TMPDIR"/jsons/outbounds.json
    echo '{' >"$TMPDIR"/jsons/route.json
    cat "$TMPDIR"/format.json | sed -n '/"outbounds":/,/^  "[a-z]/p' | sed '$d' >>"$TMPDIR"/jsons/outbounds.json
    [ "$crashcore" = "singboxr" ] && {
        echo '{' >"$TMPDIR"/jsons/providers.json
        cat "$TMPDIR"/format.json | sed -n '/^  "providers":/,/^  "[a-z]/p' | sed '$d' >>"$TMPDIR"/jsons/providers.json
    }
    cat "$TMPDIR"/format.json | sed -n '/"route":/,/^\(  "[a-z]\|}\)/p' | sed '$d' >>"$TMPDIR"/jsons/route.json
	#清理PASS规则
    sed -i 's/"PASS"/"DIRECT"/g' "$TMPDIR"/jsons/outbounds.json
}

generate_basic_jsons() {
	#适配1.14+版本（安全提取数字次版本号，避免空值或带连字符版本报错）
	_sb_minor=$(printf '%s' "$core_v" | sed -n 's/^[^0-9]*[0-9][0-9]*\.\([0-9][0-9]*\).*/\1/p')
	[ -z "$_sb_minor" ] && _sb_minor=14
	if [ "$_sb_minor" -lt 14 ];then
		preferred='"ip_accept_any": true,'
		detour_direct='"download_detour": "DIRECT"'
	else
		preferred='"preferred_by": [ "hosts" ],'
		detour_direct='"http_client": "detour_direct"'
		#生成http_clients.json
		cat >"$TMPDIR"/jsons/http_clients.json <<EOF
	{
	  "http_clients": [
		{
		  "tag": "detour_proxy",
		  "detour": "GLOBAL"
		},
		{
		  "tag": "detour_direct",
		  "detour": "DIRECT"
		}
	  ]
	}
EOF
	fi
    #生成endpoints.json
    [ "$ts_service" = ON ] || [ "$wg_service" = ON ] && [ "$zip_type" != upx ] && {
        . "$CRASHDIR"/configs/gateway.cfg
        . "$CRASHDIR"/libs/sb_endpoints.sh
    }
    #生成log.json
    cat >"$TMPDIR"/jsons/log.json <<EOF
{ "log": { "level": "info", "timestamp": true } }
EOF
    #生成add_hosts.json
    if [ "$hosts_opt" != "OFF" ]; then #本机hosts
        [ -s /data/etc/custom_hosts ] && custom_hosts='"/data/etc/custom_hosts",'
        #NTP劫持
        cat >"$TMPDIR"/jsons/add_hosts.json <<EOF
{
  "dns": {
    "servers": [
      {
        "type": "hosts",
        "tag": "hosts",
        "path": [
          $custom_hosts
          "$HOME/.hosts",
          "/etc/hosts"
        ],
        "predefined": {
          "localhost": [
            "127.0.0.1",
            "::1"
          ],
          "time.android.com": "203.107.6.88",
          "time.facebook.com": "203.107.6.88"
        }
      }
    ],
    "rules": [
      {
        $preferred
        "server": "hosts"
      }
    ]
  }
}
EOF
    fi
}

gen_dns() {
    # 安全加固：每次生成前清空规则片段变量，避免分支间残留
    fake_ip_filter_domain=''; fake_ip_filter_suffix=''; fake_ip_filter_regex=''
    custom_direct_domain_rule=''; custom_direct_suffix_rule=''; custom_direct_regex_rule=''
    direct_dns=''; proxy_dns=''; client_subnet=''
    #生成dns.json
    [ "$ipv6_dns" != "OFF" ] && strategy='prefer_ipv4' || strategy='ipv4_only'
    #获取detour出口
    auto_detour=$(grep -E '"type": "urltest"' -A 1 "$TMPDIR"/jsons/outbounds.json | grep '自动' | head -n 1 | sed 's/^[[:space:]]*"tag": //;s/,$//')
    [ -z "$auto_detour" ] && auto_detour=$(grep -E '"type": "urltest"' -A 1 "$TMPDIR"/jsons/outbounds.json | grep '"tag":' | head -n 1 | sed 's/^[[:space:]]*"tag": //;s/,$//')
    [ -z "$auto_detour" ] && auto_detour=$(grep -E '"type": "selector"' -A 1 "$TMPDIR"/jsons/outbounds.json | grep '"tag":' | head -n 1 | sed 's/^[[:space:]]*"tag": //;s/,$//')
    [ -z "$auto_detour" ] && auto_detour='"DIRECT"'
    #ecs优化
    [ "$ecs_subnet" = ON ] && {
        . "$CRASHDIR"/libs/get_ecsip.sh
        if [ -n "$ecs_address" ]; then
            client_subnet='"client_subnet": "'"$ecs_address"'",'
        else
            logger "自动获取ecs网段失败！" 33
        fi
    }
    #根据dns模式生成
    [ "$dns_mod" = "redir_host" ] && {
        global_dns=dns_proxy
        direct_dns='{ "inbound": [ "dns-in" ], "server": "dns_direct" }'
    }
    [ "$dns_mod" = "fake-ip" ] || [ "$dns_mod" = "mix" ] && {
        global_dns=dns_fakeip
        # 安全加固：统一、正确地分类转换 fake-ip 过滤规则与用户直连域名
        sb_convert_domain_rules "$CRASHDIR/configs/fake_ip_filter" "$CRASHDIR/configs/fake_ip_filter.list"
        fake_ip_filter_domain=$_fp_domain; fake_ip_filter_suffix=$_fp_suffix; fake_ip_filter_regex=$_fp_regex
        [ -n "$fake_ip_filter_domain" ] && fake_ip_filter_domain="{ \"domain\": [$fake_ip_filter_domain], \"server\": \"dns_direct\" },"
        [ -n "$fake_ip_filter_suffix" ] && fake_ip_filter_suffix="{ \"domain_suffix\": [$fake_ip_filter_suffix], \"server\": \"dns_direct\" },"
        [ -n "$fake_ip_filter_regex" ] && fake_ip_filter_regex="{ \"domain_regex\": [$fake_ip_filter_regex], \"server\": \"dns_direct\" },"
        # 用户自定义直连域名
        if [ -s "$CRASHDIR/configs/dns_direct_domains" ]; then
            sb_convert_domain_rules "$CRASHDIR/configs/dns_direct_domains"
            custom_direct_domain=$_fp_domain; custom_direct_suffix=$_fp_suffix; custom_direct_regex=$_fp_regex
            [ -n "$custom_direct_domain" ] && custom_direct_domain_rule="{ \"domain\": [$custom_direct_domain], \"server\": \"dns_direct\" },"
            [ -n "$custom_direct_suffix" ] && custom_direct_suffix_rule="{ \"domain_suffix\": [$custom_direct_suffix], \"server\": \"dns_direct\" },"
            [ -n "$custom_direct_regex" ] && custom_direct_regex_rule="{ \"domain_regex\": [$custom_direct_regex], \"server\": \"dns_direct\" },"
        fi
        proxy_dns='{ "query_type": ["A", "AAAA"], "server": "dns_fakeip", "rewrite_ttl": 1 }'
        #mix模式插入fakeip过滤规则
        [ "$dns_mod" = "mix" ] && direct_dns='{ "rule_set": ["cn"], "server": "dns_direct" },'
    }
    [ "$dns_mod" = "route" ] && {
        global_dns=dns_proxy
        direct_dns='{ "rule_set": ["cn"], "server": "dns_direct" }'
        # 用户自定义直连域名（安全加固：统一转换函数）
        if [ -s "$CRASHDIR/configs/dns_direct_domains" ]; then
            sb_convert_domain_rules "$CRASHDIR/configs/dns_direct_domains"
            custom_direct_domain=$_fp_domain; custom_direct_suffix=$_fp_suffix; custom_direct_regex=$_fp_regex
            [ -n "$custom_direct_domain" ] && custom_direct_domain_rule="{ \"domain\": [$custom_direct_domain], \"server\": \"dns_direct\" },"
            [ -n "$custom_direct_suffix" ] && custom_direct_suffix_rule="{ \"domain_suffix\": [$custom_direct_suffix], \"server\": \"dns_direct\" },"
            [ -n "$custom_direct_regex" ] && custom_direct_regex_rule="{ \"domain_regex\": [$custom_direct_regex], \"server\": \"dns_direct\" },"
        fi
    }
    #防泄露设置（修正：同时作用于 dns.json 的 final，而非仅无效替换 route.json）
    if [ "$dns_protect" = "OFF" ]; then
        _sb_dns_final="dns_direct"
        sed -i 's/"server": "dns_proxy"/"server": "dns_direct"/g' "$TMPDIR"/jsons/route.json
    else
        _sb_dns_final="dns_proxy"
    fi
    #生成add_rule_set.json
    [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ] && ! grep -Eq '"tag" *:[[:space:]]*"cn"' "$CRASHDIR"/jsons/*.json && ! grep -Eq '"tag"[[:space:]]*:[[:space:]]*\[[^]]*"cn"' "$CRASHDIR"/jsons/*.json && {
        [ "$crashcore" = "singboxr" ] && srs_path='"path": "./ruleset/cn.srs",'
        cat >"$TMPDIR"/jsons/add_rule_set.json <<EOF
{
  "route": {
    "rule_set": [
      {
        "tag": "cn",
        "type": "remote",
        "format": "binary",
        $srs_path
        "url": "https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@update/bin/geodata/srs_geosite_cn.srs",
        $detour_direct
      }
    ]
  }
}
EOF
}
    cat >"$TMPDIR"/jsons/dns.json <<EOF
{
  "dns": {
    "servers": [
      {
        "tag": "dns_proxy",
        $(parse_singbox_dns "$dns_fallback")
        "routing_mark": $routing_mark,
        "detour": $auto_detour,
        "domain_resolver": "dns_resolver"
      },
      {
        "tag": "dns_direct",
        $(parse_singbox_dns "$dns_nameserver")
        "routing_mark": $routing_mark,
        "domain_resolver": "dns_resolver"
      },
      {
        "tag": "dns_fakeip",
        "type": "fakeip",
        "inet4_range": "$fakeip4",
        "inet6_range": "$fakeip6"
      },
      {
        "tag": "dns_resolver",
        $(parse_singbox_dns "$dns_resolver")
        "routing_mark": $routing_mark
      },
      {
        "tag": "dns_proxy_server",
        $(parse_singbox_dns "$dns_proxy_server")
        "routing_mark": $routing_mark
      }
    ],
    "rules": [
      { "clash_mode": "Direct", "server": "dns_direct" },
      { "domain_suffix": ["services.googleapis.cn"], "server": "dns_fakeip", "rewrite_ttl": 1 },
      $fake_ip_filter_domain
      $fake_ip_filter_suffix
      $fake_ip_filter_regex
      $custom_direct_domain_rule
      $custom_direct_suffix_rule
      $custom_direct_regex_rule
      { "clash_mode": "Global", "query_type": ["A", "AAAA"], "server": "$global_dns", "rewrite_ttl": 1 },
      $direct_dns
      $proxy_dns
    ],
    "final": "$_sb_dns_final",
    "strategy": "$strategy",
    $client_subnet
    "reverse_mapping": true
  }
}
EOF
}

gen_outbounds() {
    #生成add_route.json
    #域名嗅探配置
    grep -q 'telegramip' "$TMPDIR"/jsons/route.json && telegramip_set=' "rule_set": [ "telegramip" ],'
    [ "$sniffer" != OFF ] && sniffer_set='{ "domain_suffix": [ "push.apple.com" ],'"$telegramip_set"' "domain": [ "Mijia Cloud" ], "invert": true, "action": "sniff", "timeout": "500ms" },'
    [ "$ts_service" = ON ] && tailscale_set='{ "inbound": [ "ts-ep" ], "port": 53, "action": "hijack-dns" },'
    cat >"$TMPDIR"/jsons/add_route.json <<EOF
{
  "route": {
    "default_domain_resolver": "dns_resolver",
    "default_mark": $routing_mark,
    "rules": [
      $tailscale_set
      $sniffer_set
      { "inbound": [ "dns-in" ], "action": "hijack-dns" },
      { "clash_mode": "Direct" , "outbound": "DIRECT" },
      { "clash_mode": "Global" , "outbound": "GLOBAL" }
    ]
  }
}
EOF
}

gen_certificate() { #生成certificate.json
    cat >"$TMPDIR"/jsons/certificate.json <<EOF
{
  "certificate": {
    "store": "mozilla"
  }
}
EOF
}

gen_inbounds() { #生成inbounds.json
    # 安全加固：纯净模式未开启公网访问时，mixed-in 仅监听 127.0.0.1
    if [ "$firewall_area" = "4" ] && [ "$public_support" != "ON" ]; then
        _sb_listen="127.0.0.1"
    else
        _sb_listen="::"
    fi
    [ -n "$authentication" ] && {
        username=$(printf '%s' "$authentication" | sed 's/:.*//' | sed 's/\\/\\\\/g; s/"/\\"/g') #混合端口账号密码
        password=$(printf '%s' "$authentication" | sed 's/^[^:]*://' | sed 's/\\/\\\\/g; s/"/\\"/g')
        userpass='"users": [{ "username": "'"$username"'", "password": "'"$password"'" }], '
    }
    cat >"$TMPDIR"/jsons/inbounds.json <<EOF
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "$_sb_listen",
      $userpass
      "listen_port": $mix_port
    },
    {
      "type": "direct",
      "tag": "dns-in",
      "listen": "$_sb_listen",
      "listen_port": $dns_port
    },
    {
      "type": "redirect",
      "tag": "redirect-in",
      "listen": "$_sb_listen",
      "listen_port": $redir_port
    },
    {
      "type": "tproxy",
      "tag": "tproxy-in",
      "listen": "$_sb_listen",
      "listen_port": $tproxy_port
    }
  ]
}
EOF
    #inbounds.json添加自定义入站
    [ "$vms_service" = ON ] || [ "$sss_service" = ON ] && {
        . "$CRASHDIR"/configs/gateway.cfg
        . "$CRASHDIR"/libs/sb_inbounds.sh
    }
    if [ "$redir_mod" = "Mix" ] || [ "$redir_mod" = "Tun" ]; then
        [ "$ipv6_redir" = 'ON' ] && [ -n "$(ip -6 rule show)" ] && ipv6_address='"fd00:face:b00c::1/126",'
		_sb_minor_tun=$(printf '%s' "$core_v" | sed -n 's/^[^0-9]*[0-9][0-9]*\.\([0-9][0-9]*\).*/\1/p')
		[ -z "$_sb_minor_tun" ] && _sb_minor_tun=14
		[ "$_sb_minor_tun" -le 14 ] && stack='"stack": "system",'
        cat >>"$TMPDIR"/jsons/tun.json <<EOF
{
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "utun",
      "address": [
        $ipv6_address
        "198.18.0.1/15"
      ],
      $stack
      "auto_route": false
    }
  ]
}
EOF
    fi
}

add_outbounds() { #生成add_outbounds.json
    add_direct=''; add_reject=''; add_global=''
    grep -qE '"tag": "DIRECT"' "$TMPDIR"/jsons/outbounds.json || add_direct='{ "tag": "DIRECT", "type": "direct" }'
    grep -qE '"tag": "REJECT"' "$TMPDIR"/jsons/outbounds.json || add_reject='{ "tag": "REJECT", "type": "block" }'
    grep -qE '"tag": "GLOBAL"' "$TMPDIR"/jsons/outbounds.json || {
        auto_proxies=$(grep -E '"type": "(selector|urltest)"' -A 1 "$TMPDIR"/jsons/outbounds.json | grep '"tag":' | sed 's/^[[:space:]]*"tag": //;$ s/,$//')
        [ -n "$auto_proxies" ] && add_global='{ "tag": "GLOBAL", "type": "selector", "outbounds": ['"$auto_proxies"', "DIRECT"]}'
    }
    # 修正：当 add_reject 为空但 add_direct 与 add_global 同时存在时也要补逗号
    [ -n "$add_direct" ] && [ -n "$add_reject$add_global" ] && add_direct="${add_direct},"
    [ -n "$add_reject" ] && [ -n "$add_global" ] && add_reject="${add_reject},"
    [ -n "$add_direct$add_reject$add_global" ] && cat >"$TMPDIR"/jsons/add_outbounds.json <<EOF
{
  "outbounds": [
    $add_direct
    $add_reject
    $add_global
  ]
}
EOF
}

gen_experimental() { #生成experimental.json
    [ "$crashcore" = "singboxr" ] && urltest_unified_delay=',"urltest_unified_delay": true'
    # 安全加固：纯净模式未开启公网访问时，external_controller 仅监听 127.0.0.1
    if [ "$firewall_area" = "4" ] && [ "$public_support" != "ON" ]; then
        _sb_ext_ctrl="127.0.0.1:$db_port"
    else
        _sb_ext_ctrl="0.0.0.0:$db_port"
    fi
    _sb_esc_secret=$(printf '%s' "$secret" | sed 's/\\/\\\\/g; s/"/\\"/g')
    cat >"$TMPDIR"/jsons/experimental.json <<EOF
{
  "experimental": {
    "clash_api": {
      "external_controller": "$_sb_ext_ctrl",
      "external_ui": "ui",
      "external_ui_download_url": "$external_ui_url",
      "secret": "$_sb_esc_secret",
      "default_mode": "Rule"
    }$urltest_unified_delay
  }
}
EOF
}

generate_custom_rules_json() { #生成自定义规则文件
    [ -n "$(grep -Ev ^# "$CRASHDIR"/yamls/rules.yaml 2>/dev/null)" ] && {
        cat "$CRASHDIR"/yamls/rules.yaml |
            sed '/^[[:space:]]*#/d; s/#.*//g' |
            sed 's/,no-resolve//g' |
            grep -oE '\-.*,.*,.*' |
            sed 's/- DOMAIN-SUFFIX,/{ "domain_suffix": [ "/g' |
            sed 's/- DOMAIN-KEYWORD,/{ "domain_keyword": [ "/g' |
            sed 's/- IP-CIDR,/{ "ip_cidr": [ "/g' |
            sed 's/- SRC-IP-CIDR,/{ "source_ip_cidr": [ "/g' |
            sed 's/- DST-PORT,/{ "port": [ /g' |
            sed 's/- SRC-PORT,/{ "source_port": [ /g' |
            sed 's/- GEOIP,/{ "geoip": [ "/g' |
            sed 's/- GEOSITE,/{ "geosite": [ "/g' |
            sed 's/- IP-CIDR6,/{ "ip_cidr": [ "/g' |
            sed 's/- DOMAIN,/{ "domain": [ "/g' |
            sed 's/- PROCESS-NAME,/{ "process_name": [ "/g' |
            sed '/"port":\|"source_port":/! s/,/" ], "outbound": "/g' |
            sed '/"port":\|"source_port":/ s/,/ ], "outbound": "/g' |
            sed 's/$/" },/g' |
            sed '1i\{ "route": { "rules": [ ' |
            sed '$s/,$/ ] } }/' >"$TMPDIR"/jsons/cust_add_rules.json
        [ ! -s "$TMPDIR"/jsons/cust_add_rules.json ] && rm -rf "$TMPDIR"/jsons/cust_add_rules.json
    }
}

normalize_and_finalize_jsons() { #修饰文件
    #清理route.json中的process_name规则以及"auto_detect_interface"
    sed -i '/"process_name": \[/,/],$/d' "$TMPDIR"/jsons/route.json
    sed -i '/"process_name": "[^"]*",/d' "$TMPDIR"/jsons/route.json
	sed -i 's/"auto_detect_interface": true/"auto_detect_interface": false/g' "$TMPDIR"/jsons/route.json
    #跳过本地tls证书验证（安全加固：fail-closed，仅显式 skip_cert=ON 时跳过）
    if [ "$skip_cert" = "ON" ]; then
        sed -i 's/"insecure": false/"insecure": true/g' "$TMPDIR"/jsons/outbounds.json "$TMPDIR"/jsons/providers.json 2>/dev/null
    else
        sed -i 's/"insecure": true/"insecure": false/g' "$TMPDIR"/jsons/outbounds.json "$TMPDIR"/jsons/providers.json 2>/dev/null
    fi
    #判断可用并修饰outbounds&providers&route.json结尾
    for file in outbounds providers route; do
        if [ -n "$(grep ${file} "$TMPDIR"/jsons/${file}.json 2>/dev/null)" ]; then
            sed -i 's/^  },$/  }/; s/^  ],$/  ]/' "$TMPDIR"/jsons/${file}.json
            echo '}' >>"$TMPDIR"/jsons/${file}.json
        else
            rm -rf "$TMPDIR"/jsons/${file}.json
        fi
    done
}

link_custom_jsons() { #合并文件
    #加载自定义配置文件
    mkdir -p "$TMPDIR"/jsons_base
    #以下为覆盖脚本的自定义文件
    for char in log dns ntp certificate http_clients experimental; do
        [ -s "$CRASHDIR"/jsons/${char}.json ] && {
            ln -sf "$CRASHDIR"/jsons/${char}.json "$TMPDIR"/jsons/cust_${char}.json
            mv -f "$TMPDIR"/jsons/${char}.json "$TMPDIR"/jsons_base #如果重复则临时备份
        }
    done
    #以下为增量添加的自定义文件
    for char in others endpoints inbounds outbounds providers route services; do
        [ -s "$CRASHDIR"/jsons/${char}.json ] && {
            ln -sf "$CRASHDIR"/jsons/${char}.json "$TMPDIR"/jsons/cust_${char}.json
        }
    done
}

test_json() { #测试自定义配置文件
    if ! error=$("$TMPDIR"/CrashCore check -D "$BINDIR" -C "$TMPDIR"/jsons 2>&1); then
        echo $error
        error_file=$(echo $error | grep -Eo 'cust.*\.json' | sed 's/cust_//g')
        [ "$error_file" = 'add_rules.json' ] && error_file="$CRASHDIR"/yamls/rules.yaml自定义规则 || error_file="$CRASHDIR"/jsons/$error_file
        logger "自定义配置文件校验失败，请检查【${error_file}】文件！" 31
        logger "尝试使用基础配置文件启动~" 33
        #清理自定义配置文件并还原基础配置
        rm -rf "$TMPDIR"/jsons/cust_*
        mv -f "$TMPDIR"/jsons_base/* "$TMPDIR"/jsons 2>/dev/null
    fi
}

modify_json() { #入口
    extract_base_jsons
    generate_basic_jsons
    gen_dns
    gen_outbounds
	gen_certificate
	gen_inbounds
    add_outbounds
	gen_experimental
    generate_custom_rules_json
    normalize_and_finalize_jsons
    link_custom_jsons
    test_json
    #清理缓存
    rm -rf "$TMPDIR"/*.json
    rm -rf "$TMPDIR"/jsons_base
    return 0
}
