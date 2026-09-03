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
mkdir -p "$APP/Contents/MacOS"
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
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHumanReadableCopyright</key><string>MIT Licensed</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Steady shows your upcoming events from the calendar accounts already set up on this Mac.</string>
  <key>NSCalendarsUsageDescription</key><string>Steady shows your upcoming events from the calendar accounts already set up on this Mac.</string>
  <key>NSAppleEventsUsageDescription</key><string>Steady reads and sends mail through the Mail app already set up on this Mac.</string>
</dict>
</plist>
PLIST

# Sign with a local Apple identity so the Keychain (Touch ID) stays stable across
# rebuilds. Set STEADY_SIGN_IDENTITY to force a specific one; otherwise the first
# local Apple Development / Developer ID identity is used, falling back to ad-hoc.
# No --deep: Steady has no nested frameworks/plugins to recurse into, and --deep
# combined with the toolchain's own linker-signed executable produces a broken
# seal ("code has no resources but signature indicates they must be present").
# grep exits 1 when no identity matches (the expected case on CI or a machine
# with no personal certificate) - `|| true` keeps that from aborting the whole
# script under `set -e`/pipefail before it ever reaches the ad-hoc fallback.
if [ -n "${STEADY_SIGN_IDENTITY:-}" ]; then
  IDENTITY_HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep "$STEADY_SIGN_IDENTITY" || true)"
else
  IDENTITY_HASH="$(security find-identity -v -p codesigning 2>/dev/null | grep -E 'Apple Development|Developer ID Application' || true)"
fi
IDENTITY_HASH="$(echo "$IDENTITY_HASH" | head -1 | awk '{print $2}')"
if [ -n "$IDENTITY_HASH" ]; then
  echo "→ signing with $IDENTITY_HASH"
  codesign --force --timestamp=none --sign "$IDENTITY_HASH" "$APP"
else
  echo "→ no developer identity found, ad-hoc signing"
  codesign --force --sign - "$APP" >/dev/null 2>&1 || true
fi

if ! codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
  echo "✗ signature check failed:" >&2
  codesign --verify --deep --strict -vvv "$APP" >&2 || true
  exit 1
fi

echo "✓ built $APP"
echo "  open with: open \"$APP\"   (look in the menu bar)"
