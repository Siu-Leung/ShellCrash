#参数1代表变量名，参数2代表变量值,参数3即文件路径
# 将任意字符串转为 POSIX 单引号字面量，防止配置被 source 时执行其中的 $()/反引号/;/&/空格
quote_cfg_val() {
    printf "'%s'" "$(printf '%s' "$1" | tr -d '\r\n' | sed "s/'/'\\\\''/g")"
}

# 安全加固：校验键名为合法 Shell 标识符，剥离换行符防多行配置注入，确保文件存在后原子替换写入
setconfig() {
    case "$1" in
        '' | [0-9]* | *[!A-Za-z0-9_]*) return 1 ;;
    esac
    [ -z "$3" ] && configpath="$CRASHDIR"/configs/ShellCrash.cfg || configpath="$3"
    mkdir -p "$(dirname "$configpath")"
    [ -f "$configpath" ] || : >"$configpath"
    _sc_val=$(printf '%s' "$2" | tr -d '\r\n')
    _sc_cnt=$(awk -v k="$1" 'index($0, k "=") == 1 { c++ } END { print c+0 }' "$configpath")
    # 若该键已唯一存在且值完全一致，直接返回不改写文件（保持同版本覆盖/重启时配置字节不变）
    if [ "$_sc_cnt" = "1" ] && \
       awk -v line="${1}=${_sc_val}" '$0 == line { ok=1; exit } END { exit (ok ? 0 : 1) }' "$configpath"; then
        return 0
    fi
    _sc_tmp="${configpath}.tmp.$$"
    if [ "$_sc_cnt" = "1" ]; then
        awk -v k="$1" -v line="${1}=${_sc_val}" '{ if (index($0, k "=") == 1) print line; else print }' "$configpath" >"$_sc_tmp" &&
            mv -f "$_sc_tmp" "$configpath"
    else
        awk -v k="$1" 'index($0, k "=") != 1' "$configpath" >"$_sc_tmp" &&
            printf '%s=%s\n' "$1" "$_sc_val" >>"$_sc_tmp" &&
            mv -f "$_sc_tmp" "$configpath"
    fi
    _sc_rc=$?
    rm -f "$_sc_tmp"
    return "$_sc_rc"
}

# 以单引号安全写入用户输入类配置值（空值直接写空，避免空单引号干扰旧判断）
setconfig_quote() {
    if [ -z "$2" ]; then
        setconfig "$1" "" "$3"
    else
        setconfig "$1" "$(quote_cfg_val "$2")" "$3"
    fi
}

# 安全加固：按纯数据解析远端下载的 bin/version 清单（严禁直接 source 执行远端脚本）
# 仅放行白名单版本键名与安全字符集 [A-Za-z0-9._+-]
load_version_file() {
    [ -r "$1" ] || return 1
    while IFS= read -r _lv_line || [ -n "$_lv_line" ]; do
        _lv_line=$(printf '%s' "$_lv_line" | tr -d '\r')
        case "$_lv_line" in
            '' | \#*) continue ;;
            *=*)
                _lv_k=${_lv_line%%=*}
                _lv_v=${_lv_line#*=}
                case "$_lv_v" in
                    *[![:alnum:]._+-]* | '') continue ;;
                esac
                case "$_lv_k" in
                    meta_v)          meta_v="$_lv_v" ;;
                    singbox_v)       singbox_v="$_lv_v" ;;
                    singboxr_v)      singboxr_v="$_lv_v" ;;
                    clash_v)         clash_v="$_lv_v" ;;
                    GeoIP_v)         GeoIP_v="$_lv_v" ;;
                    versionsh)       versionsh="$_lv_v" ;;
                    release_version) release_version="$_lv_v" ;;
                esac
                ;;
        esac
    done <"$1"
    return 0
}

# 安全加固：校验 tar.gz 归档无绝对路径、../ 遍历及符号链接/硬链接/设备节点（防 Tar Slip）
safe_tar_check() {
    _stc_entries=$(tar -tzf "$1" 2>/dev/null) || return 1
    [ -n "$_stc_entries" ] || return 1
    printf '%s\n' "$_stc_entries" | grep -Eq '(^/|^\.\./|/\.\./|/\.\.$|^\.\.$)' && return 1
    # 内部事务目录不能由升级包覆盖。
    printf '%s\n' "$_stc_entries" | grep -Eq '^(\./)*\.upg_txn(/|$)' && return 1
    _stc_listing=$(tar -tvzf "$1" 2>/dev/null) || return 1
    printf '%s\n' "$_stc_listing" | grep -Eq '^[lhcb]' && return 1
    return 0
}

# 安全加固：校验运行临时目录非符号链接并收紧权限
ensure_safe_tmpdir() {
    _est_dir="${1:-$TMPDIR}"
    [ -n "$_est_dir" ] || return 1
    [ -L "$_est_dir" ] && return 1
    mkdir -p "$_est_dir" 2>/dev/null || return 1
    [ ! -L "$_est_dir" ] && [ -d "$_est_dir" ] || return 1
    chmod 700 "$_est_dir" 2>/dev/null || true
    return 0
}

# 旁路模式没有核心进程；只在能确认专用路由时视为运行中。
_upg_gateway_active() (
    [ -f "$CRASHDIR/configs/ShellCrash.cfg" ] && . "$CRASHDIR/configs/ShellCrash.cfg" >/dev/null 2>&1
    [ -f "$CRASHDIR/configs/gateway.cfg" ] && . "$CRASHDIR/configs/gateway.cfg" >/dev/null 2>&1
    [ -n "$table" ] || table=100
    [ "$firewall_area" = 5 ] && [ -n "$table" ] && [ -n "$bypass_host" ] || exit 1
    ip route show table "$table" 2>/dev/null | awk -v host="$bypass_host" '$1 == "default" && $2 == "via" && $3 == host { found=1 } END { exit !found }'
)

# 核验升级/回滚后实例级运行健康度（systemd MainPID + CrashCore 进程 + 真实 ELF 核心本地控制器 API）
_upg_check_service_ready() {
    # 主旁转发模式不要求 CrashCore 或 systemd 进程。
    if ( [ -f "$CRASHDIR/configs/ShellCrash.cfg" ] && . "$CRASHDIR/configs/ShellCrash.cfg" >/dev/null 2>&1; [ "$firewall_area" = 5 ] ); then
        _upg_gateway_active
        return $?
    fi
    [ -n "$(pidof CrashCore 2>/dev/null)" ] || return 1
    if { [ "$(id -u 2>/dev/null)" = "0" ] || [ "$USER" = "root" ]; } && \
       grep -q 'systemd' /proc/1/comm 2>/dev/null && \
       [ "$(systemctl show -p LoadState shellcrash.service 2>/dev/null | sed 's/LoadState=//')" = "loaded" ]; then
        systemctl is-active --quiet shellcrash.service || return 1
        _ucsr_mpid=$(systemctl show -p MainPID shellcrash.service 2>/dev/null | sed 's/MainPID=//' | tr -d '\r\n ')
        case "$_ucsr_mpid" in
            '' | 0 | *[!0-9]*) return 1 ;;
        esac
        [ -d "/proc/$_ucsr_mpid" ] || return 1
    fi
    if [ -e "$TMPDIR/CrashCore" ]; then
        pidof CrashCore >/dev/null 2>&1 || return 1
        # 若运行时核心为真实 ELF 二进制（非离线测试脚本替身；优先 dd 兼容无 od 的原生 OpenWrt）
        _ucsr_is_elf=0
        if [ "$(dd if="$TMPDIR/CrashCore" bs=1 count=4 2>/dev/null)" = "$(printf '\177ELF')" ]; then
            _ucsr_is_elf=1
        elif [ "$(od -An -tx1 -N4 "$TMPDIR/CrashCore" 2>/dev/null | tr -d ' \t\r\n')" = "7f454c46" ]; then
            _ucsr_is_elf=1
        fi
        if [ "$_ucsr_is_elf" = 1 ]; then
            (
                [ -f "$CRASHDIR/configs/ShellCrash.cfg" ] && . "$CRASHDIR/configs/ShellCrash.cfg" >/dev/null 2>&1
                [ "$firewall_area" = "5" ] && exit 0
                _dbp="${db_port:-9999}"
                _try=1
                while [ "$_try" -le 8 ]; do
                    if command -v curl >/dev/null 2>&1; then
                        http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" \
                            curl -fsS --noproxy '*' --connect-timeout 1 --max-time 2 \
                            -H "Authorization: Bearer $secret" "http://127.0.0.1:${_dbp}/version" 2>/dev/null | grep -q '"version"' && exit 0
                    elif command -v wget >/dev/null 2>&1; then
                        wget --help 2>&1 | grep -q -- '-Y' && _ucsr_np='-Y off' || _ucsr_np='--no-proxy'
                        if wget --help 2>&1 | grep -q -- '--header'; then
                            http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
                                wget -q -T 2 $_ucsr_np --header="Authorization: Bearer $secret" \
                                -O - "http://127.0.0.1:${_dbp}/version" 2>/dev/null | grep -q '"version"' && exit 0
                        else
                            # OpenWrt uclient-fetch 无 --header：无 secret 查 version；有 secret 时收到 401 即代表控制器已监听响应
                            _ucsr_out=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" \
                                wget -T 2 $_ucsr_np -O - "http://127.0.0.1:${_dbp}/version" 2>&1)
                            printf '%s\n' "$_ucsr_out" | grep -q '"version"' && exit 0
                            [ -n "$secret" ] && printf '%s\n' "$_ucsr_out" | grep -q 'HTTP error 401' && exit 0
                        fi
                    else
                        exit 0
                    fi
                    sleep 1
                    _try=$((_try + 1))
                done
                exit 1
            ) || return 1
        fi
    fi
    return 0
}

# 拒绝越界路径及安装树中间组件的符号链接；不跟随链接写入树外。
_upg_path_safe() {
    case "$1" in ''|/*|.|..|../*|*/../*|*/..) return 1 ;; esac
    _ups_dir=$(dirname "$1")
    while [ "$_ups_dir" != . ] && [ "$_ups_dir" != / ]; do
        [ ! -L "$CRASHDIR/$_ups_dir" ] || return 1
        _ups_next=$(dirname "$_ups_dir")
        [ "$_ups_next" != "$_ups_dir" ] || return 1
        _ups_dir="$_ups_next"
    done
    return 0
}

# 执行 .upg_txn 快照的字节级文件与服务恢复（逐文件校验，恢复失败保留快照并返回非零）
_upg_txn_restore() {
    _utr_txn="${1:-$CRASHDIR/.upg_txn}"
    _utr_err=0
    # 新服务可能已部分启动；无法安全停下时保留现场，不覆盖正在运行的文件。
    if [ -f "$_utr_txn/start_attempt" ] && [ ! -f "$_utr_txn/rollback_stopped" ]; then
        if ! "$CRASHDIR/start.sh" stop >/dev/null 2>&1; then
            mv -f "$_utr_txn/pending" "$_utr_txn/rollback_failed" 2>/dev/null || true
            return 1
        fi
        if ! : >"$_utr_txn/rollback_stopped"; then
            mv -f "$_utr_txn/pending" "$_utr_txn/rollback_failed" 2>/dev/null || true
            return 1
        fi
    fi
    if [ -f "$_utr_txn/newlist" ]; then
        while IFS= read -r _rel || [ -n "$_rel" ]; do
            [ -n "$_rel" ] || continue
            if ! _upg_path_safe "$_rel"; then _utr_err=1; continue; fi
            if [ ! -e "$_utr_txn/bak/$_rel" ] && [ -e "$CRASHDIR/$_rel" -o -L "$CRASHDIR/$_rel" ]; then
                rm -f "$CRASHDIR/$_rel" 2>/dev/null
                [ ! -e "$CRASHDIR/$_rel" ] && [ ! -L "$CRASHDIR/$_rel" ] || _utr_err=1
            fi
        done <"$_utr_txn/newlist"
    fi
    if [ -d "$_utr_txn/bak" ]; then
        _utr_baklist="$_utr_txn/baklist.$$"
        ( cd "$_utr_txn/bak" && find . -type f | sed 's|^\./||' ) >"$_utr_baklist"
        while IFS= read -r _rel || [ -n "$_rel" ]; do
            [ -n "$_rel" ] || continue
            if ! _upg_path_safe "$_rel"; then _utr_err=1; continue; fi
            if ! mkdir -p "$CRASHDIR/$(dirname "$_rel")" 2>/dev/null || \
               [ -L "$CRASHDIR/$_rel" ] || \
               ! { cp -p -f "$_utr_txn/bak/$_rel" "$CRASHDIR/$_rel" 2>/dev/null || { cp -f "$_utr_txn/bak/$_rel" "$CRASHDIR/$_rel" 2>/dev/null && { [ ! -x "$_utr_txn/bak/$_rel" ] || chmod +x "$CRASHDIR/$_rel" 2>/dev/null || true; }; }; } || \
               ! cmp -s "$_utr_txn/bak/$_rel" "$CRASHDIR/$_rel"; then
                _utr_err=1
            fi
        done <"$_utr_baklist"
        rm -f "$_utr_baklist"
    fi
    # 新事务记录 init.sh 可能替换的单个系统服务文件；旧事务无此元数据。
    if [ -f "$_utr_txn/external/path" ]; then
        _utr_ext=$(cat "$_utr_txn/external/path" 2>/dev/null)
        case "$_utr_ext" in
            /etc/init.d/shellcrash|/etc/systemd/system/shellcrash.service|/usr/lib/systemd/system/shellcrash.service)
                if [ -L "$_utr_ext" ]; then
                    _utr_err=1
                elif [ -f "$_utr_txn/external/existed" ]; then
                    cp -pf "$_utr_txn/external/backup" "$_utr_ext" 2>/dev/null && cmp -s "$_utr_txn/external/backup" "$_utr_ext" || _utr_err=1
                elif [ -f "$_utr_txn/external/absent" ]; then
                    rm -f "$_utr_ext" 2>/dev/null || _utr_err=1
                else
                    _utr_err=1
                fi
                if [ -f "$_utr_txn/external/systemd" ]; then
                    systemctl daemon-reload >/dev/null 2>&1 || _utr_err=1
                fi
                ;;
            *) _utr_err=1 ;;
        esac
    fi
    _utr_run=$(cat "$_utr_txn/was_running" 2>/dev/null)
    if [ "$_utr_run" = "1" ]; then
        # 标记表示停服已成功：不能把残留的新版本进程当作已恢复的旧服务。
        if [ ! -f "$_utr_txn/format_v2" ] || [ -f "$_utr_txn/stopped" ] || ! _upg_check_service_ready; then
            if ! "$CRASHDIR"/start.sh start >/dev/null 2>&1 || ! _upg_check_service_ready; then
                _utr_err=1
            fi
        fi
    fi
    if [ "$_utr_err" = "0" ]; then
        rm -rf "$_utr_txn" || return 1
        return 0
    else
        # 恢复未完全成功：保留 .upg_txn/bak 恢复资料供人工核查，仅将 pending 转为 rollback_failed 防死循环
        [ -f "$_utr_txn/pending" ] && mv -f "$_utr_txn/pending" "$_utr_txn/rollback_failed" 2>/dev/null || true
        return 1
    fi
}

# 若上次升级在切换/初始化期间因 SIGKILL 或断电中断，下次加载时自动完成回滚自愈
# 注意：当升级主进程仍存活（含 V4->V6 init.sh 补写父进程链及 systemd D-Bus 清洁环境）时严禁误触发回滚！
recover_interrupted_upgrade() {
    _riu_txn="$CRASHDIR/.upg_txn"
    [ -f "$_riu_txn/pending" ] || return 0
    [ -n "$_SC_UPG_ACTIVE" ] && return 0
    # 单独的恢复锁防止多个 get_config 同时恢复；残留锁宁可人工处理。
    mkdir "$_riu_txn/recovering" 2>/dev/null || return 1
    [ -f "$_riu_txn/pending" ] || { rmdir "$_riu_txn/recovering" 2>/dev/null; return 0; }
    while IFS= read -r _riu_owner || [ -n "$_riu_owner" ]; do
        _riu_owner=$(printf '%s' "$_riu_owner" | tr -d '\r\n ')
        case "$_riu_owner" in
            '' | 0 | 1 | *[!0-9]*) continue ;;
        esac
        # PID 复用或权限不足可能导致误阻塞，不能据此冒险恢复活事务。
        if [ "$_riu_owner" = "$$" ] || [ -d "/proc/$_riu_owner" ] || kill -0 "$_riu_owner" 2>/dev/null; then
            rmdir "$_riu_txn/recovering" 2>/dev/null
            return 0
        fi
    done <"$_riu_txn/pending"
    _SC_UPG_ACTIVE="recover.$$"
    export _SC_UPG_ACTIVE
    _upg_txn_restore "$_riu_txn"
    _riu_rc=$?
    unset _SC_UPG_ACTIVE
    rmdir "$_riu_txn/recovering" 2>/dev/null || true
    return "$_riu_rc"
}

# 统一事务化脚本升级（菜单更新与定时任务 112 共用）：
# 1) 若存在上次未完成的回滚快照(rollback_failed)或并发升级锁，立即中止并完整保留 .upg_txn/bak
# 2) 暂存解包 + Tar-Slip 校验 + 关键脚本语法检查（不满足绝不触碰现用目录）
# 3) 停服前预建并逐字节校验备份快照，停服后二次同步配置快照；任何备份失败立即中止且绝不进入覆盖阶段
# 4) 子 Shell 运行 init.sh + 校验新版本落盘与实例级健康度恢复；任何失败或 INT/TERM 均字节级回滚并返回非零
apply_script_upgrade() {
    _asu_tar="$1"
    [ -s "$_asu_tar" ] || return 1
    _asu_stage="$TMPDIR/upg_stage.$$"
    _asu_txn="$CRASHDIR/.upg_txn"
    _asu_bak="$_asu_txn/bak"
    _asu_list="$_asu_txn/newlist"

    # 若存在上次恢复失败留存的 .upg_txn/rollback_failed 或并发/残留事务，严禁清空快照目录
    if [ -f "$_asu_txn/rollback_failed" ]; then
        echo "检测到上次升级回滚未完成($_asu_txn/rollback_failed)，已中止升级以保留恢复快照($_asu_bak)！" >&2
        return 1
    fi
    if [ -f "$_asu_txn/pending" ]; then
        if ! recover_interrupted_upgrade || [ -e "$_asu_txn" ]; then
            echo "检测到正在进行或未恢复完成的升级事务($_asu_txn)，已中止本次升级！" >&2
            return 1
        fi
    fi

    # 原子 mkdir 是互斥点：无 pending 的目录也可能属于正在准备的升级，绝不能删除。
    if ! mkdir "$_asu_txn" 2>/dev/null; then
        echo "升级事务目录已存在($_asu_txn)，保留快照并中止；请核查残留事务。" >&2
        return 1
    fi
    if ! mkdir "$_asu_stage"; then
        rm -rf "$_asu_txn"
        return 1
    fi
    if ! mkdir "$_asu_bak"; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi

    if ! safe_tar_check "$_asu_tar" || \
       ! tar -zxf "$_asu_tar" ${tar_para} -C "$_asu_stage" 2>/dev/null || \
       [ ! -s "$_asu_stage/start.sh" ] || [ ! -s "$_asu_stage/menu.sh" ] || \
       [ ! -s "$_asu_stage/init.sh" ] || [ ! -s "$_asu_stage/libs/get_config.sh" ] || \
       ! sh -n "$_asu_stage/start.sh" 2>/dev/null || \
       ! sh -n "$_asu_stage/menu.sh" 2>/dev/null || \
       ! sh -n "$_asu_stage/init.sh" 2>/dev/null || \
       ! sh -n "$_asu_stage/libs/get_config.sh" 2>/dev/null; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi

    _asu_copy_verify() {
        _acv_src="$1"
        _acv_dst="$2"
        mkdir -p "$(dirname "$_acv_dst")" 2>/dev/null || return 1
        { cp -pf "$_acv_src" "$_acv_dst" 2>/dev/null || { cp -f "$_acv_src" "$_acv_dst" 2>/dev/null && { [ ! -x "$_acv_src" ] || chmod +x "$_acv_dst" 2>/dev/null || true; }; }; } || return 1
        cmp -s "$_acv_src" "$_acv_dst"
    }

    # 停服前先记录新包成员列表并完成首轮字节级备份校验（磁盘满或只读时连现用服务都不停）
    if ! ( cd "$_asu_stage" && find . -type f | sed 's|^\./||' ) >"$_asu_list" || [ ! -s "$_asu_list" ]; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi
    # init 还会修改/生成非包成员配置，纳入同一旧版兼容的 newlist。
    for _cfg in configs/ShellCrash.cfg configs/command.env configs/directories.env configs/i18n.cfg; do
        printf '%s\n' "$_cfg" >>"$_asu_list" || { rm -rf "$_asu_stage" "$_asu_txn"; return 1; }
    done
    while IFS= read -r _rel || [ -n "$_rel" ]; do
        [ -n "$_rel" ] || continue
        # 不跟随安装树内符号链接写入树外，避免快照及回滚污染其他文件。
        if ! _upg_path_safe "$_rel" || [ -L "$CRASHDIR/$_rel" ]; then
            rm -rf "$_asu_stage" "$_asu_txn"
            return 1
        fi
        if [ -f "$CRASHDIR/$_rel" ]; then
            if ! _asu_copy_verify "$CRASHDIR/$_rel" "$_asu_bak/$_rel"; then
                rm -rf "$_asu_stage" "$_asu_txn"
                return 1
            fi
        fi
    done <"$_asu_list"

    _asu_was_running=0
    { [ -n "$(pidof CrashCore 2>/dev/null)" ] || _upg_gateway_active; } && _asu_was_running=1
    if ! printf '%s\n' "$_asu_was_running" >"$_asu_txn/was_running" || [ ! -s "$_asu_txn/was_running" ] || ! : >"$_asu_txn/format_v2"; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi

    # 与 init.sh 同样的平台选择；仅备份其固定服务文件，不覆盖其他系统状态。
    _asu_external=''
    _asu_sysdir=''
    [ -w /usr/lib/systemd/system ] && _asu_sysdir=/usr/lib/systemd/system
    [ -w /etc/systemd/system ] && _asu_sysdir=/etc/systemd/system
    if [ -f /etc/rc.common ] && [ "$(cat /proc/1/comm 2>/dev/null)" = procd ]; then
        _asu_external=/etc/init.d/shellcrash
    elif [ -n "$_asu_sysdir" ] && { [ "$(id -u 2>/dev/null)" = 0 ] || [ "$USER" = root ]; } && [ "$(cat /proc/1/comm 2>/dev/null)" = systemd ]; then
        _asu_external="$_asu_sysdir/shellcrash.service"
    elif rc-status -r >/dev/null 2>&1; then
        _asu_external=/etc/init.d/shellcrash
    fi
    if [ -n "$_asu_external" ]; then
        if [ -L "$_asu_external" ] || ! mkdir "$_asu_txn/external" || \
           ! printf '%s\n' "$_asu_external" >"$_asu_txn/external/path"; then
            rm -rf "$_asu_stage" "$_asu_txn"; return 1
        fi
        if [ -e "$_asu_external" ]; then
            if [ ! -f "$_asu_external" ] || ! _asu_copy_verify "$_asu_external" "$_asu_txn/external/backup" || ! : >"$_asu_txn/external/existed"; then
                rm -rf "$_asu_stage" "$_asu_txn"; return 1
            fi
        else
            : >"$_asu_txn/external/absent" || { rm -rf "$_asu_stage" "$_asu_txn"; return 1; }
        fi
        case "$_asu_external" in */systemd/system/*) : >"$_asu_txn/external/systemd" || { rm -rf "$_asu_stage" "$_asu_txn"; return 1; } ;; esac
    fi

    # 原子发布非空 pending：所有恢复资料先就绪，之后才可停服。
    if ! printf '%s\n' "$$" >"$_asu_txn/pending.tmp" || [ ! -s "$_asu_txn/pending.tmp" ] || \
       ! mv "$_asu_txn/pending.tmp" "$_asu_txn/pending"; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi
    _asu_rollback() {
        trap '' TERM INT
        _SC_UPG_ACTIVE="rollback.$$"
        export _SC_UPG_ACTIVE
        _upg_txn_restore "$_asu_txn" || true
        unset _SC_UPG_ACTIVE
        rm -rf "$_asu_stage"
    }

    _SC_UPG_ACTIVE="$$"
    export _SC_UPG_ACTIVE
    trap '_asu_rollback; exit 143' TERM
    trap '_asu_rollback; exit 130' INT

    # 停服可能部分成功：失败同样恢复快照及原运行状态。
    if [ -x "$CRASHDIR/start.sh" ] && ! "$CRASHDIR"/start.sh stop >/dev/null 2>&1; then
        trap - TERM INT
        _asu_rollback
        return 1
    fi
    if ! : >"$_asu_txn/stopped"; then
        trap - TERM INT
        _asu_rollback
        return 1
    fi
    # 停服期间可能写入配置；先写临时文件再替换，防中断损坏首轮快照。
    _asu_prep_err=0
    for _cfg in configs/ShellCrash.cfg configs/command.env configs/directories.env; do
        if [ -f "$_asu_bak/$_cfg" ] && [ -f "$CRASHDIR/$_cfg" ] && [ ! -L "$CRASHDIR/$_cfg" ]; then
            _asu_copy_verify "$CRASHDIR/$_cfg" "$_asu_txn/config.tmp" && \
                mv -f "$_asu_txn/config.tmp" "$_asu_bak/$_cfg" || _asu_prep_err=1
        elif [ -L "$CRASHDIR/$_cfg" ]; then
            _asu_prep_err=1
        fi
    done
    if [ "$_asu_prep_err" != 0 ]; then
        trap - TERM INT
        _asu_rollback
        return 1
    fi

    mkdir -p "$CRASHDIR" >/dev/null 2>&1
    _asu_ok=0
    if cp -af "$_asu_stage"/. "$CRASHDIR"/ 2>/dev/null && \
       ( CRASHDIR="$CRASHDIR" sh "$CRASHDIR"/init.sh >/dev/null ) && \
       [ -f "$_asu_txn/pending" ] && \
       { [ ! -s "$_asu_stage/version" ] || cmp -s "$_asu_stage/version" "$CRASHDIR/version"; } && \
       { [ "$_asu_was_running" = 0 ] || { : >"$_asu_txn/start_attempt" && "$CRASHDIR"/start.sh start >/dev/null 2>&1 && _upg_check_service_ready; }; }; then
        _asu_ok=1
    fi

    if [ "$_asu_ok" = 1 ]; then
        # 提交前仍保留回滚 trap；提交清理期间屏蔽普通终止信号。
        trap '' TERM INT
        unset _SC_UPG_ACTIVE
        rm -rf "$_asu_stage"
        if ! rm -rf "$_asu_txn"; then
            trap - TERM INT
            echo "升级已启动但事务清理失败，请检查 $_asu_txn" >&2
            return 1
        fi
        trap - TERM INT
        return 0
    else
        _asu_rollback
        trap - TERM INT
        return 1
    fi
}
