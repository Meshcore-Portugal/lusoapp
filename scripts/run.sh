#!/usr/bin/env bash
# lusoapp — MeshCore Companion App build & run scripts
# Usage: ./scripts/run.sh [command]
#
# Commands:
#   run       Run on connected device (default)
#   build     Build release APK
#   build-aab Build release App Bundle
#   test      Run all tests
#   clean     Clean build artifacts
#   get       Get dependencies
#   gen       Run code generation (build_runner)
#   analyze   Run static analysis
#   doctor    Check Flutter environment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[lusoapp]${NC} $*"; }
warn() { echo -e "${YELLOW}[lusoapp]${NC} $*"; }
err()  { echo -e "${RED}[lusoapp]${NC} $*" >&2; }

check_flutter() {
    if ! command -v flutter &>/dev/null; then
        err "Flutter SDK not found in PATH"
        err "Install: https://flutter.dev/docs/get-started/install"
        exit 1
    fi
}

cmd_get() {
    log "Getting dependencies..."
    flutter pub get
}

cmd_gen() {
    log "Running code generation..."
    flutter pub run build_runner build --delete-conflicting-outputs
}

cmd_test() {
    log "Running tests..."
    flutter test --reporter expanded
}

cmd_analyze() {
    log "Running static analysis..."
    flutter analyze
}

cmd_run() {
    local flavor="${1:-debug}"
    log "Running app ($flavor)..."
    if [ "$flavor" = "release" ]; then
        flutter run --release
    elif [ "$flavor" = "profile" ]; then
        flutter run --profile
    else
        flutter run
    fi
}

cmd_build_apk() {
    log "Building release APK..."
    flutter build apk --release
    log "APK: build/app/outputs/flutter-apk/app-release.apk"
}

cmd_build_aab() {
    log "Building release App Bundle..."
    flutter build appbundle --release
    log "AAB: build/app/outputs/bundle/release/app-release.aab"
}

cmd_build_linux() {
    log "Building Linux desktop..."
    flutter build linux --release
    log "Binary: build/linux/x64/release/bundle/"
}

cmd_build_windows() {
    log "Building Windows desktop..."
    flutter build windows --release
    log "Binary: build/windows/x64/runner/Release/"
}

cmd_clean() {
    log "Cleaning build artifacts..."
    flutter clean
    log "Clean complete"
}

cmd_doctor() {
    log "Checking Flutter environment..."
    flutter doctor -v
}

cmd_setup() {
    log "Initial project setup..."
    check_flutter
    # Generate platform folders if missing
    if [ ! -d "android" ] || [ ! -d "ios" ]; then
        log "Generating platform folders..."
        flutter create --org pt.meshcore --project-name lusoapp --platforms android,ios,linux,windows .
    fi
    cmd_get
    log "Setup complete. Run: ./scripts/run.sh run"
}

# --- Main ---

check_flutter

COMMAND="${1:-run}"
shift 2>/dev/null || true

case "$COMMAND" in
    run)        cmd_run "$@" ;;
    build)      cmd_build_apk ;;
    build-apk)  cmd_build_apk ;;
    build-aab)  cmd_build_aab ;;
    build-linux) cmd_build_linux ;;
    build-win)  cmd_build_windows ;;
    test)       cmd_test ;;
    clean)      cmd_clean ;;
    get)        cmd_get ;;
    gen)        cmd_gen ;;
    analyze)    cmd_analyze ;;
    doctor)     cmd_doctor ;;
    setup)      cmd_setup ;;
    *)
        echo "lusoapp — MeshCore Companion App (Portugal)"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  setup        First-time project setup (generates platform folders)"
        echo "  run          Run on connected device (debug)"
        echo "  run release  Run in release mode"
        echo "  run profile  Run in profile mode"
        echo "  build        Build release APK"
        echo "  build-apk    Build release APK"
        echo "  build-aab    Build release App Bundle (Google Play)"
        echo "  build-linux  Build Linux desktop release"
        echo "  build-win    Build Windows desktop release"
        echo "  test         Run all tests"
        echo "  analyze      Run static analysis"
        echo "  clean        Clean build artifacts"
        echo "  get          Get/update dependencies"
        echo "  gen          Run code generation (build_runner)"
        echo "  doctor       Check Flutter environment"
        exit 1
        ;;
esac
