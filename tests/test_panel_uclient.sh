#!/bin/sh
# Isolated loopback integration tests; real firmware binaries are optional.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$HERE/panel_uclient_harness.py"
