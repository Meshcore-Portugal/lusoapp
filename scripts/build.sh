#!/usr/bin/env bash
# lusoapp — Dispatcher for platform-specific build scripts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[0;32m[BUILD]\033[0m $*"; }
err() { echo -e "\033[0;31m[BUILD]\033[0m $*" >&2; }
warn() { echo -e "\033[1;33m[BUILD]\033[0m $*"; }

run_script() {
    local script="$1"
    shift
    if [ -x "$script" ]; then
        "$script" "$@"
    else
        bash "$script" "$@"
    fi
}

run_windows_script() {
    local script="$SCRIPT_DIR/build.ps1"

    if command -v pwsh >/dev/null 2>&1; then
        pwsh -File "$script" "$@"
    elif command -v powershell >/dev/null 2>&1; then
        powershell -File "$script" "$@"
    else
        err "PowerShell not found (pwsh/powershell missing)"
        exit 1
    fi
}

TARGET="${1:-all}"
if [ "$#" -gt 0 ]; then
    shift
fi

case "$TARGET" in
    linux)
        run_script "$SCRIPT_DIR/build.linux.sh" "$@"
        ;;
    android)
        run_script "$SCRIPT_DIR/build.android.sh" "$@"
        ;;
    ios)
        run_script "$SCRIPT_DIR/build.ios.sh" "$@"
        ;;
    web)
        run_script "$SCRIPT_DIR/build.web.sh" "$@"
        ;;
    windows)
        run_windows_script "$@"
        ;;
    all)
        if [[ "$(uname -s)" == "Linux" ]]; then
            log "Running Linux build..."
            run_script "$SCRIPT_DIR/build.linux.sh" "$@"
        else
            warn "Skipping Linux build on non-Linux host"
        fi

        log "Running Android build..."
        run_script "$SCRIPT_DIR/build.android.sh" "$@"

        log "Running Web build..."
        run_script "$SCRIPT_DIR/build.web.sh" "$@"

        if [[ "$(uname -s)" == "Darwin" ]]; then
            log "Running iOS build..."
            run_script "$SCRIPT_DIR/build.ios.sh" "$@"
        else
            warn "Skipping iOS build on non-macOS host"
        fi
        ;;
    *)
        err "Unknown target: $TARGET"
        echo "Usage: $(basename "$0") [all|linux|android|ios|web|windows] [target args]"
        exit 1
        ;;
esac
