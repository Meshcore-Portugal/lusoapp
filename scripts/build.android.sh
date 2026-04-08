#!/usr/bin/env bash
# lusoapp — Android build script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[BUILD-ANDROID]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD-ANDROID]\033[0m $*" >&2; }

if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter not found"
    exit 1
fi

if ! command -v adb >/dev/null 2>&1 && [ -z "${ANDROID_HOME:-}" ] && [ -z "${ANDROID_SDK_ROOT:-}" ]; then
    err "Android SDK not found (adb/ANDROID_HOME/ANDROID_SDK_ROOT)."
    exit 1
fi

log "lusoapp v$VERSION — Android Release Build"
log "=========================================="

log "Getting dependencies..."
flutter pub get

log "Running analysis..."
flutter analyze --no-fatal-infos || true

log "Running tests..."
flutter test || { err "Tests failed"; exit 1; }

mkdir -p "$DIST_DIR"

log "Building Android APK..."
flutter build apk --release

APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
if [ -f "$APK" ]; then
    OUT_APK="$DIST_DIR/lusoapp-${VERSION}.apk"
    cp "$APK" "$OUT_APK"
    SIZE=$(du -h "$OUT_APK" | cut -f1)
    log "APK: $OUT_APK ($SIZE)"
else
    err "APK not found: $APK"
    exit 1
fi

log "Building Android App Bundle..."
flutter build appbundle --release

AAB="$BUILD_DIR/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB" ]; then
    OUT_AAB="$DIST_DIR/lusoapp-${VERSION}.aab"
    cp "$AAB" "$OUT_AAB"
    SIZE=$(du -h "$OUT_AAB" | cut -f1)
    log "AAB: $OUT_AAB ($SIZE)"
else
    err "AAB not found: $AAB"
fi

log "=========================================="
log "Android build complete: v$VERSION"
