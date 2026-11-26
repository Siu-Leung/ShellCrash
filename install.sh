#!/bin/sh
# Copyright (C) Juewuy

echo "***********************************************"
echo "**                 欢迎使用                  **"
echo "**                ShellCrash                 **"
echo "**                 Hardened Edition          **"
echo "***********************************************"

language=chs
# 去原作者化：默认安装源改为本 fork 仓库（Siu-Leung/ShellCrash），不再经过上游仓库
# 安全加固：默认分支用 dev（加固版所在分支），master 是未加固的上游镜像，切勿作为默认
[ -z "$url" ] && url="https://cdn.jsdelivr.net/gh/Siu-Leung/ShellCrash@dev"

# 内置工具
cecho() {
    printf '%b\n' "$*"
}
dir_avail() {
    df -h >/dev/null 2>&1 && h="$2"
	df -P $h "${1:-.}" 2>/dev/null | awk 'NR==2 {print $4}'
}
ckcmd() {
    if command -v sh >/dev/null 2>&1; then
        command -v "$1" >/dev/null 2>&1
    else
        type "$1" >/dev/null 2>&1
    fi
}
webget() {
    # 参数【$1】代表下载目录，【$2】代表在线地址，【$3】输出显示，【$4】不启用重定向
    # 安全加固：默认开启 TLS 证书校验；仅当显式设置 SKIP_CERT=1 时才跳过证书校验
    result=""
    if curl --version >/dev/null 2>&1; then
        [ "$3" = "echooff" ] && progress='-s' || progress='-#'
        [ -z "$4" ] && redirect='-L' || redirect=''
        [ "$SKIP_CERT" = "1" ] && cert_arg='-k' || cert_arg=''
        result=$(curl -w '%{http_code}' --connect-timeout 5 $progress $redirect $cert_arg -o "$1" "$2")
        rc=$?
        if [ "$rc" = 0 ] && echo "$result" | grep -q '^2'; then
            result="200"
        else
            result=""
        fi
    elif ckcmd wget; then
        progress=''
        redirect=''
        certificate=''
        if wget --help 2>&1 | grep -q 'show-progress'; then
            [ "$3" = "echooff" ] && progress='-q' || progress='-q --show-progress'
        fi
        [ "$4" = "rediroff" ] && wget --help 2>&1 | grep -q 'max-redirect' && redirect='--max-redirect=0'
        if [ "$SKIP_CERT" = "1" ]; then
            if wget --help 2>&1 | grep -q 'no-check-certificate' || \
               ! wget --no-check-certificate --help 2>&1 | grep -qiE 'option[^a-z]*no-check-certificate'; then
                certificate='--no-check-certificate'
            fi
        fi
        [ "$3" = "echoon" ] && progress=''
        [ "$3" = "echooff" ] && progress='-q'
        wget $progress $redirect $certificate -T 5 -O "$1" "$2"
        [ $? -eq 0 ] && result="200"
    fi
}
error_down() {
    # 去原作者化：错误提示指向本 fork 仓库文档，不再引导至上游仓库
    cecho "请参考 \033[32mhttps://github.com/Siu-Leung/ShellCrash/blob/dev/README_CN.md"
    cecho "\033[33m使用其他安装源重新安装！\033[0m"
}

# 安装及初始化
set_alias() {
    while true; do
        echo "-----------------------------------------------"
        cecho "\033[36m请选择一个别名，或使用自定义别名：\033[0m"
        echo "-----------------------------------------------"
        cecho " 1 【\033[32mcrash\033[0m】"
        cecho " 2 【\033[32m sc \033[0m】"
        cecho " 3 【\033[32m mm \033[0m】"
        cecho " 0 退出安装"
        echo "-----------------------------------------------"
        read -r -p "请输入相应数字或自定义别名 > " res
        case "$res" in
        0)
            echo "安装已取消"
            exit 1
            ;;
        1)
            my_alias=crash
            ;;
        2)
            my_alias=sc
            ;;
        3)
            my_alias=mm
            ;;
        *)
            my_alias=$res
            ;;
        esac
        if ! echo "$my_alias" | grep -Eq '^[A-Za-z_][A-Za-z0-9_-]*$'; then
            cecho "\033[31m别名仅支持字母、数字、下划线和连字符，且不能以数字开头！\033[0m"
            sleep 1
            continue
        fi
        cmd=$(alias "$my_alias" 2>/dev/null | grep 'menu.sh')
        [ -z "$cmd" ] && cmd=$(command -v "$my_alias" 2>/dev/null | grep 'menu.sh')
        ckcmd "$my_alias" && [ -z "$cmd" ] && {
            cecho "\033[33m此别名和当前系统内置命令/别名冲突，请换一个！\033[0m"
            sleep 1
            continue
        }
        break
    done
}
gettar() {
    tar_tmp=$(mktemp "${TMPDIR:-/tmp}/ShellCrash.tar.gz.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/ShellCrash.tar.gz.$$")
    webget "$tar_tmp" "$url/ShellCrash.tar.gz" >/dev/null 2>&1
    if [ "$result" != "200" ]; then
        rm -f "$tar_tmp"
        cecho "\033[33m文件下载失败！\033[0m"
        error_down
        exit 1
    else
        "$CRASHDIR"/start.sh stop 2>/dev/null
        # 解压
        echo "-----------------------------------------------"
        echo "开始解压文件！"
        mkdir -p "$CRASHDIR" >/dev/null
        tar -zxf "$tar_tmp" -C "$CRASHDIR"/ || tar -zxf "$tar_tmp" --no-same-owner -C "$CRASHDIR"/
        rm -f "$tar_tmp"
        if [ -s "$CRASHDIR"/init.sh ]; then
            set_alias
            . "$CRASHDIR"/init.sh >/dev/null
            [ "$?" != 0 ] && cecho "\033[33m初始化失败，请尝试本地安装！\033[0m" && exit 1
        else
            cecho "\033[33m文件解压失败！\033[0m"
            error_down
            exit 1
        fi
    fi
}
set_usb_dir() {
    while true; do
        cecho "请选择安装目录"
        du -hL /mnt 2>/dev/null | awk '{print " "NR" "$2"  "$1}'
        read -r -p "请输入相应数字 > " num
        dir=""
        if echo "$num" | grep -Eq '^[1-9][0-9]*$'; then
            dir=$(du -hL /mnt 2>/dev/null | awk '{print $2}' | sed -n "${num}p")
        fi
        if [ -z "$dir" ]; then
            cecho "\033[31m输入错误！请重新设置！\033[0m"
            continue
        fi
        break 1
    done
}
set_xiaomi_dir() {
	cecho "\033[33m检测到当前设备为小米官方系统，请选择安装位置\033[0m"
	[ -d /data ] && cecho " 1 安装到 /data 目录,剩余空间：$(dir_avail /data -h)(支持软固化功能)"
	[ -d /userdisk ] && cecho " 2 安装到 /userdisk 目录,剩余空间：$(dir_avail /userdisk -h)(支持软固化功能)"
	[ -d /data/other_vol ] && cecho " 3 安装到 /data/other_vol 目录,剩余空间：$(dir_avail /data/other_vol -h)(支持软固化功能)"
	cecho " 4 安装到自定义目录(不推荐，不明勿用！)"
	cecho " 0 退出安装"
	echo "-----------------------------------------------"
	read -r -p "请输入相应数字 > " num
	case "$num" in
	1)
		dir=/data
		;;
	2)
		dir=/userdisk
		;;
	3)
		dir=/data/other_vol
		;;
	4)
		set_cust_dir
		;;
	*)
		exit 1
		;;
	esac
}
set_asus_usb() {
	while true; do
		echo -e "请选择U盘目录"
		du -hL /tmp/mnt 2>/dev/null | awk -F/ 'NF<=4' | awk '{print " "NR" "$2"  "$1}'
		read -r -p "请输入相应数字 > " num
		dir=""
		if echo "$num" | grep -Eq '^[1-9][0-9]*$'; then
			dir=$(du -hL /tmp/mnt 2>/dev/null | awk -F/ 'NF<=4' | awk '{print $2}' | sed -n "${num}p")
		fi
		if [ -z "$dir" ] || [ ! -f "$dir/asusware.arm/etc/init.d/S50downloadmaster" ]; then
			echo -e "\033[31m未找到下载大师自启文件：$dir/asusware.arm/etc/init.d/S50downloadmaster，请检查设置！\033[0m"
			sleep 1
		else
			break
		fi
	done
}
set_asus_dir() {
	cecho "\033[33m检测到当前设备为华硕固件，请选择安装方式\033[0m"
	cecho " 1 基于U盘+下载大师安装(支持所有固件，限ARM设备，须插入U盘或移动硬盘)"
	cecho " 2 基于自启脚本安装(仅支持部分梅林固件)"
	cecho " 0 退出安装"
	echo "-----------------------------------------------"
	read -r -p "请输入相应数字 > " num
	case "$num" in
	1)
		echo -e "请先在路由器网页后台安装下载大师并启用，之后选择外置存储所在目录！"
		sleep 2
		set_asus_usb
	;;
	2)
		cecho "如开机无法正常自启，请重新使用U盘+下载大师安装！"
		sleep 2
		dir=/jffs
	;;
	*)
		exit 1
	;;
	esac
}
set_cust_dir() {
    while true; do
        echo "-----------------------------------------------"
        echo '可用路径 剩余空间：'
        df -h | awk '{print $6,$4}' | sed 1d
        echo '路径是必须带 / 的格式，注意写入虚拟内存(/tmp,/opt,/sys...)的文件会在重启后消失！！！'
        read -r -p "请输入自定义路径 > " dir
        if [ -z "$dir" ] || [ "$(dir_avail "$dir")" = 0 ] || echo "$dir" | grep -Eq '^/(tmp|opt|sys)(/|$)'; then
            cecho "\033[31m路径错误！请重新设置！\033[0m"
            continue
        fi
        break 1
    done
}

setdir() {
    while true; do
        echo "-----------------------------------------------"
        cecho "\033[33m注意：安装ShellCrash至少需要预留约1MB的磁盘空间\033[0m"
        case "$systype" in
			Padavan) dir=/etc/storage ;;
			mi_snapshot) set_xiaomi_dir ;;
			asusrouter) set_asus_dir ;;
			ng_snapshot) dir=/tmp/mnt ;;
			*)
				cecho " 1 在\033[32m/etc目录\033[0m下安装(适合root用户)"
				cecho " 2 在\033[32m/usr/share目录\033[0m下安装(适合Linux系统)"
				cecho " 3 在\033[32m当前用户目录\033[0m下安装(适合非root用户)"
				cecho " 4 在\033[32m外置存储\033[0m中安装"
				cecho " 5 手动设置安装目录"
				cecho " 0 退出安装"
				echo "----------------------------------------------"
				read -r -p "请输入相应数字 > " num
				# 设置目录
				case "$num" in
				1)
					dir=/etc
					;;
				2)
					dir=/usr/share
					;;
				3)
					dir=~/.local/share
					mkdir -p ~/.config/systemd/user
					;;
				4)
					set_usb_dir
					;;
				5)
					set_cust_dir
					;;
				*)
					echo "安装已取消"
					exit 1
					;;
				esac
			;;
		esac

        if [ ! -w "$dir" ]; then
            cecho "\033[31m没有$dir目录写入权限！请重新设置！\033[0m"
            sleep 1
        else
            cecho "目标目录\033[32m$dir\033[0m空间剩余：$(dir_avail "$dir" -h)"
            read -r -p "确认安装？(1/0) > " res
            if [ "$res" = "1" ]; then
                CRASHDIR="$dir"/ShellCrash
                break
            fi
        fi
    done
}
install() {
    echo "-----------------------------------------------"
    echo "开始从服务器获取安装文件！"
    echo "-----------------------------------------------"
    gettar
    echo "-----------------------------------------------"
    echo "ShellCrash 已经安装成功!"
    [ "$profile" = "~/.bashrc" ] && echo "请执行【. ~/.bashrc > /dev/null】命令以更新环境变量！"
    [ -n "$(ls -l /bin/sh | grep -oE 'zsh')" ] && echo "请执行【. ~/.zshrc > /dev/null】命令以更新环境变量！"
    echo "-----------------------------------------------"
    cecho "\033[33m输入\033[30;47m $my_alias \033[0;33m命令即可管理！！！\033[0m"
    echo "-----------------------------------------------"
}
# 安全加固/去原作者化：本 fork 的加固内容只维护在 dev 分支，master/stable 是未加固的上游镜像。
# 三个选项统一落到 dev，避免用户误选到未加固版本；保留菜单项仅为兼容原交互流程。
setversion() {
    echo "-----------------------------------------------"
    cecho "\033[33m本加固版仅提供单一版本：\033[0m"
    cecho " 1 \033[32m加固版(dev，推荐)\033[0m"
    echo "-----------------------------------------------"
    read -r -p "请输入相应数字 > " num
    release_type=dev
    url=$(echo "$url" | sed "s/@[A-Za-z0-9_.-]*/@dev/; s#/master#/dev#; s#/stable#/dev#")
}

# 安装检查
check_systype() {
	[ -f "/etc/storage/started_script.sh" ] && {
		systype=Padavan #老毛子固件
		initdir='/etc/storage/started_script.sh'
	}
	[ -d "/jffs" ] && {
		systype=asusrouter #华硕固件
		[ -f "/jffs/.asusrouter" ] && initdir='/jffs/.asusrouter'
		[ -d "/jffs/scripts" ] && initdir='/jffs/scripts/nat-start'
	}
	[ -f "/data/etc/crontabs/root" ] && systype=mi_snapshot #小米设备
	[ -w "/var/mnt/cfg/firewall" ] && systype=ng_snapshot   #NETGEAR设备
}
check_user() {
	if [ "$(id -u 2>/dev/null)" != "0" ] && [ "$USER" != "root" ] && [ -z "$systype" ]; then
		echo "当前用户:${USER:-$(id -un 2>/dev/null)}"
		cecho "\033[31m请尽量使用root用户（不要直接使用sudo命令！）执行安装!\033[0m"
		echo "-----------------------------------------------"
		read -r -p "仍要安装？可能会产生未知错误！(1/0) > " res
		[ "$res" != "1" ] && exit 1
	fi
}
check_version() {
	echo "$url" | grep -Eq '(@|/)(master|stable)(/|$)' && setversion
	ver_tmp=$(mktemp "${TMPDIR:-/tmp}/sc_version.XXXXXX" 2>/dev/null || echo "${TMPDIR:-/tmp}/sc_version.$$")
	webget "$ver_tmp" "$url/version" echooff
	[ "$result" = "200" ] && versionsh=$(head -n 1 "$ver_tmp" | tr -d '\r\n ')
	rm -f "$ver_tmp"

	# 输出
	cecho "最新版本：\033[32m$versionsh\033[0m"
	echo "-----------------------------------------------"
	cecho "\033[44m如遇问题请到项目 Issues 反馈：\033[42;30m https://github.com/Siu-Leung/ShellCrash/issues \033[0m"
	cecho "\033[37m支持各种基于openwrt的路由器设备"
	cecho "\033[33m支持Debian、Centos等标准Linux系统\033[0m"
}
check_dir() {
	if [ -n "$CRASHDIR" ]; then
		echo "-----------------------------------------------"
		cecho "检测到旧的安装目录\033[36m$CRASHDIR\033[0m，是否覆盖安装？"
		cecho "\033[32m覆盖安装时不会移除配置文件！\033[0m"
		echo " 1 覆盖安装"
		echo " 2 卸载旧版本并安装"
		echo " 0 取消安装"
		read -p "请输入相应数字 > " num
		case "$num" in
		1)
			install
			;;
		2)
			[ "$CRASHDIR" != "/" ] && rm -rf "$CRASHDIR"
			echo "-----------------------------------------------"
			cecho "\033[31m 旧版本文件已卸载！\033[0m"
			setdir
			install
			;;
		9)
			echo "测试模式，变更安装位置 $CRASHDIR"
			setdir
			install
			;;
		*)
			cecho "\033[31m已取消安装！\033[0m"
			exit 1
			;;
		esac
	else
		setdir
		install
	fi
}

check_systype
check_user
check_version
check_dir
