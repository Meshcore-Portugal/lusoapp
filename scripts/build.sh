#!/usr/bin/env bash
# MCAPPPT — Linux/macOS build script for CI and release packaging
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[BUILD]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD]\033[0m $*" >&2; }

if ! command -v flutter &>/dev/null; then
    err "Flutter not found"; exit 1
fi

log "MCAPPPT v$VERSION — Release Build"
log "================================="

# Clean
log "Cleaning previous build..."
flutter clean

# Dependencies
log "Getting dependencies..."
flutter pub get

# Analyze
log "Running analysis..."
flutter analyze --no-fatal-infos || true

# Test
log "Running tests..."
flutter test || { err "Tests failed"; exit 1; }

# Build targets based on OS
case "$(uname -s)" in
    Linux*)
        log "Building Linux desktop..."
        flutter build linux --release
        
        LINUX_OUT="$BUILD_DIR/linux/x64/release/bundle"
        if [ -d "$LINUX_OUT" ]; then
            ARCHIVE="$BUILD_DIR/mcapppt-${VERSION}-linux-x64.tar.gz"
            tar -czf "$ARCHIVE" -C "$BUILD_DIR/linux/x64/release" bundle
            log "Linux archive: $ARCHIVE"
        fi
        ;;
    Darwin*)
        log "Building macOS desktop..."
        flutter build macos --release
        ;;
esac

# Always try APK if Android SDK is available
if command -v adb &>/dev/null || [ -n "${ANDROID_HOME:-}" ]; then
    log "Building Android APK..."
    flutter build apk --release
    
    APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
    if [ -f "$APK" ]; then
        SIZE=$(du -h "$APK" | cut -f1)
        log "APK: $APK ($SIZE)"
        # Copy to dist folder
        mkdir -p "$BUILD_DIR/dist"
        cp "$APK" "$BUILD_DIR/dist/mcapppt-${VERSION}.apk"
    fi
    
    log "Building Android App Bundle..."
    flutter build appbundle --release
fi

log "================================="
log "Build complete: v$VERSION"
