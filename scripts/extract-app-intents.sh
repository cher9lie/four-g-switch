#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?app bundle path}"
ARCH="${2:?target architecture}"
WORK="$ROOT/build/app-intents-$ARCH"
mkdir -p "$WORK"
find "$ROOT/macos/Sources/FourGSwitch" -name '*.swift' -type f | LC_ALL=C sort > "$WORK/sources.txt"
find "$ROOT/macos/.build" -path '*/release/FourGSwitch.build/*.swiftconstvalues' -type f | LC_ALL=C sort > "$WORK/const-values.txt"
[[ -s "$WORK/const-values.txt" ]] || { echo "Swift App Intents constant metadata was not generated"; exit 1; }
TOOLCHAIN="$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_VERSION="$(xcodebuild -version | awk '/Build version/{print $3}')"
xcrun appintentsmetadataprocessor \
  --toolchain-dir "$TOOLCHAIN" \
  --module-name FourGSwitch \
  --sdk-root "$SDK" \
  --xcode-version "$XCODE_VERSION" \
  --platform-family macOS \
  --deployment-target 13.0 \
  --target-triple "$ARCH-apple-macosx13.0" \
  --source-file-list "$WORK/sources.txt" \
  --swift-const-vals-list "$WORK/const-values.txt" \
  --output "$APP/Contents/Resources" \
  --validate-assistant-intents \
  --no-app-shortcuts-localization \
  --force
python3 "$ROOT/scripts/validate-app-intents.py" "$APP/Contents/Resources/Metadata.appintents" "$WORK/validation.json"
