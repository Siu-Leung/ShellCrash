#!/bin/sh
# Copyright (C) Juewuy
# 安全加固：已移除所有第三方 Subconverter 服务器中转，改为本机直拉订阅 + 本地解码过滤 + 本地规则模板合成（零外泄）

[ -n "$__IS_MODULE_SUBCONVERTER" ] && return
__IS_MODULE_SUBCONVERTER=1

load_lang subconverter
load_lang providers

if echo "$crashcore" | grep -q 'singbox'; then
    CORE_TYPE=singbox
else
    CORE_TYPE=clash
fi

# 零外泄本地拉取与订阅转换
subconverter() {
    while true; do
        if [ -z "$(grep "provider_temp_${CORE_TYPE}" "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null)" ]; then
            provider_temp_des=$(sed -n "1 p" "$CRASHDIR"/configs/"${CORE_TYPE}"_providers.list 2>/dev/null | awk '{print $1}')
        else
            provider_temp_file=$(grep "provider_temp_${CORE_TYPE}" "$CRASHDIR"/configs/ShellCrash.cfg | awk -F '=' '{print $2}')
            provider_temp_des=$(grep "$provider_temp_file" "$CRASHDIR"/configs/"${CORE_TYPE}"_providers.list 2>/dev/null | awk '{print $1}')
            [ -z "$provider_temp_des" ] && provider_temp_des=$provider_temp_file
        fi

        comp_box "\033[32m$SUBCONVERTER_LOCAL_BANNER\033[0m" \
            "" \
            "1) \033[32m$SUBCONVERTER_MENU_GEN\033[0m" \
            "2) $SUBCONVERTER_MENU_EXCLUDE \033[47;30m$exclude\033[0m" \
            "3) $SUBCONVERTER_MENU_INCLUDE \033[47;30m$include\033[0m" \
            "4) $SUBCONVERTER_MENU_RULE \033[32m$provider_temp_des\033[0m" \
            "5) $SUBCONVERTER_MENU_UA  \033[32m$user_agent\033[0m" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            setconfig local_sub ON
            Https=''
            Url=''
            setconfig Https
            setconfig Url
            jump_core_config
            ;;
        2)
            gen_link_flt
            ;;
        3)
            gen_link_ele
            ;;
        4)
            gen_link_config
            ;;
        5)
            set_sub_ua
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 排除节点正则
gen_link_flt() {
    comp_box "\033[33m$SUBCONVERTER_EXCLUDE_HINT1\033[0m" \
        "$SUBCONVERTER_KEYWORD_SPLIT" \
        "$SUBCONVERTER_REGEX_HINT"
    btm_box "\033[36m$SUBCONVERTER_EXCLUDE_INPUT\033[0m" \
        "$SUBCONVERTER_EXCLUDE_CLEAR" \
        "$SUBCONVERTER_BACK"
    read -r -p "$SUBCONVERTER_INPUT> " res
    case "$res" in
    0)
        return 0
        ;;
    d)
        exclude=''
        ;;
    *)
        exclude="$res"
        ;;
    esac

    if setconfig exclude "'$exclude'"; then
        common_success
    else
        common_failed
    fi
}

# 包含节点正则
gen_link_ele() {
    comp_box "\033[33m$SUBCONVERTER_INCLUDE_HINT1\033[0m" \
        "$SUBCONVERTER_KEYWORD_SPLIT" \
        "$SUBCONVERTER_REGEX_HINT"
    btm_box "\033[36m$SUBCONVERTER_INCLUDE_INPUT\033[0m" \
        "$SUBCONVERTER_INCLUDE_CLEAR" \
        "$SUBCONVERTER_BACK"
    read -r -p "$SUBCONVERTER_INPUT> " res
    case "$res" in
    0)
        return 0
        ;;
    d)
        include=""
        ;;
    *)
        include="$res"
        ;;
    esac

    if setconfig include "'$include'"; then
        common_success
    else
        common_failed
    fi
}

# 选择本地/本仓库规则模板（不走第三方 subconverter）
gen_link_config() {
    list=$(awk '{print $1}' "$CRASHDIR/configs/${CORE_TYPE}_providers.list" 2>/dev/null)
    comp_box "$SUBCONVERTER_RULE_CURRENT\033[33m$provider_temp_des\033[0m" \
        "\033[33m$PROVIDERS_TEMPLATE_SELECT\033[0m"
    list_box "$list"
    btm_box "" \
        "a) $PROVIDERS_TEMPLATE_LOCAL" \
        "" \
        "0) $COMMON_BACK"
    read -r -p "$COMMON_INPUT> " num
    case "$num" in
    "" | 0) ;;
    a)
        line_break
        read -r -p "$PROVIDERS_TEMPLATE_PATH> " dir
        if [ -s "$dir" ]; then
            if setconfig provider_temp_"$CORE_TYPE" "$dir"; then
                common_success
            else
                common_failed
            fi
        else
            msg_alert "\033[31m$PROVIDERS_TEMPLATE_NOT_FOUND\033[0m"
        fi
        ;;
    *)
        provider_temp_file=$(sed -n "${num}p" "$CRASHDIR/configs/${CORE_TYPE}_providers.list" 2>/dev/null | awk '{print $2}')
        if [ -z "$provider_temp_file" ]; then
            errornum
        else
            if setconfig provider_temp_"$CORE_TYPE" "$provider_temp_file"; then
                msg_alert "\033[32m$SUBCONVERTER_SET_OK\033[0m"
            else
                common_failed
            fi
        fi
        ;;
    esac
}

set_sub_ua() {
    while true; do
        comp_box "\033[36m$SUBCONVERTER_UA_HINT\033[0m" \
            "" \
            "$SUBCONVERTER_UA_CURRENT$user_agent"
        btm_box "1) $SUBCONVERTER_UA_AUTO" \
            "2) $SUBCONVERTER_UA_NONE" \
            "3) $SUBCONVERTER_UA_CUSTOM" \
            "4) $SUBCONVERTER_UA_CLEAR" \
            "" \
            "0) $COMMON_BACK"
        read -r -p "$COMMON_INPUT> " num
        case "$num" in
        0)
            break
            ;;
        1)
            user_agent='auto'
            ;;
        2)
            user_agent='none'
            ;;
        3)
            comp_box "\033[33m$SUBCONVERTER_UA_CUSTOM_WARN\033[0m"
            btm_box "\033[36m$SUBCONVERTER_UA_CUSTOM_INPUT\033[0m" \
                "$SUBCONVERTER_BACK"
            read -r -p "$SUBCONVERTER_INPUT> " text
            if [ "$text" = 0 ]; then
                continue
            elif [ -n "$text" ]; then
                user_agent="$text"
            fi
            ;;
        4)
            user_agent=''
            ;;
        *)
            errornum
            continue
            ;;
        esac

        if [ "$num" -ge 1 ] && [ "$num" -le 4 ]; then
            if setconfig user_agent "$user_agent"; then
                common_success
            else
                common_failed
            fi
        fi
        break
    done
}
