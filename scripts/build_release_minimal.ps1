param(
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "apk",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $ProjectDir

function Log($msg) { Write-Host "[RELEASE-MINIMAL] $msg" -ForegroundColor Cyan }

try {
    $args = @("build", $Target, "--release")

    # Minimal profile defaults are resolved in `feature_toggles.dart`
    # via `FEATURE_PRESET=minimal`.
    $defines = @(
        "FEATURE_PRESET=minimal"
    )

    foreach ($d in $defines) {
        $args += "--dart-define=$d"
    }

    Log "Target: $Target"
    Log "Feature profile: minimal"
    foreach ($d in $defines) { Log "  $d" }

    if ($DryRun) {
        Log "Dry-run only. Command: flutter $($args -join ' ')"
        exit 0
    }

    & flutter @args
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Log "Build finished successfully."
}
finally {
    Pop-Location
}
