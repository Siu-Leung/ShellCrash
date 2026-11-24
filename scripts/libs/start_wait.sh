if [ "$network_check" = "OFF" ]; then
    #复用网络检查开关：禁用自启网络检查时，也跳过启动后的面板端口校验
    test=skip
else
    i=1
    while [ -z "$test" ] && [ "$i" -lt 30 ]; do
        if curl --version >/dev/null 2>&1; then
            test=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" all_proxy="" ALL_PROXY="" curl -s --noproxy '*' --connect-timeout 2 --max-time 3 -H "Authorization: Bearer $secret" "http://127.0.0.1:${db_port}/proxies" | grep -o proxies)
        else
            test=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" wget -q --timeout=2 -Y off --header="Authorization: Bearer $secret" -O - "http://127.0.0.1:${db_port}/proxies" 2>/dev/null | grep -o proxies)
            [ -z "$test" ] && test=$(http_proxy="" https_proxy="" HTTP_PROXY="" HTTPS_PROXY="" wget -q --timeout=2 --no-proxy --header="Authorization: Bearer $secret" -O - "http://127.0.0.1:${db_port}/proxies" 2>/dev/null | grep -o proxies)
        fi
        [ -n "$test" ] && break
        sleep 1
        i=$((i + 1))
    done
fi
