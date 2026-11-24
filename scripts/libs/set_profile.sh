
set_profile() {
    case "$my_alias" in
        '' | [0-9]* | *[!A-Za-z0-9_-]*) my_alias=crash ;;
    esac
    [ -z "$shtype" ] && shtype=sh
    if [ -w "$1" ] || { [ ! -e "$1" ] && [ -w "$(dirname "$1")" ]; }; then
        [ -f "$1" ] && sed -i "/ShellCrash\/menu.sh/d" "$1"
        printf 'alias %s="%s %s/menu.sh"\n' "$my_alias" "$shtype" "$CRASHDIR" >>"$1" #设置快捷命令环境变量
        sed -i '/^export CRASHDIR=/d' "$1"
        printf 'export CRASHDIR="%s"\n' "$CRASHDIR" >>"$1" #设置路径环境变量
    fi
    export CRASHDIR
}