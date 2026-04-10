# lusoapp — Windows build script for CI and release packaging
param(
    [switch]$SkipTests,
    [switch]$ApkOnly,
    [switch]$WindowsOnly,
    [switch]$Web,
    [ValidateSet("x64", "arm64", "armv7")]
    [string]$LinuxArch,
    [string]$BaseHref = "/"
)

$ErrorActionPreference = "Stop"
$ProjectDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Push-Location $ProjectDir

function Log($msg)  { Write-Host "[BUILD] $msg" -ForegroundColor Green }
function Err($msg)  { Write-Host "[BUILD] $msg" -ForegroundColor Red }

function Convert-ToWslPath([string]$WinPath) {
    $normalized = $WinPath -replace '\\', '/'
    if ($normalized -match '^([A-Za-z]):/(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2]
        return "/mnt/$drive/$rest"
    }
    return $normalized
}

function Invoke-WslLinuxBuild([string]$Arch) {
    $wslCmd = Get-Command wsl -ErrorAction SilentlyContinue
    if (-not $wslCmd) {
        Err "WSL is not installed. Install WSL2 first: wsl --install"
        throw "WSL not available"
    }

    # Fast-fail on architecture mismatch before apt/package steps.
    $wslHostArch = (wsl bash -lc "uname -m" 2>$null).Trim()
    if (-not $wslHostArch) {
        Err "Unable to detect WSL host architecture (uname -m)."
        exit 1
    }
    if ($Arch -eq "arm64" -and $wslHostArch -notin @("aarch64", "arm64")) {
        Err "Host arch is $wslHostArch; ARM64 build requires ARM64 Linux (e.g., Raspberry Pi 64-bit)."
        exit 2
    }
    if ($Arch -eq "armv7" -and $wslHostArch -notin @("armv7l", "arm")) {
        Err "Host arch is $wslHostArch; ARMv7 build requires ARMv7 Linux."
        exit 2
    }
    if ($Arch -eq "x64" -and $wslHostArch -notin @("x86_64", "amd64")) {
        Err "Host arch is $wslHostArch; x64 build requires x86_64 Linux."
        exit 2
    }

    $wslProjectDir = Convert-ToWslPath $ProjectDir
    $linuxCmdTemplate = @'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Ensure required Linux desktop build dependencies are present.
if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update || true
    sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev curl git unzip xz-utils
else
    apt-get update || true
    apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev curl git unzip xz-utils
fi

host_arch="$(uname -m)"
case "__ARCH__" in
    x64)
        if [ "\$host_arch" != "x86_64" ] && [ "\$host_arch" != "amd64" ]; then
            echo "[BUILD] Host arch is \$host_arch, but x64 Linux build was requested." >&2
            exit 2
        fi
        ;;
    arm64)
        if [ "\$host_arch" != "aarch64" ] && [ "\$host_arch" != "arm64" ]; then
            echo "[BUILD] Host arch is \$host_arch; ARM64 build requires ARM64 Linux (e.g., Raspberry Pi 64-bit)." >&2
            exit 2
        fi
        ;;
    armv7)
        if [ "\$host_arch" != "armv7l" ] && [ "\$host_arch" != "arm" ]; then
            echo "[BUILD] Host arch is \$host_arch; ARMv7 build requires ARMv7 Linux." >&2
            exit 2
        fi
        ;;
esac

# Always use native Linux Flutter SDK inside WSL (never Windows /mnt/c one).
if [ ! -x "$HOME/flutter/bin/flutter" ]; then
    git clone https://github.com/flutter/flutter.git -b stable "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"
hash -r

cd '__WSL_PROJECT_DIR__'
flutter --suppress-analytics --version
flutter config --enable-linux-desktop >/dev/null
./scripts/run.sh build-linux-__ARCH__
'@

    $linuxCmd = $linuxCmdTemplate.Replace('__ARCH__', $Arch).Replace('__WSL_PROJECT_DIR__', $wslProjectDir)

    Log "Running Linux $Arch build in WSL..."
    wsl bash -lc $linuxCmd
    if ($LASTEXITCODE -eq 2) {
        Err "Architecture mismatch for Linux '$Arch' build."
        Err "Current WSL host is x86_64. Build ARM64/ARMv7 on matching ARM Linux host (e.g., Raspberry Pi)."
        exit 2
    }
    if ($LASTEXITCODE -ne 0) {
        Err "WSL Linux $Arch build failed (exit code $LASTEXITCODE)."
        exit $LASTEXITCODE
    }
}

# Parse version from pubspec
$VersionLine = Select-String -Path "pubspec.yaml" -Pattern "^version:" | Select-Object -First 1
$Version = ($VersionLine -split '\s+')[1].Trim("'", '"')

Log "lusoapp v$Version - Release Build"
Log "================================="

# Check Flutter
$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $LinuxArch -and -not $flutterCmd) {
    Err "Flutter not found in PATH"
    Pop-Location; exit 1
}

try {
    # Dedicated Linux build mode (delegates to WSL for ARM targets).
    if ($LinuxArch) {
        switch ($LinuxArch) {
            "x64" {
                Log "Linux x64 requested from Windows build script."
                Log "Use native Linux/WSL environment for linux desktop output."
                Invoke-WslLinuxBuild "x64"
            }
            "arm64" { Invoke-WslLinuxBuild "arm64" }
            "armv7" { Invoke-WslLinuxBuild "armv7" }
        }
        return
    }

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

    # Linux desktop (x86_64 and ARM64 for Raspberry Pi)
    if (-not $ApkOnly) {
        Log "Building Linux x86_64 desktop..."
        flutter build linux --release
        # Note: ARM64 cross-compilation requires Linux build machine
        # To build ARM64 from Windows, use WSL2 or build on actual ARM64 Linux machine

        $LinuxOut = Join-Path $ProjectDir "build\linux\x64\release\bundle"
        if (Test-Path $LinuxOut) {
            $archive = Join-Path $DistDir "mcapppt-${Version}-linux-x64.tar.gz"
            # Using PowerShell compression (note: tar.gz requires 7z or tar)
            if (Get-Command tar -ErrorAction SilentlyContinue) {
                pushd "$ProjectDir\build\linux\x64\release"
                tar -czf $archive bundle
                popd
                $size = (Get-Item $archive).Length / 1MB
                Log ("Linux x86_64 archive: $archive ({0:N1} MB)" -f $size)
            }
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
