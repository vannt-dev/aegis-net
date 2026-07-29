#!/usr/bin/env bash
#
# Builds the Rust DNS engine (libaegis_core) as an XCFramework for the iOS
# PacketTunnel extension. Run on macOS with Xcode and the Rust toolchain.
#
#   ./ios/build_rust_ios.sh
#
# Output: ios/Frameworks/AegisCore.xcframework  (drag into Xcode, or add to the
# PacketTunnel target's "Frameworks and Libraries").
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CRATE_DIR="$(cd "$SCRIPT_DIR/../rust/aegis_core" && pwd)"
OUT_DIR="$SCRIPT_DIR/Frameworks"

cd "$CRATE_DIR"

rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
cargo build --release --target x86_64-apple-ios

# Combine the two simulator slices (Apple Silicon + Intel) into one fat lib.
SIM_DIR="target/ios-sim-universal/release"
mkdir -p "$SIM_DIR"
lipo -create \
  "target/aarch64-apple-ios-sim/release/libaegis_core.a" \
  "target/x86_64-apple-ios/release/libaegis_core.a" \
  -output "$SIM_DIR/libaegis_core.a"

rm -rf "$OUT_DIR/AegisCore.xcframework"
mkdir -p "$OUT_DIR"
xcodebuild -create-xcframework \
  -library "target/aarch64-apple-ios/release/libaegis_core.a" \
  -library "$SIM_DIR/libaegis_core.a" \
  -output "$OUT_DIR/AegisCore.xcframework"

echo "✅ Built $OUT_DIR/AegisCore.xcframework"
