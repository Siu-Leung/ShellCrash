# Private fallback for OpenWrt uclient-fetch versions without arbitrary headers/methods.
# Only loopback IPv4 HTTP is allowed. Bearer data stays on the stdin pipe, not argv/logs.
_panel_local_url() {
    case $1 in http://127.0.0.1:*) _panel_target=${1#http://127.0.0.1:};; *) return 1;; esac
    _panel_port=${_panel_target%%/*}
    [ "$_panel_target" != "$_panel_port" ] || return 1
    case $_panel_port in ''|*[!0-9]*) return 1;; esac
    [ "$_panel_port" -gt 0 ] 2>/dev/null && [ "$_panel_port" -le 65535 ] 2>/dev/null || return 1
    _panel_path=/${_panel_target#*/}
    case $_panel_path in *' '*|*"$(printf '\r')"*|*'
'*) return 1;; esac
}

_panel_nc_request() (
    # $1: method, $2: URL, $3: body. system() kills only its own nc child on timeout.
    case $1 in GET|PUT|PATCH|POST|DELETE) :;; *) return 1;; esac
    _panel_local_url "$2" || return 1
    case ${secret:-} in *"$(printf '\r')"*|*'
'*) return 1;; esac
    command -v ucode >/dev/null 2>&1 && command -v busybox >/dev/null 2>&1 || return 1
    [ -r "$CRASHDIR/libs/panel_response.uc" ] || return 1
    # Verify fs module before sending so PUT/PATCH never fires without a response parser.
    ucode -e 'import { stdin } from "fs";' >/dev/null 2>&1 || return 1
    _panel_length=$(LC_ALL=C printf '%s' "$3" | wc -c) || return 1
    # Private directory prevents symlink attacks and is removed by this process only.
    umask 077
    _panel_tmp=$(mktemp -d "${TMPDIR:-/tmp}/panel-http.XXXXXXXX") || return 1
    trap 'rm -rf "$_panel_tmp"' 0
    trap 'exit 1' 1 2 3 15
    {
        printf '%s %s HTTP/1.1\r\nHost: 127.0.0.1:%s\r\n' "$1" "$_panel_path" "$_panel_port"
        [ -z "${secret:-}" ] || printf 'Authorization: Bearer %s\r\n' "$secret"
        printf 'Content-Type: application/json\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s' "$_panel_length" "$3"
    } | ucode -e 'let rc = system(["busybox", "nc", "127.0.0.1", ARGV[0]], 5000); exit(rc == 0 ? 0 : 1);' "$_panel_port" >"$_panel_tmp/response" 2>/dev/null || return 1
    ucode "$CRASHDIR/libs/panel_response.uc" "$1" <"$_panel_tmp/response" 2>/dev/null
)
