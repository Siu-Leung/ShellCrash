

[ -n "$(find --help 2>&1 | grep -o size)" ] && find_para=' -size +2000'             #find命令兼容

#根据环境权衡决定是否把裸二进制存于$BINDIR(rom)——省RAM，前提是rom装得下
#$1=裸二进制字节数。仅当$TMPDIR在内存(tmpfs)时裸存才省RAM；
#再按$BINDIR文件系统估算裸二进制落盘体积(透明压缩fs约2:1)，需留有余量($raw_margin,默认8M)
store_raw_worth_it(){
    case "$(df -P -T "$TMPDIR" 2>/dev/null | awk 'END{print $2}')" in tmpfs|ramfs) ;; *) return 1 ;; esac
    rom_free=$(df -P -k "$BINDIR" 2>/dev/null | awk 'END{print $4}')          #KB
    [ -z "$rom_free" ] && return 1
    case "$(df -P -T "$BINDIR" 2>/dev/null | awk 'END{print $2}')" in
        squashfs|ubifs|overlay|overlayfs) est=$(( ${1:-0}/1024/2 )) ;;    #透明压缩，约2:1
        *) est=$(( ${1:-0}/1024 )) ;;                                     #无压缩，全量
    esac
    [ $(( rom_free - est )) -gt "${raw_margin:-8192}" ] && return 0 || return 1
}

core_unzip() { #$1:需要解压的文件 $2:目标文件名
    if echo "$1" |grep -q 'tar.gz$' ;then
        [ "$BINDIR" = "$TMPDIR" ] && rm -rf "$TMPDIR"/CrashCore #小闪存模式防止空间不足
        [ -n "$(tar --help 2>&1 | grep -o 'no-same-owner')" ] && tar_para='--no-same-owner' #tar命令兼容
        mkdir -p "$TMPDIR"/core_tmp
        tar -zxf "$1" ${tar_para} -C "$TMPDIR"/core_tmp/
        for file in $(find "$TMPDIR"/core_tmp $find_para 2>/dev/null); do
            [ -f "$file" ] && [ -n "$(echo $file | sed 's#.*/##' | grep -iE '(CrashCore|sing|meta|mihomo|clash|pre)')" ] && mv -f "$file" "$TMPDIR"/"$2"
        done
        rm -rf "$TMPDIR"/core_tmp
    elif echo "$1" |grep -q '.gz$' ;then
        gunzip -c "$1" > "$TMPDIR"/"$2"
    elif echo "$1" |grep -q '.raw$' ;then
        ln -sf "$1" "$TMPDIR"/"$2"
    elif echo "$1" |grep -q '.upx$' ;then
        ln -sf "$1" "$TMPDIR"/"$2"
    else
        mv -f "$1" "$TMPDIR"/"$2"
    fi
    chmod +x "$TMPDIR"/"$2"
}
core_find(){
    if [ ! -f "$TMPDIR"/CrashCore ];then
        [ -n "$(find "$CRASHDIR"/CrashCore.* $find_para 2>/dev/null)" ] && [ "$CRASHDIR" != "$BINDIR" ] &&
            mv -f "$CRASHDIR"/CrashCore.* "$BINDIR"/
        core_dir=$(find "$BINDIR"/CrashCore.* $find_para 2>/dev/null | head -n 1)
        [ -n "$core_dir" ] && core_unzip "$core_dir" CrashCore
    fi
}
core_rollback(){ #内核更新启动失败时恢复上一套可用内核与元信息
    [ -d "$TMPDIR/core_bak" ] || return 1
    rm -f "$BINDIR"/CrashCore.tar.gz "$BINDIR"/CrashCore.gz "$BINDIR"/CrashCore.upx "$BINDIR"/CrashCore.raw "$TMPDIR"/CrashCore
    for _bf in "$TMPDIR"/core_bak/CrashCore.*; do
        [ -f "$_bf" ] && mv -f "$_bf" "$BINDIR/"
    done
    [ -n "$CORE_PREV_V" ] && { core_v="$CORE_PREV_V"; setconfig core_v "$core_v"; }
    [ -n "$CORE_PREV_CMD" ] && { COMMAND="$CORE_PREV_CMD"; setconfig COMMAND "$COMMAND" "$CRASHDIR"/configs/command.env; }
    [ -n "$CORE_PREV_TYPE" ] && { crashcore="$CORE_PREV_TYPE"; setconfig crashcore "$crashcore"; }
    rm -rf "$TMPDIR/core_bak"
    return 0
}
core_check(){
    CORE_PREV_V="$core_v"
    CORE_PREV_CMD="$COMMAND"
    CORE_PREV_TYPE="$crashcore"
    # 安全加固：先对候选内核做解压与二进制自检，通过前绝不删除既有可用内核
    rm -f "$TMPDIR"/core_new
    core_unzip "$1" core_new
    sbcheck=$(echo "$crashcore" | grep 'singbox')
    v=''
    if [ -n "$sbcheck" ] && "$TMPDIR"/core_new -h 2>&1 | grep -q 'sing-box'; then
        v=$("$TMPDIR"/core_new version 2>/dev/null | grep version | awk '{print $3}')
        _new_cmd='"$TMPDIR/CrashCore run -D $BINDIR -C $TMPDIR/jsons"'
    elif [ -z "$sbcheck" ] && "$TMPDIR"/core_new -h 2>&1 | grep -q '\-t';then
        v=$("$TMPDIR"/core_new -v 2>/dev/null | head -n 1 | sed 's/ linux.*//;s/.* //')
        _new_cmd='"$TMPDIR/CrashCore -d $BINDIR -f $TMPDIR/config.yaml"'
    fi
    if [ -z "$v" ]; then
        rm -rf "$1" "$TMPDIR"/core_new
        return 2
    fi
    # 候选 Clash/Mihomo 内核若存在现用 config.yaml，额外做离线语法预检
    if [ -z "$sbcheck" ] && [ -s "$BINDIR/config.yaml" ]; then
        "$TMPDIR"/core_new -t -d "$BINDIR" -f "$BINDIR/config.yaml" >/dev/null 2>&1 || {
            rm -rf "$1" "$TMPDIR"/core_new
            return 2
        }
    fi
    # 备份旧内核归档至 $TMPDIR/core_bak，便于后续启动失败时自动回滚
    rm -rf "$TMPDIR/core_bak"
    mkdir -p "$TMPDIR/core_bak"
    for _oldf in "$BINDIR"/CrashCore.tar.gz "$BINDIR"/CrashCore.gz "$BINDIR"/CrashCore.upx "$BINDIR"/CrashCore.raw; do
        [ -f "$_oldf" ] && cp -f "$_oldf" "$TMPDIR/core_bak/" 2>/dev/null
    done
    [ -n "$(pidof CrashCore)" ] && "$CRASHDIR"/start.sh stop #停止旧内核准备切换
    rm -f "$BINDIR"/CrashCore.tar.gz "$BINDIR"/CrashCore.gz "$BINDIR"/CrashCore.upx "$BINDIR"/CrashCore.raw
    _swap_ok=0
    if [ "$zip_type" = 'upx' ];then
        mv -f "$1" "$BINDIR/CrashCore.upx" && rm -f "$TMPDIR"/core_new && ln -sf "$BINDIR/CrashCore.upx" "$TMPDIR/CrashCore" && _swap_ok=1
    elif store_raw_worth_it "$(wc -c < "$TMPDIR/core_new")" ;then
        mv -f "$TMPDIR/core_new" "$BINDIR/CrashCore.raw" && rm -f "$1" && ln -sf "$BINDIR/CrashCore.raw" "$TMPDIR/CrashCore" && _swap_ok=1
    elif [ -z "$zip_type" ];then
        gzip -c "$TMPDIR/core_new" > "$BINDIR/CrashCore.gz" && mv -f "$TMPDIR/core_new" "$TMPDIR/CrashCore" && _swap_ok=1
    else
        mv -f "$1" "$BINDIR/CrashCore.$zip_type" && mv -f "$TMPDIR/core_new" "$TMPDIR/CrashCore" && _swap_ok=1
    fi
    if [ "$_swap_ok" != 1 ]; then
        core_rollback
        rm -rf "$1" "$TMPDIR"/core_new
        return 2
    fi
    COMMAND="$_new_cmd"
    core_v="$v"
    setconfig COMMAND "$COMMAND" "$CRASHDIR"/configs/command.env && . "$CRASHDIR"/configs/command.env
    setconfig crashcore "$crashcore"
    setconfig core_v "$core_v"
    setconfig_quote custcorelink "$custcorelink"
    return 0
}
core_webget(){
    . "$CRASHDIR"/libs/web_get_bin.sh
    . "$CRASHDIR"/libs/check_target.sh
    if [ -z "$custcorelink" ];then
        [ -z "$zip_type" ] && zip_type='tar.gz'
        #若环境适合裸存(见store_raw_worth_it，按典型核心~45M估算)，避免下载upx，改取tar.gz的裸二进制
        [ "$zip_type" = 'upx' ] && store_raw_worth_it 47185920 && zip_type='tar.gz'
        get_bin "$TMPDIR/Coretmp.$zip_type" "bin/$crashcore/${target}-linux-${cpucore}.$zip_type"
    else
        zip_type=""
        case "$custcorelink" in
            *.tar.gz) zip_type="tar.gz" ;;
            *.gz)     zip_type="gz" ;;
            *.upx)    zip_type="upx" ;;
        esac
        [ -n "$zip_type" ] && webget "$TMPDIR/Coretmp.$zip_type" "$custcorelink"
    fi
    #校验内核
    if [ "$?" = 0 ] && [ -n "$zip_type" ];then
        core_check "$TMPDIR/Coretmp.$zip_type"
    else
        rm -f "$TMPDIR/Coretmp.$zip_type"
        return 1
    fi
}
