#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TARGET="apk"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    apk|appbundle)
      TARGET="$1"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "[RELEASE-FULL] Unknown argument: $1" >&2
      echo "Usage: ./scripts/build_release_full.sh [apk|appbundle] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

log() { echo "[RELEASE-FULL] $*"; }

cd "$PROJECT_DIR"

# Full profile defaults are resolved in `feature_toggles.dart`
# via `FEATURE_PRESET=full`.
DEFINES=(
  "FEATURE_PRESET=full"
)

CMD=(flutter build "$TARGET" --release)
for d in "${DEFINES[@]}"; do
  CMD+=("--dart-define=$d")
done

log "Target: $TARGET"
log "Feature profile: full"
for d in "${DEFINES[@]}"; do
  log "  $d"
done

if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry-run only. Command: ${CMD[*]}"
  exit 0
fi

"${CMD[@]}"
log "Build finished successfully."
