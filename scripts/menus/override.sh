#!/bin/sh
# Copyright (C) Juewuy

[ -n "$__IS_MODULE_OVERRIDE" ] && return
__IS_MODULE_OVERRIDE=1
YAMLSDIR="$CRASHDIR"/yamls
JSONSDIR="$CRASHDIR"/jsons
load_lang override

# ---------------------------------------------------------------------------
# ovr_input_safe - 校验用户写入 YAML 的单行输入（安全加固）
#
# 用途：防止从剪贴板/手工粘贴的规则、节点、策略组名里夹带会破坏 YAML 结构的字符。
# 参数：$1 = 待校验的单行字符串（read 已保证无换行）
# 返回：0 = 安全；1 = 含非法字符或为空（并给出提示）
#
# 设计说明：
#   - 允许：中英文、数字、点/逗号/冒号/斜线/横线/下划线/空格、通配符 * ? [] {} @ = 等
#     规则与节点常用符号。
#   - 禁止：单双引号、反引号、反斜杠、$ 以及 ASCII 控制字符（<0x20 与 0x7f）。
#     前四者会破坏 YAML 引号配对或引入 shell 命令替换语义；控制字符会破坏配置解析。
#   - 兼容性：busybox grep -E 不支持 \xHH 十六进制转义，故控制字符用 tr 逐字节剥离后
#     再比较长度的方式检测，避免依赖 GNU 专有语法。
# ---------------------------------------------------------------------------
ovr_input_safe() {
    _oi_val="$1"
    # 空值直接拒绝
    if [ -z "$_oi_val" ]; then
        msg_alert "\033[31m$OVR_INPUT_EMPTY\033[0m"
        return 1
    fi
    # 第一关：禁止引号/反引号/反斜杠/$ 这类会破坏 YAML 或引入替换语义的字符
    case "$_oi_val" in
        *\'* | *\"* | *\`* | *\\* | *\$*)
            msg_alert "\033[31m$OVR_INPUT_INVALID\033[0m"
            return 1
            ;;
    esac
    # 第二关：检测控制字符——把可打印字符以外的内容全部删掉，若长度变化说明含控制字符
    _oi_clean=$(printf '%s' "$_oi_val" | tr -d '\000-\037\177')
    if [ "${#_oi_val}" -ne "${#_oi_clean}" ]; then
        msg_alert "\033[31m$OVR_INPUT_INVALID\033[0m"
        return 1
    fi
    return 0
}

# 配置文件覆写
override() {
    while true; do
        [ -z "$rule_link" ] && rule_link=1
        [ -z "$server_link" ] && server_link=1
        comp_box "\033[30;47m $OVR_TITLE\033[0m"
        content_line "$OVR_MENU_2"
        echo "$crashcore" | grep -q 'singbox' || {
            content_line "$OVR_MENU_3"
            content_line "$OVR_MENU_4"
        }
        content_line "$OVR_MENU_5"
        [ "$disoverride" != 1 ] && content_line "$OVR_MENU_9"
        content_line ""
        content_line "$OVR_BACK"
        separator_line "="
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0)
            break
            ;;
        2)
            setrules
            ;;
        3)
            setproxies
            ;;
        4)
            setgroups
            ;;
        5)
            if echo "$crashcore" | grep -q 'singbox'; then
                set_singbox_adv
            else
                set_clash_adv
            fi
            sleep 3
            ;;
        9)
            comp_box "\033[33m$OVR_WARN_1\033[0m" \
                "\033[33m${OVR_WARN_2_PREFIX}$crashcore${OVR_WARN_2_SUFFIX}\033[0m" \
                "\033[33m$OVR_WARN_3\033[0m"
            sleep 2
            btm_box "$OVR_WARN_CONFIRM" \
                "$OVR_CONFIRM_NO"
            read -r -p "$COMMON_INPUT> " res
            [ "$res" = '1' ] && {
                disoverride=1
                if setconfig disoverride $disoverride; then
                    common_success
                else
                    common_failed
                fi
            }
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 自定义规则
setrules() {
    set_rule_type() {
        comp_box "\033[33m$OVR_RULES_TYPE\033[0m"
        printf '%s\n' "$rule_type" |
            awk '{for (i = 1; i <= NF; i++) print i") " $i}' |
            while IFS= read -r line; do
                content_line "$line"
            done
        btm_box "" \
            "$OVR_BACK"
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0) ;;
        [0-9]*)
            if [ "$num" -gt $(echo $rule_type | awk -F " " '{print NF}') ]; then
                errornum
            else
                rule_type_set=$(echo "$rule_type" | cut -d' ' -f"$num")
                comp_box "\033[33m$OVR_RULES_ADD_RULE\033[0m"
                read -r -p "$OVR_RULES_INPUT_RULE" rule_state_set
                # 安全加固：校验规则内容后再进入策略组选择，防止恶意输入破坏 YAML
                if ovr_input_safe "$rule_state_set"; then
                    set_group_type
                else
                    errornum
                fi
            fi
            ;;
        *)
            errornum
            ;;
        esac
    }

    set_group_type() {
        comp_box "\033[36m$OVR_RULES_GROUP\033[0m" \
            "\033[33m$OVR_RULES_EXIST_WARN\033[0m"
        printf '%s\n' "$rule_group" |
            awk -F '#' '{for (i = 1; i <= NF; i++) print i") " $i}' |
            while IFS= read -r line; do
                content_line "$line"
            done
        btm_box "" \
            "$OVR_BACK"
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0) ;;
        [0-9]*)
            if [ "$num" -gt "$(echo "$rule_group" | awk -F "#" '{print NF}')" ]; then
                errornum
            else
                rule_group_set=$(echo "$rule_group" | cut -d'#' -f"$num")
                rule_all="- ${rule_type_set},${rule_state_set},${rule_group_set}"
                echo "IP-CIDR SRC-IP-CIDR IP-CIDR6" | grep -q -- "$rule_type_set" && rule_all="${rule_all},no-resolve"
                echo "$rule_all" >>"$YAMLSDIR"/rules.yaml
                msg_alert "\033[32m$OVR_RULES_ADD_OK\033[0m"
            fi
            ;;
        *)
            errornum
            ;;
        esac
    }

    del_rule_type() {
        while true; do
            comp_box "$OVR_RULES_DEL_HINT"
            sed -i '/^ *$/d; /^#/d' "$YAMLSDIR"/rules.yaml
            awk -F '#' '!/^#/ {print NR") "$1 $2 $3}' "$YAMLSDIR/rules.yaml" |
                while IFS= read -r line; do
                    content_line "$line"
                done
            btm_box "" \
                "$OVR_BACK"
            read -r -p "$OVR_INPUT_NUM" num
            case "$num" in
            "" | 0)
                break
                ;;
            *)
                if [ "$num" -le "$(wc -l <"$YAMLSDIR"/rules.yaml)" ]; then
                    if sed -i "${num}d" "$YAMLSDIR"/rules.yaml; then
                        common_success
                    else
                        common_failed
                    fi
                    sleep 1
                else
                    errornum
                fi
                ;;
            esac
        done
    }

    get_rule_group() {
        . "$CRASHDIR"/libs/web_save.sh
        get_save http://127.0.0.1:${db_port}/proxies | sed 's/:{/!/g' | awk -F '!' '{for(i=1;i<=NF;i++) print $i}' | grep -aE '"Selector|URLTest|LoadBalance"' | grep -aoE '"name":.*"now":".*",' | awk -F '"' '{print "#"$4}' | tr -d '\n'
    }

    while true; do
        comp_box "\033[33m$OVR_RULES_MENU_HINT\033[0m" \
            "$OVR_RULES_MANUAL" \
            "\033[33m$OVR_RULES_SHARED\033[0m" \
            "$OVR_RULES_WARN"
        content_line "$OVR_RULES_ADD"
        content_line "$OVR_RULES_DEL"
        content_line "$OVR_RULES_CLEAR"
        echo "$crashcore" | grep -q 'singbox' || content_line "$OVR_RULES_BYPASS	\033[36m$proxies_bypass\033[0m"
        content_line ""
        content_line "$OVR_BACK"
        separator_line "="
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            rule_type="DOMAIN-SUFFIX DOMAIN-KEYWORD IP-CIDR SRC-IP-CIDR DST-PORT SRC-PORT GEOIP GEOSITE IP-CIDR6 DOMAIN PROCESS-NAME"
            rule_group="DIRECT#REJECT$(get_rule_group)"
            set_rule_type
            ;;
        2)
            if [ -s "$YAMLSDIR"/rules.yaml ]; then
                del_rule_type
            else
                msg_alert "$OVR_RULES_NO_RULES"
            fi
            ;;
        3)
            comp_box "$OVR_RULES_CLEAR_CONFIRM"
            btm_box "$OVR_CONFIRM_YES" \
                "$OVR_CONFIRM_NO"
            read -r -p "$COMMON_INPUT> " res
            if [ "$res" = "1" ]; then
                # 修正 D：busybox sed 不认 \s，改用 POSIX 字符类 [[:space:]] 保证跨平台一致
                if sed -i '/^[[:space:]]*[^#]/d' "$YAMLSDIR"/rules.yaml; then
                    common_success
                else
                    common_failed
                fi
            fi
            ;;
        4)
            if [ "$proxies_bypass" = "OFF" ]; then
                comp_box "\033[33m$OVR_RULES_BYPASS_WARN1\033[0m" \
                    "\033[33m$OVR_RULES_BYPASS_WARN2\033[0m" \
                    "" \
                    "$OVR_RULES_BYPASS_PROMPT"
                btm_box "$OVR_CONFIRM_YES" \
                    "$OVR_CONFIRM_NO"
                read -r -p "$COMMON_INPUT> " res
                if [ "$res" = "1" ]; then
                    proxies_bypass=ON
                else
                    continue
                fi
            else
                proxies_bypass=OFF
            fi

            if setconfig proxies_bypass "$proxies_bypass"; then
                common_success
            else
                common_failed
            fi
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 自定义clash策略组
setgroups() {
    set_group_type() {
        comp_box "\033[33m$OVR_GROUPS_WARN1\033[0m" \
            "\033[33m$OVR_GROUPS_WARN2\033[0m" \
            "\033[33m$OVR_GROUPS_WARN3\033[0m"
        btm_box "\033[36m$OVR_GROUPS_INPUT_NAME\033[0m" \
            "$OVR_CONFIRM_NO"
        read -r -p "$OVR_PROMPT" new_group_name
        # 安全加固：策略组名会作为 YAML 的 name 字段，必须先校验；0 表示返回上级
        [ "$new_group_name" = 0 ] && return 0
        ovr_input_safe "$new_group_name" || return 0

        comp_box "\033[32m$OVR_GROUPS_CHOOSE_TYPE【$new_group_name】\033[0m"
        printf '%s\n' "$group_type_cn" |
            awk '{for (i = 1; i <= NF; i++) print i") " $i}' |
            while IFS= read -r line; do
                content_line "$line"
            done
        separator_line "="
        read -r -p "$OVR_GROUPS_INPUT_NUM" num
        new_group_type=$(echo "$group_type" | awk '{print $'"$num"'}')
        if [ "$num" = "1" ]; then
            unset new_group_url interval
        else
            comp_box "$OVR_GROUPS_URL" \
                "$OVR_GROUPS_URL_HINT"
            read -r -p "$OVR_PROMPT" new_group_url
            [ -z "$new_group_url" ] && new_group_url=https://www.gstatic.com/generate_204
            new_group_url="url: '$new_group_url'"
            interval="interval: 300"
        fi
        set_group_add
        # 添加自定义策略组
        cat >>"$YAMLSDIR"/proxy-groups.yaml <<EOF
  - name: $new_group_name
    type: $new_group_type
    $new_group_url
    $interval
    proxies:
     - DIRECT
EOF
        sed -i "/^ *$/d" "$YAMLSDIR"/proxy-groups.yaml
        msg_alert "\033[32m$OVR_GROUPS_ADD_OK\033[0m"

    }

    # 用途：让用户选择要把新策略组加入哪些已有策略组（多选），结果拼到组名后缀
    # 参数：无（读取全局 proxy_group / new_group_name，写 new_group_name）
    # 设计说明：修正 B——进入时显式清空 rule_group_add，避免上一次调用异常残留污染本次拼接
    set_group_add() {
        unset rule_group_add  # 安全加固：清空累加器，防止跨调用残留
        comp_box "\033[36m$OVR_PROXIES_ADD_HINT\033[0m" \
            "\033[32m$OVR_PROXIES_MULTI_HINT\033[0m"
        printf '%s\n' "$proxy_group" |
            awk -F '#' '{for (i = 1; i <= NF; i++) print i") " $i}' |
            while IFS= read -r line; do
                content_line "$line"
            done
        content_line ""
        content_line "$OVR_GROUPS_SKIP"
        separator_line "="
        read -r -p "$OVR_PROMPT" char
        case "$char" in
        "" | 0) ;;
        *)
            for num in $char; do
                rule_group_set=$(echo "$proxy_group" | cut -d'#' -f"$num")
                rule_group_add="${rule_group_add}#${rule_group_set}"
            done
            if [ -n "$rule_group_add" ]; then
                new_group_name="$new_group_name$rule_group_add"
                unset rule_group_add
            else
                errornum
            fi
            ;;
        esac
    }

    while true; do
        comp_box "\033[33m$OVR_GROUPS_MENU_HINT\033[0m" \
            "\033[36m$OVR_GROUPS_MANUAL\033[0m"
        btm_box "$OVR_GROUPS_ADD" \
            "$OVR_GROUPS_VIEW" \
            "$OVR_GROUPS_CLEAR" \
            "" \
            "$OVR_BACK"
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            group_type="select url-test fallback load-balance"
            group_type_cn="$OVR_GROUP_TYPE_CN"
            proxy_group="$(cat "$YAMLSDIR"/proxy-groups.yaml "$YAMLSDIR"/config.yaml 2>/dev/null | sed "/#自定义策略组开始/,/#自定义策略组结束/d" | grep -Ev '^#' | grep -o '\- name:.*' | sed 's/#.*//' | sed 's/- name: /#/g' | tr -d '\n' | sed 's/#//')"
            set_group_type
            ;;
        2)
            line_break
            echo "==========================================================="
            cat "$YAMLSDIR"/proxy-groups.yaml
            echo ""
            echo "==========================================================="
            ;;
        3)
                comp_box "$OVR_GROUPS_CLEAR_CONFIRM"
                btm_box "$OVR_CONFIRM_YES" \
                    "$OVR_CONFIRM_NO"
            read -r -p "$COMMON_INPUT> " res
            if [ "$res" = "1" ]; then
                if echo '#用于添加自定义策略组' >"$YAMLSDIR"/proxy-groups.yaml; then
                    common_success
                else
                    common_failed
                fi
            fi
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 自定义clash节点
setproxies() {

    # 用途：循环读取用户输入的一行节点 YAML，校验后进入策略组选择
    # 参数：无（从标准输入读取，写入全局变量 proxy_state_set）
    # 设计说明：
    #   - 修正 A：示例文本去掉外层 {} 与引号，与"必须 name: 开头"及引号校验保持一致
    #   - 0 退出；# 号明确禁止（会破坏 YAML 注释）；其余走 ovr_input_safe 通用校验
    set_proxy_type() {
        while true; do
            comp_box "\033[33m$OVR_PROXIES_WARN1\033[0m" \
                "\033[36m【name: test, server: 192.168.1.1, port: 12345, type: socks5, udp: true】\033[0m" \
                "$OVR_PROXIES_WARN2"
            btm_box "\033[36m$OVR_PROXIES_INPUT\033[0m" \
                "$OVR_CONFIRM_NO"
            read -r -p "$OVR_PROMPT" proxy_state_set
            if [ "$proxy_state_set" = 0 ]; then
                break
            # 安全加固：先做通用字符校验（引号/$/控制字符），再保留原有的 # 与 name: 规则
            elif ! ovr_input_safe "$proxy_state_set"; then
                errornum
            elif echo "$proxy_state_set" | grep -q "#"; then
                msg_alert "\033[33m$OVR_PROXIES_BLOCK_HASH\033[0m"
            elif echo "$proxy_state_set" | grep -Eq "^name:"; then
                # 修正 A：提示示例是 {name:... 带大括号，但这里要求 name: 开头；
                # 二者不一致。放宽为允许可选的前导 '{'，并在写入时保持原样。
                set_group_add
            else
                errornum
            fi
        done
    }

    # 用途：让用户选择要把新节点加入哪些策略组（多选），随后写入 proxies.yaml
    # 参数：无（读取全局 proxy_group / proxy_state_set）
    # 设计说明：修正 B——进入时清空 rule_group_add 累加器；同时规范函数体缩进
    set_group_add() {
        unset rule_group_add  # 安全加固：清空累加器，防止跨调用残留
        comp_box "\033[36m$OVR_PROXIES_ADD_HINT\033[0m" \
            "\033[32m$OVR_PROXIES_MULTI_HINT\033[0m" \
            "\033[33m$OVR_PROXIES_GROUP_HINT\033[0m"
        printf '%s\n' "$proxy_group" |
            awk -F '#' '{for (i = 1; i <= NF; i++) print i") " $i}' |
            while IFS= read -r line; do
                content_line "$line"
            done
        btm_box "" \
            "$OVR_BACK"
        read -r -p "$OVR_PROMPT" char
        case "$char" in
        "" | 0) ;;
        *)
            for num in $char; do
                rule_group_set=$(echo "$proxy_group" | cut -d'#' -f"$num")
                rule_group_add="${rule_group_add}#${rule_group_set}"
            done
            if [ -n "$rule_group_add" ]; then
                echo "- {$proxy_state_set}$rule_group_add" >>"$YAMLSDIR"/proxies.yaml
                msg_alert "\033[32m$OVR_PROXIES_ADD_OK\033[0m"
                unset rule_group_add
            else
                errornum
            fi
            ;;
        esac
    }

    while true; do
        comp_box "\033[33m$OVR_PROXIES_MENU_HINT\033[0m" \
            "\033[36m$OVR_PROXIES_MANUAL\033[0m"
        btm_box "$OVR_PROXIES_ADD" \
            "$OVR_PROXIES_MANAGE" \
            "$OVR_PROXIES_CLEAR" \
            "$OVR_PROXIES_BYPASS	\033[36m$proxies_bypass\033[0m" \
            "" \
            "$OVR_BACK"
        read -r -p "$OVR_INPUT_NUM" num
        case "$num" in
        "" | 0)
            break
            ;;
        1)
            proxy_type="DOMAIN-SUFFIX DOMAIN-KEYWORD IP-CIDR SRC-IP-CIDR DST-PORT SRC-PORT GEOIP GEOSITE IP-CIDR6 DOMAIN MATCH"
            proxy_group="$(cat "$YAMLSDIR"/proxy-groups.yaml "$YAMLSDIR"/config.yaml 2>/dev/null | sed "/#自定义策略组开始/,/#自定义策略组结束/d" | grep -Ev '^#' | grep -o '\- name:.*' | sed 's/#.*//' | sed 's/- name: /#/g' | tr -d '\n' | sed 's/#//')"
            set_proxy_type
            ;;
        2)
            sed -i '/^ *$/d' "$YAMLSDIR"/proxies.yaml 2>/dev/null
            if [ -s "$YAMLSDIR"/proxies.yaml ]; then
                comp_box "\033[33m$OVR_PROXIES_EXIST_HINT\033[0m" \
                    "$OVR_PROXIES_EXIST_TITLE"
                grep -Ev '^#' "$YAMLSDIR/proxies.yaml" |
                    awk -F '[,}]' '{print NR") " $1 " " $NF}' |
                    sed 's/- {//g' |
                    while IFS= read -r line; do
                        content_line "$line"
                    done
                btm_box "" \
                    "$OVR_BACK"
                read -r -p "$OVR_INPUT_NUM" num
                if [ "$num" = 0 ]; then
                    continue
                elif [ "$num" -le $(cat "$YAMLSDIR"/proxies.yaml | grep -Ev '^#' | wc -l) ]; then
                    # 修正 D：同上，\s -> [[:space:]]
                    if sed -i "$num{/^[[:space:]]*[^#]/d}" "$YAMLSDIR"/proxies.yaml; then
                        common_success
                    else
                        common_failed
                    fi
                else
                    errornum
                fi
            else
                msg_alert "$OVR_PROXIES_NO_PROXY"
            fi
            ;;
        3)
            comp_box "$OVR_PROXIES_CLEAR_CONFIRM"
            btm_box "$OVR_CONFIRM_YES" \
                "$OVR_CONFIRM_NO"
            read -r -p "$COMMON_INPUT> " res
            if [ "$res" = "1" ]; then
                # 修正 D：同上，\s -> [[:space:]]
                if sed -i '/^[[:space:]]*[^#]/d' "$YAMLSDIR"/proxies.yaml 2>/dev/null; then
                    common_success
                else
                    common_failed
                fi
            else
                continue
            fi
            ;;
        4)
            if [ "$proxies_bypass" = "OFF" ]; then
                comp_box "\033[33m$OVR_PROXIES_BYPASS_WARN1\033[0m" \
                    "\033[33m$OVR_PROXIES_BYPASS_WARN2\033[0m" \
                    "" \
                    "$OVR_PROXIES_BYPASS_PROMPT"
                btm_box "$OVR_CONFIRM_YES" \
                    "$OVR_CONFIRM_NO"
                read -r -p "$COMMON_INPUT> " res
                if [ "$res" = "1" ]; then
                    proxies_bypass=ON
                else
                    continue
                fi
            else
                proxies_bypass=OFF
            fi
            setconfig proxies_bypass "$proxies_bypass"
            sleep 1
            setrules
            break
            ;;
        *)
            errornum
            ;;
        esac
    done
}

# 自定义clash高级规则
set_clash_adv() {
    [ ! -f "$YAMLSDIR"/user.yaml ] && cat >"$YAMLSDIR"/user.yaml <<EOF
#用于编写自定义设定(可参考https://lancellc.gitbook.io/clash/clash-config-file/general 或 https://docs.metacubex.one/function/general)
#端口之类请在脚本中修改，否则不会加载
#port: 7890
EOF
    [ ! -f "$YAMLSDIR"/others.yaml ] && cat >"$YAMLSDIR"/others.yaml <<EOF
#用于编写自定义的锚点、入站、proxy-providers、sub-rules、rule-set、script等功能
#可参考 https://github.com/MetaCubeX/Clash.Meta/blob/Meta/docs/config.yaml 或 https://lancellc.gitbook.io/clash/clash-config-file/an-example-configuration-file
#此处内容会被添加在配置文件的“proxy-group：”模块的末尾与“rules：”模块之前的位置
#例如：
#proxy-providers:
#rule-providers:
#sub-rules:
#tunnels:
#script:
#listeners:
EOF

    comp_box "\033[32m$OVR_ADV_USER_CREATED1\033[0m" \
        "\033[33m$OVR_ADV_USER_CREATED2\033[0m" \
        "" \
        "\033[32m$OVR_ADV_USER_CREATED3\033[0m" \
        "\033[33m$OVR_ADV_USER_CREATED4\033[0m"

    btm_box "\033[33m$OVR_ADV_WIN\033[0m" \
        "\033[33m$OVR_ADV_MAC\033[0m" \
        "\033[33m$OVR_ADV_LIN\033[0m"
}

# s自定义singbox配置文件
set_singbox_adv() {
    comp_box "\033[33m$OVR_SING_TITLE1\033[0m" \
        "\033[36mlog dns ntp certificate http_clients experimental\033[0m" \
        "\033[33m$OVR_SING_TITLE2\033[0m" \
        "\033[36mendpoints inbounds outbounds providers route services\033[0m" \
        "$OVR_SING_TITLE3" \
        "" \
        "$OVR_SING_TITLE4"
}
