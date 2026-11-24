
. "$CRASHDIR"/libs/check_cmd.sh

start_legacy(){	
    _piddir="${TMPDIR:-/tmp/ShellCrash}"
    mkdir -p "$_piddir"
    ckcmd nohup && _nohup=nohup
    if ckcmd su && grep -q '^shellcrash:x:0:7890' /etc/passwd 2>/dev/null;then
        su shellcrash -c "$_nohup $1 >/dev/null 2>&1 & echo \$! > $_piddir/$2.pid"
    elif ckcmd setsid; then
        $_nohup setsid $1 >/dev/null 2>&1 &
        echo $! > "$_piddir/$2.pid"
    else
        $_nohup $1 >/dev/null 2>&1 &
        echo $! > "$_piddir/$2.pid"
    fi
}
