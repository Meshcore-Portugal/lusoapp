param(
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "apk",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $ProjectDir

function Log($msg) { Write-Host "[RELEASE-FULL] $msg" -ForegroundColor Green }

try {
    $args = @("build", $Target, "--release")

    # Full profile defaults are resolved in `feature_toggles.dart`
    # via `FEATURE_PRESET=full`.
    $defines = @(
        "FEATURE_PRESET=full"
    )

    foreach ($d in $defines) {
        $args += "--dart-define=$d"
    }

    Log "Target: $Target"
    Log "Feature profile: full"
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
