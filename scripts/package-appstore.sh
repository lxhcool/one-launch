#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/OneLaunch.app"
PKG_PATH="$ROOT_DIR/dist/OneLaunch-appstore.pkg"
BUILD_ROOT="$ROOT_DIR/.build"
PROFILE_PLIST_PATH="$BUILD_ROOT/appstore-profile.plist"
SIGN_ENTITLEMENTS_PATH="$BUILD_ROOT/appstore-sign-entitlements.plist"

: "${BUNDLE_ID:?Set BUNDLE_ID to the App Store Connect bundle ID, for example com.example.OneLaunch}"
: "${APP_SIGN_IDENTITY:?Set APP_SIGN_IDENTITY to your Mac App Distribution certificate name}"
: "${INSTALLER_SIGN_IDENTITY:?Set INSTALLER_SIGN_IDENTITY to your Mac Installer Distribution certificate name}"
: "${PROVISIONING_PROFILE:?Set PROVISIONING_PROFILE to the downloaded Mac App Store .provisionprofile path}"

if [ ! -f "$PROVISIONING_PROFILE" ]; then
  echo "Provisioning profile not found: $PROVISIONING_PROFILE" >&2
  exit 1
fi

MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}" \
BUILD_VERSION="${BUILD_VERSION:-1}" \
BUNDLE_ID="$BUNDLE_ID" \
"$ROOT_DIR/scripts/package-app.sh"

cp "$PROVISIONING_PROFILE" "$APP_DIR/Contents/embedded.provisionprofile"
xattr -cr "$APP_DIR"

security cms -D -i "$PROVISIONING_PROFILE" -o "$PROFILE_PLIST_PATH"
APP_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST_PATH")"
TEAM_IDENTIFIER="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$PROFILE_PLIST_PATH")"

cat > "$SIGN_ENTITLEMENTS_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.application-identifier</key>
  <string>$APP_IDENTIFIER</string>
  <key>com.apple.developer.team-identifier</key>
  <string>$TEAM_IDENTIFIER</string>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-only</key>
  <true/>
</dict>
</plist>
PLIST

codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$SIGN_ENTITLEMENTS_PATH" \
  --sign "$APP_SIGN_IDENTITY" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"

rm -f "$PKG_PATH"
productbuild \
  --component "$APP_DIR" /Applications \
  --sign "$INSTALLER_SIGN_IDENTITY" \
  "$PKG_PATH"

echo "Built App Store package: $PKG_PATH"
echo "Validate:"
echo "  xcrun altool --validate-app -f \"$PKG_PATH\" -t macos -u APPLE_ID -p APP_SPECIFIC_PASSWORD"
echo "Upload:"
echo "  xcrun altool --upload-app -f \"$PKG_PATH\" -t macos -u APPLE_ID -p APP_SPECIFIC_PASSWORD"
