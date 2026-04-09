# lusoapp — Windows build script for CI and release packaging
param(
    [switch]$SkipTests,
    [switch]$ApkOnly,
    [switch]$WindowsOnly,
    [switch]$Web,
    [string]$BaseHref = "/"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $ProjectDir

function Log($msg)  { Write-Host "[BUILD] $msg" -ForegroundColor Green }
function Err($msg)  { Write-Host "[BUILD] $msg" -ForegroundColor Red }

# Parse version from pubspec
$VersionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
$Version = ($VersionLine -split '\s+')[1].Trim("'", '"')

Log "lusoapp v$Version - Release Build"
Log "================================="

# Check Flutter
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Err "Flutter not found in PATH"
    Pop-Location; exit 1
}

try {
    # Clean
    Log "Cleaning previous build..."
    flutter clean
    # Also clear stale CMake cache to prevent wrong install prefix (C:/Program Files/...)
    $cmakeCache = Join-Path $ProjectDir "build\windows\x64\CMakeCache.txt"
    if (Test-Path $cmakeCache) {
        Remove-Item -Path $cmakeCache -Force
        Log "Cleared stale CMake cache"
    }

    # Dependencies
    Log "Getting dependencies..."
    flutter pub get

    # Analyze
    Log "Running analysis..."
    flutter analyze --no-fatal-infos 2>$null
    if ($LASTEXITCODE -ne 0) { Log "Analysis warnings (non-fatal)" }

    # Test
    if (-not $SkipTests) {
        Log "Running tests..."
        flutter test
        if ($LASTEXITCODE -ne 0) { Err "Tests failed"; Pop-Location; exit 1 }
    }

    $DistDir = Join-Path $ProjectDir "build\dist"
    if (-not (Test-Path $DistDir)) { New-Item -ItemType Directory -Path $DistDir -Force | Out-Null }

    # Windows desktop
    if (-not $ApkOnly) {
        Log "Building Windows desktop..."
        flutter build windows --release

        $WinOut = Join-Path $ProjectDir "build\windows\x64\runner\Release"
        if (Test-Path $WinOut) {
            $archive = Join-Path $DistDir "lusoapp-${Version}-windows-x64.zip"
            Compress-Archive -Path "$WinOut\*" -DestinationPath $archive -Force
            $size = (Get-Item $archive).Length / 1MB
            Log ("Windows archive: $archive ({0:N1} MB)" -f $size)
        }
    }

    # Web — built when -Web is explicit, or when running a full build (no platform filter)
    $buildWeb = $Web -or (-not $ApkOnly -and -not $WindowsOnly)
    if ($buildWeb) {
        Log "Building web release (base-href='$BaseHref')..."
        flutter build web --release --base-href $BaseHref
        if ($LASTEXITCODE -ne 0) { Err "Web build failed"; Pop-Location; exit 1 }

        $WebOut = Join-Path $ProjectDir "build\web"
        if (Test-Path $WebOut) {
            $archive = Join-Path $DistDir "lusoapp-${Version}-web.zip"
            Compress-Archive -Path "$WebOut\*" -DestinationPath $archive -Force
            $size = (Get-Item $archive).Length / 1MB
            Log ("Web archive: $archive ({0:N1} MB)" -f $size)
            Log "  Deploy: unzip and serve build\web\ over HTTPS (Web Bluetooth requires HTTPS)"
        }
    }

    # Android APK
    if (-not $WindowsOnly) {
        $hasAndroid = (Test-Path env:ANDROID_HOME) -or (Get-Command adb -ErrorAction SilentlyContinue)
        if ($hasAndroid) {
            Log "Building Android APK..."
            flutter build apk --release

            $apk = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-release.apk"
            if (Test-Path $apk) {
                $dest = Join-Path $DistDir "lusoapp-${Version}.apk"
                Copy-Item $apk $dest -Force
                $size = (Get-Item $dest).Length / 1MB
                Log ("APK: $dest ({0:N1} MB)" -f $size)
            }

            Log "Building Android App Bundle..."
            flutter build appbundle --release

            $aab = Join-Path $ProjectDir "build\app\outputs\bundle\release\app-release.aab"
            if (Test-Path $aab) {
                $dest = Join-Path $DistDir "lusoapp-${Version}.aab"
                Copy-Item $aab $dest -Force
                Log "AAB: $dest"
            }
        } else {
            Log "Android SDK not found, skipping APK build"
        }
    }

    Log "================================="
    Log "Build complete: v$Version"
    Log "Artifacts: $DistDir"

    if (Test-Path $DistDir) {
        Get-ChildItem $DistDir | ForEach-Object {
            $s = $_.Length / 1MB
            Log ("  {0} ({1:N1} MB)" -f $_.Name, $s)
        }
    }
}
finally {
    Pop-Location
}
