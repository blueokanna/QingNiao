#!/usr/bin/env pwsh
# Build signed release artifacts for Qingniao SMS.
#
# Usage (PowerShell):
#   $env:QINGNIAO_KEYSTORE_PATH  = "D:\keys\qingniao.jks"
#   $env:QINGNIAO_STORE_PASSWORD = "******"
#   $env:QINGNIAO_KEY_ALIAS      = "qingniao"
#   $env:QINGNIAO_KEY_PASSWORD   = "******"
#   powershell -File tool\build-release.ps1
#   powershell -File tool\build-release.ps1 -SplitAbi
#   powershell -File tool\build-release.ps1 -Bundle
#
# Without all four credentials android/app/build.gradle.kts rejects the build
# through verifyReleaseSigning, so no release artifact is signed with a debug key.

[CmdletBinding()]
param(
    [switch]$SplitAbi,
    [switch]$Bundle,
    [string]$OutDir = "build/app/outputs"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    $required = @(
        "QINGNIAO_KEYSTORE_PATH",
        "QINGNIAO_STORE_PASSWORD",
        "QINGNIAO_KEY_ALIAS",
        "QINGNIAO_KEY_PASSWORD"
    )
    $missing = @()
    foreach ($name in $required) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
            $missing += $name
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "Missing signing environment variables: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "See docs/RELEASE.md for setup." -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $env:QINGNIAO_KEYSTORE_PATH -PathType Leaf)) {
        Write-Host "Keystore not found: $($env:QINGNIAO_KEYSTORE_PATH)" -ForegroundColor Red
        exit 1
    }

    $flutterArgs = @("build")
    if ($Bundle) {
        $flutterArgs += @("appbundle", "--release")
    } else {
        $flutterArgs += @("apk", "--release")
        if ($SplitAbi) { $flutterArgs += "--split-per-abi" }
    }

    # The Flutter tool writes a plugin registrant into android/app/src/main/java
    # for debug builds; it includes the integration_test dev plugin, which is not
    # on the release compile classpath. Removing it lets the tool regenerate a
    # release-appropriate registrant (debug builds regenerate it automatically).
    $registrant = Join-Path $root "android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java"
    if (Test-Path -LiteralPath $registrant) {
        Remove-Item -LiteralPath $registrant -Force
        Write-Host "Removed stale GeneratedPluginRegistrant.java (integration_test dev plugin)" -ForegroundColor DarkGray
    }

    Write-Host "==> flutter $($flutterArgs -join ' ')" -ForegroundColor Cyan
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "flutter build failed (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }

    $patterns = @()
    if ($Bundle) {
        $patterns = @("appbundle/release/*.aab")
    } elseif ($SplitAbi) {
        $patterns = @("flutter-apk/*-release.apk")
    } else {
        $patterns = @("flutter-apk/app-release.apk")
    }

    $files = @()
    foreach ($pattern in $patterns) {
        $found = Get-ChildItem -Path (Join-Path $OutDir $pattern) -ErrorAction SilentlyContinue
        if ($found) { $files += $found }
    }
    if ($files.Count -eq 0) {
        Write-Host "Build finished but no artifact matched: $($patterns -join ', ')" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Artifacts:" -ForegroundColor Green
    foreach ($file in $files) {
        $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash
        $size = "{0:N1} MB" -f ($file.Length / 1MB)
        Write-Host ("  {0}  ({1})" -f $file.FullName, $size)
        Write-Host ("    SHA-256 {0}" -f $hash)
    }
    Write-Host ""
    Write-Host "Install: adb install -r <apk>" -ForegroundColor DarkGray
    exit 0
} finally {
    Pop-Location
}
