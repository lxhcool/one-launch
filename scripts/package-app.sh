#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="$ROOT_DIR/.build"
HOME_OVERRIDE="$ROOT_DIR/.home"
CACHE_DIR="$BUILD_ROOT/swiftpm-cache"
CONFIG_DIR="$BUILD_ROOT/swiftpm-config"
SECURITY_DIR="$BUILD_ROOT/swiftpm-security"
CLANG_CACHE_DIR="$BUILD_ROOT/clang-modulecache"
SWIFTPM_MODULECACHE_DIR="$BUILD_ROOT/swiftpm-modulecache"
APP_DIR="$ROOT_DIR/dist/OneLaunch.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
BUNDLE_ID="${BUNDLE_ID:-cool.lxh.one-launch}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-14.0}"
APP_CATEGORY="${APP_CATEGORY:-public.app-category.productivity}"

mkdir -p \
  "$HOME_OVERRIDE" \
  "$CACHE_DIR" \
  "$CONFIG_DIR" \
  "$SECURITY_DIR" \
  "$CLANG_CACHE_DIR" \
  "$SWIFTPM_MODULECACHE_DIR" \
  "$MACOS_DIR" \
  "$RESOURCES_DIR"

HOME="$HOME_OVERRIDE" \
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULECACHE_DIR" \
swift build \
  -c release \
  --product OneLaunch \
  --disable-sandbox \
  --cache-path "$CACHE_DIR" \
  --config-path "$CONFIG_DIR" \
  --security-path "$SECURITY_DIR"

BIN_PATH="$(HOME="$HOME_OVERRIDE" \
  CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_DIR" \
  SWIFTPM_MODULECACHE_OVERRIDE="$SWIFTPM_MODULECACHE_DIR" \
  swift build \
  -c release \
  --product OneLaunch \
  --disable-sandbox \
  --show-bin-path \
  --cache-path "$CACHE_DIR" \
  --config-path "$CONFIG_DIR" \
  --security-path "$SECURITY_DIR")/OneLaunch"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/OneLaunch"
chmod +x "$MACOS_DIR/OneLaunch"

ICON_SRC="$ROOT_DIR/icon.png"
if [ -f "$ICON_SRC" ]; then
  ICONSET_DIR="$BUILD_ROOT/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      >/dev/null
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      >/dev/null
  sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    >/dev/null
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    >/dev/null
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    >/dev/null
  sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  if ! iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"; then
    echo "iconutil failed, falling back to sips direct icns conversion"
    sips -s format icns "$ICON_SRC" --out "$RESOURCES_DIR/AppIcon.icns" >/dev/null
  fi
  rm -rf "$ICONSET_DIR"
  echo "Generated app icon from icon.png"
fi

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleExecutable</key>
  <string>OneLaunch</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>OneLaunch</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>$APP_CATEGORY</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

touch "$APP_DIR"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_DIR" || true
fi
killall Dock 2>/dev/null || true

echo "Built app bundle: $APP_DIR"
