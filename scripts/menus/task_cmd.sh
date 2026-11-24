#!/bin/sh
# Copyright (C) Juewuy

#加载全局变量
[ -z "$CRASHDIR" ] && CRASHDIR=$( cd $(dirname $0);cd ..;pwd)
. "$CRASHDIR"/libs/get_config.sh
#加载工具
. "$CRASHDIR"/libs/check_cmd.sh
. "$CRASHDIR"/libs/set_config.sh
. "$CRASHDIR"/libs/web_get_bin.sh
. "$CRASHDIR"/libs/logger.sh
. "$CRASHDIR"/libs/i18n.sh
[ -z "$TASKCFGDIR" ] && TASKCFGDIR="$CRASHDIR"/configs/task

load_lang task_cmd

task_logger(){
    [ "$task_push" = 1 ] && push= || push=off
    [ -n "$2" -a "$2" != 0 ] && echo -e "\033[$2m$1\033[0m"
    [ "$3" = 'off' ] && push=off
    echo "$1" |grep -qE "($TASK_CMD_EVERY|$TASK_CMD_HOURLY)([1-9]|[1-9][0-9])$TASK_CMD_MIN" && {
        push=off
        cover=on
    }
    logger "$1" 0 "$push" "$cover"
}

#任务命令
check_update(){ #检查更新工具（安全加固：纯数据解析 bin/version，禁止 source 执行远端文件；下载失败返回非零）
    if get_bin "$TMPDIR"/crashversion "$1" echooff; then
        load_version_file "$TMPDIR"/crashversion
        rm -rf "$TMPDIR"/crashversion
        return 0
    else
        rm -rf "$TMPDIR"/crashversion
        return 1
    fi
}
update_core(){ #自动更新内核（带启动失败自动回滚）
    #检查版本
    if ! check_update bin/version; then
        task_logger "$TASK_CMD_CORE_DL_FAIL"
        return 1
    fi
    # 安全加固：eval 取间接变量有注入风险，改用白名单函数（get_config.sh 已在本文件头部加载）
    crash_v_new=$(get_version_var "${crashcore}_v")
    if [ -z "$crash_v_new" -o "$crash_v_new" = "$core_v" ];then
        task_logger "$TASK_CMD_CORE_SKIP"
        return 0
    else
        . "$CRASHDIR"/libs/core_tools.sh && core_webget #调用下载工具
        case "$?" in
        0)
            if "$CRASHDIR"/start.sh start; then
                rm -rf "$TMPDIR/core_bak"
                task_logger "$TASK_CMD_CORE_DONE"
                return 0
            else
                # 新内核启动失败：自动回滚至上一套可用内核并重启
                core_rollback && "$CRASHDIR"/start.sh start >/dev/null 2>&1
                task_logger "$TASK_CMD_CORE_VERIFY_FAIL"
                return 1
            fi
        ;;
        1)
            task_logger "$TASK_CMD_CORE_DL_FAIL"
            return 1
        ;;
        *)
            task_logger "$TASK_CMD_CORE_VERIFY_FAIL"
            [ -z "$(pidof CrashCore 2>/dev/null)" ] && "$CRASHDIR"/start.sh start
            return 1
        ;;
        esac
    fi
}
update_scripts(){ #自动更新脚本（调用统一事务化升级 apply_script_upgrade）
    #检查版本（version 文件为纯版本号文本，如 1.9.7-hardened.2）
    versionsh=""
    if ! get_bin "$TMPDIR"/crashversion version echooff; then
        rm -rf "$TMPDIR"/crashversion
        task_logger "$TASK_CMD_CORE_DL_FAIL"
        return 1
    fi
    versionsh=$(head -n 1 "$TMPDIR"/crashversion | tr -d '\r\n ')
    rm -rf "$TMPDIR"/crashversion
    if [ -z "$versionsh" ]; then
        task_logger "$TASK_CMD_CORE_DL_FAIL"
        return 1
    elif [ "$versionsh" = "$versionsh_l" ];then
        task_logger "$TASK_CMD_SCRIPT_SKIP"
        return 0
    else
        get_bin "$TMPDIR"/ShellCrash.tar.gz "ShellCrash.tar.gz"
        if [ "$?" != "0" ];then
            rm -rf "$TMPDIR"/ShellCrash.tar.gz
            task_logger "$TASK_CMD_CORE_DL_FAIL"
            return 1
        fi
        if apply_script_upgrade "$TMPDIR/ShellCrash.tar.gz"; then
            rm -rf "$TMPDIR"/ShellCrash.tar.gz
            return 0
        else
            rm -rf "$TMPDIR"/ShellCrash.tar.gz
            task_logger "$TASK_CMD_SCRIPT_UNZIP_FAIL"
            return 1
        fi
    fi
}
update_mmdb(){ #自动更新数据库（任一文件更新失败时透传非零退出码）
    _mmdb_fail=0
    getgeo(){
        #检查版本
        if ! check_update bin/version; then
            task_logger "$TASK_CMD_DB_DL_FAIL_PREFIX$2$TASK_CMD_DB_DL_FAIL_SUFFIX"
            _mmdb_fail=1
            return 1
        fi
        geo_v="$(echo $2 | awk -F "." '{print $1}')_v" #获取版本号类型比如Country_v
        geo_v_new=$GeoIP_v
        # 安全加固：同上，geo_v 由文件名拼接而来，改白名单读取杜绝注入
        geo_v_now=$(get_version_var "$geo_v")
        if [ -z "$geo_v_new" -o "$geo_v_new" = "$geo_v_now" ];then
            task_logger "$TASK_CMD_DB_SKIP_PREFIX$2$TASK_CMD_DB_SKIP_SUFFIX"
        else
            #更新文件
            get_bin "$TMPDIR"/$1 "bin/geodata/$2"
            if [ "$?" != "0" ];then
                task_logger "$TASK_CMD_DB_DL_FAIL_PREFIX$2$TASK_CMD_DB_DL_FAIL_SUFFIX"
                rm -rf "$TMPDIR"/$1
                _mmdb_fail=1
                return 1
            else
                mv -f "$TMPDIR"/$1 "$BINDIR"/$1
                setconfig $geo_v $GeoIP_v
                task_logger "$TASK_CMD_DB_OK_PREFIX$2$TASK_CMD_DB_OK_SUFFIX"
            fi
        fi
        return 0
    }
    [ -n "${cn_mini_v}" ] && { [ -s "$BINDIR"/Country.mmdb ] || [ -s "$CRASHDIR"/Country.mmdb ]; } && getgeo Country.mmdb cn_mini.mmdb
    [ -n "${china_ip_list_v}" ] && { [ -s "$BINDIR"/cn_ip.txt ] || [ -s "$CRASHDIR"/cn_ip.txt ]; } && getgeo cn_ip.txt china_ip_list.txt
    [ -n "${china_ipv6_list_v}" ] && { [ -s "$BINDIR"/cn_ipv6.txt ] || [ -s "$CRASHDIR"/cn_ipv6.txt ]; } && getgeo cn_ipv6.txt china_ipv6_list.txt
    [ -n "${geosite_v}" ] && { [ -s "$BINDIR"/GeoSite.dat ] || [ -s "$CRASHDIR"/GeoSite.dat ]; } && getgeo GeoSite.dat geosite.dat
    [ -n "${geoip_cn_v}" ] && { [ -s "$BINDIR"/geoip.db ] || [ -s "$CRASHDIR"/geoip.db ]; } && getgeo geoip.db geoip_cn.db
    [ -n "${geosite_cn_v}" ] && { [ -s "$BINDIR"/geosite.db ] || [ -s "$CRASHDIR"/geosite.db ]; } && getgeo geosite.db geosite_cn.db
    return "$_mmdb_fail"
}
reset_firewall(){ #重设透明路由防火墙
    "$CRASHDIR"/start.sh stop_firewall
    "$CRASHDIR"/start.sh afstart
}
ntp(){
    ckcmd ntpd && ntpd -n -q -p 203.107.6.88 >/dev/null 2>&1 || exit 0
}
web_save_auto(){
    . "$CRASHDIR"/libs/web_save.sh && web_save
}
update_config() { #更新订阅并重启
    # 修复：补齐 && 以真正调用 get_core_config，并用 restart 使新配置生效
    . "$CRASHDIR"/starts/core_config.sh && get_core_config && "$CRASHDIR"/start.sh restart
}
hotupdate() { #热更新订阅
    . "$CRASHDIR"/starts/core_config.sh && get_core_config || exit 1
    if echo "$crashcore" | grep -q 'singbox'; then
        # Sing-Box 不支持 Clash PUT /configs 热重载，自动降级为平滑重启
        "$CRASHDIR"/start.sh restart
        exit $?
    fi
    . "$CRASHDIR"/starts/check_core.sh && check_core &&
    . "$CRASHDIR"/starts/"$target"_modify.sh && modify_"$format" &&
    . "$CRASHDIR"/libs/web_restore.sh && put_save "http://127.0.0.1:$db_port/configs" "{\"path\":\"$BINDIR/config.$format\"}"
    _rc=$?
    [ "$start_old" = "ON" ] && [ ! -L "$TMPDIR"/CrashCore ] && rm -f "$TMPDIR"/CrashCore
    exit "$_rc"
}

case "$1" in
    [1-9][0-9][0-9])
        task_command=$(cat "$CRASHDIR"/task/task_${i18n}.list "$TASKCFGDIR"/task.user 2>/dev/null | awk -F '#' -v id="$1" '$1 == id {print $2; exit}')
        task_name=$(cat "$CRASHDIR"/task/task_${i18n}.list "$TASKCFGDIR"/task.user 2>/dev/null | awk -F '#' -v id="$1" '$1 == id {print $3; exit}')
        [ -z "$task_command" ] && exit 1
        #task_logger "任务$task_name 开始执行"
        if eval "$task_command"; then
            _task_rc=0
            task_res="$TASK_CMD_RES_OK"
        else
            _task_rc=$?
            [ "$_task_rc" -eq 0 ] && _task_rc=1
            task_res="$TASK_CMD_RES_FAIL"
        fi
        task_logger "$TASK_CMD_EXEC_PREFIX${2:-$task_name}$TASK_CMD_EXEC_MID$task_res"
        exit "$_task_rc"
    ;;
    update_core|update_scripts|update_mmdb|reset_firewall|ntp|web_save_auto|update_config|hotupdate)
        "$1"
    ;;
    *)
        echo "Unsupported task command: $1" >&2
        exit 1
    ;;
esac
