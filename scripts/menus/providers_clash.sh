#!/bin/sh
# Copyright (C) Juewuy

[ -n "$__IS_PROVIDERS_CLASH" ] && return
__IS_PROVIDERS_CLASH=1

load_lang providers

. "$CRASHDIR"/libs/web_get_bin.sh

_pc_esc() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\r\n'
}

# 生成clash的providers配置文件
gen_providers() {
    . "$CFG_PATH" >/dev/null 2>&1
    provider_temp_file="$provider_temp_clash"
    if [ -z "$provider_temp_file" ]; then
        provider_temp_file="$(sed -n "1p" "$CRASHDIR"/configs/"${CORE_TYPE}"_providers.list | awk '{print $2}')"
    fi

    if [ -s "$provider_temp_file" ]; then
        ln -sf "$provider_temp_file" "$TMPDIR"/provider_temp_file
    else
        msg_alert "\033[33m$PROVIDERS_FETCHING_TEMPLATE\033[0m"
        get_bin "$TMPDIR"/provider_temp_file "rules/${CORE_TYPE}_providers/$provider_temp_file"
        [ -z "$(grep -o 'rules' "$TMPDIR"/provider_temp_file 2>/dev/null)" ] && {
            rm -f "$TMPDIR"/provider_temp_file
            msg_alert "\033[31m$PROVIDERS_DOWNLOAD_FAILED\033[0m"
            . "$CRASHDIR"/menus/9_upgrade.sh && setserver
            return 1
        }
    fi
    # 生成proxy_providers模块
    rm -rf "$TMPDIR"/providers
    mkdir -p "$TMPDIR"/providers
    # 预创建文件并写入对应文件头
    echo 'proxy-providers:' >"$TMPDIR"/providers/providers.yaml
    # 切割模版文件
    sed -n '/^proxy-groups:/,/^[a-z]/ { /^rule/d; p; }' "$TMPDIR"/provider_temp_file >"$TMPDIR"/providers/proxy-groups.yaml
    sed -n '/^rule/,$p' "$TMPDIR"/provider_temp_file >"$TMPDIR"/providers/rules.yaml
    rm -rf "$TMPDIR"/provider_temp_file
    # 基于单订阅生成providers模块
    providers_tags=''
    if [ -n "$1" ]; then
        gen_providers_txt "$@"
        providers_tags=$1
    else
        # 基于全部订阅/本地文件生成
        [ -s "$CRASHDIR"/configs/providers.cfg ] && {
            while IFS= read -r line || [ -n "$line" ]; do
                case "$line" in "" | \#*) continue ;; esac
                set -f
                gen_providers_txt $line
                set +f
                providers_tags=$(echo "$providers_tags, $tag" | sed 's/^, //')
            done <"$CRASHDIR"/configs/providers.cfg
        }
        # 基于全部节点分享链接生成
        [ -s "$CRASHDIR"/configs/providers_uri.cfg ] && {
            mkdir -p "$CRASHDIR"/providers
            awk 'NF >= 2 && $1 !~ /^#/ { print ($1=="vmess" ? $2 : ($2 ~ /#/ ? $2 : $2 "#" $1)) }' "$CRASHDIR"/configs/providers_uri.cfg >"$CRASHDIR"/providers/uri_group
            gen_providers_txt "Uri_group" "./providers/uri_group" "3" "12"
            providers_tags=$(echo "$providers_tags, Uri_group" | sed 's/^, //')
        }
    fi
    # 修饰模版文件并合并（ENVIRON 避免 & / \ 破坏替换）
    PC_TAGS="$providers_tags" awk '{
        rep = ENVIRON["PC_TAGS"]
        out = ""
        rest = $0
        while ((i = index(rest, "{providers_tags}")) > 0) {
            out = out substr(rest, 1, i - 1) rep
            rest = substr(rest, i + 16)
        }
        print out rest
    }' "$TMPDIR"/providers/proxy-groups.yaml >"$TMPDIR"/providers/proxy-groups.yaml.tmp &&
        mv -f "$TMPDIR"/providers/proxy-groups.yaml.tmp "$TMPDIR"/providers/proxy-groups.yaml
    cut -c 1- "$TMPDIR"/providers/providers.yaml "$TMPDIR"/providers/proxy-groups.yaml "$TMPDIR"/providers/rules.yaml >"$TMPDIR"/config.yaml
    rm -rf "$TMPDIR"/providers
    # 同步 $BINDIR/providers 软链，兼容分目录安装
    [ -n "$BINDIR" ] && [ "$BINDIR" != "$CRASHDIR" ] && [ -d "$CRASHDIR/providers" ] && [ ! -e "$BINDIR/providers" ] &&
        ln -sf "$CRASHDIR/providers" "$BINDIR/providers" 2>/dev/null
    # 调用内核测试
    . "$CRASHDIR"/starts/check_core.sh && check_core && "$TMPDIR"/CrashCore -t -d "$BINDIR" -f "$TMPDIR"/config.yaml
    if [ "$?" = 0 ]; then
        msg_alert "\033[32m$PROVIDERS_GEN_OK\033[0m"
        mkdir -p "$CRASHDIR"/yamls
        mv -f "$TMPDIR"/config.yaml "$CRASHDIR"/yamls/config.yaml
        comp_box "$PROVIDERS_RESTART_ASK"
        btm_box "1) $PROVIDERS_YES" \
            "0) $PROVIDERS_NO"
        read -r -p "$COMMON_INPUT> " res
        [ "$res" = 1 ] && {
            start_core && . "$CRASHDIR"/libs/set_cron.sh && cronset "$PROVIDERS_CRON_SUB_UPDATE"
            exit
        }
    else
        rm -rf "$TMPDIR"/CrashCore
        rm -rf "$TMPDIR"/config.yaml
        msg_alert "\033[31m$PROVIDERS_GEN_FAILED\033[0m"
    fi
}

gen_providers_txt() {
    if [ -n "$(echo "$2" | grep -E '^./')" ]; then
        type=file
        path=$(_pc_esc "$2")
        download_url=
    else
        type=http
        path=$(_pc_esc "./providers/$1.yaml")
        download_url=$(_pc_esc "$2")
    fi
    tag=$1
    interval=${3:-3}
    interval2=${4:-12}
    echo "$interval" | grep -Eq '^[0-9]+$' || interval=3
    echo "$interval2" | grep -Eq '^[0-9]+$' || interval2=12
    ua=$(_pc_esc "${5:-clash.meta}")
    exclude=$(_pc_esc "${6#\#}")
    include=$(_pc_esc "${7#\#}")
    skip_cert_verify=''

    cat >>"$TMPDIR"/providers/providers.yaml <<EOF
  ${1}:
    type: $type
    url: "$download_url"
    path: "$path"
    interval: $((interval2 * 3600))
    health-check:
      enable: true
      lazy: true
      url: "https://www.gstatic.com/generate_204"
      interval: $((interval * 60))
EOF
    [ "$crashcore" = 'meta' ] && {
        # 节点 TLS 按 node_tls：follow=不覆盖（跟随订阅），skip/verify=统一覆盖
        [ -f "$CRASHDIR"/libs/tls_policy.sh ] && . "$CRASHDIR"/libs/tls_policy.sh
        case "$(tls_node_mode)" in
        skip) skip_cert_verify='skip-cert-verify: true' ;;
        verify) skip_cert_verify='skip-cert-verify: false' ;;
        esac
        cat >>"$TMPDIR"/providers/providers.yaml <<EOF
    header:
      User-Agent: ["$ua"]
    override:
      udp: true
      $skip_cert_verify
    filter: "$include"
    exclude-filter: "$exclude"
EOF
    }
    # 写入提供者
    echo '  - {name: '"$tag"', type: url-test, tolerance: 100, lazy: true, use: ['"$tag"']}' >>"$TMPDIR"/providers/proxy-groups.yaml
}
