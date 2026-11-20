#!/bin/sh
# test_local_sub_convert.sh —— 零外泄本地订阅拉取与转换引擎 + 零信任二次审计回归测试
set -e
cd "$(dirname "$0")/.."

FAIL=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

echo "== 1. 语法检查（sh -n）=="
for f in \
    scripts/libs/local_sub_convert.sh \
    scripts/starts/core_config.sh \
    scripts/menus/subconverter.sh \
    scripts/menus/6_core_config.sh \
    scripts/starts/bfstart.sh \
    scripts/starts/singbox_modify.sh \
    scripts/init.sh \
    install.sh \
    install_en.sh \
    tools/tg_bot.sh \
    sync_pkg.sh; do
    if sh -n "$f"; then pass "sh -n $f"; else fail "sh -n $f"; fi
done

echo "== 2. 本地订阅格式识别与解码过滤（Base64 / URI / Clash YAML）=="
CRASHDIR="$SANDBOX/crash"
TMPDIR="$SANDBOX/tmp"
BINDIR="$CRASHDIR"
mkdir -p "$CRASHDIR/configs" "$CRASHDIR/providers" "$CRASHDIR/libs" "$TMPDIR"
cp scripts/libs/web_get.sh scripts/libs/web_get_bin.sh scripts/libs/set_proxy.sh scripts/libs/logger.sh scripts/libs/web_json.sh "$CRASHDIR/libs/"
. ./scripts/libs/local_sub_convert.sh

# 2a. Base64 编码订阅（含缺失 padding + 过滤）
RAW_URIS=$(printf 'ss://YWVzLTI1Ni1nY206cGFzcw@1.1.1.1:443#HK-01\nvless://uuid@2.2.2.2:443#US-Test\ntrojan://pwd@3.3.3.3:443#JP-Expired\n')
printf '%s' "$RAW_URIS" | base64 | tr -d '\n=' >"$SANDBOX/sub_b64.raw"
if local_normalize_sub_file "$SANDBOX/sub_b64.raw" "$SANDBOX/out_b64" "" "Expired"; then
    if [ "$LOCAL_SUB_FMT" = "uri" ] && grep -q 'HK-01' "$LOCAL_SUB_OUT" && grep -q 'US-Test' "$LOCAL_SUB_OUT" && ! grep -q 'Expired' "$LOCAL_SUB_OUT"; then
        pass "Base64 订阅本地解码与 exclude 过滤正确"
    else
        fail "Base64 解码输出异常: $(cat "$LOCAL_SUB_OUT" 2>/dev/null)"
    fi
else
    fail "Base64 订阅本地归一化返回失败"
fi

# 2b. 明文 URI 列表 + include 过滤
printf 'vless://u@4.4.4.4:443#SG-Fast\r\nhy2://p@5.5.5.5:443#HK-Slow\r\n' >"$SANDBOX/sub_uri.raw"
if local_normalize_sub_file "$SANDBOX/sub_uri.raw" "$SANDBOX/out_uri" "SG" ""; then
    if [ "$LOCAL_SUB_FMT" = "uri" ] && grep -q 'SG-Fast' "$LOCAL_SUB_OUT" && ! grep -q 'HK-Slow' "$LOCAL_SUB_OUT"; then
        pass "明文 URI 订阅本地归一化与 include 过滤正确"
    else
        fail "明文 URI 输出异常"
    fi
else
    fail "明文 URI 归一化失败"
fi

# 2c. Clash YAML 订阅识别
cat >"$SANDBOX/sub_yaml.raw" <<'EOF'
proxies:
  - {name: HK-A, type: ss, server: 1.2.3.4, port: 443, cipher: aes-128-gcm, password: pwd}
EOF
if local_normalize_sub_file "$SANDBOX/sub_yaml.raw" "$SANDBOX/out_yaml" "" ""; then
    if [ "$LOCAL_SUB_FMT" = "yaml" ] && grep -q 'HK-A' "$LOCAL_SUB_OUT"; then
        pass "Clash YAML 订阅识别正确"
    else
        fail "Clash YAML 输出异常"
    fi
else
    fail "Clash YAML 归一化失败"
fi

echo "== 3. 端到端本地拉取转换生成 Clash config.yaml（离线模拟 webget）=="
mkdir -p "$CRASHDIR/rules/clash_providers"
cp rules/clash_providers/ShellCrash_RS_Nano.yaml "$CRASHDIR/rules/clash_providers/"
printf 'ShellCrash-ruleset极简规则 ShellCrash_RS_Nano.yaml\n' >"$CRASHDIR/configs/clash_providers.list"
printf 'MySub https://sub.example.invalid/token123 3 12 clash.meta #Expired #\n' >"$CRASHDIR/configs/providers.cfg"
printf 'Node1 vless://uuid@9.9.9.9:443\n' >"$CRASHDIR/configs/providers_uri.cfg"

# 覆盖 webget 为本地 mock，模拟机场返回 Base64 订阅
webget() {
    printf '%s' "$RAW_URIS" | base64 >"$1"
    return 0
}
logger() { :; }
skip_cert=OFF
LOCAL_SUB_SKIP_CORE_TEST=1
if local_build_clash_config; then
    CFG="$CRASHDIR/yamls/config.yaml"
    if [ -s "$CFG" ] \
        && grep -q 'type: file' "$CFG" \
        && grep -q 'path: "./providers/MySub.txt"' "$CFG" \
        && grep -q 'path: "./providers/uri_group"' "$CFG" \
        && grep -q 'skip-cert-verify: false' "$CFG" \
        && ! grep -q 'https://sub.example.invalid' "$CFG"; then
        pass "Clash 本地转换生成纯 file provider 配置，无原始订阅 URL 残留"
    else
        fail "Clash 本地转换配置内容不符预期"
    fi
else
    fail "local_build_clash_config 执行失败"
fi

echo "== 4. 零信任二级审计静态断言 =="
if ! grep -q '/sub?target=' scripts/starts/core_config.sh; then
    pass "core_config.sh 已彻底移除第三方 /sub 拼接"
else
    fail "core_config.sh 仍残留第三方 /sub 拼接"
fi
if ! grep -q 'gen_link_server' scripts/menus/subconverter.sh; then
    pass "subconverter.sh 已移除第三方服务器选择入口"
else
    fail "subconverter.sh 仍残留第三方服务器选择"
fi
if ! grep -q 'board\.zash\.run\.place' scripts/starts/bfstart.sh; then
    pass "bfstart.sh 已移除外部在线面板跳转"
else
    fail "bfstart.sh 仍残留外部在线面板链接"
fi
if ! grep -q "release_type 'master'" scripts/init.sh; then
    pass "init.sh 容器环境已锁定 dev 分支"
else
    fail "init.sh 容器环境仍指向 master"
fi
if ! grep -Eq 'curl[^#]*-ko ' install.sh install_en.sh; then
    pass "install.sh / install_en.sh 默认开启 TLS 证书校验"
else
    fail "install.sh / install_en.sh 仍默认 -k 跳过证书校验"
fi
if ! grep -Eq 'juewuy|t\.me/\+RKujv|t\.me/ShellCrash' tools/tg_bot.sh tools/ShellDDNS.sh; then
    pass "tools/tg_bot.sh 与 tools/ShellDDNS.sh 无上游外链残留"
else
    fail "tools/ 仍残留上游外链"
fi
if ! grep -q 'testingcf\.jsdelivr\.net' scripts/starts/singbox_modify.sh rules/clash_providers/*.yaml rules/singbox_providers/*.json; then
    pass "规则模板与 singbox_modify.sh 已消除 testingcf.jsdelivr.net"
else
    fail "仍存在 testingcf.jsdelivr.net"
fi
if ! grep -q 'Siu-Leung/ShellClash' .github/workflows/*.yml .github/workflows/*.yaml rules/*.ini; then
    pass "workflows 与 rules/*.ini 无 ShellClash 拼写错误"
else
    fail "仍存在 ShellClash 拼写错误"
fi


echo "== 5. 深度工程与安全加固回归（set_config / domain_resolver / 纯净监听 / CI 并发锁）=="
. ./scripts/libs/set_config.sh
TEST_CFG="$SANDBOX/test.cfg"
if setconfig 'valid_key' 'hello_world' "$TEST_CFG" && grep -qx 'valid_key=hello_world' "$TEST_CFG"; then
    pass "setconfig 合法键值原子写入正常"
else
    fail "setconfig 合法写入失败"
fi
if ! setconfig 'bad;rm -rf /' 'x' "$TEST_CFG" && ! setconfig '123bad' 'x' "$TEST_CFG"; then
    pass "setconfig 拦截非法键名注入"
else
    fail "setconfig 未拦截非法键名"
fi
NL_VAL=$(printf 'abc\nINJECTED=1')
setconfig 'nl_key' "$NL_VAL" "$TEST_CFG"
if ! grep -q '^INJECTED=' "$TEST_CFG"; then
    pass "setconfig 剥离换行符防止多行配置注入"
else
    fail "setconfig 允许了换行符注入"
fi
if grep -q '"domain_resolver": "dns_proxy_server"' scripts/menus/providers_singbox.sh     && grep -q '"domain_resolver": "dns_proxy_server"' scripts/libs/local_sub_convert.sh; then
    pass "providers_singbox 与 local_sub_convert 的 domain_resolver 为字面 tag"
else
    fail "domain_resolver 仍错误展开变量"
fi
if grep -q '127.0.0.1:\$db_port' scripts/starts/clash_modify.sh     && grep -q '127.0.0.1:\$db_port' scripts/starts/singbox_modify.sh; then
    pass "纯净模式默认绑定 127.0.0.1 防止公网裸奔"
else
    fail "纯净模式绑定加固缺失"
fi
if grep -q 'shellcrash-update-branch' .github/workflows/core_easy_update.yaml     && grep -q 'git pull --rebase origin update' .github/workflows/update_meta_core.yaml     && grep -q 'git pull --rebase origin update' .github/workflows/update_singbox_core.yaml; then
    pass "CI 并发锁与 rebase 防冲突推送已配置"
else
    fail "CI 并发锁配置不完整"
fi

if [ "$FAIL" -gt 0 ]; then
    printf '\n\033[31m失败 %d 项\033[0m\n' "$FAIL"
    exit 1
fi
printf '\n\033[32m全部通过 (local_sub_convert + zero-trust audit)\033[0m\n'
