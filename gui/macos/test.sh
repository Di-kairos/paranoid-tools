#!/usr/bin/env bash
# The ParanoidBar gate: compilation + a selftest of the pure logic (--selftest, the analog of
# ST_NO_MAIN=1 for the Windows tray). The GUI surface (windows/menus) is checked by hand — see gui/README.md.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
./ParanoidBar --selftest
echo "gui/macos: build + selftest OK"
