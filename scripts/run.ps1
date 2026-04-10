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

function Invoke-RunWeb {
    $port = if ($Args.Count -gt 0) { $Args[0] } else { "8080" }
    Log "Running app on web-server (port $port)..."
    Log "Open http://localhost:$port in your browser"
    flutter run -d web-server --web-port $port
}

function Invoke-BuildScript {
    param([hashtable]$BuildParams = @{})
    $buildScript = Join-Path $ProjectDir "scripts\build.ps1"
    if (-not (Test-Path $buildScript)) {
        throw "Build script not found: $buildScript"
    }
    $argText = ($BuildParams.GetEnumerator() | ForEach-Object {
        if ($_.Value -is [bool]) {
            if ($_.Value) { "-$($_.Key)" } else { "" }
        } else {
            "-$($_.Key) $($_.Value)"
        }
    } | Where-Object { $_ -ne "" }) -join ' '
    Log "Delegating build to scripts\build.ps1 $argText"
    & $buildScript @BuildParams
    if ($LASTEXITCODE -ne 0) {
        Err "build.ps1 failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
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
    Write-Host "  web            Run web-server (avoids browser launch issues)"
    Write-Host "  web <port>     Run web-server on custom port (default 8080)"
    Write-Host "  build          Build Android artifacts via scripts\build.ps1"
    Write-Host "  build-apk      Build Android artifacts via scripts\build.ps1"
    Write-Host "  build-aab      Build Android artifacts via scripts\build.ps1"
    Write-Host "  build-win      Build Windows desktop via scripts\build.ps1"
    Write-Host "  build-linux [arch]   Build Linux via scripts\build.ps1 (x64, arm64, armv7)"
    Write-Host "  build-linux-x64      Build Linux x86_64 via scripts\build.ps1"
    Write-Host "  build-linux-arm64    Build Linux ARM64 via WSL through scripts\build.ps1"
    Write-Host "  build-linux-armv7    Build Linux ARMv7 via WSL through scripts\build.ps1"
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
    Write-Host "  .\scripts\run.ps1 run           # Debug run (pick device)
  .\scripts\run.ps1 web           # Web server on port 8080
  .\scripts\run.ps1 web 3000      # Web server on port 3000"
    Write-Host "  .\scripts\run.ps1 build         # Release APK"
    Write-Host "  .\scripts\run.ps1 build-win     # Windows desktop"
    Write-Host ""
}

# --- Main ---

Test-Flutter

try {
    switch ($Command) {
        "run"              { Invoke-Run }
        "web"              { Invoke-RunWeb }
        "build"             { Invoke-BuildScript @{ ApkOnly = $true } }
        "build-apk"         { Invoke-BuildScript @{ ApkOnly = $true } }
        "build-aab"         { Invoke-BuildScript @{ ApkOnly = $true } }
        "build-win"         { Invoke-BuildScript @{ WindowsOnly = $true; SkipTests = $true } }
        "build-linux"       {
            $arch = if ($Args.Count -gt 0) { $Args[0] } else { "x64" }
            Invoke-BuildScript @{ LinuxArch = $arch }
        }
        "build-linux-x64"   { Invoke-BuildScript @{ LinuxArch = "x64" } }
        "build-linux-arm64" { Invoke-BuildScript @{ LinuxArch = "arm64" } }
        "build-linux-armv7" { Invoke-BuildScript @{ LinuxArch = "armv7" } }
        "test"             { Invoke-Test }
        "clean"            { Invoke-Clean }
        "get"              { Invoke-Get }
        "gen"              { Invoke-Gen }
        "analyze"          { Invoke-Analyze }
        "doctor"           { Invoke-Doctor }
        "setup"            { Invoke-Setup }
        "devices"          { Invoke-Devices }
        "help"             { Show-Help }
        default            { Show-Help }
    }
}
catch {
    Err $_.Exception.Message
    exit 1
}
finally {
    Pop-Location
}
