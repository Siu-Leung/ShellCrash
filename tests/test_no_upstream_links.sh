#!/bin/sh
# 兼容未安装 ripgrep 的纯 Linux 环境：无 rg 时自动回退到 POSIX grep
if ! command -v rg >/dev/null 2>&1; then
    rg() {
        _q=""; _F=""; _P=""; _c=""; _n=""; _i=""; _inv=""; _pat=""; _excl="--exclude-dir=.git"
        while [ $# -gt 0 ]; do
            case "$1" in
                -q) _q="-q"; shift ;;
                -F) _F="-F"; shift ;;
                -P) _P="-P"; shift ;;
                -c) _c="-c"; shift ;;
                -n) _n="-n"; shift ;;
                -i) _i="-i"; shift ;;
                -v) _inv="-v"; shift ;;
                -g)
                    _g="$2"; shift 2
                    case "$_g" in
                        !*) _v="${_g#!}"; _v="${_v%/*}"; _excl="$_excl --exclude=$_v --exclude-dir=$_v" ;;
                    esac
                    ;;
                --glob=!*)
                    _v="${1#--glob=!}"; _v="${_v%/*}"; shift
                    _excl="$_excl --exclude=$_v --exclude-dir=$_v"
                    ;;
                --glob=*) shift ;;
                -e) shift; _pat="$1"; shift ;;
                --) shift; break ;;
                -*) shift ;;
                *) break ;;
            esac
        done
        if [ -z "$_pat" ] && [ $# -gt 0 ]; then _pat="$1"; shift; fi
        _mode="-E"; [ -n "$_F" ] && _mode="-F"; [ -n "$_P" ] && _mode="-P"
        _rec=""
        for _p in "$@"; do [ -d "$_p" ] && _rec="-r"; done
        grep $_rec $_mode $_q $_c $_n $_i $_inv $_excl -- "$_pat" "$@"
    }
fi
# 去原作者化离线回归：断言源码树与 README 不再含上游引流/下载外链，
# 所有仓库下载源统一指向本 fork（Siu-Leung/ShellCrash），并校验改过的 shell 脚本语法。
# 用途：防止上游域名/仓库在后续改动中被重新引入。
# 参数：无
# 返回：0=全部通过；1=存在失败项
# 设计说明：
#   - 排除 tests/ 自身（测试断言里必须写出被禁止的字样）与 SECURITY_HARDENING.md（历史说明）；
#   - bot_tg.lang 的 t.me/BotFather 是 Telegram 官方机器人申请入口，功能必需，单独豁免；
#   - 同时检查预打包 ShellCrash.tar.gz 解压后的内容，防止包内残留旧外链。
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAIL=0
ok(){ printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad(){ printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

# 递归枚举待扫文件：源码、README、Dockerfile、工作流、rules、docker 文档；排除 tests/ 与 .git
list_files(){
    ( cd "$ROOT" && rg --files -g '!tests/**' -g '!.git/**' -g '!ShellCrash.tar.gz' \
        -g '!SECURITY_HARDENING.md' )
}

echo '== 1. 源码树/README：无上游仓库与引流字样 =='
PAT='juewuy/ShellCrash|juewuy\.github\.io|t\.me/ShellClash|(testingcf|purge)\.jsdelivr\.net/gh/juewuy|raw\.githubusercontent\.com/juewuy|github\.com/juewuy'
hits=$(cd "$ROOT" && rg -n --hidden -g '!tests/**' -g '!.git/**' -g '!ShellCrash.tar.gz' \
    -g '!SECURITY_HARDENING.md' "$PAT" . 2>/dev/null || true)
if [ -z "$hits" ]; then
    ok '源码树与 README 无上游外链'
else
    bad "源码树仍有上游外链：
$hits"
fi

# BotFather 是官方申请入口，必须保留；其余 t.me/ 引流不允许
# 注：t.me/BotFather 是官方机器人申请入口，必须保留；ShellCrashtg_bot 是上游公共机器人，已停用
for f in scripts/lang/chs/bot_tg.lang scripts/lang/en/bot_tg.lang; do
    extra=$(cd "$ROOT" && rg -n 't\.me/' "$f" 2>/dev/null | rg -v 't\.me/BotFather' || true)
    if [ -z "$extra" ]; then ok "$(basename $(dirname "$f"))/$(basename "$f") 仅保留 BotFather 官方入口"; \
    else bad "$f 存在非 BotFather 的 t.me 链接：$extra"; fi
done

echo '== 2. 下载源统一指向本 fork =='
for f in install.sh install_en.sh scripts/libs/web_get_bin.sh scripts/libs/web_get.sh \
         public/servers.list public/servers_chs.list public/servers_en.list Dockerfile; do
    if rg -q 'Siu-Leung/ShellCrash' "$ROOT/$f" 2>/dev/null; then
        ok "$(basename "$f") 含 fork 下载源"
    else
        bad "$f 缺少 fork 下载源"
    fi
done
# servers.list 的 101/104 必须保留 jsdelivr @$rt 拼接结构（在 get_bin 中）
# 101/104 使用 jsdelivr，get_bin 中需保留 @$rt 拼接：用固定串检查分支条件与 @ 拼接同时存在
if rg -q -F '"$url_id" = 101 -o "$url_id" = 104' "$ROOT/scripts/libs/web_get_bin.sh" && \
   rg -q -F "')@\$rt/\$2\"" "$ROOT/scripts/libs/web_get_bin.sh"; then
    ok 'get_bin 保留 101/104 jsdelivr 特殊拼接'
else
    bad 'get_bin 丢失 101/104 jsdelivr 特殊拼接'
fi

echo '== 3. 展示型外链已从菜单/语言文件清除 =='
for f in scripts/menu.sh scripts/menus/bot_tg.sh scripts/menus/9_upgrade.sh scripts/menus/8_tools.sh; do
    if rg -q 't\.me/ShellClash|juewuy\.github\.io|github\.com/juewuy' "$ROOT/$f" 2>/dev/null; then
        bad "$f 仍有上游引流展示"
    else ok "$(basename "$f") 无上游引流展示"; fi
done

echo '== 4. shell 语法校验（sh -n）=='
for f in install.sh install_en.sh scripts/libs/web_get.sh scripts/libs/web_get_bin.sh \
         scripts/menu.sh scripts/menus/bot_tg.sh scripts/menus/9_upgrade.sh scripts/menus/8_tools.sh sync_pkg.sh; do
    if sh -n "$ROOT/$f" 2>/dev/null; then ok "sh -n $f"; else bad "sh -n $f"; fi
done

echo '== 5. 预打包 tar.gz 内无上游外链 =='
TMP=$(mktemp -d)
tar -xzf "$ROOT/ShellCrash.tar.gz" -C "$TMP"
hits=$(cd "$TMP" && rg -n --hidden -g '!SECURITY_HARDENING.md' "$PAT" . 2>/dev/null | \
    rg -v 't\.me/BotFather' || true)
if [ -z "$hits" ]; then ok '包内无上游外链'; else bad "包内仍有上游外链：
$hits"; fi
rm -rf "$TMP"

echo '== 6. 默认分支锁定 dev（master/stable 是未加固上游镜像）=='
for f in install.sh install_en.sh scripts/libs/web_get_bin.sh README_CN.md README.md; do
    if rg -q 'Siu-Leung/ShellCrash@master|Siu-Leung/ShellCrash/master' "$ROOT/$f" 2>/dev/null; then
        bad "$f 默认源仍指向未加固的 master 分支"
    else ok "$f 无 master 默认源"; fi
done
# get_bin 的 rt 回退必须是 dev
if rg -q 'rt="\$release_type" \|\| rt=dev' "$ROOT/scripts/libs/web_get_bin.sh"; then
    ok 'get_bin 分支回退为 dev'
else bad 'get_bin 分支回退非 dev（会拉到未加固版）'; fi
# setversion 必须强制 dev
for f in install.sh install_en.sh; do
    if rg -q 'release_type=dev' "$ROOT/$f" 2>/dev/null; then ok "$f setversion 强制 dev"; \
    else bad "$f setversion 未强制 dev"; fi
done

echo '== 7. fork 自身下载源不使用失效的 testingcf 镜像 =='
# 实测 testingcf.jsdelivr.net 对新建 fork 返回 403；指向 Siu-Leung/ShellCrash 的该前缀必须清零。
# 规则集的 testingcf（gh/DustinWin、gh/MetaCubeX）是第三方仓库、实测 200，不在此限制内。
_bad_tc=$(cd "$ROOT" && rg -n 'testingcf\.jsdelivr\.net/gh/Siu-Leung' --glob '!*.tar.gz' . 2>/dev/null || true)
if [ -z "$_bad_tc" ]; then ok '无失效的 testingcf fork 源'; else bad "仍有失效 testingcf 源：\n$_bad_tc"; fi
for f in install.sh install_en.sh scripts/libs/web_get_bin.sh scripts/libs/web_get.sh; do
    if rg -q 'cdn\.jsdelivr\.net/gh/Siu-Leung/ShellCrash|raw\.githubusercontent\.com/Siu-Leung/ShellCrash' "$ROOT/$f" 2>/dev/null; then
        ok "$(basename "$f") 使用已验证可用源"
    else bad "$f 缺少可用 CDN/raw 源"; fi
done

echo ''
if [ "$FAIL" -eq 0 ]; then echo '\033[32m全部通过\033[0m'; else echo "\033[31m失败 $FAIL 项\033[0m"; exit 1; fi
