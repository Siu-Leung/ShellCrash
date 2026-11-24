#!/bin/sh
# Copyright (C) Juewuy

. "$CRASHDIR"/libs/urlencode.sh
. "$CRASHDIR"/libs/check_target.sh
. "$CRASHDIR"/libs/web_get_bin.sh
. "$CRASHDIR"/libs/compare.sh
. "$CRASHDIR"/libs/set_config.sh
. "$CRASHDIR"/libs/logger.sh
. "$CRASHDIR"/libs/i18n.sh

update_servers() { #更新servers_${i18n}.list
    get_bin "$TMPDIR"/servers_${i18n}.list public/servers_${i18n}.list
    [ "$?" = 0 ] && mv -f "$TMPDIR"/servers_${i18n}.list "$CRASHDIR"/configs/servers_${i18n}.list
}
gen_ua(){  #自动生成ua
    [ -z "$user_agent" -o "$user_agent" = "auto" ] && {
        if echo "$crashcore" | grep -q 'singbox'; then
            user_agent="sing-box/$core_v"
        elif [ "$crashcore" = meta ]; then
            user_agent="clash.meta/mihomo"
        else
            user_agent="clash"
        fi
    }
    [ "$user_agent" = "none" ] && unset user_agent
}
get_core_config() { #下载或本地转换内核配置文件（零第三方转换站外发）
    gen_ua
    # 安全加固：彻底移除第三方 subconverter 在线转换路径。
    # 1) 若未设置直链 Https（如启用了本地拉取转换模式），则通过 local_sub_convert.sh 在本机直拉订阅并合成配置。
    if [ -z "$Https" ]; then
        if [ -s "$CRASHDIR"/configs/providers.cfg ] || [ -s "$CRASHDIR"/configs/providers_uri.cfg ]; then
            echo "-----------------------------------------------"
            logger "正在本地直拉订阅并转换【$target】配置文件（零外泄）…………" 36
            . "$CRASHDIR"/libs/local_sub_convert.sh
            if local_sub_convert; then
                echo -e "\033[32m已成功完成本地订阅拉取与配置转换！\033[0m"
                return 0
            else
                logger "本地订阅拉取或转换失败，请检查订阅链接与网络连接！" 31
                return 1
            fi
        else
            logger "未配置直链订阅或本地提供者，请先在配置文件管理中添加订阅！" 31
            return 1
        fi
    fi

    # 2) 直链模式（Https 非空）：直接从用户原始 URL 拉取配置，绝不经过第三方中转
    Https=$(echo "$Https" | sed 's/\\&/\&/g')   #还原转义
    echo "-----------------------------------------------"
    logger "正在直连源地址获取【$target】配置文件…………" 36
    core_config_new="$TMPDIR"/"$target"_config."$format"
    rm -rf "$core_config_new"
    webget "$core_config_new" "$Https" echoon rediron skipceron "$user_agent"
    if [ "$?" != "0" ]; then
        echo "-----------------------------------------------"
        logger "配置文件获取失败！" 31
        echo -e "\033[31m请检查订阅链接或尝试使用【本地拉取并转换配置文件】功能！\033[0m"
        echo "-----------------------------------------------"
        return 1
    else
        Https=""
        if echo "$crashcore" | grep -q 'singbox'; then
            . "$CRASHDIR"/starts/singbox_config_check.sh
        else
            . "$CRASHDIR"/starts/clash_config_check.sh
        fi
        check_config || return 1
        #如果不同则备份并替换文件（确保目录存在且仅替换成功后提示成功）
        mkdir -p "$(dirname "$core_config")"
        if [ -s "$core_config" ]; then
            if compare "$core_config_new" "$core_config"; then
                rm -f "$core_config_new"
            else
                cp -f "$core_config" "$core_config".bak && mv -f "$core_config_new" "$core_config" || return 1
            fi
        else
            mv -f "$core_config_new" "$core_config" || return 1
        fi
        echo -e "\033[32m已成功获取配置文件！\033[0m"
    fi
    return 0
}
