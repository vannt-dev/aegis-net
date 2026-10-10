#!/usr/bin/env bash
#
# Fetches the Rust DNS engine already built, for a checkout without the
# engine's source (rust/aegis_core is a private submodule). Run on macOS.
#
#   ./ios/fetch_prebuilt_engine.sh            # this checkout's version, else the latest release
#   ./ios/fetch_prebuilt_engine.sh v1.6.0     # a release by its tag
#
# Output: ios/Frameworks/AegisCore.xcframework, the same file
# ./ios/build_rust_ios.sh produces from the source.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/Frameworks"
RELEASES="https://github.com/vannt-dev/aegis-net/releases"
NAME="AegisCore.xcframework.zip"

if [ $# -ge 1 ]; then
  PLACES=("$RELEASES/download/$1")
else
  # develop runs ahead of the last release, so this version may not be out yet.
  VERSION="$(sed -n 's/^version:[[:space:]]*\([0-9.]*\).*/\1/p' "$SCRIPT_DIR/../pubspec.yaml" | head -1)"
  PLACES=("$RELEASES/download/v$VERSION" "$RELEASES/latest/download")
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for PLACE in "${PLACES[@]}"; do
  if curl -fsSL "$PLACE/$NAME" -o "$WORK/$NAME" &&
     curl -fsSL "$PLACE/$NAME.sha256" -o "$WORK/$NAME.sha256"; then
    EXPECTED="$(awk '{print $1}' "$WORK/$NAME.sha256")"
    ACTUAL="$(shasum -a 256 "$WORK/$NAME" | awk '{print $1}')"
    if [ "$EXPECTED" != "$ACTUAL" ]; then
      echo "❌ Checksum of $PLACE/$NAME is $ACTUAL, expected $EXPECTED" >&2
      exit 1
    fi
    rm -rf "$OUT_DIR/AegisCore.xcframework"
    mkdir -p "$OUT_DIR"
    ditto -x -k "$WORK/$NAME" "$OUT_DIR"
    echo "✅ $OUT_DIR/AegisCore.xcframework (from $PLACE)"
    exit 0
  fi
  echo "No prebuilt engine at $PLACE"
done

echo "❌ No release carries $NAME yet. Releases before 1.6.0 do not have it." >&2
exit 1
