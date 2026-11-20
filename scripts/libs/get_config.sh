
# 检查配置文件
[ -z "$TASKCFGDIR" ] && TASKCFGDIR="$CRASHDIR"/configs/task
[ -f "$CRASHDIR"/configs/ShellCrash.cfg ] || . "$CRASHDIR"/init.sh >/dev/null 2>&1
[ -f "$CRASHDIR"/configs/directories.env ] && . "$CRASHDIR"/configs/directories.env >/dev/null 2>&1
. "$CRASHDIR"/configs/command.env >/dev/null 2>&1
. "$CRASHDIR"/configs/ShellCrash.cfg

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
