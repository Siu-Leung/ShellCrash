#!/bin/sh
# doctor.sh —— ShellCrash Linux 代理一键健康自检（纯只读，不修改任何系统或配置文件）

run_doctor() {
    [ -z "$CRASHDIR" ] && CRASHDIR=$(cd "$(dirname "$0")/.." && pwd)
    # 严格只读加载现存配置文件，绝不调用 get_config.sh 以免触发 init.sh 或自动回滚副作用
    [ -f "$CRASHDIR/configs/directories.env" ] && . "$CRASHDIR/configs/directories.env" 2>/dev/null
    [ -f "$CRASHDIR/configs/command.env" ] && . "$CRASHDIR/configs/command.env" 2>/dev/null
    [ -f "$CRASHDIR/configs/ShellCrash.cfg" ] && . "$CRASHDIR/configs/ShellCrash.cfg" 2>/dev/null
    [ -z "$mix_port" ] && mix_port=7890
    [ -z "$redir_port" ] && redir_port=7892
    [ -z "$tproxy_port" ] && tproxy_port=7893
    [ -z "$db_port" ] && db_port=9999
    [ -z "$dns_port" ] && dns_port=1053

    _doc_ok()   { printf '  [\033[32mOK\033[0m]   %s\n' "$1"; }
    _doc_warn() { printf '  [\033[33mWARN\033[0m] %s\n' "$1"; }
    _doc_info() { printf '  [INFO] %s\n' "$1"; }

    echo "==============================================="
    printf '\033[36mShellCrash 运行环境与安全健康自检 (doctor)\033[0m\n'
    echo "==============================================="

    # 1. 版本与供应链
    _doc_info "脚本版本: ${versionsh_l:-unknown} | 内核: ${crashcore:-unset} (${core_v:-unknown}) | 架构: ${cpucore:-unset}"
    _doc_info "安装目录: $CRASHDIR | 数据目录: ${BINDIR:-$CRASHDIR} | 缓存目录: ${TMPDIR:-/tmp/ShellCrash}"
    if [ "${release_type:-dev}" = "dev" ]; then
        _doc_ok "更新分支已锁定加固版 dev (url_id=${url_id:-custom})"
    else
        _doc_warn "当前 release_type=${release_type} 非 dev，建议在 9->7 切回加固版 dev"
    fi
    if [ -f "$CRASHDIR/.upg_txn/rollback_failed" ]; then
        _doc_warn "检测到未完成的升级回滚快照: $CRASHDIR/.upg_txn/bak (请先核查恢复后再升级)"
    elif [ -f "$CRASHDIR/.upg_txn/pending" ]; then
        _doc_warn "检测到挂起的升级事务标记: $CRASHDIR/.upg_txn/pending"
    fi

    # 2. 进程与运行模式
    _pid=$(pidof CrashCore 2>/dev/null | awk '{print $NF}')
    if [ -n "$_pid" ]; then
        _rss=$(awk '/^VmRSS:/ {printf "%.1f MB", $2/1024}' "/proc/$_pid/status" 2>/dev/null)
        _doc_ok "CrashCore 运行中 (PID=$_pid, RSS=${_rss:-unknown})"
    else
        _doc_warn "CrashCore 当前未运行"
    fi
    _doc_info "代理模式: redir_mod=${redir_mod:-unset} | firewall_area=${firewall_area:-unset} | firewall_mod=${firewall_mod:-unset} | dns_mod=${dns_mod:-unset}"

    # 3. 安全策略与监听边界
    # 与下载器共用同一套有效值计算（tls_policy.sh 只有纯函数，只读安全）
    [ -f "$CRASHDIR/libs/tls_policy.sh" ] && . "$CRASHDIR/libs/tls_policy.sh"
    case "$skip_cert" in
    "" | OFF) _doc_ok "项目文件下载证书校验已开启 (skip_cert=${skip_cert:-OFF})" ;;
    ON) _doc_warn "项目文件下载证书校验已关闭 (skip_cert=ON)，存在中间人风险" ;;
    *) _doc_warn "skip_cert=$skip_cert 不是有效值（ON/OFF），已按严格校验处理" ;;
    esac
    case "$sub_tls" in
    "" | auto | strict | skip) ;;
    *) _doc_warn "sub_tls=$sub_tls 不是有效值（auto/strict/skip），已按 auto 处理" ;;
    esac
    case "$(tls_sub_mode 2>/dev/null)" in
    strict) _doc_ok "订阅拉取：严格校验 (sub_tls=strict)" ;;
    skip) _doc_warn "订阅拉取：始终跳过证书 (sub_tls=skip)" ;;
    *) _doc_info "订阅拉取：自动 (sub_tls=auto，仅确认是 HTTPS 证书错误时跳过并记日志)" ;;
    esac
    case "$node_tls" in
    "" | follow | skip | verify) ;;
    *) _doc_warn "node_tls=$node_tls 不是有效值（follow/skip/verify），已按兼容规则处理" ;;
    esac
    case "$(tls_node_mode 2>/dev/null)" in
    verify) _doc_ok "节点证书：全部校验 (node_tls=verify)" ;;
    skip) _doc_warn "节点证书：全部跳过 (node_tls=skip)" ;;
    *) _doc_info "节点证书：跟随订阅 (node_tls=follow)" ;;
    esac
    if [ "$firewall_area" = "4" ] && [ "$public_support" != "ON" ]; then
        _doc_ok "纯净模式监听已收敛至 127.0.0.1 (mix=$mix_port, dns=$dns_port, panel=$db_port)"
    else
        if [ -n "$secret" ]; then
            _doc_ok "面板监听端口 $db_port 已设置访问密钥"
        else
            _doc_warn "面板监听端口 $db_port 未设置访问密钥 (secret 为空)"
        fi
    fi
    if [ "$bot_tg_service" = "ON" ]; then
        [ -f "$CRASHDIR/configs/gateway.cfg" ] && . "$CRASHDIR/configs/gateway.cfg" 2>/dev/null
        if echo "$TG_CHATID" | grep -Eq '^-?[0-9]+$' && echo "$TG_TOKEN" | grep -Eq '^[0-9]+:[A-Za-z0-9_-]{20,}$'; then
            _doc_ok "自建 Telegram Bot 凭证与 Chat ID 校验正常"
        else
            _doc_warn "Telegram Bot 已启用但 TG_TOKEN/TG_CHATID 缺失或格式非法"
        fi
    fi
    if [ "$push_TG" = "publictoken" ]; then
        _doc_warn "检测到旧版 publictoken 推送配置（已弃用），请更换为自建 Bot Token"
    fi

    # 4. 本地订阅与配置状态
    _prov_cnt=0
    [ -s "$CRASHDIR/configs/providers.cfg" ] && _prov_cnt=$(grep -cvE '^[[:space:]]*(#|$)' "$CRASHDIR/configs/providers.cfg" 2>/dev/null || echo 0)
    _uri_cnt=0
    [ -s "$CRASHDIR/configs/providers_uri.cfg" ] && _uri_cnt=$(grep -cvE '^[[:space:]]*(#|$)' "$CRASHDIR/configs/providers_uri.cfg" 2>/dev/null || echo 0)
    _local_files=0
    if [ -d "$CRASHDIR/providers" ]; then
        _local_files=$(find "$CRASHDIR/providers" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
    fi
    if [ "$local_sub" = "ON" ]; then
        _doc_ok "零外泄本地拉取转换已启用 (订阅=$_prov_cnt, 单节点=$_uri_cnt, 本地缓存文件=$_local_files)"
    else
        _doc_info "订阅提供者: 订阅=$_prov_cnt, 单节点=$_uri_cnt, 本地缓存文件=$_local_files (local_sub=${local_sub:-OFF})"
    fi
    if echo "$crashcore" | grep -q 'singbox'; then
        _cfg="$CRASHDIR/jsons/config.json"
    else
        _cfg="$CRASHDIR/yamls/config.yaml"
    fi
    if [ -s "$_cfg" ]; then
        _doc_ok "内核配置文件就绪: $_cfg"
    else
        _doc_warn "未检测到内核配置文件: $_cfg"
    fi

    # 5. Linux 网络栈与核心依赖
    if [ -r /proc/sys/net/ipv4/ip_forward ]; then
        _ipf=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)
        if [ "$_ipf" = "1" ]; then
            _doc_ok "IPv4 转发已开启 (net.ipv4.ip_forward=1)"
        elif [ "$firewall_area" = "1" ] || [ "$firewall_area" = "3" ]; then
            _doc_warn "透明代理模式下 net.ipv4.ip_forward=$_ipf（应为 1）"
        else
            _doc_info "net.ipv4.ip_forward=$_ipf"
        fi
    fi
    if [ -c /dev/net/tun ]; then
        _doc_ok "/dev/net/tun 设备可用"
    elif [ "$redir_mod" = "Tun" ] || [ "$redir_mod" = "Mix" ]; then
        _doc_warn "当前模式 $redir_mod 需要 TUN，但未检测到 /dev/net/tun"
    fi

    _missing=""
    for _cmd in curl wget base64 awk sed; do
        command -v "$_cmd" >/dev/null 2>&1 || _missing="$_missing $_cmd"
    done
    if [ -z "$_missing" ]; then
        _doc_ok "基础工具链完整 (curl/wget/base64/awk/sed)"
    else
        _doc_info "未安装的可选/基础命令:$_missing"
    fi
    echo "==============================================="
    return 0
}
