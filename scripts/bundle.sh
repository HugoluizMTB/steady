#!/usr/bin/env bash
# Build Steady and wrap the SwiftPM executable into a proper .app bundle so it
# runs as a menu-bar (LSUIElement) app. Usage: ./scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Steady"
BUNDLE_ID="app.steady.Steady"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/$APP_NAME.app"

echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/$APP_NAME"

echo "→ assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHumanReadableCopyright</key><string>MIT Licensed</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so networking entitlements/Keychain work locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ built $APP"
echo "  open with: open \"$APP\"   (look in the menu bar)"
