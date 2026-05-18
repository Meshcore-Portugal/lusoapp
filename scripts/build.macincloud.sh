#!/usr/bin/env bash
# lusoapp — MacinCloud iOS build pipeline with icon generation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$BUILD_DIR/dist"
ICON_CONFIG="$PROJECT_DIR/flutter_launcher_icons_macincloud.yaml"
VERSION=$(grep 'version:' "$PROJECT_DIR/pubspec.yaml" | head -1 | awk '{print $2}' | tr -d "'\"")
BUILD_MODE="release"
RUN_CLEAN=true
RUN_ANALYZE=true
RUN_TESTS=true
RUN_ICONS=true
NO_CODESIGN=false
EXPORT_OPTIONS_PLIST=""

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[MACINCLOUD-BUILD]\033[0m $*"; }
err() { echo -e "\033[0;31m[MACINCLOUD-BUILD]\033[0m $*" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --debug                      Build debug iOS app bundle
  --release                    Build release iOS IPA (default)
  --skip-clean                 Skip flutter clean
  --skip-analyze               Skip flutter analyze
  --skip-tests                 Skip flutter test
  --skip-icons                 Skip icon generation
  --no-codesign                Build without code signing
  --export-options-plist PATH  Export options plist for IPA export
  -h, --help                   Show this help

Examples:
  ./scripts/build.macincloud.sh --release
  ./scripts/build.macincloud.sh --release --export-options-plist ios/ExportOptions.plist
  ./scripts/build.macincloud.sh --debug --skip-tests
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug)
            BUILD_MODE="debug"
            ;;
        --release)
            BUILD_MODE="release"
            ;;
        --skip-clean)
            RUN_CLEAN=false
            ;;
        --skip-analyze)
            RUN_ANALYZE=false
            ;;
        --skip-tests)
            RUN_TESTS=false
            ;;
        --skip-icons)
            RUN_ICONS=false
            ;;
        --no-codesign)
            NO_CODESIGN=true
            ;;
        --export-options-plist)
            if [[ $# -lt 2 ]]; then
                err "Missing value for --export-options-plist"
                exit 1
            fi
            EXPORT_OPTIONS_PLIST="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "Unknown argument: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    err "This script must run on macOS (MacinCloud)."
    exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter not found in PATH"
    exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
    err "xcodebuild not found. Install Xcode command line tools."
    exit 1
fi

if ! command -v pod >/dev/null 2>&1; then
    err "CocoaPods not found (pod command missing)."
    err "Install with: sudo gem install cocoapods"
    exit 1
fi

if [[ ! -d "$PROJECT_DIR/ios" ]]; then
    err "iOS platform folder not found. Run: flutter create --platforms=ios ."
    exit 1
fi

if [[ "$RUN_ICONS" == "true" ]] && [[ ! -f "$ICON_CONFIG" ]]; then
    err "Icon config file missing: $ICON_CONFIG"
    exit 1
fi

if [[ -n "$EXPORT_OPTIONS_PLIST" ]] && [[ ! -f "$EXPORT_OPTIONS_PLIST" ]]; then
    err "Export options plist not found: $EXPORT_OPTIONS_PLIST"
    exit 1
fi

log "lusoapp v$VERSION — MacinCloud iOS $BUILD_MODE pipeline"
log "============================================================="

if [[ "$RUN_CLEAN" == "true" ]]; then
    log "Cleaning previous build artifacts..."
    flutter clean
fi

log "Getting dependencies..."
flutter pub get

if [[ "$RUN_ICONS" == "true" ]]; then
    log "Generating launcher icons for Android + iOS..."
    dart run flutter_launcher_icons -f flutter_launcher_icons_macincloud.yaml
fi

log "Installing CocoaPods dependencies..."
(
    cd ios
    pod install --repo-update
)

if [[ "$RUN_ANALYZE" == "true" ]]; then
    log "Running static analysis..."
    flutter analyze --no-fatal-infos
fi

if [[ "$RUN_TESTS" == "true" ]]; then
    log "Running tests..."
    flutter test
fi

mkdir -p "$DIST_DIR"

if [[ "$BUILD_MODE" == "release" ]]; then
    log "Building signed iOS IPA..."
    CMD=(flutter build ipa --release)

    if [[ "$NO_CODESIGN" == "true" ]]; then
        CMD+=(--no-codesign)
    fi

    if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
        CMD+=("--export-options-plist=$EXPORT_OPTIONS_PLIST")
    fi

    "${CMD[@]}"

    IPA_PATH=$(find "$BUILD_DIR/ios/ipa" -maxdepth 1 -type f -name "*.ipa" | head -1 || true)

    if [[ -n "$IPA_PATH" ]] && [[ -f "$IPA_PATH" ]]; then
        OUT_IPA="$DIST_DIR/lusoapp-${VERSION}-ios-release.ipa"
        cp "$IPA_PATH" "$OUT_IPA"
        SIZE=$(du -h "$OUT_IPA" | cut -f1)
        log "IPA: $OUT_IPA ($SIZE)"
    else
        err "IPA file not found in $BUILD_DIR/ios/ipa"
        err "The build may have produced only an archive due to signing/export settings."
        exit 1
    fi
else
    log "Building debug iOS app bundle..."
    flutter build ios --debug

    APP_DIR="$BUILD_DIR/ios/iphoneos/Runner.app"
    if [[ -d "$APP_DIR" ]]; then
        OUT_APP="$DIST_DIR/lusoapp-${VERSION}-ios-debug.app.tar.gz"
        tar -czf "$OUT_APP" -C "$BUILD_DIR/ios/iphoneos" Runner.app
        SIZE=$(du -h "$OUT_APP" | cut -f1)
        log "App bundle archive: $OUT_APP ($SIZE)"
    else
        err "App bundle not found: $APP_DIR"
        exit 1
    fi
fi

log "============================================================="
log "MacinCloud build completed successfully."
