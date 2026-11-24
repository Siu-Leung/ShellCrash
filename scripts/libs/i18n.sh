
load_lang() {
    i18n=$(cat "$CRASHDIR"/configs/i18n.cfg 2>/dev/null)
    case "$i18n" in
        chs|en) ;;
        *) i18n=chs ;;
    esac
    case "$1" in
        '' | */* | *..*) return 1 ;;
    esac
    i18n_file="$CRASHDIR/lang/$i18n/$1.lang"
    [ -s "$i18n_file" ] && . "$i18n_file"
}