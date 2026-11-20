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

LOCAL_SUB_URI_RE='^(ss|ssr|vmess|vless|trojan|hysteria|hysteria2|hy2|tuic|anytls|shadowtls|wireguard|socks|http)://'

# 转义双引号与反斜杠，防止过滤正则破坏 YAML/JSON 字符串语法
local_escape_dq() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 字面量替换模板占位符（避免 sed 对 / 和 & 的特殊解释）
local_replace_placeholder() {
    _file=$1
    _needle=$2
    _repl=$3
    awk -v n="$_needle" -v r="$_repl" '
        {
            out = ""
            line = $0
            while ((idx = index(line, n)) > 0) {
                out = out substr(line, 1, idx - 1) r
                line = substr(line, idx + length(n))
            }
            print out line
        }
    ' "$_file" >"${_file}.tmp.$$" && mv -f "${_file}.tmp.$$" "$_file"
}

# 本地 Base64 解码（兼容 BusyBox / GNU base64 / openssl，自动处理 URL-safe 与缺失 padding）
local_b64_decode() {
    _in_file=$1
    _out_file=$2
    _clean=$(tr -d '\r\n\t ' <"$_in_file" | tr '_-' '/+')
    [ -n "$_clean" ] || return 1
    # 校验是否为合法 Base64 字符集
    printf '%s' "$_clean" | grep -Eq '^[A-Za-z0-9+/]+={0,2}$' || return 1
    _rem=$(( ${#_clean} % 4 ))
    case "$_rem" in
        2) _clean="${_clean}==" ;;
        3) _clean="${_clean}=" ;;
        1) return 1 ;;
    esac
    if command -v base64 >/dev/null 2>&1; then
        printf '%s' "$_clean" | base64 -d >"$_out_file" 2>/dev/null
    elif command -v openssl >/dev/null 2>&1; then
        printf '%s' "$_clean" | openssl base64 -d -A >"$_out_file" 2>/dev/null
    else
        return 1
    fi
}

# 对 URI 列表按节点名称（# 后片段或整行）执行 include / exclude 正则过滤
local_filter_uri_file() {
    _src=$1
    _dst=$2
    _inc=$3
    _exc=$4
    awk -v inc="$_inc" -v exc="$_exc" '
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
    tr -d '\r' <"$_raw" >"${_raw}.norm"

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
        tr -d '\r' <"${_raw}.dec" >"${_raw}.dec.norm"
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

    mkdir -p "$CRASHDIR/providers" "$TMPDIR/local_sub"
    _stage_raw="$TMPDIR/local_sub/${_tag}.raw"
    _dest_prefix="$CRASHDIR/providers/${_tag}"

    case "$_src" in
        ./providers/*)
            _local_src="$CRASHDIR/${_src#./}"
            [ -s "$_local_src" ] || return 1
            cp -f "$_local_src" "$_stage_raw"
            ;;
        http://* | https://*)
            _ua_arg="$_ua"
            [ "$_ua_arg" = "none" ] && _ua_arg=""
            [ "$_ua_arg" = "auto" ] && _ua_arg="clash.meta/mihomo"
            if ! webget "$_stage_raw" "$_src" echoon rediron skipceron "$_ua_arg"; then
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

# 生成纯本地 Clash/Mihomo 配置文件（所有 provider 均为 type: file，不向外发任何订阅请求）
# 参数：可选单条 provider 参数 ($1=name $2=link $3=interval $4=interval2 $5=ua $6=#exclude $7=#include)
# 若无参数则拉取 providers.cfg + providers_uri.cfg 中的全部订阅
local_build_clash_config() {
    if [ -z "$(grep 'provider_temp_clash' "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null)" ]; then
        _tpl_file=$(sed -n '1p' "$CRASHDIR"/configs/clash_providers.list 2>/dev/null | awk '{print $2}')
    else
        _tpl_file=$(grep 'provider_temp_clash' "$CRASHDIR"/configs/ShellCrash.cfg | awk -F '=' '{print $2}')
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
    [ "$skip_cert" != "OFF" ] && _skip_line="      skip-cert-verify: true" || _skip_line="      skip-cert-verify: false"

    _append_clash_file_provider() {
        _ptag=$1
        _ppath=$2
        _pint=${3:-3}
        _pexc=$4
        _pinc=$5
        cat >>"$TMPDIR/providers/providers.yaml" <<EOF
  ${_ptag}:
    type: file
    path: "${_ppath}"
    health-check:
      enable: true
      lazy: true
      url: "https://www.gstatic.com/generate_204"
      interval: $((_pint * 60))
    override:
      udp: true
${_skip_line}
EOF
        [ -n "$_pinc" ] && printf '    filter: "%s"\n' "$(local_escape_dq "$_pinc")" >>"$TMPDIR/providers/providers.yaml"
        [ -n "$_pexc" ] && printf '    exclude-filter: "%s"\n' "$(local_escape_dq "$_pexc")" >>"$TMPDIR/providers/providers.yaml"
        echo '  - {name: '"$_ptag"', type: url-test, tolerance: 100, lazy: true, use: ['"$_ptag"']}' >>"$TMPDIR/providers/proxy-groups.yaml"
        _tags=$(printf '%s, %s' "$_tags" "$_ptag" | sed 's/^, //')
        _ok_count=$((_ok_count + 1))
    }

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
            while read -r _p_name _p_link _p_int _p_int2 _p_ua _p_exc _p_inc; do
                [ -z "$_p_name" ] && continue
                case "$_p_name" in \#*) continue ;; esac
                _p_exc=${_p_exc#\#}
                _p_inc=${_p_inc#\#}
                [ -z "$_p_exc" ] && _p_exc="$exclude"
                [ -z "$_p_inc" ] && _p_inc="$include"
                [ -z "$_p_ua" ] && _p_ua="${user_agent:-clash.meta}"
                if local_fetch_one_provider "$_p_name" "$_p_link" "$_p_ua" "$_p_inc" "$_p_exc"; then
                    _append_clash_file_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                else
                    logger "本地拉取或解析订阅失败，已跳过：$_p_name" 33
                fi
            done <"$CRASHDIR/configs/providers.cfg"
        fi
        if [ -s "$CRASHDIR/configs/providers_uri.cfg" ]; then
            mkdir -p "$CRASHDIR/providers"
            awk '{ print ($1=="vmess" ? $2 : $2 "#" $1) }' "$CRASHDIR/configs/providers_uri.cfg" >"$TMPDIR/local_sub/uri_group.raw"
            local_filter_uri_file "$TMPDIR/local_sub/uri_group.raw" "$CRASHDIR/providers/uri_group" "$include" "$exclude"
            rm -f "$TMPDIR/local_sub/uri_group.raw"
            if [ -s "$CRASHDIR/providers/uri_group" ]; then
                _append_clash_file_provider "Uri_group" "./providers/uri_group" "3" "$exclude" "$include"
            fi
        fi
    fi

    if [ "$_ok_count" -eq 0 ]; then
        logger "未能成功拉取或解析任何有效订阅节点！" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
        return 1
    fi

    local_replace_placeholder "$TMPDIR/providers/proxy-groups.yaml" "{providers_tags}" "$_tags"
    cat "$TMPDIR/providers/providers.yaml" "$TMPDIR/providers/proxy-groups.yaml" "$TMPDIR/providers/rules.yaml" >"$TMPDIR/config.yaml"
    rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"

    # 若内核存在则校验生成的配置；离线/无内核测试环境允许跳过
    if [ "${LOCAL_SUB_SKIP_CORE_TEST:-0}" != "1" ]; then
        . "$CRASHDIR"/starts/check_core.sh && check_core
        if ! "$TMPDIR"/CrashCore -t -d "$BINDIR" -f "$TMPDIR/config.yaml"; then
            logger "本地转换生成的 Clash 配置文件校验失败！" 31
            rm -f "$TMPDIR/config.yaml"
            return 1
        fi
    fi

    mkdir -p "$CRASHDIR/yamls"
    [ -s "$CRASHDIR/yamls/config.yaml" ] && cp -f "$CRASHDIR/yamls/config.yaml" "$CRASHDIR/yamls/config.yaml.bak"
    mv -f "$TMPDIR/config.yaml" "$CRASHDIR/yamls/config.yaml"
    return 0
}

# 生成纯本地 Sing-BoxR 配置文件（所有 provider 均为 type: local）
local_build_singbox_config() {
    if [ -z "$(grep 'provider_temp_singbox' "$CRASHDIR"/configs/ShellCrash.cfg 2>/dev/null)" ]; then
        _tpl_file=$(sed -n '1p' "$CRASHDIR"/configs/singbox_providers.list 2>/dev/null | awk '{print $2}')
    else
        _tpl_file=$(grep 'provider_temp_singbox' "$CRASHDIR"/configs/ShellCrash.cfg | awk -F '=' '{print $2}')
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
    [ "$skip_cert" != "OFF" ] && _override_tls='true' || _override_tls='false'

    _append_sb_local_provider() {
        _ptag=$1
        _ppath=$2
        _pint=${3:-3}
        _pexc=$4
        _pinc=$5
        _exc_line=""
        _inc_line=""
        [ -n "$_pexc" ] && _exc_line="      \"exclude\": \"$(local_escape_dq "$_pexc")\","
        [ -n "$_pinc" ] && _inc_line="      \"include\": \"$(local_escape_dq "$_pinc")\","
        cat >>"$TMPDIR/providers/providers.json" <<EOF
    {
      "tag": "$_ptag",
      "type": "local",
      "path": "$_ppath",
${_exc_line}
${_inc_line}
      "health_check": {
        "enabled": true,
        "url": "https://www.gstatic.com/generate_204",
        "interval": "${_pint}m",
        "timeout": "3s"
      },
      "override_dialer": {
        "domain_resolver": "dns_proxy_server"
      },
      "override_tls": {
        "enabled": true,
        "insecure": $_override_tls
      }
    },
EOF
        echo '{ "tag": "'"$_ptag"'", "type": "urltest", "tolerance": 100, "providers": ["'"$_ptag"'"], "include": ".*" },' >>"$TMPDIR/providers/outbounds_add.json"
        _tags=$(printf '%s, "%s"' "$_tags" "$_ptag" | sed 's/^, //')
        _ok_count=$((_ok_count + 1))
    }

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
            while read -r _p_name _p_link _p_int _p_int2 _p_ua _p_exc _p_inc; do
                [ -z "$_p_name" ] && continue
                case "$_p_name" in \#*) continue ;; esac
                _p_exc=${_p_exc#\#}
                _p_inc=${_p_inc#\#}
                [ -z "$_p_exc" ] && _p_exc="$exclude"
                [ -z "$_p_inc" ] && _p_inc="$include"
                [ -z "$_p_ua" ] && _p_ua="${user_agent:-clash.meta}"
                if local_fetch_one_provider "$_p_name" "$_p_link" "$_p_ua" "$_p_inc" "$_p_exc"; then
                    _append_sb_local_provider "$_p_name" "$LOCAL_SUB_REL_PATH" "${_p_int:-3}" "$_p_exc" "$_p_inc"
                else
                    logger "本地拉取或解析订阅失败，已跳过：$_p_name" 33
                fi
            done <"$CRASHDIR/configs/providers.cfg"
        fi
        if [ -s "$CRASHDIR/configs/providers_uri.cfg" ]; then
            mkdir -p "$CRASHDIR/providers"
            awk '{ print ($1=="vmess" ? $2 : $2 "#" $1) }' "$CRASHDIR/configs/providers_uri.cfg" >"$TMPDIR/local_sub/uri_group.raw"
            local_filter_uri_file "$TMPDIR/local_sub/uri_group.raw" "$CRASHDIR/providers/uri_group" "$include" "$exclude"
            rm -f "$TMPDIR/local_sub/uri_group.raw"
            if [ -s "$CRASHDIR/providers/uri_group" ]; then
                _append_sb_local_provider "Uri_group" "./providers/uri_group" "3" "$exclude" "$include"
            fi
        fi
    fi

    if [ "$_ok_count" -eq 0 ]; then
        logger "未能成功拉取或解析任何有效订阅节点！" 31
        rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
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
        if ! "$TMPDIR"/CrashCore merge "$TMPDIR/config.json" -C "$TMPDIR/providers"; then
            logger "本地转换生成的 Sing-Box 配置文件合并失败！" 31
            rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
            return 1
        fi
        mkdir -p "$CRASHDIR/jsons"
        [ -s "$CRASHDIR/jsons/config.json" ] && cp -f "$CRASHDIR/jsons/config.json" "$CRASHDIR/jsons/config.json.bak"
        mv -f "$TMPDIR/config.json" "$CRASHDIR/jsons/config.json"
    fi

    rm -rf "$TMPDIR/providers" "$TMPDIR/local_sub"
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
