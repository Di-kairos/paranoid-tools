#!/usr/bin/env bash
# Гейт ParanoidBar: компиляция + selftest чистой логики (--selftest, аналог ST_NO_MAIN=1
# у Windows-tray). GUI-поверхность (окна/меню) проверяется руками — см. gui/README.md.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
./ParanoidBar --selftest
echo "gui/macos: build + selftest OK"
