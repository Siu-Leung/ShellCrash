#!/bin/sh
# Verify both init templates are rendered as inert, exact shell path literals.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT HUP INT TERM
. "$ROOT/scripts/libs/set_config.sh"
. "$ROOT/scripts/libs/service_template.sh"

for template in shellcrash.procd shellcrash.openrc; do
    for suffix in 'plain' 'space path' 'disk&data' 'percent%data' "quote'path" 'dollar$(false)' 'slash\path'; do
        selected="$SANDBOX/$suffix/ShellCrash"
        destination="$SANDBOX/$template"
        install_service_template "$ROOT/scripts/starts/$template" "$destination" "$selected" || {
            printf 'FAIL render %s: %s\n' "$template" "$suffix" >&2
            exit 1
        }
        # Execute only the fallback assignment, never a system service.
        assignment=$(grep '^\[ -z "\$CRASHDIR" \] && CRASHDIR=' "$destination")
        actual=$(CRASHDIR= sh -c "$assignment; printf '%s' \"\$CRASHDIR\"")
        [ "$actual" = "$selected" ] || {
            printf 'FAIL path %s: %s\n' "$template" "$suffix" >&2
            exit 1
        }
    done
    printf 'PASS %s: seven special paths preserved\n' "$template"
done
printf 'existing service\n' >"$SANDBOX/existing"
printf 'invalid template\n' >"$SANDBOX/invalid"
if install_service_template "$SANDBOX/invalid" "$SANDBOX/existing" "$SANDBOX/path"; then
    echo 'FAIL invalid template accepted' >&2
    exit 1
fi
[ "$(cat "$SANDBOX/existing")" = 'existing service' ] || {
    echo 'FAIL existing service changed after render failure' >&2
    exit 1
}
printf 'PASS invalid template leaves existing service unchanged\n'
