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
    _sc_tmp="${configpath}.tmp.$$"
    awk -v k="$1" 'index($0, k "=") != 1' "$configpath" >"$_sc_tmp" &&
        printf '%s=%s\n' "$1" "$_sc_val" >>"$_sc_tmp" &&
        mv -f "$_sc_tmp" "$configpath"
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
