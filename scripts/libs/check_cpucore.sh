
check_cpucore(){ #自动获取内核架构
    cputype=$(uname -ms | tr ' ' '_' | tr '[A-Z]' '[a-z]')
    [ -n "$(echo $cputype | grep -E "linux.*armv.*")" ] && cpucore="armv5"
    [ -n "$(echo $cputype | grep -E "linux.*armv7.*")" ] && [ -n "$(cat /proc/cpuinfo | grep vfp)" ] && [ ! -d /jffs ] && cpucore="armv7"
    [ -n "$(echo $cputype | grep -E "linux.*aarch64.*|linux.*armv8.*")" ] && cpucore="arm64"
    [ -n "$(echo $cputype | grep -E "linux.*86.*")" ] && cpucore="386"
    [ -n "$(echo $cputype | grep -E "linux.*86_64.*")" ] && cpucore="amd64"
    if [ -n "$(echo $cputype | grep -E "linux.*mips.*")" ]; then
        if echo "$cputype" | grep -qE "mips64el|mipsel|mipsle"; then
            mipstype=1
        elif command -v hexdump >/dev/null 2>&1; then
            mipstype=$(printf 'I' | hexdump -o 2>/dev/null | awk '{ print substr($2,6,1); exit}') #通过判断大小端判断mips或mipsle
        elif command -v od >/dev/null 2>&1; then
            mipstype=$(printf 'I\0' | od -An -to2 2>/dev/null | awk '{ print substr($1,6,1); exit}')
        else
            [ "$(dd if=/bin/sh bs=1 skip=5 count=1 2>/dev/null)" = "$(printf '\002')" ] && mipstype=0 || mipstype=1
        fi
        [ "$mipstype" = "0" ] && cpucore="mips-softfloat" || cpucore="mipsle-softfloat"
    fi
    [ -n "$cpucore" ] && setconfig cpucore $cpucore
}
