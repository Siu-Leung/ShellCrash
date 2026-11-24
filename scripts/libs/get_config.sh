
# 检查未完成的升级事务并自动回滚自愈，再加载配置文件
[ -f "$CRASHDIR/.upg_txn/pending" ] && . "$CRASHDIR"/libs/set_config.sh && recover_interrupted_upgrade
[ -z "$TASKCFGDIR" ] && TASKCFGDIR="$CRASHDIR"/configs/task
[ -f "$CRASHDIR"/configs/ShellCrash.cfg ] || . "$CRASHDIR"/init.sh >/dev/null 2>&1
[ -f "$CRASHDIR"/configs/directories.env ] && . "$CRASHDIR"/configs/directories.env >/dev/null 2>&1
[ -f "$CRASHDIR"/configs/command.env ] && . "$CRASHDIR"/configs/command.env >/dev/null 2>&1
[ -f "$CRASHDIR"/configs/ShellCrash.cfg ] && . "$CRASHDIR"/configs/ShellCrash.cfg

[ -z "$mix_port" ] && mix_port=7890
[ -z "$redir_port" ] && redir_port=7892
[ -z "$tproxy_port" ] && tproxy_port=7893
[ -z "$db_port" ] && db_port=9999
[ -z "$dns_port" ] && dns_port=1053
[ -z "$dns_redir_port" ] && dns_redir_port="$dns_port"
[ -z "$fwmark" ] && fwmark="$redir_port"
routing_mark=$((fwmark + 2))
[ -z "$table" ] && table=100

[ -z "$fakeip4" ] && fakeip4="198.18.0.0/15"
[ -z "$fakeip6" ] && fakeip6="2001:2::/64"

[ -z "$dns_nameserver" ] && {
    dns_nameserver='223.5.5.5, 1.2.4.8'
    netstat -ntlup 2>/dev/null | grep -q '127.0.0.1:53' || ss -ntlup 2>/dev/null | grep -q '127.0.0.1:53' && dns_nameserver='127.0.0.1'
}
[ -z "$dns_fallback" ] && dns_fallback="1.1.1.1, 8.8.8.8"
[ -z "$dns_resolver" ] && dns_resolver="223.5.5.5, 2400:3200::1"
[ -z "$dns_proxy_server" ] && dns_proxy_server="$dns_resolver"
# 安全加固：DNS 是否遵循分流规则，默认 ON 保持原行为；OFF 可规避与 nameserver-policy 的语义重叠
[ -z "$dns_respect_rules" ] && dns_respect_rules=ON

# ---------------------------------------------------------------------------
# 安全加固：TLS 证书校验默认开启（原版默认跳过，存在中间人替换下载内容的风险）
# 用途：控制 webget() 是否给 curl 加 -k / wget 加 --no-check-certificate
# 取值：OFF = 严格校验证书（默认，安全）；ON = 跳过校验（仅供自签/老设备兼容）
# 设计说明：web_get.sh 依据本变量决定证书参数；这里给出安全默认值，
#   已有配置中显式写过 skip_cert 的用户不受影响（向下兼容）。
# ---------------------------------------------------------------------------
[ -z "$skip_cert" ] && skip_cert=OFF

# ---------------------------------------------------------------------------
# get_version_var - 按变量名安全读取内核/数据库版本（安全加固，替代 eval）
# 用途：原代码用 `eval echo \$$var` 间接取变量值，若 var 来自被篡改的配置可导致命令执行。
# 参数：$1 = 版本变量名（如 meta_v / Country_v / china_ip_list_v）
# 返回：回显对应变量的值；变量名不在白名单内时回显空（不执行任何命令）
# 设计说明：
#   - 采用 case 白名单而非 eval：只暴露脚本内部已知的 *_v 变量，杜绝注入面。
#   - 白名单覆盖所有内核类型(meta/clash/clashpre/singbox/singboxr)与数据库版本变量。
#   - 新增版本变量时必须同步在此登记，否则读取为空——这是有意的安全默认值。
# ---------------------------------------------------------------------------
get_version_var() {
    # 每个分支直接引用具体变量，完全不经 eval —— 即使 $1 被注入也无法执行代码
    case "$1" in
        # 内核版本变量
        meta_v)            printf '%s' "$meta_v" ;;
        clash_v)           printf '%s' "$clash_v" ;;
        clashpre_v)        printf '%s' "$clashpre_v" ;;
        singbox_v)         printf '%s' "$singbox_v" ;;
        singboxr_v)        printf '%s' "$singboxr_v" ;;
        # 数据库版本变量（geo_v 由文件名首字母段拼成，注意 GeoSite/GeoIP 的大小写变体）
        Country_v)         printf '%s' "$Country_v" ;;
        cn_mini_v)         printf '%s' "$cn_mini_v" ;;
        cn_ip_v)           printf '%s' "$cn_ip_v" ;;
        cn_ipv6_v)         printf '%s' "$cn_ipv6_v" ;;
        china_ip_list_v)   printf '%s' "$china_ip_list_v" ;;
        china_ipv6_list_v) printf '%s' "$china_ipv6_list_v" ;;
        GeoSite_v)         printf '%s' "$GeoSite_v" ;;
        geosite_v)         printf '%s' "$geosite_v" ;;
        GeoIP_v)           printf '%s' "$GeoIP_v" ;;
        geoip_v)           printf '%s' "$geoip_v" ;;
        geoip_cn_v)        printf '%s' "$geoip_cn_v" ;;
        geosite_cn_v)      printf '%s' "$geosite_cn_v" ;;
        mrs_v)             printf '%s' "$mrs_v" ;;
        srs_v)             printf '%s' "$srs_v" ;;
        mrs_geosite_cn_v)  printf '%s' "$mrs_geosite_cn_v" ;;
        srs_geoip_cn_v)    printf '%s' "$srs_geoip_cn_v" ;;
        srs_geosite_cn_v)  printf '%s' "$srs_geosite_cn_v" ;;
    esac
}
