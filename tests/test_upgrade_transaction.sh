#!/bin/sh
# Entirely isolated fixtures; never invokes a host service manager.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
if ! command -v python3 >/dev/null 2>&1; then
    echo 'SKIP test_upgrade_transaction: python3 unavailable'
    exit 0
fi
exec python3 "$ROOT/tests/test_upgrade_transaction_fixture.py"
