#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="$ROOT_DIR/dist/Sonote.app"
DST_APP="/Applications/Sonote.app"

if [[ ! -d "$SRC_APP" ]] || [[ "${1:-}" == "--rebuild" ]]; then
  "$ROOT_DIR/scripts/build_app.sh"
fi

echo "Stopping running Sonote instances..."
killall Sonote 2>/dev/null || true
sleep 0.5

echo "Installing $SRC_APP -> $DST_APP ..."
rm -rf "$DST_APP"
cp -R "$SRC_APP" "$DST_APP"

echo "Launching $DST_APP ..."
open "$DST_APP"
echo "✅ Installed and launched: $DST_APP"
