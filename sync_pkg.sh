#!/bin/sh
# 把源码 scripts/ public/ version 的全部改动同步进预打包 ShellCrash.tar.gz
# 包内是扁平化结构：scripts/libs/x.sh -> libs/x.sh, scripts/lang/... -> lang/..., public/servers*.list -> servers*.list
# 零信任基线统一：全量同步 scripts/（排除 README.md）与 public/servers*.list、version，
# 彻底消除历史预打包基线与源码树之间的滞后差异。
set -e
cd "$(dirname "$0")"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
tar -xzf ShellCrash.tar.gz -C "$STAGE"

# 全量同步 scripts/ 下的脚本与语言文件（保留目录层级，跳过文档 README.md）
(
    cd scripts
    find . -type f ! -name 'README.md' | while IFS= read -r rel; do
        rel=${rel#./}
        mkdir -p "$STAGE/$(dirname "$rel")"
        cp -p "$rel" "$STAGE/$rel"
    done
)

# 同步 public/ 下的源列表与根目录版本号
cp -p public/servers.list      "$STAGE/servers.list"
cp -p public/servers_chs.list  "$STAGE/servers_chs.list"
cp -p public/servers_en.list   "$STAGE/servers_en.list"
[ -f version ] && cp -p version "$STAGE/version"

# 重新打包（保持与原包一致的相对路径条目，无 ./ 前缀、无隐藏文件丢失）
( cd "$STAGE" && find . -mindepth 1 | sed 's#^\./##' | sort | tar --no-recursion -czf "$OLDPWD/ShellCrash.tar.gz" -T - )
echo "ShellCrash.tar.gz rebuilt:"
tar -tzf ShellCrash.tar.gz | wc -l
