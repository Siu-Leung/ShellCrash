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

# 执行 .upg_txn 快照的字节级文件与服务恢复（供主动回滚与崩溃自愈共用）
_upg_txn_restore() {
    _utr_txn="${1:-$CRASHDIR/.upg_txn}"
    if [ -f "$_utr_txn/newlist" ]; then
        while IFS= read -r _rel; do
            [ -n "$_rel" ] || continue
            [ -e "$_utr_txn/bak/$_rel" ] || rm -f "$CRASHDIR/$_rel" 2>/dev/null
        done <"$_utr_txn/newlist"
    fi
    if [ -d "$_utr_txn/bak" ]; then
        ( cd "$_utr_txn/bak" && find . -type f | sed 's|^\./||' ) | while IFS= read -r _rel; do
            [ -n "$_rel" ] || continue
            mkdir -p "$CRASHDIR/$(dirname "$_rel")"
            cp -f "$_utr_txn/bak/$_rel" "$CRASHDIR/$_rel" 2>/dev/null
        done
    fi
    _utr_run=$(cat "$_utr_txn/was_running" 2>/dev/null)
    rm -rf "$_utr_txn"
    [ "$_utr_run" = "1" ] && "$CRASHDIR"/start.sh start >/dev/null 2>&1 || true
    return 0
}

# 若上次升级在切换/初始化期间因 SIGKILL 或断电中断，下次加载时自动完成回滚自愈
# 注意：当升级主进程仍存活（含 systemd 通过 D-Bus 拉起 bfstart/afstart 的清洁环境）时严禁误触发回滚！
recover_interrupted_upgrade() {
    _riu_txn="$CRASHDIR/.upg_txn"
    [ -f "$_riu_txn/pending" ] || return 0
    [ -n "$_SC_UPG_ACTIVE" ] && return 0
    _riu_owner=$(head -n 1 "$_riu_txn/pending" 2>/dev/null | tr -d '\r\n ')
    case "$_riu_owner" in
        '' | *[!0-9]*) ;;
        *)
            if [ "$_riu_owner" = "$$" ]; then
                return 0
            elif [ -d "/proc/$_riu_owner" ]; then
                _riu_cmd=$(tr '\0' ' ' <"/proc/$_riu_owner/cmdline" 2>/dev/null || true)
                case "$_riu_cmd" in
                    *sh* | *menu* | *task* | *ShellCrash* | '') return 0 ;;
                esac
            elif [ ! -d /proc ] && kill -0 "$_riu_owner" 2>/dev/null; then
                return 0
            fi
            ;;
    esac
    _SC_UPG_ACTIVE="recover.$$"
    export _SC_UPG_ACTIVE
    _upg_txn_restore "$_riu_txn"
    unset _SC_UPG_ACTIVE
    return 0
}

# 统一事务化脚本升级（菜单更新与定时任务 112 共用）：
# 1) 暂存解包 + Tar-Slip 校验 + 关键脚本语法检查（不满足绝不触碰现用目录）
# 2) 执行 start.sh stop 并校验退出码，停服失败立即中止
# 3) 在 $CRASHDIR/.upg_txn 写入回滚快照与绑定主进程 PID 的 pending 标记（防自身子进程或 systemd 钩子误回滚）
# 4) 子 Shell 运行 init.sh + 校验新版本落盘与运行态恢复；任何失败或 INT/TERM 均字节级回滚并返回非零
apply_script_upgrade() {
    _asu_tar="$1"
    [ -s "$_asu_tar" ] || return 1
    _asu_stage="$TMPDIR/upg_stage.$$"
    _asu_txn="$CRASHDIR/.upg_txn"
    _asu_bak="$_asu_txn/bak"
    _asu_list="$_asu_txn/newlist"
    rm -rf "$_asu_stage" "$_asu_txn"
    mkdir -p "$_asu_stage" "$_asu_bak" || return 1

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

    _asu_was_running=0
    [ -n "$(pidof CrashCore 2>/dev/null)" ] && _asu_was_running=1
    printf '%s\n' "$_asu_was_running" >"$_asu_txn/was_running"

    # 停服失败时严禁覆盖运行中的脚本目录
    if [ -x "$CRASHDIR/start.sh" ] && ! "$CRASHDIR"/start.sh stop >/dev/null 2>&1; then
        rm -rf "$_asu_stage" "$_asu_txn"
        return 1
    fi

    # 记录新包内所有相对路径，并对既有同名文件与关键配置做字节级备份
    ( cd "$_asu_stage" && find . -type f | sed 's|^\./||' ) >"$_asu_list"
    while IFS= read -r _rel; do
        [ -n "$_rel" ] || continue
        if [ -e "$CRASHDIR/$_rel" ]; then
            mkdir -p "$_asu_bak/$(dirname "$_rel")"
            cp -p "$CRASHDIR/$_rel" "$_asu_bak/$_rel" 2>/dev/null || cp -f "$CRASHDIR/$_rel" "$_asu_bak/$_rel" 2>/dev/null
        fi
    done <"$_asu_list"
    for _cfg in configs/ShellCrash.cfg configs/command.env configs/directories.env; do
        if [ -f "$CRASHDIR/$_cfg" ]; then
            mkdir -p "$_asu_bak/configs"
            cp -p "$CRASHDIR/$_cfg" "$_asu_bak/$_cfg" 2>/dev/null || cp -f "$CRASHDIR/$_cfg" "$_asu_bak/$_cfg" 2>/dev/null
        fi
    done

    _asu_rollback() {
        trap '' TERM INT
        _SC_UPG_ACTIVE="rollback.$$"
        export _SC_UPG_ACTIVE
        _upg_txn_restore "$_asu_txn"
        unset _SC_UPG_ACTIVE
        rm -rf "$_asu_stage" "$_asu_txn" "$_asu_tar"
    }

    printf '%s\n' "$$" >"$_asu_txn/pending"
    _SC_UPG_ACTIVE="$$"
    export _SC_UPG_ACTIVE
    trap '_asu_rollback; exit 143' TERM
    trap '_asu_rollback; exit 130' INT

    mkdir -p "$CRASHDIR" >/dev/null 2>&1
    _asu_ok=0
    if cp -af "$_asu_stage"/. "$CRASHDIR"/ 2>/dev/null && \
       ( CRASHDIR="$CRASHDIR" sh "$CRASHDIR"/init.sh >/dev/null ) && \
       [ -f "$_asu_txn/pending" ] && \
       { [ ! -s "$_asu_stage/version" ] || cmp -s "$_asu_stage/version" "$CRASHDIR/version"; } && \
       { [ "$_asu_was_running" = 0 ] || { "$CRASHDIR"/start.sh start >/dev/null 2>&1 && { [ ! -x "$TMPDIR/CrashCore" ] || pidof CrashCore >/dev/null 2>&1; }; }; }; then
        _asu_ok=1
    fi

    trap - TERM INT
    if [ "$_asu_ok" = 1 ]; then
        unset _SC_UPG_ACTIVE
        rm -rf "$_asu_stage" "$_asu_txn"
        return 0
    else
        _asu_rollback
        return 1
    fi
}
