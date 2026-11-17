#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_ARCH="${1:?expected arm64 or x86_64}"
ACTUAL_ARCH="$(uname -m)"
[[ "$ACTUAL_ARCH" == "$EXPECTED_ARCH" ]] || { echo "Expected $EXPECTED_ARCH runner, got $ACTUAL_ARCH"; exit 1; }
export LIBUSB_PREFIX="$(cat "$ROOT/build/libusb-prefix.txt")"
export MACOSX_DEPLOYMENT_TARGET=13.0
cd "$ROOT/macos"
swift test --parallel
swift build -c release --arch "$EXPECTED_ARCH"
BIN_DIR="$(swift build -c release --arch "$EXPECTED_ARCH" --show-bin-path)"
VERSION="$(tr -d '\r\n' < "$ROOT/VERSION")"
NAME="FourGSwitch-$VERSION-macos-$EXPECTED_ARCH"
STAGE="$ROOT/dist/$NAME"
APP="$STAGE/FourGSwitch.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources/ThirdParty"
cp "$BIN_DIR/FourGSwitch" "$APP/Contents/MacOS/FourGSwitch"
cp -L "$LIBUSB_PREFIX/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
OLD_LIBRARY="$(otool -L "$APP/Contents/MacOS/FourGSwitch" | awk '/libusb-1.0/{print $1;exit}')"
[[ -n "$OLD_LIBRARY" ]] || { echo "libusb load command missing";exit 1; }
install_name_tool -change "$OLD_LIBRARY" '@executable_path/../Frameworks/libusb-1.0.0.dylib' "$APP/Contents/MacOS/FourGSwitch"
install_name_tool -id '@rpath/libusb-1.0.0.dylib' "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.cher9lie.four-g-switch</string>
  <key>CFBundleName</key><string>FourGSwitch</string>
  <key>CFBundleDisplayName</key><string>4G 网卡开关</string>
  <key>CFBundleExecutable</key><string>FourGSwitch</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>3.0.0</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 cher9lie. MIT.</string>
</dict></plist>
PLIST
cp "$ROOT/build/libusb/libusb-1.0.29.tar.bz2" "$APP/Contents/Resources/ThirdParty/"
cp "$ROOT/build/libusb/libusb-1.0.29/COPYING" "$APP/Contents/Resources/ThirdParty/libusb-COPYING.txt"
cp "$ROOT/third_party/NOTICES.md" "$APP/Contents/Resources/ThirdParty/NOTICES.md"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/README.md" "$STAGE/README.md"
IDENTITY="${MACOS_SIGNING_IDENTITY:--}"
SIGN_OPTIONS=()
if [[ "$IDENTITY" != "-" ]]; then SIGN_OPTIONS+=(--options runtime --timestamp); fi
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
codesign --force --sign "$IDENTITY" "${SIGN_OPTIONS[@]}" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"
[[ "$(lipo -archs "$APP/Contents/MacOS/FourGSwitch")" == "$EXPECTED_ARCH" ]]
[[ "$(lipo -archs "$APP/Contents/Frameworks/libusb-1.0.0.dylib")" == "$EXPECTED_ARCH" ]]
"$APP/Contents/MacOS/FourGSwitch" --version
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/$NAME.zip"
if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ROOT/dist/$NAME.zip" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/$NAME.zip"
fi
hdiutil create -volname "4G 网卡开关" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/dist/$NAME.dmg"
