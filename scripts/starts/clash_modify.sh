#!/bin/sh
# Copyright (C) Juewuy

prepare_clash_base_config() {
    ##########需要变更的配置###########
    [ "$ipv6_dns" != "OFF" ] && dns_v6='true' || dns_v6='false'
    external="external-controller: 0.0.0.0:$db_port"
    if [ "$redir_mod" = "Mix" -o "$redir_mod" = "Tun" ]; then
        [ "$crashcore" = 'meta' ] && tun_meta=', device: utun, auto-route: false, auto-detect-interface: false'
        tun="tun: {enable: true, stack: mips$tun_meta}"
    else
        tun='tun: {enable: false}'
    fi
    exper='experimental: {ignore-resolve-fail: true, interface-name: en0}'
    #Meta内核专属配置
    [ "$crashcore" = 'meta' ] && {
        [ -z "$(grep 'PROCESS' "$CRASHDIR"/yamls/*.yaml)" ] && find_process='find-process-mode: "off"'
        #ecs优化：对直连/代理/proxy-server DNS 统一附加 ECS，bootstrap 域名服务器保持不变以免循环依赖
        [ "$ecs_subnet" = ON ] && {
            . "$CRASHDIR"/libs/get_ecsip.sh
            if [ -n "$ecs_address" ];then
                dns_nameserver=$(append_ecs_to_dns "$dns_nameserver" "$ecs_address")
                dns_fallback=$(append_ecs_to_dns "$dns_fallback" "$ecs_address")
                dns_proxy_server=$(append_ecs_to_dns "$dns_proxy_server" "$ecs_address")
            else
                logger "自动获取ecs网段失败！" 33
            fi
        }
    }
    #dns配置
    [ -z "$(cat "$CRASHDIR"/yamls/user.yaml 2>/dev/null | grep '^dns:')" ] && {
        [ "$crashcore" != meta ] && dns_resolver='223.5.5.5'
        # 安全加固：对所有 YAML flow 列表项加单引号，防止 https://[IPv6]:port 中的方括号/冒号破坏 YAML 解析
        _yaml_flow_list() {
            printf '%s' "$1" | awk -F',' '{
                out = ""
                for (i = 1; i <= NF; i++) {
                    s = $i
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
                    if (s == "") continue
                    gsub(/\047/, "\047\047", s)
                    out = (out == "" ? "\047" s "\047" : out ", \047" s "\047")
                }
                print out
            }'
        }
        _q_res=$(_yaml_flow_list "$dns_resolver")
        _q_ns=$(_yaml_flow_list "$dns_nameserver")
        if [ "$firewall_area" = "4" ] && [ "$public_support" != "ON" ]; then
            _dns_listen="127.0.0.1:$dns_port"
        else
            _dns_listen=":$dns_port"
        fi
        cat >"$TMPDIR"/dns.yaml <<EOF
dns:
  enable: true
  listen: $_dns_listen
  use-hosts: true
  ipv6: $dns_v6
  default-nameserver: [ $_q_res ]
  direct-nameserver: [ $_q_ns ]
  enhanced-mode: fake-ip
  fake-ip-range: $fakeip4
  fake-ip-range6: $fakeip6
  fake-ip-filter:
EOF
        if [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "fake-ip" ]; then
            cat "$CRASHDIR"/configs/fake_ip_filter "$CRASHDIR"/configs/fake_ip_filter.list 2>/dev/null | grep -v '#' | sed "s/^/    - '/" | sed "s/$/'/" >>"$TMPDIR"/dns.yaml
        else
            echo "    - '+.*'" >>"$TMPDIR"/dns.yaml #使用fake-ip模拟redir_host
        fi
        #mix模式fakeip绕过cn
        [ "$dns_mod" = "mix" ] && echo '    - "rule-set:cn"' >>"$TMPDIR"/dns.yaml
        #mix和route模式插入用户自定义直连域名
        if [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ]; then
            if [ -s "$CRASHDIR/configs/dns_direct_domains" ]; then
                cat "$CRASHDIR/configs/dns_direct_domains" | grep -v '^#' | sed "s/^/    - '/" | sed "s/$/'/" >>"$TMPDIR"/dns.yaml
            fi
        fi
        #mix模式和route模式插入分流设置
        if [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ]; then
            [ "$dns_protect" != "OFF" ] && dns_final="$dns_fallback" || dns_final="$dns_nameserver"
            # 构建nameserver-policy
            # 安全加固：respect-rules 默认 ON 保持原行为；设为 OFF 可规避与 nameserver-policy 语义重叠导致的解析异常
            if [ "$dns_respect_rules" = "OFF" ]; then
                echo "  respect-rules: false" >>"$TMPDIR"/dns.yaml
            else
                echo "  respect-rules: true" >>"$TMPDIR"/dns.yaml
            fi
            echo "  nameserver-policy:" >>"$TMPDIR"/dns.yaml
            _q_ps=$(_yaml_flow_list "$dns_proxy_server")
            _q_fin=$(_yaml_flow_list "$dns_final")
            # 添加用户自定义直连域名
            if [ -s "$CRASHDIR/configs/dns_direct_domains" ]; then
                cat "$CRASHDIR/configs/dns_direct_domains" | grep -v '^#' | while read domain; do
                    [ -n "$domain" ] && echo "    '$domain': [ $_q_ns ]" >>"$TMPDIR"/dns.yaml
                done
            fi
            # 添加CN规则集
            echo "    'rule-set:cn': [ $_q_ns ]" >>"$TMPDIR"/dns.yaml
            cat >>"$TMPDIR"/dns.yaml <<EOF
  proxy-server-nameserver: [ $_q_ps ]
  nameserver: [ $_q_fin ]
EOF
            if [ "$crashcore" = "meta" ] && [ "$dns_mod" = "route" ] && [ "$dns_protect" != "OFF" ] && [ "$dns_failover" = "ON" ]; then
                cat >>"$TMPDIR"/dns.yaml <<EOF
  fallback: [ $_q_ns ]
  fallback-filter:
    geoip: false
  fallback-lazy-query: true
EOF
            fi
        else
            cat >>"$TMPDIR"/dns.yaml <<EOF
  nameserver: [ $_q_ns ]
EOF
        fi
    }
    #域名嗅探配置
    [ "$sniffer" = "ON" ] && [ "$crashcore" = "meta" ] && sniffer_set="sniffer: {enable: true, parse-pure-ip: true, skip-domain: ['+.push.apple.com', 'Mijia Cloud'], sniff: {http: {ports: [80, 8080-8880], override-destination: true}, tls: {ports: [443, 8443]}, quic: {ports: [443, 8443]}}}"
    [ "$crashcore" = "clashpre" ] && [ "$dns_mod" = "redir_host" -o "$sniffer" = "ON" ] && exper="experimental: {ignore-resolve-fail: true, interface-name: en0,sniff-tls-sni: true}"
}

generate_set_and_hosts_yaml() {
    # 安全加固：纯净模式(firewall_area=4)下未开启公网访问时，默认仅绑定 127.0.0.1，避免无密码端口裸奔公网
    if [ "$firewall_area" = "4" ] && [ "$public_support" != "ON" ]; then
        _allow_lan='false'
        _ext_ctrl="127.0.0.1:$db_port"
    else
        _allow_lan='true'
        _ext_ctrl=":$db_port"
    fi
    _esc_auth=$(printf '%s' "$authentication" | sed 's/\\/\\\\/g; s/"/\\"/g')
    _esc_secret=$(printf '%s' "$secret" | sed 's/\\/\\\\/g; s/"/\\"/g')
    #生成set.yaml
    cat >"$TMPDIR"/set.yaml <<EOF
mixed-port: $mix_port
redir-port: $redir_port
tproxy-port: $tproxy_port
authentication: ["$_esc_auth"]
allow-lan: $_allow_lan
mode: Rule
log-level: info
ipv6: true
external-controller: $_ext_ctrl
external-ui: ui
external-ui-url: "$external_ui_url"
secret: "$_esc_secret"
$tun
$exper
$sniffer_set
$find_process
routing-mark: $routing_mark
unified-delay: true
EOF
    #读取本机hosts并生成配置文件
    if [ "$hosts_opt" != "OFF" ] && [ -z "$(grep -aE '^hosts:' "$CRASHDIR"/yamls/user.yaml 2>/dev/null)" ]; then
        #NTP劫持
        cat >"$TMPDIR"/hosts.yaml <<EOF
use-system-hosts: true
hosts:
  'time.android.com': 203.107.6.88
  'time.facebook.com': 203.107.6.88
EOF
        if [ "$crashcore" = "meta" ]; then
            echo "  'services.googleapis.cn': services.googleapis.com" >>"$TMPDIR"/hosts.yaml
        fi
        #加载本机hosts
        sys_hosts=/etc/hosts
        [ -f /data/etc/custom_hosts ] && sys_hosts='/etc/hosts /data/etc/custom_hosts'
        cat $sys_hosts | while read line; do
            [ -n "$(echo "$line" | grep -oE "([0-9]{1,3}[\.]){3}")" ] &&
                [ -z "$(echo "$line" | grep -oE '^#')" ] &&
                hosts_ip=$(echo $line | awk '{print $1}') &&
                hosts_domain=$(echo $line | awk '{print $2}') &&
                [ -z "$(cat "$TMPDIR"/hosts.yaml | grep -oE "$hosts_domain")" ] &&
                echo "  '$hosts_domain': $hosts_ip" >>"$TMPDIR"/hosts.yaml
        done
    fi
}

split_and_customize_yaml_parts() {
    #分割配置文件
    yaml_char='proxies proxy-groups proxy-providers rules rule-providers sub-rules listeners'
    for char in $yaml_char; do
        sed -n "/^$char:/,/^[a-z]/ { /^[a-z]/d; p; }" $core_config >"$TMPDIR"/${char}.yaml
        #支持 Clash 常见的单行 flow-style 非空节点列表，例如 proxies: [{name: ..., type: ...}]
        #修正：空列表 proxies: [] 不生成空 "- " 项（避免 Mihomo 报 proxy 0: missing type）
        if [ "$char" = proxies ] && [ ! -s "$TMPDIR"/proxies.yaml ]; then
            sed -n 's/^proxies:[[:space:]]*\[[[:space:]]*\([^][:space:]].*\)\][[:space:]]*$/  - \1/p' "$core_config" >"$TMPDIR"/proxies.yaml
        fi
    done
    #节点 TLS 证书策略（node_tls）：follow=跟随订阅不改（默认）；skip=全部跳过；verify=全部校验
    [ -f "$CRASHDIR"/libs/tls_policy.sh ] && . "$CRASHDIR"/libs/tls_policy.sh
    case "$(tls_node_mode)" in
    skip)
        sed -i 's/skip-cert-verify: false/skip-cert-verify: true/g' "$TMPDIR"/proxies.yaml "$TMPDIR"/proxy-providers.yaml 2>/dev/null
        # 没写 skip-cert-verify 的节点也补上 true，"全部跳过"才名副其实
        type tls_yaml_force_skip >/dev/null 2>&1 && tls_yaml_force_skip "$TMPDIR"/proxies.yaml
        ;;
    verify)
        sed -i 's/skip-cert-verify: true/skip-cert-verify: false/g' "$TMPDIR"/proxies.yaml "$TMPDIR"/proxy-providers.yaml 2>/dev/null
        ;;
    esac
    #插入自定义策略组
    sed -i "/#自定义策略组开始/,/#自定义策略组结束/d" "$TMPDIR"/proxy-groups.yaml
    sed -i "/#自定义策略组/d" "$TMPDIR"/proxy-groups.yaml
    [ -n "$(grep -Ev '^#' "$CRASHDIR"/yamls/proxy-groups.yaml 2>/dev/null)" ] && {
        #获取空格数
        space_name=$(grep -aE '^ *- \{?name: ' "$TMPDIR"/proxy-groups.yaml | head -n 1 | grep -oE '^ *')
        space_proxy="$space_name    "
        #合并自定义策略组到proxy-groups.yaml
        cat "$CRASHDIR"/yamls/proxy-groups.yaml | sed "/^#/d" | sed "s/#.*//g" | sed '1i\ #自定义策略组开始' | sed '$a\ #自定义策略组结束' | sed "s/^ */${space_name}  /g" | sed "s/^ *- /${space_proxy}- /g" | sed "s/^ *- name: /${space_name}- name: /g"  | sed "s/^ *- {name: /${space_name}- {name: /g" >"$TMPDIR"/proxy-groups_add.yaml
        cat "$TMPDIR"/proxy-groups.yaml >>"$TMPDIR"/proxy-groups_add.yaml
        mv -f "$TMPDIR"/proxy-groups_add.yaml "$TMPDIR"/proxy-groups.yaml
        oldIFS="$IFS"
        grep "\- name: " "$CRASHDIR"/yamls/proxy-groups.yaml | sed "/^#/d" | while read line; do #将自定义策略组插入现有的proxy-group
            new_group=$(echo $line | grep -Eo '^ *- name:.*#' | cut -d'#' -f1 | sed 's/.*name: //g')
            proxy_groups=$(echo $line | grep -Eo '#.*' | sed "s/#//")
            IFS="#"
            for name in $proxy_groups; do
                line_a=$(grep -n "\- name: $name" "$TMPDIR"/proxy-groups.yaml | head -n 1 | awk -F: '{print $1}') #获取group行号
                [ -n "$line_a" ] && {
                    line_b=$(grep -A 8 "\- name: $name" "$TMPDIR"/proxy-groups.yaml | grep -n "proxies:$" | head -n 1 | awk -F: '{print $1}') #获取proxies行号
                    line_c=$((line_a + line_b - 1))                                                                                           #计算需要插入的行号
                    space=$(sed -n "$((line_c + 1))p" "$TMPDIR"/proxy-groups.yaml | grep -oE '^ *')                                           #获取空格数
                    [ "$line_c" -gt 2 ] && sed -i "${line_c}a\\${space}- ${new_group} #自定义策略组" "$TMPDIR"/proxy-groups.yaml
                }
            done
            IFS="$oldIFS"
        done
    }
    #插入自定义代理
    sed -i "/#自定义代理/d" "$TMPDIR"/proxies.yaml
    sed -i "/#自定义代理/d" "$TMPDIR"/proxy-groups.yaml
    [ -n "$(grep -Ev '^#' "$CRASHDIR"/yamls/proxies.yaml 2>/dev/null)" ] && {
        space_proxy=$(cat "$TMPDIR"/proxies.yaml | grep -aE '^ *- ' | head -n 1 | grep -oE '^ *')                                                            #获取空格数
        cat "$CRASHDIR"/yamls/proxies.yaml | sed "s/^ *- /${space_proxy}- /g" | sed "/^#/d" | sed "/^ *$/d" | sed 's/#.*/ #自定义代理/g' >>"$TMPDIR"/proxies.yaml #插入节点
        oldIFS="$IFS"
        cat "$CRASHDIR"/yamls/proxies.yaml | sed "/^#/d" | while read line; do #将节点插入proxy-group
            proxy_name=$(echo $line | grep -Eo 'name: .+, ' | cut -d',' -f1 | sed 's/name: //g')
            proxy_groups=$(echo $line | grep -Eo '#.*' | sed "s/#//")
            IFS="#"
            for name in $proxy_groups; do
                line_a=$(grep -n "\- name: $name" "$TMPDIR"/proxy-groups.yaml | head -n 1 | awk -F: '{print $1}') #获取group行号
                [ -n "$line_a" ] && {
                    line_b=$(grep -A 8 "\- name: $name" "$TMPDIR"/proxy-groups.yaml | grep -n "proxies:$" | head -n 1 | awk -F: '{print $1}') #获取proxies行号
                    line_c=$((line_a + line_b - 1))                                                                                           #计算需要插入的行号
                    space=$(sed -n "$((line_c + 1))p" "$TMPDIR"/proxy-groups.yaml | grep -oE '^ *')                                           #获取空格数
                    [ "$line_c" -gt 2 ] && sed -i "${line_c}a\\${space}- ${proxy_name} #自定义代理" "$TMPDIR"/proxy-groups.yaml
                }
            done
            IFS="$oldIFS"
        done
    }
}

add_custom_inbounds_and_rules() {
    #添加自定义入站
    { [ "$vms_service" = ON ] || [ "$sss_service" = ON ]; } && [ -f "$CRASHDIR"/configs/gateway.cfg ] && {
        . "$CRASHDIR"/configs/gateway.cfg
        . "$CRASHDIR"/libs/meta_listeners.sh
    }
    #节点绕过功能支持
    sed -i "/#节点绕过/d" "$TMPDIR"/rules.yaml
    [ "$proxies_bypass" = "ON" ] && {
        cat "$TMPDIR"/proxies.yaml | sed '/^proxy-/,$d' | sed '/^rule-/,$d' | grep -v '^[[:space:]]*#' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '!a[$0]++' | sed 's/^/\ -\ IP-CIDR,/g' | sed 's|$|/32,DIRECT,no-resolve #节点绕过|g' >>"$TMPDIR"/proxies_bypass
        cat "$TMPDIR"/proxies.yaml | sed '/^proxy-/,$d' | sed '/^rule-/,$d' | grep -v '^[[:space:]]*#' | grep -vE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -oE '[a-zA-Z0-9][-a-zA-Z0-9]{0,62}(\.[a-zA-Z0-9][-a-zA-Z0-9]{0,62})+\.?' | awk '!a[$0]++' | sed 's/^/\ -\ DOMAIN,/g' | sed 's/$/,DIRECT #节点绕过/g' >>"$TMPDIR"/proxies_bypass
        cat "$TMPDIR"/rules.yaml >>"$TMPDIR"/proxies_bypass
        mv -f "$TMPDIR"/proxies_bypass "$TMPDIR"/rules.yaml
    }
    #插入自定义规则
    sed -i "/#自定义规则/d" "$TMPDIR"/rules.yaml
    [ -s "$CRASHDIR"/yamls/rules.yaml ] && {
        cat "$CRASHDIR"/yamls/rules.yaml | sed "/^#/d" | sed '$a\' | sed 's/$/ #自定义规则/g' >"$TMPDIR"/rules.add
        cat "$TMPDIR"/rules.yaml >>"$TMPDIR"/rules.add
        mv -f "$TMPDIR"/rules.add "$TMPDIR"/rules.yaml
    }
}

preserve_geodata_yaml() {
    #保留订阅规则依赖的Geo数据设置，本地自定义同名配置优先
    : >"$TMPDIR"/geodata_base.yaml
    : >"$TMPDIR"/geodata.yaml
    for char in geodata-mode geodata-loader geosite-matcher geo-auto-update geo-update-interval geox-url; do
        awk -v key="$char" '
            /^[^[:space:]#]/ { emit = ($0 ~ ("^" key ":")) }
            emit { print }
        ' "$core_config" >>"$TMPDIR"/geodata_base.yaml
    done
    for char in geodata-mode geodata-loader geosite-matcher geo-auto-update geo-update-interval geox-url; do
        grep -qE "^$char:" "$CRASHDIR"/yamls/user.yaml "$CRASHDIR"/yamls/others.yaml 2>/dev/null && continue
        awk -v key="$char" '
            /^[^[:space:]#]/ { emit = ($0 ~ ("^" key ":")) }
            emit { print }
        ' "$TMPDIR"/geodata_base.yaml >>"$TMPDIR"/geodata.yaml
    done
}

merger_yaml() {
    #mix和route模式生成rule-providers
    [ "$dns_mod" = "mix" ] || [ "$dns_mod" = "route" ] && ! grep -Eq '^[[:space:]]*cn:' "$TMPDIR"/rule-providers.yaml && ! grep -q '^rule-providers' "$CRASHDIR"/yamls/others.yaml 2>/dev/null && {
        [ -n "$(tail -c1 "$TMPDIR"/rule-providers.yaml)" ] && echo >>"$TMPDIR"/rule-providers.yaml #结尾无换行时先补换行，防止下方追加内容粘行
        space=$(sed -n "1p" "$TMPDIR"/rule-providers.yaml | grep -oE '^ *') #获取空格数
        [ -z "$space" ] && space='  '
        # 去原作者化：规则提供者地址改从本 fork 仓库的 update 分支获取
        echo "${space}cn: {type: http, behavior: domain, format: mrs, path: ./ruleset/cn.mrs, interval: 86400, url: https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@update/bin/geodata/mrs_geosite_cn.mrs}" >>"$TMPDIR"/rule-providers.yaml
    }
    #对齐rules中的空格
    sed -i 's/^ *-/ -/g' "$TMPDIR"/rules.yaml
    #合并文件
    [ -s "$CRASHDIR"/yamls/user.yaml ] && {
        yaml_user="$CRASHDIR"/yamls/user.yaml
        #set和user去重,且优先使用user.yaml
        cp -f "$TMPDIR"/set.yaml "$TMPDIR"/set_bak.yaml
        for char in mode allow-lan log-level tun experimental external-ui-url interface-name dns store-selected unified-delay; do
            [ -n "$(grep -E "^$char" $yaml_user)" ] && sed -i "/^$char/d" "$TMPDIR"/set.yaml
        done
    }
    [ -s "$TMPDIR"/dns.yaml ] && yaml_dns="$TMPDIR"/dns.yaml
    [ -s "$TMPDIR"/hosts.yaml ] && yaml_hosts="$TMPDIR"/hosts.yaml
    [ -s "$CRASHDIR"/yamls/others.yaml ] && yaml_others="$CRASHDIR"/yamls/others.yaml
    yaml_add=
    for char in $yaml_char; do #将额外配置文件合并
        [ -s "$TMPDIR"/${char}.yaml ] && {
            sed -i "1i\\${char}:" "$TMPDIR"/${char}.yaml
            yaml_add="$yaml_add $TMPDIR/${char}.yaml"
        }
    done
    preserve_geodata_yaml
    #合并完整配置文件
    cut -c 1- "$TMPDIR"/set.yaml "$TMPDIR"/geodata.yaml $yaml_dns $yaml_hosts $yaml_user $yaml_others $yaml_add >"$TMPDIR"/config.yaml
}

test_yaml() {
    #测试自定义配置文件
    "$TMPDIR"/CrashCore -t -d "$BINDIR" -f "$TMPDIR"/config.yaml >/dev/null
    if [ "$?" != 0 ]; then
        logger "$("$TMPDIR"/CrashCore -t -d "$BINDIR" -f "$TMPDIR"/config.yaml | grep -Eo 'error.*=.*')" 31
        logger "自定义配置文件校验失败！将使用基础配置文件启动！" 33
        logger "错误详情请参考 "$TMPDIR"/error.yaml 文件！" 33
        mv -f "$TMPDIR"/config.yaml "$TMPDIR"/error.yaml >/dev/null 2>&1
        sed -i "/#自定义策略组开始/,/#自定义策略组结束/d" "$TMPDIR"/proxy-groups.yaml
        mv -f "$TMPDIR"/set_bak.yaml "$TMPDIR"/set.yaml >/dev/null 2>&1
        #合并基础配置文件
        cut -c 1- "$TMPDIR"/set.yaml "$TMPDIR"/geodata_base.yaml $yaml_dns $yaml_add >"$TMPDIR"/config.yaml
        sed -i "/#自定义/d" "$TMPDIR"/config.yaml
        if ! "$TMPDIR"/CrashCore -t -d "$BINDIR" -f "$TMPDIR"/config.yaml >/dev/null; then
            logger "基础配置文件校验仍然失败，已中止启动！" 31
            return 1
        fi
    fi
    return 0
}

finalize_clash_yaml() {
    #建立软连接
    [ ""$TMPDIR"" = ""$BINDIR"" ] || ln -sf "$TMPDIR"/config.yaml "$BINDIR"/config.yaml 2>/dev/null || cp -f "$TMPDIR"/config.yaml "$BINDIR"/config.yaml
    #清理缓存
    for char in $yaml_char set set_bak dns hosts geodata geodata_base; do
        rm -f "$TMPDIR"/${char}.yaml
    done
}

#修饰clash配置文件
modify_yaml() {
    prepare_clash_base_config
    generate_set_and_hosts_yaml
    split_and_customize_yaml_parts
    add_custom_inbounds_and_rules
    merger_yaml
    if test_yaml; then
        finalize_clash_yaml
        return 0
    else
        for char in $yaml_char set set_bak dns hosts geodata geodata_base; do
            rm -f "$TMPDIR"/${char}.yaml
        done
        return 1
    fi
}
