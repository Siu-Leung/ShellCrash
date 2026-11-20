
get_ecs_address() {
    for f in /tmp/resolv.conf.auto /tmp/resolv.conf /tmp/resolv.conf.d/resolv.conf.auto; do
        [ -f "$f" ] || continue
        ip=$(grep -A1 "^# Interface wan$" "$f" | grep nameserver | awk '{printf "%s ", $2}')
        [ -n "$ip" ] && return
    done
    . "$CRASHDIR"/libs/web_get_lite.sh
    #轮询公网IP，提取并校验为合法IPv4才采用，否则继续尝试下一个
    for web in http://ddns.oray.com/checkip http://members.3322.org/dyndns/getip http://ipinfo.io/ip; do
        ip=$(web_get_lite "$web" 0 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -1)
        [ -n "$ip" ] && return
    done
}
get_ecs_address
[ -n "$ip" ] && ecs_address="${ip%.*}.0/24"

# 安全加固：给逗号分隔的 DNS server 列表的每一项追加 ECS fragment 参数（mihomo/Clash.Meta 语法）
# 用法：append_ecs_to_dns "<dns列表>" "<ecs子网>"
# 原实现用 sed 拼字符串且只作用于 fallback，既脆弱又不完整；这里对 nameserver/fallback/proxy-server 统一处理。
# bootstrap(default-nameserver/dns_resolver) 故意不改，避免 ECS 查询依赖尚未解析的 DNS 造成循环。
append_ecs_to_dns() {
    _ecs_list="$1"
    _ecs_subnet="$2"
    if [ -z "$_ecs_list" ] || [ -z "$_ecs_subnet" ]; then
        printf '%s' "$_ecs_list"
        return 0
    fi
    _ecs_out=""
    _ecs_ifs="$IFS"
    IFS=','
    for _ecs_srv in $_ecs_list; do
        _ecs_srv=$(printf '%s' "$_ecs_srv" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -z "$_ecs_srv" ] && continue
        case "$_ecs_srv" in
            *'#'*) _ecs_srv="${_ecs_srv}&ecs-override=true&ecs=$_ecs_subnet" ;;
            *)     _ecs_srv="${_ecs_srv}#ecs-override=true&ecs=$_ecs_subnet" ;;
        esac
        # 注：mihomo 用 '#' 引导 URL 参数段，已含 '#' 时用 '&' 续接
        [ -n "$_ecs_out" ] && _ecs_out="$_ecs_out, "
        _ecs_out="$_ecs_out$_ecs_srv"
    done
    IFS="$_ecs_ifs"
    printf '%s' "$_ecs_out"
}
