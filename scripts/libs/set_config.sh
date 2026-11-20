#参数1代表变量名，参数2代表变量值,参数3即文件路径
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
