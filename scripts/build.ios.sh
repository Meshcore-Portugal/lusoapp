#!/usr/bin/env bash
# lusoapp — iOS build script (macOS only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[BUILD-IOS]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD-IOS]\033[0m $*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    err "iOS builds require macOS with Xcode."
    exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter not found"
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    err "Xcode command line tools not found (xcodebuild missing)"
    exit 1
fi

if [ ! -d "$PROJECT_DIR/ios" ]; then
    err "iOS platform folder not found. Run: flutter create --platforms=ios ."
    exit 1
fi

log "lusoapp v$VERSION — iOS Release Build (no codesign)"
log "===================================================="

log "Getting dependencies..."
flutter pub get

if command -v pod >/dev/null 2>&1; then
    log "Installing CocoaPods dependencies..."
    (
        cd ios
        pod install
    )
else
    err "CocoaPods not found (pod command missing)."
    err "Install with: brew install cocoapods"
    exit 1
fi

log "Building iOS IPA (no codesign)..."
flutter build ipa --release --no-codesign

mkdir -p "$DIST_DIR"
IPA_PATH=$(find "$BUILD_DIR/ios/ipa" -maxdepth 1 -type f -name "*.ipa" | head -1 || true)

if [ -n "$IPA_PATH" ] && [ -f "$IPA_PATH" ]; then
    OUT_IPA="$DIST_DIR/lusoapp-${VERSION}-ios.ipa"
    cp "$IPA_PATH" "$OUT_IPA"
    SIZE=$(du -h "$OUT_IPA" | cut -f1)
    log "IPA: $OUT_IPA ($SIZE)"
else
    err "IPA file not found in $BUILD_DIR/ios/ipa"
    err "Build finished, but output path may differ."
fi

log "===================================================="
log "iOS build complete: v$VERSION"
