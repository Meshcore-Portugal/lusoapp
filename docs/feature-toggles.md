# Feature Toggles and Release Presets

This project supports build-time app feature toggles using Flutter `--dart-define` values.

The toggle logic is centralized in:
- `lib/config/feature_toggles.dart`

## Quick Start

Use one preset define for most releases:
- `FEATURE_PRESET=legacy` (default if omitted)
- `FEATURE_PRESET=minimal`
- `FEATURE_PRESET=full`

### PowerShell presets

- Minimal:

```powershell
./scripts/build_release_minimal.ps1
```

- Full:

```powershell
./scripts/build_release_full.ps1
```

- Build AAB instead of APK:

```powershell
./scripts/build_release_minimal.ps1 -Target appbundle
./scripts/build_release_full.ps1 -Target appbundle
```

- Dry run:

```powershell
./scripts/build_release_minimal.ps1 -DryRun
./scripts/build_release_full.ps1 -DryRun
```

### Bash presets (Linux/CI)

- Minimal:

```bash
bash ./scripts/build_release_minimal.sh
```

- Full:

```bash
bash ./scripts/build_release_full.sh
```

- Build AAB instead of APK:

```bash
bash ./scripts/build_release_minimal.sh appbundle
bash ./scripts/build_release_full.sh appbundle
```

- Dry run:

```bash
bash ./scripts/build_release_minimal.sh --dry-run
bash ./scripts/build_release_full.sh --dry-run
```

## Preset Definitions

### `legacy` (default)
- Topology: off
- Plan333: on
- Telemetry: on
- RX Log: on
- Noise Floor: on
- Data Export: on
- Event: off

### `minimal`
- Topology: off
- Plan333: on
- Telemetry: on
- RX Log: off
- Noise Floor: off
- Data Export: off
- Event: off

### `full`
- Topology: on
- Plan333: on
- Telemetry: on
- RX Log: on
- Noise Floor: on
- Data Export: on
- Event: on

## Per-App Overrides

Per-app defines always override preset defaults.

Available flags:
- `FEATURE_APP_TOPOLOGY`
- `FEATURE_APP_PLAN333`
- `FEATURE_APP_TELEMETRY`
- `FEATURE_APP_RXLOG`
- `FEATURE_APP_NOISEFLOOR`
- `FEATURE_APP_DATAEXPORT`
- `FEATURE_APP_EVENT`

Example: minimal preset, but force RX Log on:

```bash
flutter build apk --release \
  --dart-define=FEATURE_PRESET=minimal \
  --dart-define=FEATURE_APP_RXLOG=true
```

Example (PowerShell):

```powershell
flutter build apk --release `
  --dart-define=FEATURE_PRESET=minimal `
  --dart-define=FEATURE_APP_RXLOG=true
```

## Runtime Effect

When a feature is disabled:
- Its tile is hidden from the Apps screen.
- Its route is not registered in the router.

This means disabled modules are both hidden in UI and blocked from deep-link/navigation access.

## Recommended Release Flow

1. Pick preset (`minimal` or `full`).
2. Run script in dry-run mode and verify flags.
3. Build APK/AAB.
4. Sanity-check Apps tab in release build.
5. If needed, add one or more per-app overrides.
