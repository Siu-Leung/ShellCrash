#!/bin/sh
# 从源码干净重建预打包 ShellCrash.tar.gz（不保留旧包里的过期脚本与 README.md）
# 包内是扁平化结构：
#   scripts/... -> 根目录对应路径（排除 README.md）
#   public/*.list -> 根目录 *.list
#   rules/*_providers/*_providers.list -> 根目录 *_providers.list
#   cn_ip.txt / cn_ipv6.txt -> 优先取本地 bin/geodata/，否则沿用旧包内置基线
#   version -> 根目录 version
set -e
cd "$(dirname "$0")"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

# 仅保留旧包内置的 cn_ip.txt / cn_ipv6.txt（若本地无 bin/geodata/ 源文件）
if [ -f bin/geodata/china_ip_list.txt ]; then
    cp -p bin/geodata/china_ip_list.txt "$STAGE/cn_ip.txt"
elif [ -f ShellCrash.tar.gz ]; then
    tar -xzf ShellCrash.tar.gz -C "$STAGE" cn_ip.txt 2>/dev/null || true
fi
if [ -f bin/geodata/china_ipv6_list.txt ]; then
    cp -p bin/geodata/china_ipv6_list.txt "$STAGE/cn_ipv6.txt"
elif [ -f ShellCrash.tar.gz ]; then
    tar -xzf ShellCrash.tar.gz -C "$STAGE" cn_ipv6.txt 2>/dev/null || true
fi

# 全量同步 scripts/ 下的脚本与语言文件（保留目录层级，跳过文档 README.md）
(
    cd scripts
    find . -type f ! -name 'README.md' | while IFS= read -r rel; do
        rel=${rel#./}
        mkdir -p "$STAGE/$(dirname "$rel")"
        cp -p "$rel" "$STAGE/$rel"
    done
)

# 全量同步 public/ 下的全部 .list 配置文件
for f in public/*.list; do
    [ -f "$f" ] && cp -p "$f" "$STAGE/$(basename "$f")"
done

# 同步规则模板清单
[ -f rules/clash_providers/clash_providers.list ] && cp -p rules/clash_providers/clash_providers.list "$STAGE/clash_providers.list"
[ -f rules/singbox_providers/singbox_providers.list ] && cp -p rules/singbox_providers/singbox_providers.list "$STAGE/singbox_providers.list"

# 同步根目录版本号
[ -f version ] && cp -p version "$STAGE/version"

# 干净重新打包（无 ./ 前缀，条目排序以保持可复现）
( cd "$STAGE" && find . -mindepth 1 | sed 's#^\./##' | sort | tar --no-recursion -czf "$OLDPWD/ShellCrash.tar.gz" -T - )
echo "ShellCrash.tar.gz rebuilt cleanly:"
tar -tzf ShellCrash.tar.gz | wc -l
