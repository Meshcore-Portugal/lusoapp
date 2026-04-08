#!/usr/bin/env bash
# lusoapp — Linux desktop build script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[BUILD-LINUX]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD-LINUX]\033[0m $*" >&2; }

if [[ "$(uname -s)" != "Linux" ]]; then
    err "Linux build requires a Linux host."
    exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter not found"
    exit 1
fi

log "lusoapp v$VERSION — Linux Release Build"
log "========================================"

log "Getting dependencies..."
flutter pub get

log "Running analysis..."
flutter analyze --no-fatal-infos || true

log "Running tests..."
flutter test || { err "Tests failed"; exit 1; }

log "Building Linux desktop..."
flutter build linux --release

LINUX_OUT="$BUILD_DIR/linux/x64/release/bundle"
if [ -d "$LINUX_OUT" ]; then
    mkdir -p "$DIST_DIR"
    ARCHIVE="$DIST_DIR/lusoapp-${VERSION}-linux-x64.tar.gz"
    tar -czf "$ARCHIVE" -C "$BUILD_DIR/linux/x64/release" bundle
    SIZE=$(du -h "$ARCHIVE" | cut -f1)
    log "Linux archive: $ARCHIVE ($SIZE)"
else
    err "Linux output folder not found: $LINUX_OUT"
    exit 1
fi

log "========================================"
log "Linux build complete: v$VERSION"
