#!/bin/bash
set -euo pipefail

# Development packaging only. This script does not install, publish, notarize,
# alter login items, or use a Developer ID identity from the keychain.
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

DOTS_ARCH="${DOTS_ARCH:-arm64}"
case "$DOTS_ARCH" in
  arm64|x86_64) ;;
  *) printf 'Unsupported DOTS_ARCH: %s\n' "$DOTS_ARCH" >&2; exit 2 ;;
esac

APP_NAME="Dots Companion"
EXECUTABLE_NAME="DotsCompanion"
OUTPUT_DIR="$PROJECT_DIR/dist"
OUTPUT_APP="$OUTPUT_DIR/$APP_NAME.app"
OUTPUT_ZIP="$OUTPUT_DIR/$APP_NAME.zip"

export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/ModuleCache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

printf 'Building %s for %s…\n' "$APP_NAME" "$DOTS_ARCH"
xcrun swift build --build-system native --disable-sandbox --configuration release --arch "$DOTS_ARCH"
BIN_DIR="$(xcrun swift build --build-system native --disable-sandbox --configuration release --arch "$DOTS_ARCH" --show-bin-path)"
test -x "$BIN_DIR/$EXECUTABLE_NAME"

mkdir -p "$OUTPUT_DIR"
STAGING_DIR="$(mktemp -d "$OUTPUT_DIR/.dots-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/$APP_NAME.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$STAGED_APP/Contents/MacOS/$EXECUTABLE_NAME"
chmod 755 "$STAGED_APP/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"

# Only the explicitly named asset is bundled. Do not recursively copy resources
# that could contain development credentials or private reference material.
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon' "$STAGED_APP/Contents/Info.plist"
fi

plutil -lint "$STAGED_APP/Contents/Info.plist"
plutil -lint "$PROJECT_DIR/Resources/DotsCompanion.entitlements"
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$PROJECT_DIR/Resources/DotsCompanion.entitlements" "$STAGED_APP"
codesign --verify --strict --verbose=2 "$STAGED_APP"

ditto -c -k --sequesterRsrc --keepParent "$STAGED_APP" "$STAGING_DIR/$APP_NAME.zip"

# Replace only this script's generated artifacts, and only after a successful build,
# signature verification, and archive creation. A failed build preserves prior output.
rm -rf "$OUTPUT_APP"
mv "$STAGED_APP" "$OUTPUT_APP"
mv -f "$STAGING_DIR/$APP_NAME.zip" "$OUTPUT_ZIP"

printf '\nDevelopment app: %s\nArchive: %s\n' "$OUTPUT_APP" "$OUTPUT_ZIP"
printf 'Ad-hoc signed with hardened runtime. Not Developer ID signed or notarized.\n'
printf 'Launch: open "%s"\n' "$OUTPUT_APP"
