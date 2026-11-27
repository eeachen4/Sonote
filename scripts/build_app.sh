#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sonote"
APP_BUNDLE="$ROOT_DIR/dist/${APP_NAME}.app"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
DERIVED_DATA="$ROOT_DIR/.build/xcode-release"

echo "1/4 Generating macOS AppIcon.icns..."
rm -rf "$ICONSET_DIR"
swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/Resources/AppIcon.icns"

echo "2/4 Building release binary + MLX Metal shaders via xcodebuild..."
cd "$ROOT_DIR"
xcodebuild \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA" \
  build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
EXECUTABLE="$PRODUCTS_DIR/$APP_NAME"

if [[ ! -f "$EXECUTABLE" ]]; then
  echo "❌ Expected executable not found at $EXECUTABLE"
  exit 1
fi

echo "3/4 Packaging ${APP_BUNDLE} (including MLX Metal shader bundles)..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SwiftPM / MLX resource bundles (critical for mlx-swift_Cmlx.bundle / default.metallib!)
shopt -s nullglob
for bundle in "$PRODUCTS_DIR"/*.bundle; do
  echo "  Bundling $(basename "$bundle")..."
  cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
  # Also place mlx bundle next to executable so both Bundle.main and Bundle.module find metallib
  cp -R "$bundle" "$APP_BUNDLE/Contents/MacOS/"
done

# If default.metallib exists inside mlx-swift_Cmlx.bundle, also expose a copy in Contents/Resources/mlx.metallib
METALLIB=$(find "$PRODUCTS_DIR" -name "default.metallib" -o -name "mlx.metallib" | head -n 1 || true)
if [[ -n "$METALLIB" ]]; then
  echo "  Bundling Metal shader library: $METALLIB"
  cp "$METALLIB" "$APP_BUNDLE/Contents/Resources/mlx.metallib"
  cp "$METALLIB" "$APP_BUNDLE/Contents/MacOS/mlx.metallib"
fi

SIGN_ID="${SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  # Prefer a local persistent signing certificate (if available) so macOS TCC permissions survive rebuilds
  DETECTED_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Sonote" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
  if [[ -n "$DETECTED_ID" ]]; then
    SIGN_ID="$DETECTED_ID"
  else
    SIGN_ID="-"
  fi
fi

echo "4/4 Signing ${APP_BUNDLE} with identity: ${SIGN_ID}..."
codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"

echo ""
echo "✅ Build complete: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
