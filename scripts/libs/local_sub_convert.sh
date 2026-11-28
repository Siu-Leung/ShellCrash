#!/bin/sh
# local_sub_convert.sh —— 零外泄本地订阅拉取与转换引擎
# 设计目标：
#   1. 订阅链接只直连用户自己配置的原始订阅源，绝不发给任何第三方 subconverter 服务器。
#   2. 本地自动识别并归一化常见订阅格式：
#      - Clash / Mihomo YAML（含 proxies: 字段）
#      - Base64 编码节点订阅（支持标准与 URL-safe Base64，自动补齐 padding）
#      - 明文分享链接列表（ss/ssr/vmess/vless/trojan/hysteria/hysteria2/hy2/tuic/anytls/wireguard）
#      - Sing-Box JSON 配置
#   3. 将拉取并解码后的订阅落盘到 $CRASHDIR/providers/<tag>.(yaml|txt)，
#      套用本仓库规则模板生成纯本地 provider 配置（Clash type: file / Sing-Box type: local），
#      支持 include / exclude 正则过滤与定时自动更新/热更新。

. "$CRASHDIR"/libs/web_get.sh
. "$CRASHDIR"/libs/web_get_bin.sh
. "$CRASHDIR"/libs/logger.sh
. "$CRASHDIR"/libs/tls_policy.sh

LOCAL_SUB_URI_RE='^(ss|ssr|vmess|vless|trojan|hysteria|hysteria2|hy2|tuic|anytls|shadowtls|wireguard|socks|http)://'

# 校验提供者标签安全（防路径遍历 ../ 与 YAML/JSON 注入）
local_valid_tag() {
    case "$1" in
        '' | *..* | */* | *\\* | *\"* | *\'* | *\`* | *\$* | *:* | *,* | *\[* | *\]* | *\{* | *\}* | *[[:space:]]*) return 1 ;;
    esac
    return 0
}

# 转义双引号与反斜杠，防止过滤正则破坏 YAML/JSON 字符串语法
local_escape_dq() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 字面量替换模板占位符（通过 ENVIRON 传参，彻底避免 awk -v 对反斜杠和 sed 对 /& 的特殊解释）
local_replace_placeholder() {
    _file=$1
    _needle=$2
    _repl=$3
    _LSC_N="$_needle" _LSC_R="$_repl" awk '
        BEGIN { n = ENVIRON["_LSC_N"]; r = ENVIRON["_LSC_R"]; nlen = length(n) }
        {
            out = ""
            line = $0
            while ((idx = index(line, n)) > 0) {
                out = out substr(line, 1, idx - 1) r
                line = substr(line, idx + nlen)
            }
            print out line
        }
    ' "$_file" >"${_file}.tmp.$$" && mv -f "${_file}.tmp.$$" "$_file"
}

# 同步 $CRASHDIR/providers 到 $BINDIR/providers（兼容小闪存/分离目录模式）
local_sync_bindir_providers() {
    [ -n "$BINDIR" ] && [ "$CRASHDIR" != "$BINDIR" ] || return 0
    mkdir -p "$BINDIR/providers"
    for _pf in "$CRASHDIR"/providers/*; do
        [ -f "$_pf" ] && ln -sf "$_pf" "$BINDIR/providers/"
    done
}

# 本地 Base64 流式解码（兼容大订阅避免 ARG_MAX，支持 URL-safe 与自动补齐 padding）
local_b64_decode() {
    _in_file=$1
    _out_file=$2
    _b64_tmp="${_out_file}.b64.$$"
    [ -f "$_in_file" ] && [ -r "$_in_file" ] || return 1
    tr -d '\r\n\t ' <"$_in_file" >"${_b64_tmp}.raw" || { rm -f "${_b64_tmp}.raw"; return 1; }
    tr '_-' '/+' <"${_b64_tmp}.raw" >"$_b64_tmp" || { rm -f "$_b64_tmp" "${_b64_tmp}.raw"; return 1; }
    rm -f "${_b64_tmp}.raw"
    [ -s "$_b64_tmp" ] || { rm -f "$_b64_tmp"; return 1; }
    # 包括 NUL 在内逐字节检查；不强制末尾未使用位为零，以兼容常见解码器。
    _bad=$(LC_ALL=C tr -d 'A-Za-z0-9+/=' <"$_b64_tmp" | wc -c)
    _pad=$(LC_ALL=C tr -cd '=' <"$_b64_tmp" | wc -c)
    _len=$(wc -c <"$_b64_tmp")
    _rem=$(( _len % 4 ))
    if [ "$_bad" -ne 0 ] || [ "$_pad" -gt 2 ] ||
       { [ "$_pad" -gt 0 ] && LC_ALL=C grep -q '=[^=]' "$_b64_tmp"; } ||
       { [ "$_pad" -gt 0 ] && [ "$_rem" -ne 0 ] && ! { [ "$_pad" -eq 1 ] && [ "$_rem" -eq 3 ]; }; }; then
        rm -f "$_b64_tmp"
        return 1
    fi
    case "$_rem" in
        2) printf '==' >>"$_b64_tmp" || { rm -f "$_b64_tmp"; return 1; } ;;
        # 也兼容原实现支持的单个缺失填充，如 TQ=。
        3) printf '=' >>"$_b64_tmp" || { rm -f "$_b64_tmp"; return 1; } ;;
        1) rm -f "$_b64_tmp"; return 1 ;;
    esac
    if command -v base64 >/dev/null 2>&1; then
        base64 -d <"$_b64_tmp" >"$_out_file" 2>/dev/null
        _rc=$?
    elif busybox base64 --help >/dev/null 2>&1; then
        busybox base64 -d <"$_b64_tmp" >"$_out_file" 2>/dev/null
        _rc=$?
    elif command -v openssl >/dev/null 2>&1; then
        openssl base64 -d -A <"$_b64_tmp" >"$_out_file" 2>/dev/null
        _rc=$?
    elif command -v ucode >/dev/null 2>&1 && ucode -e 'import * as fs from "fs"; if (type(fs.readfile) != "function" || type(fs.writefile) != "function") exit(1);' >/dev/null 2>&1; then
        # 只有模块实际可用才选 ucode；输出失败必须向调用方传递。
        ucode -e 'import * as fs from "fs"; let s = fs.readfile(ARGV[0]); if (s === null) exit(1); let d = b64dec(s); if (d === null || fs.writefile(ARGV[1], d) !== length(d)) exit(1);' -- "$_b64_tmp" "$_out_file" 2>/dev/null
        _rc=$?
    else
        # 兜底：先按 76 字节切行避免 BusyBox awk 超长单行 O(N^2)，再用 LC_ALL=C 原样输出字节
        sed 's/.\{76\}/&\
/g' "$_b64_tmp" | LC_ALL=C awk '
            BEGIN { for (i = 0; i < 64; i++) t[substr("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/", i + 1, 1)] = i }
            NF {
                s = $0; n = length(s)
                for (i = 1; i <= n; i += 4) {
                    a = t[substr(s, i, 1)]; b = t[substr(s, i + 1, 1)]
                    c1 = substr(s, i + 2, 1); c2 = substr(s, i + 3, 1)
                    c = t[c1]; d = t[c2]
                    printf "%c", a * 4 + int(b / 16)
                    if (c1 != "=" && c1 != "") printf "%c", (b % 16) * 16 + int(c / 4)
                    if (c2 != "=" && c2 != "") printf "%c", (c % 4) * 64 + d
                }
            }
        ' >"$_out_file" 2>/dev/null
        _rc=$?
    fi
    rm -f "$_b64_tmp"
    return "$_rc"
}

# 对 URI 列表按节点名称（# 后片段或整行）执行 include / exclude 正则过滤
local_filter_uri_file() {
    _src=$1
    _dst=$2
    _inc=$3
    _exc=$4
    _LSC_INC="$_inc" _LSC_EXC="$_exc" awk '
        BEGIN { inc = ENVIRON["_LSC_INC"]; exc = ENVIRON["_LSC_EXC"] }
        {
            sub(/\r$/, "")
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            if ($0 == "" || $0 ~ /^#/) next
            if (inc != "" && $0 !~ inc) next
            if (exc != "" && $0 ~ exc) next
            print $0
        }
    ' "$_src" >"$_dst"
}

# 去除 UTF-8 BOM (EF BB BF) 和回车 CR，兼容 Windows/机场导出的订阅
local_strip_bom_cr() {
    awk 'NR==1 { sub(/^\357\273\277/, "") } { sub(/\r$/, ""); print }' "$1" >"$2"
}

# 检测并归一化单个订阅文件：
# 参数：$1=原始文件 $2=输出目标前缀(不含扩展名) $3=include正则 $4=exclude正则
# 输出全局变量：LOCAL_SUB_FMT (yaml|uri|json) 与 LOCAL_SUB_OUT (最终本地文件路径)
local_normalize_sub_file() {
    _raw=$1
    _prefix=$2
    _inc=$3
    _exc=$4
    LOCAL_SUB_FMT=""
    LOCAL_SUB_OUT=""

    [ -s "$_raw" ] || return 1
    local_strip_bom_cr "$_raw" "${_raw}.norm"

    # 1. 判断是否为 Clash/Mihomo YAML（含 proxies: 或 proxy-providers:）
    if grep -Eq '^[[:space:]]*(proxies|proxy-providers):' "${_raw}.norm"; then
        LOCAL_SUB_FMT="yaml"
        LOCAL_SUB_OUT="${_prefix}.yaml"
        mv -f "${_raw}.norm" "$LOCAL_SUB_OUT"
        return 0
    fi

    # 2. 判断是否为明文分享链接列表
    if grep -Eq "$LOCAL_SUB_URI_RE" "${_raw}.norm"; then
        LOCAL_SUB_FMT="uri"
        LOCAL_SUB_OUT="${_prefix}.txt"
        local_filter_uri_file "${_raw}.norm" "$LOCAL_SUB_OUT" "$_inc" "$_exc"
        rm -f "${_raw}.norm"
        [ -s "$LOCAL_SUB_OUT" ] && return 0
        return 1
    fi

    # 3. 判断是否为 Sing-Box JSON
    if grep -Eq '"outbounds"[[:space:]]*:' "${_raw}.norm"; then
        LOCAL_SUB_FMT="json"
        LOCAL_SUB_OUT="${_prefix}.json"
        mv -f "${_raw}.norm" "$LOCAL_SUB_OUT"
        return 0
    fi

    # 4. 尝试 Base64 解码（标准机场通用订阅格式）
    if local_b64_decode "${_raw}.norm" "${_raw}.dec"; then
        local_strip_bom_cr "${_raw}.dec" "${_raw}.dec.norm"
        if grep -Eq "$LOCAL_SUB_URI_RE" "${_raw}.dec.norm"; then
            LOCAL_SUB_FMT="uri"
            LOCAL_SUB_OUT="${_prefix}.txt"
            local_filter_uri_file "${_raw}.dec.norm" "$LOCAL_SUB_OUT" "$_inc" "$_exc"
            rm -f "${_raw}.norm" "${_raw}.dec" "${_raw}.dec.norm"
            [ -s "$LOCAL_SUB_OUT" ] && return 0
            return 1
        elif grep -Eq '^[[:space:]]*(proxies|proxy-providers):' "${_raw}.dec.norm"; then
            LOCAL_SUB_FMT="yaml"
            LOCAL_SUB_OUT="${_prefix}.yaml"
            mv -f "${_raw}.dec.norm" "$LOCAL_SUB_OUT"
            rm -f "${_raw}.norm" "${_raw}.dec"
            return 0
        elif grep -Eq '"outbounds"[[:space:]]*:' "${_raw}.dec.norm"; then
            LOCAL_SUB_FMT="json"
            LOCAL_SUB_OUT="${_prefix}.json"
            mv -f "${_raw}.dec.norm" "$LOCAL_SUB_OUT"
            rm -f "${_raw}.norm" "${_raw}.dec"
            return 0
        fi
        rm -f "${_raw}.dec" "${_raw}.dec.norm"
    fi

    rm -f "${_raw}.norm"
    return 1
}

# 将单个订阅拉取并归一化到本地 $CRASHDIR/providers/
# 参数：$1=tag $2=url_or_local_path $3=ua $4=include $5=exclude
# 输出全局变量：LOCAL_SUB_REL_PATH (如 ./providers/tag.yaml)
local_fetch_one_provider() {
    _tag=$1
    _src=$2
    _ua=${3:-clash.meta}
    _inc=$4
    _exc=$5
    LOCAL_SUB_REL_PATH=""

    if ! local_valid_tag "$_tag"; then
        logger "非法提供者名称已拒绝：$_tag" 31
        return 1
    fi

    _out_dir="${LOCAL_SUB_STAGE_DIR:-$CRASHDIR/providers}"
    mkdir -p "$_out_dir" "$TMPDIR/local_sub"
    _stage_raw="$TMPDIR/local_sub/${_tag}.raw"
    _dest_prefix="${_out_dir}/${_tag}"

    case "$_src" in
        ./providers/*)
            case "$_src" in *..* ) return 1 ;; esac
            _local_src="$CRASHDIR/${_src#./}"
            [ -s "$_local_src" ] || return 1
            cp -f "$_local_src" "$_stage_raw"
            ;;
        http://* | https://*)
            _ua_arg="$_ua"
            [ "$_ua_arg" = "none" ] && _ua_arg=""
            [ "$_ua_arg" = "auto" ] && _ua_arg="clash.meta/mihomo"
            # 订阅拉取按 sub_tls 策略（默认 auto：先校验，证书不对自动跳过重试并记日志）
            if ! sub_webget "$_stage_raw" "$_src" echoon rediron "$_ua_arg"; then
                rm -f "$_stage_raw"
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac

    if local_normalize_sub_file "$_stage_raw" "$_dest_prefix" "$_inc" "$_exc"; then
        rm -f "$_stage_raw"
        LOCAL_SUB_REL_PATH="./providers/${LOCAL_SUB_OUT##*/}"
        return 0
    fi
    rm -f "$_stage_raw"
    return 1
}

# 将暂存目录中的已校验 provider 原子提交到 $CRASHDIR/providers 并同步 $BINDIR/providers
local_commit_staged_providers() {
    [ -d "$LOCAL_SUB_STAGE_DIR" ] || return 0
    mkdir -p "$CRASHDIR/providers"
    for _sf in "$LOCAL_SUB_STAGE_DIR"/*; do
        [ -f "$_sf" ] && mv -f "$_sf" "$CRASHDIR/providers/${_sf##*/}"
    done
    local_sync_bindir_providers
}

# 单个源临时拉取失败时，如本地已有上次有效缓存则保留并告警，避免静默丢节点
local_fallback_cached_provider() {
    _fb_tag=$1
    LOCAL_SUB_REL_PATH=""
    for _ext in yaml txt json; do
        if [ -s "$CRASHDIR/providers/${_fb_tag}.${_ext}" ]; then
            cp -f "$CRASHDIR/providers/${_fb_tag}.${_ext}" "$LOCAL_SUB_STAGE_DIR/${_fb_tag}.${_ext}"
            LOCAL_SUB_REL_PATH="./providers/${_fb_tag}.${_ext}"
            return 0
        fi
    done
    return 1
}

# 生成纯本地 Clash/Mihomo 配置文件（所有 provider 均为 type: file，不向外发任何订阅请求）
# 参数：可选单条 provider 参数 ($1=name $2=link $3=interval $4=interval2 $5=ua $6=#exclude $7=#include)
# 若无参数则拉取 providers.cfg + providers_uri.cfg 中的全部订阅
local_build_clash_config() {
    if [ -z "$(grep 'provider_temp_clash' "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null)" ]; then
        _tpl_file=$(sed -n '1p' "$CRASHDIR"/configs/clash_providers.list 2>/dev/null | awk '{print $2}')
    else
        _tpl_file=$(grep 'provider_temp_clash' "$CRASHDIR"/configs/ShellCrash.cfg | tail -n 1 | cut -d= -f2- | tr -d "'\"")
    fi
    [ -z "$_tpl_file" ] && _tpl_file="ShellCrash_RS_Nano.yaml"

    mkdir -p "$TMPDIR/providers"
    if [ -s "$_tpl_file" ]; then
        cp -f "$_tpl_file" "$TMPDIR/provider_temp_file"
    elif [ -s "$CRASHDIR/rules/clash_providers/$_tpl_file" ]; then
        cp -f "$CRASHDIR/rules/clash_providers/$_tpl_file" "$TMPDIR/provider_temp_file"
    else
        get_bin "$TMPDIR/provider_temp_file" "rules/clash_providers/$_tpl_file"
    fi
    if ! grep -q 'rules' "$TMPDIR/provider_temp_file" 2>/dev/null; then
        logger "本地规则模板获取失败：$_tpl_file" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/provider_temp_file"
        return 1
    fi

    echo 'proxy-providers:' >"$TMPDIR/providers/providers.yaml"
    sed -n '/^proxy-groups:/,/^[a-z]/ { /^rule/d; p; }' "$TMPDIR/provider_temp_file" >"$TMPDIR/providers/proxy-groups.yaml"
    sed -n '/^rule/,$p' "$TMPDIR/provider_temp_file" >"$TMPDIR/providers/rules.yaml"
    rm -f "$TMPDIR/provider_temp_file"

    _tags=""
    _ok_count=0
    # 节点 TLS 按 node_tls 策略：follow=不覆盖（跟随订阅），skip/verify=统一覆盖
    case "$(tls_node_mode)" in
    skip) _skip_line="      skip-cert-verify: true" ;;
    verify) _skip_line="      skip-cert-verify: false" ;;
    *) _skip_line="" ;;
    esac

    _append_clash_file_provider() {
        _ptag=$1
        _ppath=$2
        _pint=$3
        _pexc=$4
        _pinc=$5
        case "$_pint" in
            '' | *[!0-9]*) _pint=3 ;;
            0) _pint=3 ;;
        esac
        _ppath_esc=$(local_escape_dq "$_ppath")
        cat >>"$TMPDIR/providers/providers.yaml" <<EOF
  ${_ptag}:
    type: file
    path: "${_ppath_esc}"
    health-check:
      enable: true
      lazy: true
      url: "https://www.gstatic.com/generate_204"
      interval: $((_pint * 60))
    override:
      udp: true
EOF
        [ -n "$_skip_line" ] && printf '%s\n' "$_skip_line" >>"$TMPDIR/providers/providers.yaml"
        [ -n "$_pinc" ] && printf '    filter: "%s"\n' "$(local_escape_dq "$_pinc")" >>"$TMPDIR/providers/providers.yaml"
        [ -n "$_pexc" ] && printf '    exclude-filter: "%s"\n' "$(local_escape_dq "$_pexc")" >>"$TMPDIR/providers/providers.yaml"
        echo '  - {name: '"$_ptag"', type: url-test, tolerance: 100, lazy: true, use: ['"$_ptag"']}' >>"$TMPDIR/providers/proxy-groups.yaml"
        _tags=$(printf '%s, %s' "$_tags" "$_ptag" | sed 's/^, //')
        _ok_count=$((_ok_count + 1))
    }

    LOCAL_SUB_STAGE_DIR="$TMPDIR/local_sub/stage_providers"
    rm -rf "$LOCAL_SUB_STAGE_DIR"
    mkdir -p "$LOCAL_SUB_STAGE_DIR"

    if [ -n "$1" ]; then
        _t_name=$1
        _t_link=$2
        _t_int=${3:-3}
        _t_ua=${5:-${user_agent:-clash.meta}}
        _t_exc=${6#\#}
        _t_inc=${7#\#}
        [ -z "$_t_exc" ] && _t_exc="$exclude"
        [ -z "$_t_inc" ] && _t_inc="$include"
        if local_fetch_one_provider "$_t_name" "$_t_link" "$_t_ua" "$_t_inc" "$_t_exc"; then
            _append_clash_file_provider "$_t_name" "$LOCAL_SUB_REL_PATH" "$_t_int" "$_t_exc" "$_t_inc"
        else
            logger "本地拉取或解析订阅失败：$_t_name" 31
        fi
    else
        if [ -s "$CRASHDIR/configs/providers.cfg" ]; then
            while read -r _p_name _p_link _p_int _p_int2 _p_ua _p_exc _p_inc || [ -n "$_p_name" ]; do
                [ -z "$_p_name" ] && continue
                case "$_p_name" in \#*) continue ;; esac
                _p_exc=${_p_exc#\#}
                _p_inc=${_p_inc#\#}
                [ -z "$_p_exc" ] && _p_exc="$exclude"
                [ -z "$_p_inc" ] && _p_inc="$include"
                [ -z "$_p_ua" ] && _p_ua="${user_agent:-clash.meta}"
                if local_fetch_one_provider "$_p_name" "$_p_link" "$_p_ua" "$_p_inc" "$_p_exc"; then
                    _append_clash_file_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                elif local_fallback_cached_provider "$_p_name"; then
                    logger "本地拉取订阅失败，已保留上次有效缓存：$_p_name" 33
                    _append_clash_file_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                else
                    logger "本地拉取或解析订阅失败，已跳过：$_p_name" 33
                fi
            done <"$CRASHDIR/configs/providers.cfg"
        fi
        if [ -s "$CRASHDIR/configs/providers_uri.cfg" ]; then
            mkdir -p "$TMPDIR/local_sub"
            awk 'NF>=2 && $1 !~ /^#/ { print ($1=="vmess" || index($2,"#")>0 ? $2 : $2 "#" $1) }' "$CRASHDIR/configs/providers_uri.cfg" >"$TMPDIR/local_sub/uri_group.raw"
            local_filter_uri_file "$TMPDIR/local_sub/uri_group.raw" "$LOCAL_SUB_STAGE_DIR/uri_group" "$include" "$exclude"
            rm -f "$TMPDIR/local_sub/uri_group.raw"
            if [ -s "$LOCAL_SUB_STAGE_DIR/uri_group" ]; then
                _append_clash_file_provider "Uri_group" "./providers/uri_group" "3" "$exclude" "$include"
            fi
        fi
    fi

    if [ "$_ok_count" -eq 0 ]; then
        logger "未能成功拉取或解析任何有效订阅节点！" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
        LOCAL_SUB_STAGE_DIR=""
        return 1
    fi

    local_replace_placeholder "$TMPDIR/providers/proxy-groups.yaml" "{providers_tags}" "$_tags"
    cat "$TMPDIR/providers/providers.yaml" "$TMPDIR/providers/proxy-groups.yaml" "$TMPDIR/providers/rules.yaml" >"$TMPDIR/config.yaml"

    # 若内核存在则基于暂存目录先做完整配置校验，校验失败不覆盖既有 providers 缓存与 config.yaml
    if [ "${LOCAL_SUB_SKIP_CORE_TEST:-0}" != "1" ]; then
        . "$CRASHDIR"/starts/check_core.sh && check_core
        _verify_dir="$TMPDIR/local_sub/verify_dir"
        rm -rf "$_verify_dir"
        mkdir -p "$_verify_dir"
        for _bf in "$BINDIR"/*; do
            [ -e "$_bf" ] || continue
            [ "${_bf##*/}" = "providers" ] && continue
            ln -sf "$_bf" "$_verify_dir/${_bf##*/}" 2>/dev/null || true
        done
        ln -sf "$LOCAL_SUB_STAGE_DIR" "$_verify_dir/providers"
        if ! "$TMPDIR"/CrashCore -t -d "$_verify_dir" -f "$TMPDIR/config.yaml"; then
            logger "本地转换生成的 Clash 配置文件校验失败！已保留原有配置与订阅缓存。" 31
            rm -rf "$TMPDIR/config.yaml" "$TMPDIR/providers" "$TMPDIR/local_sub"
            LOCAL_SUB_STAGE_DIR=""
            return 1
        fi
    fi

    # 校验通过后再原子提交暂存的 providers 缓存与主配置文件
    local_commit_staged_providers
    mkdir -p "$CRASHDIR/yamls"
    [ -s "$CRASHDIR/yamls/config.yaml" ] && cp -f "$CRASHDIR/yamls/config.yaml" "$CRASHDIR/yamls/config.yaml.bak"
    mv -f "$TMPDIR/config.yaml" "$CRASHDIR/yamls/config.yaml"
    rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
    LOCAL_SUB_STAGE_DIR=""
    return 0
}

# 生成纯本地 Sing-BoxR 配置文件（所有 provider 均为 type: local）
local_build_singbox_config() {
    # 普通官方 sing-box 不支持 Sing-BoxR 的 providers / use_all_providers 扩展，提前给出明确提示
    if [ "$crashcore" = "singbox" ]; then
        logger "标准版 Sing-Box 不支持本地 provider 规则模板合成，请切换为 Sing-BoxR 或 Mihomo，或直接导入原生 Sing-Box JSON！" 31
        return 1
    fi
    if [ -z "$(grep 'provider_temp_singbox' "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null)" ]; then
        _tpl_file=$(sed -n '1p' "$CRASHDIR"/configs/singbox_providers.list 2>/dev/null | awk '{print $2}')
    else
        _tpl_file=$(grep 'provider_temp_singbox' "$CRASHDIR"/configs/ShellCrash.cfg | tail -n 1 | cut -d= -f2- | tr -d "'\"")
    fi
    [ -z "$_tpl_file" ] && _tpl_file="ShellCrash_RS_Nano.json"

    mkdir -p "$TMPDIR/providers"
    if [ -s "$_tpl_file" ]; then
        cp -f "$_tpl_file" "$TMPDIR/provider_temp_file"
    elif [ -s "$CRASHDIR/rules/singbox_providers/$_tpl_file" ]; then
        cp -f "$CRASHDIR/rules/singbox_providers/$_tpl_file" "$TMPDIR/provider_temp_file"
    else
        get_bin "$TMPDIR/provider_temp_file" "rules/singbox_providers/$_tpl_file"
    fi
    if ! grep -q 'route' "$TMPDIR/provider_temp_file" 2>/dev/null; then
        logger "本地规则模板获取失败：$_tpl_file" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/provider_temp_file"
        return 1
    fi

    cat >"$TMPDIR/providers/providers.json" <<'EOF'
{
  "providers": [
EOF
    cat >"$TMPDIR/providers/outbounds_add.json" <<'EOF'
{
  "outbounds": [
EOF

    _tags=""
    _ok_count=0
    # 节点 TLS 按 node_tls 策略：follow=不写 override_tls（跟随订阅），skip/verify=统一覆盖 insecure
    case "$(tls_node_mode)" in
    skip) _override_tls='true' ;;
    verify) _override_tls='false' ;;
    *) _override_tls='' ;;
    esac
    if [ -n "$_override_tls" ]; then
        _sb_tls_block=',
      "override_tls": {
        "enabled": true,
        "insecure": '"$_override_tls"'
      }'
    else
        _sb_tls_block=''
    fi

    _append_sb_local_provider() {
        _ptag=$1
        _ppath=$2
        _pint=$3
        _pexc=$4
        _pinc=$5
        case "$_pint" in
            '' | *[!0-9]*) _pint=3 ;;
            0) _pint=3 ;;
        esac
        _ptag_esc=$(local_escape_dq "$_ptag")
        _ppath_esc=$(local_escape_dq "$_ppath")
        # 修正：Sing-BoxR type:local provider 不支持 providers[].include/exclude 字段，
        # 节点正则筛选应放在 urltest 出站组对象上（与内置 Sing-BoxR 模板一致）。
        cat >>"$TMPDIR/providers/providers.json" <<EOF
    {
      "tag": "$_ptag_esc",
      "type": "local",
      "path": "$_ppath_esc",
      "health_check": {
        "enabled": true,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "${_pint}m",
        "timeout": "3s"
      },
      "override_dialer": {
        "domain_resolver": "dns_proxy_server"
      }${_sb_tls_block}
    },
EOF
        _ob_inc='.*'
        [ -n "$_pinc" ] && _ob_inc=$(local_escape_dq "$_pinc")
        _ob_exc=''
        [ -n "$_pexc" ] && _ob_exc=', "exclude": "'"$(local_escape_dq "$_pexc")"'"'
        echo '{ "tag": "'"$_ptag_esc"'", "type": "urltest", "tolerance": 100, "providers": ["'"$_ptag_esc"'"], "include": "'"$_ob_inc"'"'"$_ob_exc"' },' >>"$TMPDIR/providers/outbounds_add.json"
        _tags=$(printf '%s, "%s"' "$_tags" "$_ptag_esc" | sed 's/^, //')
        _ok_count=$((_ok_count + 1))
    }

    LOCAL_SUB_STAGE_DIR="$TMPDIR/local_sub/stage_providers"
    rm -rf "$LOCAL_SUB_STAGE_DIR"
    mkdir -p "$LOCAL_SUB_STAGE_DIR"

    if [ -n "$1" ]; then
        _t_name=$1
        _t_link=$2
        _t_int=${3:-3}
        _t_ua=${5:-${user_agent:-clash.meta}}
        _t_exc=${6#\#}
        _t_inc=${7#\#}
        [ -z "$_t_exc" ] && _t_exc="$exclude"
        [ -z "$_t_inc" ] && _t_inc="$include"
        if local_fetch_one_provider "$_t_name" "$_t_link" "$_t_ua" "$_t_inc" "$_t_exc"; then
            _append_sb_local_provider "$_t_name" "$LOCAL_SUB_REL_PATH" "$_t_int" "$_t_exc" "$_t_inc"
        else
            logger "本地拉取或解析订阅失败：$_t_name" 31
        fi
    else
        if [ -s "$CRASHDIR/configs/providers.cfg" ]; then
            while read -r _p_name _p_link _p_int _p_int2 _p_ua _p_exc _p_inc || [ -n "$_p_name" ]; do
                [ -z "$_p_name" ] && continue
                case "$_p_name" in \#*) continue ;; esac
                _p_exc=${_p_exc#\#}
                _p_inc=${_p_inc#\#}
                [ -z "$_p_exc" ] && _p_exc="$exclude"
                [ -z "$_p_inc" ] && _p_inc="$include"
                [ -z "$_p_ua" ] && _p_ua="${user_agent:-clash.meta}"
                if local_fetch_one_provider "$_p_name" "$_p_link" "$_p_ua" "$_p_inc" "$_p_exc"; then
                    _append_sb_local_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                elif local_fallback_cached_provider "$_p_name"; then
                    logger "本地拉取订阅失败，已保留上次有效缓存：$_p_name" 33
                    _append_sb_local_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                else
                    logger "本地拉取或解析订阅失败，已跳过：$_p_name" 33
                fi
            done <"$CRASHDIR/configs/providers.cfg"
        fi
        if [ -s "$CRASHDIR/configs/providers_uri.cfg" ]; then
            mkdir -p "$TMPDIR/local_sub"
            awk 'NF>=2 && $1 !~ /^#/ { print ($1=="vmess" || index($2,"#")>0 ? $2 : $2 "#" $1) }' "$CRASHDIR/configs/providers_uri.cfg" >"$TMPDIR/local_sub/uri_group.raw"
            local_filter_uri_file "$TMPDIR/local_sub/uri_group.raw" "$LOCAL_SUB_STAGE_DIR/uri_group" "$include" "$exclude"
            rm -f "$TMPDIR/local_sub/uri_group.raw"
            if [ -s "$LOCAL_SUB_STAGE_DIR/uri_group" ]; then
                _append_sb_local_provider "Uri_group" "./providers/uri_group" "3" "$exclude" "$include"
            fi
        fi
    fi

    if [ "$_ok_count" -eq 0 ]; then
        logger "未能成功拉取或解析任何有效订阅节点！" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
        LOCAL_SUB_STAGE_DIR=""
        return 1
    fi

    sed -i '$s/},/}]}/' "$TMPDIR/providers/outbounds_add.json"
    sed -i '$s/},/}]}/' "$TMPDIR/providers/providers.json"
    cp -f "$TMPDIR/provider_temp_file" "$TMPDIR/providers/outbounds.json"
    local_replace_placeholder "$TMPDIR/providers/outbounds.json" "{providers_tags}" "$_tags"
    local_replace_placeholder "$TMPDIR/providers/outbounds.json" "\"providers_tags\"" "$_tags"
    rm -f "$TMPDIR/provider_temp_file"

    if [ "${LOCAL_SUB_SKIP_CORE_TEST:-0}" != "1" ]; then
        . "$CRASHDIR"/starts/check_core.sh && check_core
        _verify_dir="$TMPDIR/local_sub/verify_dir"
        rm -rf "$_verify_dir"
        mkdir -p "$_verify_dir"
        for _bf in "$BINDIR"/*; do
            [ -e "$_bf" ] || continue
            [ "${_bf##*/}" = "providers" ] && continue
            ln -sf "$_bf" "$_verify_dir/${_bf##*/}" 2>/dev/null || true
        done
        ln -sf "$LOCAL_SUB_STAGE_DIR" "$_verify_dir/providers"
        if ! "$TMPDIR"/CrashCore merge "$TMPDIR/config.json" -C "$TMPDIR/providers" || \
           ! "$TMPDIR"/CrashCore check -D "$_verify_dir" -c "$TMPDIR/config.json"; then
            logger "本地转换生成的 Sing-Box 配置文件合并或校验失败！已保留原有配置与订阅缓存。" 31
            rm -rf "$TMPDIR/config.json" "$TMPDIR/providers" "$TMPDIR/local_sub"
            LOCAL_SUB_STAGE_DIR=""
            return 1
        fi
        local_commit_staged_providers
        mkdir -p "$CRASHDIR/jsons"
        [ -s "$CRASHDIR/jsons/config.json" ] && cp -f "$CRASHDIR/jsons/config.json" "$CRASHDIR/jsons/config.json.bak"
        mv -f "$TMPDIR/config.json" "$CRASHDIR/jsons/config.json"
    else
        local_commit_staged_providers
    fi

    rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
    LOCAL_SUB_STAGE_DIR=""
    return 0
}

# 统一入口：根据当前内核自动选择 Clash/Mihomo 或 Sing-BoxR 本地拉取与转换
local_sub_convert() {
    if echo "$crashcore" | grep -q 'singbox'; then
        local_build_singbox_config "$@"
    else
        local_build_clash_config "$@"
    fi
}
