#!/usr/bin/env bash
# MCAPPPT — MeshCore Companion App build & run scripts
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

log()  { echo -e "${GREEN}[MCAPPPT]${NC} $*"; }
warn() { echo -e "${YELLOW}[MCAPPPT]${NC} $*"; }
err()  { echo -e "${RED}[MCAPPPT]${NC} $*" >&2; }

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
    local arch="${1:-x64}"
    local host_arch
    host_arch="$(uname -m)"
    case "$arch" in
        x64|x86)
            log "Building Linux x86_64 desktop..."
            if [[ "$host_arch" != "x86_64" && "$host_arch" != "amd64" ]]; then
                err "Host architecture is $host_arch; x64 build requires x86_64 Linux host."
                exit 2
            fi
            flutter build linux --release
            log "Binary: build/linux/x64/release/bundle/"
            ;;
        arm64|aarch64)
            log "Building Linux ARM64 (Raspberry Pi)..."
            if [[ "$host_arch" != "aarch64" && "$host_arch" != "arm64" ]]; then
                err "Host architecture is $host_arch; ARM64 build requires an ARM64 Linux host."
                err "Use Raspberry Pi OS 64-bit or an ARM64 Linux runner."
                exit 2
            fi
            flutter build linux --release
            log "Binary: build/linux/arm64/release/bundle/"
            ;;
        armv7|arm)
            log "Building Linux ARMv7 (32-bit Raspberry Pi)..."
            if [[ "$host_arch" != "armv7l" && "$host_arch" != "arm" ]]; then
                err "Host architecture is $host_arch; ARMv7 build requires an ARMv7 Linux host."
                exit 2
            fi
            flutter build linux --release
            log "Binary: build/linux/arm/release/bundle/"
            ;;
        *)
            err "Unknown architecture: $arch"
            err "Use: x64, arm64, or armv7"
            exit 1
            ;;
    esac
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
        flutter create --org pt.meshcore --project-name mcapppt --platforms android,ios,linux,windows .
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
    build-linux) cmd_build_linux "$@" ;;
    build-linux-x64) cmd_build_linux x64 ;;
    build-linux-arm64) cmd_build_linux arm64 ;;
    build-linux-armv7) cmd_build_linux armv7 ;;
    build-win)  cmd_build_windows ;;
    test)       cmd_test ;;
    clean)      cmd_clean ;;
    get)        cmd_get ;;
    gen)        cmd_gen ;;
    analyze)    cmd_analyze ;;
    doctor)     cmd_doctor ;;
    setup)      cmd_setup ;;
    *)
        echo "MCAPPPT — MeshCore Companion App (Portugal)"
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
        echo "  build-linux [arch]   Build Linux desktop release (x64, arm64, armv7)"
        echo "  build-linux-x64      Build Linux x86_64 release"
        echo "  build-linux-arm64    Build Linux ARM64 (Raspberry Pi 4/5)"
        echo "  build-linux-armv7    Build Linux ARMv7 (32-bit Raspberry Pi)"
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
