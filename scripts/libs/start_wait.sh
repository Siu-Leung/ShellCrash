if [ "$network_check" = "OFF" ]; then
    #复用网络检查开关：禁用自启网络检查时，也跳过启动后的面板端口校验
    test=skip
else
    i=1
    while [ -z "$test" ] && [ "$i" -lt 30 ]; do
        if curl --version >/dev/null 2>&1; then
            test=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" curl -s --noproxy '*' --connect-timeout 2 --max-time 3 -H "Authorization: Bearer $secret" "http://127.0.0.1:${db_port}/proxies" | grep -o proxies)
        elif wget --help 2>&1 | grep -q -- '--header'; then
            wget --help 2>&1 | grep -q -- '-Y' && _sw_np='-Y off' || _sw_np='--no-proxy'
            test=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" wget -q -T 2 $_sw_np --header="Authorization: Bearer $secret" -O - "http://127.0.0.1:${db_port}/proxies" 2>/dev/null | grep -o proxies)
        elif command -v wget >/dev/null 2>&1; then
            # OpenWrt uclient-fetch 无 --header：无 secret 查 proxies；有 secret 收到 HTTP error 401 即说明控制器已就绪
            _sw_out=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" wget -T 2 -Y off -O - "http://127.0.0.1:${db_port}/proxies" 2>&1)
            printf '%s\n' "$_sw_out" | grep -q 'proxies' && test=proxies
            [ -z "$test" ] && [ -n "$secret" ] && printf '%s\n' "$_sw_out" | grep -q 'HTTP error 401' && test=proxies
        else
            break
        fi
        [ -n "$test" ] && break
        sleep 1
        i=$((i + 1))
    done
fi
