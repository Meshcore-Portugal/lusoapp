# MCAPPPT — MeshCore Companion App build & run scripts
# Usage: .\scripts\run.ps1 [command]
#
# Commands:
#   run       Run on connected device (default)
#   build     Build release APK
#   build-aab Build release App Bundle
#   test      Run all tests
#   clean     Clean build artifacts
#   get       Get dependencies
#   gen       Run code generation
#   analyze   Run static analysis
#   doctor    Check Flutter environment

param(
    [Parameter(Position = 0)]
    [string]$Command = "run",

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Args
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $ProjectDir

function Log($msg)  { Write-Host "[MCAPPPT] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[MCAPPPT] $msg" -ForegroundColor Yellow }
function Err($msg)  { Write-Host "[MCAPPPT] $msg" -ForegroundColor Red }

function Test-Flutter {
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if (-not $flutterCmd) {
        # Check common install locations
        $candidates = @(
            "$env:USERPROFILE\flutter\bin\flutter.bat",
            "$env:USERPROFILE\dev\flutter\bin\flutter.bat",
            "C:\flutter\bin\flutter.bat",
            "C:\src\flutter\bin\flutter.bat",
            "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
        )
        foreach ($path in $candidates) {
            if (Test-Path $path) {
                $dir = Split-Path -Parent $path
                Log "Found Flutter at $dir — adding to PATH for this session"
                $env:PATH = "$dir;$env:PATH"
                return
            }
        }
        Err "Flutter SDK not found in PATH"
        Err "Install: https://flutter.dev/docs/get-started/install"
        Err ""
        Err "After installing, either:"
        Err "  1. Add Flutter to system PATH, or"
        Err "  2. Set FLUTTER_HOME environment variable"
        Pop-Location
        exit 1
    }
}

function Invoke-Get {
    Log "Getting dependencies..."
    flutter pub get
}

function Invoke-Gen {
    Log "Running code generation..."
    flutter pub run build_runner build --delete-conflicting-outputs
}

function Invoke-Test {
    Log "Running tests..."
    flutter test --reporter expanded
}

function Invoke-Analyze {
    Log "Running static analysis..."
    flutter analyze
}

function Invoke-Run {
    $flavor = if ($Args.Count -gt 0) { $Args[0] } else { "debug" }
    Log "Running app ($flavor)..."
    switch ($flavor) {
        "release" { flutter run --release }
        "profile" { flutter run --profile }
        default   { flutter run }
    }
}

function Invoke-BuildApk {
    Log "Building release APK..."
    flutter build apk --release
    $apk = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-release.apk"
    Log "APK: $apk"
    if (Test-Path $apk) {
        $size = (Get-Item $apk).Length / 1MB
        Log ("Size: {0:N1} MB" -f $size)
    }
}

function Invoke-BuildAab {
    Log "Building release App Bundle..."
    flutter build appbundle --release
    Log "AAB: build\app\outputs\bundle\release\app-release.aab"
}

function Invoke-BuildWindows {
    Log "Building Windows desktop..."
    flutter build windows --release
    $outDir = Join-Path $ProjectDir "build\windows\x64\runner\Release"
    Log "Binary: $outDir"
    if (Test-Path $outDir) {
        $exe = Get-ChildItem $outDir -Filter "*.exe" | Select-Object -First 1
        if ($exe) { Log "Executable: $($exe.Name)" }
    }
}

function Invoke-BuildLinux {
    Log "Building Linux desktop..."
    flutter build linux --release
    Log "Binary: build/linux/x64/release/bundle/"
}

function Invoke-Clean {
    Log "Cleaning build artifacts..."
    flutter clean
    Log "Clean complete"
}

function Invoke-Doctor {
    Log "Checking Flutter environment..."
    flutter doctor -v
}

function Invoke-Setup {
    Log "Initial project setup..."
    Test-Flutter

    # Generate platform folders if missing
    if (-not (Test-Path "android") -or -not (Test-Path "windows")) {
        Log "Generating platform folders..."
        flutter create --org pt.meshcore --project-name mcapppt --platforms android,ios,windows,linux .
    }

    Invoke-Get
    Log "Setup complete. Run: .\scripts\run.ps1 run"
}

function Invoke-Devices {
    Log "Connected devices:"
    flutter devices
}

function Show-Help {
    Write-Host ""
    Write-Host "MCAPPPT - MeshCore Companion App (Portugal)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\scripts\run.ps1 <command>" -ForegroundColor White
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  setup          First-time project setup (generates platform folders)"
    Write-Host "  run            Run on connected device (debug)"
    Write-Host "  run release    Run in release mode"
    Write-Host "  run profile    Run in profile mode"
    Write-Host "  build          Build release APK"
    Write-Host "  build-apk      Build release APK"
    Write-Host "  build-aab      Build release App Bundle (Google Play)"
    Write-Host "  build-win      Build Windows desktop release"
    Write-Host "  build-linux    Build Linux desktop release"
    Write-Host "  test           Run all tests"
    Write-Host "  analyze        Run static analysis"
    Write-Host "  clean          Clean build artifacts"
    Write-Host "  get            Get/update dependencies"
    Write-Host "  gen            Run code generation (build_runner)"
    Write-Host "  devices        List connected devices"
    Write-Host "  doctor         Check Flutter environment"
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\scripts\run.ps1 setup        # First time"
    Write-Host "  .\scripts\run.ps1 run           # Debug run"
    Write-Host "  .\scripts\run.ps1 build         # Release APK"
    Write-Host "  .\scripts\run.ps1 build-win     # Windows desktop"
    Write-Host ""
}

# --- Main ---

Test-Flutter

try {
    switch ($Command) {
        "run"         { Invoke-Run }
        "build"       { Invoke-BuildApk }
        "build-apk"  { Invoke-BuildApk }
        "build-aab"  { Invoke-BuildAab }
        "build-win"  { Invoke-BuildWindows }
        "build-linux" { Invoke-BuildLinux }
        "test"        { Invoke-Test }
        "clean"       { Invoke-Clean }
        "get"         { Invoke-Get }
        "gen"         { Invoke-Gen }
        "analyze"     { Invoke-Analyze }
        "doctor"      { Invoke-Doctor }
        "setup"       { Invoke-Setup }
        "devices"     { Invoke-Devices }
        "help"        { Show-Help }
        default       { Show-Help }
    }
}
finally {
    Pop-Location
}
