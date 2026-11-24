. "$CRASHDIR"/libs/web_get.sh

# get_bin —— 专用于项目内部文件的下载
# 用途：根据 url_id/分支类型拼接出仓库文件直链，并调用 webget 下载
# 参数：$1=本地目标路径 $2=仓库内相对路径 $3=显示模式 $4=重定向控制 $5=证书校验 $6=自定义UA
# 返回：透传 webget 的返回值（0 成功，1 失败）
# 设计说明：bin/ 文件固定在 update 分支下载（该分支含完整内核二进制）；
#           public/ 与 rules/ 在 dev 分支下载；101/104 为 jsdelivr 源，需保留 @$rt 拼接结构。
# 去原作者化：update_url 默认值指向本 fork 仓库（Siu-Leung/ShellCrash），不再经过上游仓库。
# 安全加固：默认分支由 master 改为 dev —— fork 的 master 分支是未加固的上游原样镜像，
#           加固内容(dev)全在 dev 分支；若默认走 master，用户更新脚本会把加固冲掉。
get_bin() { #专用于项目内部文件的下载
    [ -z "$update_url" ] && update_url=https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev
    if [ -n "$url_id" ]; then
        [ -n "$release_type" ] && rt="$release_type" || rt=dev
        echo "$2" | grep -q '^bin/' && rt=update #/bin文件改为在update分支下载
        echo "$2" | grep -qE '^public/|^rules/' && rt=dev #/public和/rules文件改为在dev分支下载    
        if [ "$url_id" = 101 -o "$url_id" = 104 ]; then
            bin_url="$(cat "$CRASHDIR"/configs/servers_chs.list 2>/dev/null | awk -v id="$url_id" 'BEGIN{u="https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash"} $1 == id {u=$3; exit} END{print u}')@$rt/$2" #jsdelivr特殊处理
        else
            bin_url="$(cat "$CRASHDIR"/configs/servers_chs.list 2>/dev/null | awk -v id="$url_id" 'BEGIN{u="https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash"} $1 == id {u=$3; exit} END{print u}')/$rt/$2"
        fi
    else
        # 安全加固：默认安装仅写入 update_url(@dev) 而未设 url_id；下载 bin/* 时自动切到 update 分支，
        # 下载 public/* 或 rules/* 时切到 dev 分支，确保首次安装即可拉到自主编译内核与最新资源
        _base_url="$update_url"
        if echo "$2" | grep -q '^bin/'; then
            _base_url=$(printf '%s\n' "$_base_url" | sed -e 's#Siu-Leung/ShellCrash@[^/]*#Siu-Leung/ShellCrash@update#' -e 's#Siu-Leung/ShellCrash/[^/]*#Siu-Leung/ShellCrash/update#')
        elif echo "$2" | grep -qE '^public/|^rules/'; then
            _base_url=$(printf '%s\n' "$_base_url" | sed -e 's#Siu-Leung/ShellCrash@[^/]*#Siu-Leung/ShellCrash@dev#' -e 's#Siu-Leung/ShellCrash/[^/]*#Siu-Leung/ShellCrash/dev#')
        fi
        bin_url="$_base_url/$2"
    fi
    webget "$1" "$bin_url" "$3" "$4" "$5" "$6"
}
