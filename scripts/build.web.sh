#!/usr/bin/env bash
# lusoapp — Web build script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")
BASE_HREF="${1:-/}"

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[BUILD-WEB]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD-WEB]\033[0m $*" >&2; }

if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter not found"
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    err "zip not found"
    exit 1
fi

log "lusoapp v$VERSION — Web Release Build"
log "======================================"
log "Base href: $BASE_HREF"

log "Getting dependencies..."
flutter pub get

log "Running analysis..."
flutter analyze --no-fatal-infos || true

log "Running tests..."
flutter test || { err "Tests failed"; exit 1; }

log "Building web bundle..."
flutter build web --release --base-href "$BASE_HREF"

WEB_OUT="$BUILD_DIR/web"
if [ -d "$WEB_OUT" ]; then
    mkdir -p "$DIST_DIR"
    ARCHIVE="$DIST_DIR/lusoapp-${VERSION}-web.zip"
    rm -f "$ARCHIVE"
    (
        cd "$WEB_OUT"
        zip -qr "$ARCHIVE" .
    )
    SIZE=$(du -h "$ARCHIVE" | cut -f1)
    log "Web archive: $ARCHIVE ($SIZE)"
    log "Deploy the contents over HTTPS if you need browser BLE/Web Bluetooth features."
else
    err "Web output folder not found: $WEB_OUT"
    exit 1
fi

log "======================================"
log "Web build complete: v$VERSION"