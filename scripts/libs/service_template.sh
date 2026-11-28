#!/bin/sh
# Render the service fallback as a shell literal without interpreting path data.

# install_service_template <source> <destination> <install-directory>
# Atomically installs a syntax-checked service template. The caller must source
# set_config.sh first for quote_cfg_val. Returns nonzero on any failure.
install_service_template() (
    _ist_source=$1
    _ist_destination=$2
    _ist_directory=$3
    [ -f "$_ist_source" ] && [ -n "$_ist_directory" ] &&
        [ ! -d "$_ist_destination" ] || return 1
    # quote_cfg_val intentionally strips line breaks; reject those paths
    # instead of installing a service that refers to a different directory.
    _ist_cr=$(printf '\r')
    case "$_ist_directory" in
        *'
'* | *"$_ist_cr"*) return 1 ;;
    esac
    _ist_quoted=$(quote_cfg_val "$_ist_directory") || return 1
    _ist_temporary=$(mktemp "${_ist_destination}.tmp.XXXXXX") || return 1
    SC_SERVICE_DIRECTORY="$_ist_quoted" awk '
        $0 == "[ -z \"$CRASHDIR\" ] && CRASHDIR=/etc/ShellCrash" {
            print "[ -z \"$CRASHDIR\" ] && CRASHDIR=" ENVIRON["SC_SERVICE_DIRECTORY"]
            count++
            next
        }
        { print }
        END { if (count != 1) exit 1 }
    ' "$_ist_source" >"$_ist_temporary" &&
        sh -n "$_ist_temporary" && chmod 755 "$_ist_temporary" &&
        mv -f "$_ist_temporary" "$_ist_destination" && return 0
    rm -f "$_ist_temporary"
    return 1
)
