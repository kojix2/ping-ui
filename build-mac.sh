#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="$(awk -F': ' '$1 == "name" { print $2; exit }' shard.yml)"
VERSION="$(awk -F': ' '$1 == "version" { print $2; exit }' shard.yml)"
DISPLAY_NAME="Ping UI"
BUNDLE_ID="io.github.kojix2.ping-ui"
EXECUTABLE_PATH="bin/$APP_NAME"
APP_BUNDLE="$DISPLAY_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
DIST_DIR="dist"
STAGING_DIR="dmg_stage"
DMG_NAME="ping-ui-macos-v${VERSION}.dmg"
VOL_NAME="$DISPLAY_NAME"
ICON_NAME="app_icon"
ICON_PNG="resources/$ICON_NAME.png"
ICON_ICNS="resources/$ICON_NAME.icns"

if [[ -z "$APP_NAME" || -z "$VERSION" ]]; then
  echo "Failed to read app name/version from shard.yml" >&2
  exit 1
fi

echo "Building $DISPLAY_NAME v$VERSION..."
shards install
shards build --release

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Executable not found: $EXECUTABLE_PATH" >&2
  exit 1
fi

unexpected_libs="$({ otool -L "$EXECUTABLE_PATH" | tail -n +2 | awk '{print $1}'; } | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
if [[ -n "$unexpected_libs" ]]; then
  echo "Found non-system dynamic libraries:" >&2
  echo "$unexpected_libs" >&2
  echo "Update build-mac.sh to bundle these libraries before shipping." >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$DIST_DIR" "$STAGING_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DIST_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$ICON_ICNS" ]]; then
  cp "$ICON_ICNS" "$RESOURCES_DIR/$ICON_NAME.icns"
elif [[ -f "$ICON_PNG" ]]; then
  if ! command -v iconutil >/dev/null 2>&1; then
    echo "iconutil not found; skipping icon generation" >&2
  else
    ICONSET_DIR="resources/$ICON_NAME.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
    sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
    sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
    sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
    sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
    sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME.icns"
    rm -rf "$ICONSET_DIR"
  fi
fi

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF

if [[ -f "$RESOURCES_DIR/$ICON_NAME.icns" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string $ICON_NAME" "$PLIST_PATH"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create "$DMG_NAME" \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -quiet

rm -rf "$STAGING_DIR"
mv "$DMG_NAME" "$DIST_DIR/"
mv "$APP_BUNDLE" "$DIST_DIR/"

echo "Created: $DIST_DIR/$DMG_NAME"
echo "Created: $DIST_DIR/$APP_BUNDLE"
