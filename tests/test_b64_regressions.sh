#!/bin/sh
# Local, offline regressions. Optional OPENWRT_ROOT points to an extracted
# official OpenWrt rootfs matching the current CPU architecture.
set -u
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd) || exit 1
CRASHDIR=$ROOT/scripts
export CRASHDIR
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT HUP INT TERM
ok=0 bad=0
pass() { ok=$((ok + 1)); printf 'PASS %s\n' "$*"; }
fail() { bad=$((bad + 1)); printf 'FAIL %s\n' "$*" >&2; }
mkdir "$T/awk" "$T/applet" "$T/cmd" "$T/ucode" "$T/nofs" "$T/fail" || exit 1
# Controlled PATHs expose neither the host base64 nor openssl accidentally.
for d in awk applet cmd ucode nofs fail; do
    for cmd in sh tr wc grep rm mv sed awk dd hexdump od mkdir cat cp; do
        p=$(command -v "$cmd" 2>/dev/null || :)
        [ -n "$p" ] && ln -s "$p" "$T/$d/$cmd"
    done
done
for d in awk ucode nofs fail; do
    printf '#!/bin/sh\nexit 1\n' >"$T/$d/busybox"
    chmod +x "$T/$d/busybox"
done
profiles='awk'
if command -v busybox >/dev/null 2>&1 && busybox base64 --help >/dev/null 2>&1; then
    ln -s "$(command -v busybox)" "$T/applet/busybox"
    profiles="$profiles applet"
fi
if command -v base64 >/dev/null 2>&1; then
    ln -s "$(command -v base64)" "$T/cmd/base64"
    printf '#!/bin/sh\nexit 1\n' >"$T/cmd/busybox"
    chmod +x "$T/cmd/busybox"
    profiles="$profiles cmd"
fi
rm -f "$T/fail/dd"
printf '#!/bin/sh\nexit 17\n' >"$T/fail/dd"
chmod +x "$T/fail/dd"
OW=${OPENWRT_ROOT:-}
HAVE_UCODE=0
if [ -n "$OW" ] && [ -x "$OW/usr/bin/ucode" ] && [ -d "$OW/usr/lib/ucode" ]; then
    mkdir "$T/empty-modules"
    for d in ucode nofs; do
        if [ "$d" = ucode ]; then opt="-L '$OW/usr/lib/ucode'"; else opt="-L '$T/empty-modules'"; fi
        printf '#!/bin/sh\nLD_LIBRARY_PATH="%s/lib:%s/usr/lib" exec "%s/usr/bin/ucode" %s "$@"\n' "$OW" "$OW" "$OW" "$opt" >"$T/$d/ucode"
        chmod +x "$T/$d/ucode"
    done
    if "$T/ucode/ucode" -e 'import * as fs from "fs"; if (type(fs.readfile) != "function") exit(1);' >/dev/null 2>&1 &&
       ! "$T/nofs/ucode" -e 'import * as fs from "fs";' >/dev/null 2>&1; then
        HAVE_UCODE=1
    else
        printf 'FAIL ucode fixture module isolation\n' >&2; exit 1
    fi
fi
run_decode() {
    PATH="$T/$1" TMPDIR="$T" /bin/sh -c '. "$CRASHDIR/libs/local_sub_convert.sh"; local_b64_decode "$1" "$2"' _ "$T/in" "$T/out"
}
run_random() {
    PATH="$T/$1" TMPDIR="$T" /bin/sh -c 'ckcmd() { command -v "$1" >/dev/null 2>&1; }; . "$CRASHDIR/libs/gen_base64.sh"; gen_random "$1"' _ "$2" >"$T/random"
}
# Includes UTF-8 and bytes producing + / or - _; whitespace is accepted.
printf 'trojan://example.invalid:443#香港\n\377\376\375\000' >"$T/expected"
base64 <"$T/expected" | tr -d '\r\n' >"$T/standard"
tr '+/' '-_' <"$T/standard" | tr -d '=' >"$T/url"
[ "$HAVE_UCODE" = 1 ] && profiles="$profiles ucode nofs"
random_profiles=$profiles
for d in openssl uuencode; do
    p=$(command -v "$d" 2>/dev/null || :)
    if [ -n "$p" ]; then
        mkdir "$T/$d"
        for c in sh tr wc grep rm sed awk dd hexdump od mkdir cat; do
            q=$(command -v "$c" 2>/dev/null || :)
            [ -n "$q" ] && ln -s "$q" "$T/$d/$c"
        done
        printf '#!/bin/sh\nexit 1\n' >"$T/$d/busybox"; chmod +x "$T/$d/busybox"
        ln -s "$p" "$T/$d/$d"
        random_profiles="$random_profiles $d"
    fi
done
for d in $profiles; do
    for form in standard url; do
        cp "$T/$form" "$T/in"
        if run_decode "$d" && cmp -s "$T/expected" "$T/out"; then pass "$d $form binary/UTF-8"; else fail "$d $form binary/UTF-8"; fi
    done
    printf ' T\tQ\r\n== ' >"$T/in"
    if run_decode "$d" && [ "$(cat "$T/out")" = M ]; then pass "$d whitespace"; else fail "$d whitespace"; fi
    printf TQ= >"$T/in"
    if run_decode "$d" && [ "$(cat "$T/out")" = M ]; then pass "$d historical partial padding"; else fail "$d historical partial padding"; fi
    for value in '====' 'AA=A' 'A===' 'TQ==AAAA' 'A' '=AAA' 'AAAA=' 'AAA==='; do
        printf '%s' "$value" >"$T/in"
        if run_decode "$d"; then fail "$d rejects $value"; else pass "$d rejects $value"; fi
    done
    printf 'TQ==\000' >"$T/in"
    if run_decode "$d"; then fail "$d rejects NUL"; else pass "$d rejects NUL"; fi
    printf 'cHJveGllczogW10K====' >"$T/in"
    if PATH="$T/$d" /bin/sh -c '. "$CRASHDIR/libs/local_sub_convert.sh"; local_normalize_sub_file "$1" "$2" "" ""' _ "$T/in" "$T/normalized" >/dev/null 2>&1; then fail "$d malformed YAML normalization"; else pass "$d malformed YAML normalization"; fi
    cp "$T/standard" "$T/in"
    mkdir "$T/destination"
    # destination.b64.$$ can be created, but writing destination itself fails.
    if PATH="$T/$d" /bin/sh -c '. "$CRASHDIR/libs/local_sub_convert.sh"; local_b64_decode "$1" "$2"' _ "$T/in" "$T/destination" 2>/dev/null; then fail "$d rejects directory output"; else pass "$d rejects directory output"; fi
    rmdir "$T/destination"
done
for d in $random_profiles; do
    for n in 1 2 3 16 32 64 256; do
        if run_random "$d" "$n" && base64 -d <"$T/random" >"$T/decoded" && [ "$(wc -c <"$T/decoded")" -eq "$n" ]; then pass "$d random $n"; else fail "$d random $n"; fi
    done
    for n in '' 0 -1 x 1x; do
        if run_random "$d" "$n"; then fail "$d rejects random [$n]"; else pass "$d rejects random [$n]"; fi
    done
done
if run_random fail 16; then fail 'failed random source returned success'
elif [ -s "$T/random" ]; then fail 'failed random source emitted data'
else pass 'failed random source propagates'; fi
# Every stage must fail closed without output, including short reads and
# encoders which exit nonzero after emitting bytes.
rm -f "$T/fail/dd"
printf '#!/bin/sh\nfor a do case "$a" in of=*) : > "${a#of=}" ;; esac; done\nexit 0\n' >"$T/fail/dd"; chmod +x "$T/fail/dd"
if run_random fail 16 || [ -s "$T/random" ]; then fail 'short random read'; else pass 'short random read'; fi
rm -f "$T/fail/dd"; ln -s "$(command -v dd)" "$T/fail/dd"
printf '#!/bin/sh\nprintf broken\nexit 7\n' >"$T/fail/base64"; chmod +x "$T/fail/base64"
if run_random fail 16 || [ -s "$T/random" ]; then fail 'encoder failure'; else pass 'encoder failure'; fi
rm -f "$T/fail/base64"
printf '#!/bin/sh\nprintf broken\nexit 7\n' >"$T/fail/openssl"; chmod +x "$T/fail/openssl"
if run_random fail 16 || [ -s "$T/random" ]; then fail 'openssl failure'; else pass 'openssl failure'; fi
rm -f "$T/fail/openssl"
if [ -e /dev/full ] && [ "$HAVE_UCODE" = 1 ]; then
    printf TQ== >"$T/in"
    # The decoder stages beside the destination; use a writable /tmp symlink
    # for the destination while keeping the staging file inside the sandbox.
    ln -s /dev/full "$T/full"
    if PATH="$T/ucode" /bin/sh -c '. "$CRASHDIR/libs/local_sub_convert.sh"; local_b64_decode "$1" "$2"' _ "$T/in" "$T/full" 2>/dev/null; then fail 'ucode /dev/full'; else pass 'ucode /dev/full'; fi
fi
if [ "$HAVE_UCODE" = 0 ]; then printf 'SKIP real ucode (set OPENWRT_ROOT)\n'; fi
printf '%s passed, %s failed\n' "$ok" "$bad"
[ "$bad" -eq 0 ]
