#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/libusb"
PREFIX="$WORK/install"
mkdir -p "$WORK"
VERSION=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["version"])' "$ROOT/third_party/libusb.json")
URL=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["url"])' "$ROOT/third_party/libusb.json")
SHA=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["sha256"])' "$ROOT/third_party/libusb.json")
ARCHIVE="$WORK/libusb-$VERSION.tar.bz2"
if [[ ! -f "$ARCHIVE" ]]; then curl --fail --location --retry 3 "$URL" -o "$ARCHIVE"; fi
printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -f "$PREFIX/lib/libusb-1.0.0.dylib" ]]; then
  tar -xjf "$ARCHIVE" -C "$WORK"
  (
    cd "$WORK/libusb-$VERSION"
    export MACOSX_DEPLOYMENT_TARGET=13.0
    export CFLAGS="-O2 -mmacosx-version-min=13.0"
    export LDFLAGS="-mmacosx-version-min=13.0"
    ./configure --prefix="$PREFIX" --enable-shared --disable-static --disable-dependency-tracking
    make -j 3
    make install
  )
fi
printf '%s\n' "$PREFIX" > "$ROOT/build/libusb-prefix.txt"
