#!/bin/sh
# Copyright (C) Juewuy

[ -n "$__IS_MODULE_6_CORECONFIG_LOADED" ] && return
__IS_MODULE_6_CORECONFIG_LOADED=1

load_lang 6_core_config

if echo "$crashcore" | grep -q 'singbox'; then
    CONFIG_PATH="$CRASHDIR"/jsons/config.json
    CORE_TYPE=singbox
else
    CONFIG_PATH="$CRASHDIR"/yamls/config.yaml
    CORE_TYPE=clash
fi
URI_EXP='ss|vmess|vless|trojan|tuic|anytls|shadowtls|hysteria(2)?'

# 按变量名字面值删除订阅配置
delete_provider() {
    provider_name=$1
    provider_file=$2
    [ -f "$provider_file" ] || return 0
    provider_tmp="$provider_file.tmp.$$"
    NAME="$provider_name" awk 'index($0, ENVIRON["NAME"] " ") != 1' "$provider_file" >"$provider_tmp" &&
        cat "$provider_tmp" >"$provider_file"
    provider_status=$?
    rm -f "$provider_tmp"
    return "$provider_status"
}

# 配置文件主界面
set_core_config() {
    while true; do
        list=$(cat "$CRASHDIR"/configs/providers.cfg "$CRASHDIR"/configs/providers_uri.cfg 2>/dev/null |
            LC_ALL=C awk '{
    f1 = $1
    f2 = $2
    gsub(/\360[\200-\277][\200-\277][\200-\277]/,"",f1)
    if (length(f1) > 12)
        f1 = substr(f1, 1, 8) ".."
    if (length(f2) > 30)
        f2 = substr(f2, 1, 30) "..."
    printf "%-7s \t%-28s\n", f1, f2
}')
        comp_box "\033[30;47m$CORECFG_TITLE\033[0m"
        [ -n "$list" ] && {
            content_line "\033[36m$CORECFG_HINT_SELECT_PROVIDER\033[0m"
            content_line ""
            list_box "$list"
            separator_line "-"
        }
        btm_box "a) $CORECFG_MENU_A" \
            "b) $CORECFG_MENU_B" \
            "c) $CORECFG_MENU_C" \
            "d) $CORECFG_MENU_D" \
            "e) $CORECFG_MENU_E" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT_L> " num
        case "$num" in
        "" | 0)
            break
            ;;
        [1-9] | [1-9][0-9])
            line=$(cat "$CRASHDIR"/configs/providers.cfg "$CRASHDIR"/configs/providers_uri.cfg 2>/dev/null | sed -n "$num p")
            setproviders "$line"
            ;;
        a)
            setproviders
            ;;
        b)
            if [ -s "$CRASHDIR"/configs/providers.cfg ] || [ -s "$CRASHDIR"/configs/providers_uri.cfg ]; then
                if [ "$crashcore" = meta ] || [ "$crashcore" = singboxr ]; then
                    . "$CRASHDIR"/menus/providers.sh
                    providers
                else
                    msg_alert "\033[33m$CORECFG_CORE_ONLY\033[0m"
                fi
            else
                msg_alert "$CORECFG_ADD_PROVIDER_FIRST"
            fi
            ;;
        c)
            # 安全加固：已移除第三方在线订阅转换（原 CORECFG_SUBCONV_DISABLED），
            # 升级为零外泄「本地拉取并转换配置文件」，订阅只直连原始源并在本机解码合成。
            if [ -s "$CRASHDIR"/configs/providers.cfg ] || [ -s "$CRASHDIR"/configs/providers_uri.cfg ]; then
                if [ "$crashcore" = meta ] || [ "$crashcore" = singboxr ]; then
                    . "$CRASHDIR"/menus/subconverter.sh
                    subconverter
                else
                    msg_alert "\033[33m$CORECFG_CORE_ONLY\033[0m"
                fi
            else
                msg_alert "$CORECFG_ADD_PROVIDER_FIRST"
            fi
            ;;
        d)
            comp_box "\033[33m$CORECFG_CLEAR_WARN\033[0m" \
                "" \
                "$CORECFG_CLEAR_CONFIRM"
            btm_box "1) $CORECFG_YES" \
                "0) $CORECFG_NO_BACK"
            read -r -p "$COMMON_INPUT> " res
            [ "$res" = 1 ] && {
                rm -f "$CRASHDIR"/configs/providers.cfg
                rm -f "$CRASHDIR"/configs/providers_uri.cfg
                common_success
            }
            ;;
        e)
            checkcfg=$(cat "$CFG_PATH")
            . "$CRASHDIR"/menus/override.sh && override
            if [ -n "$PID" ]; then
                checkcfg_new=$(cat "$CFG_PATH")
                [ "$checkcfg" != "$checkcfg_new" ] && checkrestart
            fi
            ;;
        *)
            error_letter
            ;;
        esac
    done
}

# 校验提供者名称，拒绝路径穿越和 YAML/JSON/Shell 危险字符
_valid_provider_name() {
    [ -n "$1" ] || return 1
    echo "$1" | grep -Eq '^[0-9]+$' && return 1
    case "$1" in
    *..* | */* | *\\* | *\"* | *\'* | *\`* | *\$* | *\;* | *\|* | *\#* | *\[* | *\]* | *\{* | *\}* | *,* | *:*)
        return 1
        ;;
    esac
    return 0
}

# 添加/管理提供者
setproviders() {
    case "$(echo "$@" | cut -d ' ' -f 2)" in
    http* | ./providers*)
        set -f
        set -- $@
        set +f
        name=$1
        link=$2
        interval=$3
        interval2=$4
        ua=$5
        exclude_w=${6#\#}
        include_w=${7#\#}
        ;;
    *://*)
        set -f
        set -- $@
        set +f
        name=$1
        link_uri=$2
        ;;
    *)
        unset name link link_uri interval interval2 ua exclude_w include_w
        ;;
    esac
    last_name="$name"
    [ -z "$interval" ] && interval=3
    [ -z "$interval2" ] && interval2=12
    [ -z "$ua" ] && ua='clash.meta'

    while true; do
        link_info=$(echo "$link$link_uri" | cut -c 1-30)
        comp_box "\033[36m$CORECFG_PROVIDER_SUPPORT\033[0m"

        content_line "1) $CORECFG_SET_NAME	\033[32m$name\033[0m"
        content_line "2) $CORECFG_SET_LINK	\033[36m$link_info\033[0m"
        [ -n "$link" ] &&
            content_line "3) $CORECFG_SET_OVERRIDE"
        content_line ""
        content_line "a) $CORECFG_SAVE_PROVIDER"
        content_line "d) $CORECFG_DEL_PROVIDER"
        content_line ""
        content_line "\033[36m$CORECFG_MORE_CONFIG_HINT\033[0m"
        [ -n "$link" ] &&
            content_line "b) $CORECFG_GEN_LOCAL_ONE"
        [ -n "$link$link_uri" ] &&
            content_line "c) $CORECFG_GEN_ONLINE_ONE"
        echo "$link" | grep -q '^http' &&
            content_line "e) $CORECFG_GET_ONLINE_DIRECT"
        echo "$link" | grep -q '^./providers' &&
            content_line "e) $CORECFG_USE_DIRECT"
        btm_box "" \
            "0) $COMMON_BACK"
        read -r -p "$CORECFG_INPUT_ALNUM> " input
        case "$input" in
        "" | 0)
            break
            ;;
        1)
            while true; do
                comp_box "\033[33m$CORECFG_NAME_HINT\033[0m"
                btm_box "\033[36m$CORECFG_INPUT_NAME\033[0m" \
                    "$CORECFG_OR_BACK"
                read -r -p "$CORECFG_INPUT> " text
                text=$(printf "%.12s" "$text" | tr -d ' \t\r\n') # 截断12字符+去空白
                if [ "$text" = 0 ]; then
                    break
                elif _valid_provider_name "$text" && ! grep -Fq "$text " "$CRASHDIR"/configs/providers.cfg 2>/dev/null; then
                    name="$text"
                    common_success
                    break
                else
                    error_input
                fi
            done
            ;;
        2)
            while true; do
                comp_box "$CORECFG_LINK_HINT1" \
                    "" \
                    "$CORECFG_LINK_HINT2\n$URI_EXP" \
                    "" \
                    "$CORECFG_LINK_HINT3\033[32m$CRASHDIR/providers\033[0m$CORECFG_LINK_HINT4" \
                    "" \
                    "$CORECFG_LINK_HINT5"
                list=$(
                    for f in "$CRASHDIR"/providers/*; do
                        [ "$f" = "$CRASHDIR"/providers/uri_group ] && continue
                        [ -f "$f" ] || continue
                        printf '%s\n' "${f##*/}"
                    done | sort
                )
                if [ -n "$list" ]; then
                    list_box "$list"
                    btm_box "" \
                        "$CORECFG_INPUT0_BACK"
                    read -r -p "$CORECFG_SELECT_FILE_OR_LINK> " text
                else
                    btm_box "\033[36m$CORECFG_INPUT_LINK\033[0m" \
                        "$CORECFG_OR_BACK"
                    read -r -p "$CORECFG_INPUT> " text
                fi
                text=$(echo "$text" | sed 's/ //g') # 去空格
                case "$text" in
                0)
                    break
                    ;;
                http*)
                    # 处理订阅链接
                    text=$(echo "$text" | sed 's/ *(.*)//g; s/#.*//g') # 处理注释及超链接
                    link="$text"
                    link_uri=''
                    common_success
                    break
                    ;;
                [1-9] | [1-9][0-9])
                    # 处理本地文件
                    file=$(printf '%s\n' "$list" | sed -n "${text}p")
                    if [ -s "$CRASHDIR/providers/$file" ]; then
                        link="./providers/$file"
                        [ -z "$name" ] && name="_$(printf "%.11s" "$file" | tr -d ' \t\r\n/\\"`$[]{},:#|;'\''')"
                        link_uri=''
                        common_success
                        break
                    else
                        errornum
                    fi
                    ;;
                *)
                    # 处理分享链接
                    if [ -n "$(echo "$text" | grep -E "^$URI_EXP")" ]; then
                        link_uri=$(echo "$text" | sed 's/#.*//g') # 删除注释
                        link=''
                        if [ -z "$name" ]; then
                            _raw_tag=$(printf '%s' "$text" | sed -n 's/.*#//p')
                            _raw_tag=$(printf '%s' "$_raw_tag" | tr -d ' \t\r\n/\\"`$[]{},:#|;'\''' | cut -c 1-12)
                            if _valid_provider_name "$_raw_tag"; then
                                name="$_raw_tag"
                            else
                                name="node_$(date +%s 2>/dev/null | tail -c 5)"
                            fi
                        fi
                        common_success
                        break
                    else
                        error_input
                    fi
                    ;;
                esac
            done
            ;;
        3)
            custproviders
            ;;
        a)
            saveproviders && common_success
            break
            ;;
        b)
            if [ -n "$name" ] && [ -n "$link" ]; then
                saveproviders
                . "$CRASHDIR/menus/providers_$CORE_TYPE.sh"
                gen_providers "$name" "$link" "$interval" "$interval2" "$ua" "#$exclude_w" "#$include_w"
            else
                msg_alert "\033[31m$CORECFG_FILL_REQUIRED\033[0m"
            fi
            ;;
        c)
            # 安全加固：单订阅同样走零外泄本地拉取并转换，绝不发送给第三方转换站
            if [ -n "$name" ] && [ -n "$link" ]; then
                saveproviders
                . "$CRASHDIR"/libs/local_sub_convert.sh
                if local_sub_convert "$name" "$link" "$interval" "$interval2" "$ua" "#$exclude_w" "#$include_w"; then
                    setconfig local_sub ON
                    setconfig Https
                    setconfig Url
                    comp_box "$CORECFG_START_APPLY"
                    btm_box "1) $CORECFG_YES" \
                        "0) $CORECFG_NO"
                    read -r -p "$COMMON_INPUT> " res
                    if [ "$res" = 1 ]; then
                        start_core
                    else
                        main_menu
                    fi
                    exit
                else
                    msg_alert "\033[31m$CORECFG_LOCAL_SUB_FAILED\033[0m"
                fi
            elif [ -n "$name" ] && [ -n "$link_uri" ]; then
                saveproviders
                setconfig local_sub ON
                setconfig Https
                setconfig Url
                jump_core_config
            else
                msg_alert "\033[31m$CORECFG_FILL_REQUIRED\033[0m"
            fi
            ;;
        d)
            if [ -n "$name" ] && [ -n "$link" ]; then
                delete_provider "$name" "$CRASHDIR"/configs/providers.cfg 2>/dev/null
                msg_alert "\033[32m$COMMON_SUCCESS\033[0m"
            elif [ -n "$name" ] && [ -n "$link_uri" ]; then
                delete_provider "$name" "$CRASHDIR"/configs/providers_uri.cfg 2>/dev/null
                msg_alert "\033[32m$COMMON_SUCCESS\033[0m"
            fi
            break
            ;;
        e)
            if [ -n "$link" ]; then
                comp_box "\033[31m$CORECFG_DANGER1\033[0m" \
                    "\033[31m$CORECFG_DANGER2\033[0m"
                btm_box "1) $CORECFG_DANGER_CONFIRM" \
                    "0) $COMMON_BACK"
                read -r -p "$COMMON_INPUT> " res
                [ "$res" = "1" ] && {
                    file=""
                    case "$link" in
                    ./providers/*)
                        case "$link" in
                        *..*) ;;
                        *) file="$CRASHDIR/${link#./}" ;;
                        esac
                        ;;
                    esac
                    if [ -n "$file" ] && [ -f "$file" ] && [ ! -L "$file" ]; then
                        [ -n "$name" ] && saveproviders
                        ln -sf "$file" "$CONFIG_PATH"
                        common_success
                        break
                    elif echo "$link" | grep -q '^http'; then
                        [ -n "$name" ] && saveproviders
                        Https="$link"
                        Url=''
                        setconfig_quote Https "$Https"
                        setconfig Url
                        # 获取在线文件
                        jump_core_config
                        break
                    else
                        msg_alert "\033[31m$CORECFG_FILL_REQUIRED\033[0m"
                    fi
                }
            else
                msg_alert "\033[31m$CORECFG_FILL_REQUIRED\033[0m"
            fi
            ;;
        *)
            error_letter
            ;;
        esac
    done
}

# 保存
saveproviders() {
    [ -n "$name" ] && {
        [ -s "$CRASHDIR"/configs/providers.cfg ] && delete_provider "$last_name" "$CRASHDIR"/configs/providers.cfg
        [ -s "$CRASHDIR"/configs/providers_uri.cfg ] && delete_provider "$last_name" "$CRASHDIR"/configs/providers_uri.cfg
    }
    if [ -n "$name" ] && [ -n "$link" ]; then
        [ -z "$ua" ] && ua='clash.meta'
        echo "$name $link $interval $interval2 $ua #$exclude_w #$include_w" >>"$CRASHDIR"/configs/providers.cfg
        return 0
    elif [ -n "$name" ] && [ -n "$link_uri" ]; then
        echo "$name $link_uri" >>"$CRASHDIR"/configs/providers_uri.cfg
        return 0
    else
        msg_alert "\033[31m$CORECFG_FILL_REQUIRED\033[0m"
        return 1
    fi
}

# 本地生成覆写
custproviders() {
    while true; do
        top_box "1) $CORECFG_INTERVAL1\033[47;30m$interval\033[0m $CORECFG_MIN" \
            "2) $CORECFG_INTERVAL2\033[47;30m$interval2\033[0m $CORECFG_HOUR"
        echo "$link" | grep -q '^http' &&
            content_line "3) $CORECFG_SET_UA\033[47;30m$ua\033[0m"
        btm_box "4) $CORECFG_SET_EXCLUDE\033[47;30m$exclude_w\033[0m" \
            "5) $CORECFG_SET_INCLUDE\033[47;30m$include_w\033[0m" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            while true; do
                comp_box "$CORECFG_CUR_INTERVAL$interval $CORECFG_MIN"
                btm_box "\033[36m$CORECFG_INPUT_INTERVAL1\033[0m" \
                    "$CORECFG_RESET_INTERVAL1" \
                    "$CORECFG_OR_BACK"
                read -r -p "$CORECFG_INPUT> " num
                if [ "$num" = "r" ]; then
                    interval=3
                elif echo "$num" | grep -Eq '^[0-9]+$' && [ "$num" -ge 1 ]; then
                    interval="$num"
                else
                    errornum
                    continue
                fi
                common_success
                break
            done
            ;;
        2)
            while true; do
                comp_box "$CORECFG_CUR_INTERVAL$interval2 $CORECFG_HOUR"
                btm_box "\033[36m$CORECFG_INPUT_INTERVAL2\033[0m" \
                    "$CORECFG_RESET_INTERVAL2" \
                    "$CORECFG_OR_BACK"
                read -r -p "$CORECFG_INPUT> " num
                if [ "$num" = "r" ]; then
                    interval2=12
                elif echo "$num" | grep -Eq '^[0-9]+$' && [ "$num" -ge 1 ]; then
                    interval2="$num"
                else
                    errornum
                    continue
                fi
                common_success
                break
            done
            ;;
        3)
            if [ -z "$ua" ]; then
                comp_box "$CORECFG_CUR_UA_NONE"
            else
                comp_box "$CORECFG_CUR_UA$ua"
            fi
            btm_box "\033[36m$CORECFG_INPUT_UA\033[0m" \
                "$CORECFG_RESET_UA" \
                "$CORECFG_OR_BACK"
            read -r -p "$CORECFG_INPUT> " text
            case "$text" in
            0)
                continue
                ;;
            r)
                ua='clash.meta'
                ;;
            *)
                ua=$(echo "$text" | tr -d ' \t\r\n')
                [ -z "$ua" ] && ua='clash.meta'
                ;;
            esac
            common_success
            ;;
        4)
            if [ -z "$exclude_w" ]; then
                comp_box "$CORECFG_CUR_EXCLUDE_NONE"
            else
                comp_box "$CORECFG_CUR_EXCLUDE$exclude_w"
            fi

            btm_box "\033[36m$CORECFG_INPUT_EXCLUDE\033[0m" \
                "$CORECFG_CLEAR_EXCLUDE" \
                "$CORECFG_OR_BACK"
            read -r -p "$CORECFG_INPUT> " text
            text=$(echo "$text" | sed 's/ //g') # 去空格
            case "$text" in
            0)
                continue
                ;;
            c)
                exclude_w=''
                ;;
            *)
                exclude_w="$text"
                ;;
            esac
            common_success
            ;;
        5)
            if [ -z "$include_w" ]; then
                comp_box "$CORECFG_CUR_INCLUDE_NONE"
            else
                comp_box "$CORECFG_CUR_INCLUDE$include_w"
            fi
            btm_box "\033[36m$CORECFG_INPUT_INCLUDE\033[0m" \
                "$CORECFG_CLEAR_INCLUDE" \
                "$CORECFG_OR_BACK"
            read -r -p "$CORECFG_INPUT> " text
            text=$(echo "$text" | sed 's/ //g') # 去空格
            case "$text" in
            0)
                continue
                ;;
            c)
                include_w=''
                ;;
            *)
                include_w="$text"
                ;;
            esac
            common_success
            ;;
        *)
            error_letter
            ;;
        esac
    done
}

# 调用工具在线获取配置文件
jump_core_config() {
    . "$CRASHDIR"/starts/core_config.sh && get_core_config
    if [ "$?" = 0 ]; then
        if [ "$inuserguide" != 1 ]; then
            comp_box "$CORECFG_START_APPLY"
            btm_box "1) $CORECFG_YES" \
                "0) $CORECFG_NO"
            read -r -p "$COMMON_INPUT> " res
            if [ "$res" = 1 ]; then
                start_core
            else
                main_menu
            fi
            exit
        fi
    fi
}
