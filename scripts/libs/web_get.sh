. "$CRASHDIR"/libs/set_proxy.sh

# webget —— 项目内部文件下载器（带代理/直连双路径与失败清理）
# 用途：根据 CrashCore 是否运行，选择代理（raw.githubusercontent.com）或直连（jsdelivr CDN）地址下载文件
# 参数：$1=本地目标路径 $2=在线地址 $3=输出显示(echooff/echoon) $4=重定向控制(rediroff)
#       $5=证书校验(skipceroff) $6=自定义UA
# 返回：0 成功；1 失败（失败时仅删除本次新建的普通文件，保留原有文件/符号链接/设备文件）
# 设计说明：代理模式下把 jsdelivr/gh.jwsc 地址映射回 raw 直链，避免 CDN 在代理环境下不可用；
#           直连模式反之把 raw 映射为 jsdelivr 镜像加速。
# 去原作者化：两条 sed 映射中的仓库路径统一改为本 fork（Siu-Leung/ShellCrash），映射逻辑保持不变。
webget() (
    if pidof CrashCore >/dev/null; then
        setproxy #设置临时代理，【$1】代表下载目录，【$2】代表在线地址
        url=$(printf '%s\n' "$2" |
            sed -e 's#https://.*jsdelivr.net/gh/Siu-Leung/ShellCrash[@|/]#https://raw.githubusercontent.com/Siu-Leung/ShellCrash/#' \
                -e 's#https://gh.jwsc.eu.org/#https://raw.githubusercontent.com/Siu-Leung/ShellCrash/#')
    else
        url=$(printf '%s\n' "$2" |
            sed 's#https://raw.githubusercontent.com/Siu-Leung/ShellCrash/#https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@#')
    fi
    # ===============================================

    #参数【$1】代表下载目录，【$2】代表在线地址
    #参数【$3】代表输出显示，【$4】不启用重定向
    #参数【$5】代表验证证书，【$6】使用自定义UA
    _out_path="$1"
    _orig_url="$2"
    _ua="$6"
    #记录目标原本是否存在，下载失败时只清理本次新建的文件
    target_existed=''
    if [ -e "$_out_path" ] || [ -L "$_out_path" ]; then target_existed=1; fi
    if wget --help 2>&1 | grep -q 'show-progress' >/dev/null 2>&1; then
        [ "$3" = "echooff" ] && progress='-q' || progress='-q --show-progress'
        [ "$4" = "rediroff" ] && redirect='--max-redirect=0' || redirect=''
        # 安全加固：fail-closed，仅当未强制 skipceroff 且显式 skip_cert=ON 时才跳过校验
        if [ "$5" = "skipceroff" ] || [ "${skip_cert:-OFF}" = OFF ] || [ "$skip_cert" != "ON" ]; then
            certificate=''
        else
            certificate='--no-check-certificate'
        fi
        if [ -n "$_ua" ]; then
            wget_proxy on --user-agent "$_ua" $progress $redirect $certificate --timeout=3 -O "$_out_path" "$url" && return 0 #成功则退出否则重试
            wget_proxy off --user-agent "$_ua" $progress $redirect $certificate --timeout=5 -O "$_out_path" "$_orig_url" && return 0
        else
            wget_proxy on $progress $redirect $certificate --timeout=3 -O "$_out_path" "$url" && return 0 #成功则退出否则重试
            wget_proxy off $progress $redirect $certificate --timeout=5 -O "$_out_path" "$_orig_url" && return 0
        fi
    elif curl --version >/dev/null 2>&1; then
        [ "$4" = "rediroff" ] && redirect='' || redirect='-L'
        # 安全加固：fail-closed，仅当未强制 skipceroff 且显式 skip_cert=ON 时才跳过校验
        if [ "$5" = "skipceroff" ] || [ "${skip_cert:-OFF}" = OFF ] || [ "$skip_cert" != "ON" ]; then
            certificate=''
        else
            certificate='-k'
        fi
        if [ "$3" = "echooff" ]; then
            progress='-s'
        elif echo "$url" | grep -q 'jsdelivr.net'; then
            progress='-#'
            . "$CRASHDIR"/libs/web_get_curlbar.sh && curl_fsize
        else
            progress='-#'
        fi
        # curl 8.x 代理鉴权头兼容（避免未加引号拆词导致 base64 被当成第二个 URL）
        auth_hdr=""
        if [ -n "$authentication" ] && curl --version | grep -q '^curl 8.' && ckcmd base64; then
            auth_b64=$(printf '%s' "$authentication" | base64 | tr -d '\r\n')
            [ -n "$auth_b64" ] && auth_hdr="Proxy-Authorization: Basic $auth_b64"
        fi
        if [ -n "$fsize_raw" ] && [ "$fsize_raw" -gt 204800 ] 2>/dev/null; then
            result=$(execute_curl "$_out_path" "$url" "$fsize_raw" "$_ua" "$auth_hdr" "$redirect" "$certificate")
        else
            result=$(
                set -- -w '%{http_code}' --connect-timeout 3 $progress $redirect $certificate
                [ -n "$_ua" ] && set -- "$@" --user-agent "$_ua"
                [ -n "$auth_hdr" ] && set -- "$@" --proxy-header "$auth_hdr"
                curl "$@" -o "$_out_path" "$url"
            )
        fi
        rc=$?
        #传输中断时状态码仍可能是200，须同时检查curl退出码
        [ "$rc" = 0 ] && [ "$result" = "200" ] && return 0 #成功则退出否则重试
        export https_proxy="" http_proxy="" HTTPS_PROXY="" HTTP_PROXY="" all_proxy="" ALL_PROXY=""

        if [ -n "$fsize_raw" ] && [ "$fsize_raw" -gt 204800 ] 2>/dev/null; then
            result=$(execute_curl "$_out_path" "$_orig_url" "$fsize_raw" "$_ua" "" "$redirect" "$certificate")
        else
            result=$(
                set -- -w '%{http_code}' --connect-timeout 5 $progress $redirect $certificate
                [ -n "$_ua" ] && set -- "$@" --user-agent "$_ua"
                curl "$@" -o "$_out_path" "$_orig_url"
            )
        fi
        rc=$?
        [ "$rc" = 0 ] && [ "$result" = "200" ] && return 0
    elif ckcmd wget; then
        [ "$3" = "echooff" ] && progress='-q'
        wget_proxy on $progress -O "$_out_path" "$url" && return 0 #成功则退出否则重试
        wget_proxy off $progress -O "$_out_path" "$_orig_url" && return 0
    else
        echo "No Curl or Wget！！！"
        return 1
    fi
    #下载失败：只删除本次新建的普通文件；原有文件、符号链接、设备文件(如/dev/null)一律保留
    [ -z "$target_existed" ] && [ -f "$1" ] && [ ! -L "$1" ] && rm -f -- "$1"
    return 1 #不透传wget的4、8等退出码，调用方以返回值1判定失败
)
