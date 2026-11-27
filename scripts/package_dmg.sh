#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sonote"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$ROOT_DIR/Resources/Info.plist" 2>/dev/null || echo "1.5.0")
DMG_OUT="$ROOT_DIR/dist/${APP_NAME}-${VERSION}-arm64.dmg"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"

if [[ ! -d "$APP_BUNDLE" ]] || [[ "${1:-}" == "--rebuild" ]]; then
  "$ROOT_DIR/scripts/build_app.sh"
fi

echo "Packaging DMG installer: $DMG_OUT ..."
rm -rf "$STAGING_DIR" "$DMG_OUT"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "Sonote ${VERSION}" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_OUT"

rm -rf "$STAGING_DIR"
echo ""
echo "✅ DMG created: $DMG_OUT ($(du -h "$DMG_OUT" | awk '{print $1}'))"
