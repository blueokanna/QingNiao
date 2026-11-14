#!/usr/bin/env pwsh
# Non-interactive device checks for Qingniao SMS (debug build).
#
# Verifies: adb device, package installed, default SMS role, runtime permissions,
# radio/airplane state, notification permission, and (debug builds) the promoted
# notification capability via the DEBUG_ACCESS broadcast. Real inbound SMS still
# needs another phone; the script prints the remaining manual step.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\verify-device.ps1
#   powershell ... -Serial 3B164H019D900000

[CmdletBinding()]
param(
    [string]$Serial = "",
    [string]$Package = "com.blue.qingniao"
)

$ErrorActionPreference = "Continue"
$script:pass = 0
$script:warn = 0
$script:fail = 0

function Write-Result([string]$state, [string]$message) {
    switch ($state) {
        "PASS" { $script:pass++; Write-Host "PASS  $message" -ForegroundColor Green }
        "WARN" { $script:warn++; Write-Host "WARN  $message" -ForegroundColor Yellow }
        default { $script:fail++; Write-Host "FAIL  $message" -ForegroundColor Red }
    }
}

function Invoke-Adb([string[]]$Arguments) {
    if ($Serial) { & adb -s $Serial @Arguments 2>&1 } else { & adb @Arguments 2>&1 }
}

$devices = (& adb devices 2>&1) | Select-String "device$"
if (-not $devices) {
    Write-Result "FAIL" "no adb device connected"
    exit 1
}
if (-not $Serial) {
    $Serial = (($devices[0] -split "\s+")[0])
}
Write-Result "PASS" "device $Serial"

$model = (Invoke-Adb @("shell", "getprop", "ro.product.model") | Out-String).Trim()
$sdk = (Invoke-Adb @("shell", "getprop", "ro.build.version.sdk") | Out-String).Trim()
$rom = (Invoke-Adb @("shell", "getprop", "ro.build.version.release") | Out-String).Trim()
Write-Host "      model=$model android=$rom api=$sdk" -ForegroundColor DarkGray

$path = (Invoke-Adb @("shell", "pm", "path", $Package) | Out-String).Trim()
if ($path -match "package:") {
    Write-Result "PASS" "$Package installed"
} else {
    Write-Result "FAIL" "$Package not installed"
    exit 1
}

$holders = (Invoke-Adb @("shell", "cmd", "role", "get-role-holders", "android.app.role.SMS") | Out-String)
if ($holders -match [regex]::Escape($Package)) {
    Write-Result "PASS" "default SMS role held"
} else {
    Write-Result "FAIL" "default SMS role NOT held (holders: $($holders.Trim()))"
}

$dump = (Invoke-Adb @("shell", "dumpsys", "package", $Package) | Out-String)
foreach ($permission in @("READ_SMS", "SEND_SMS", "RECEIVE_SMS", "RECEIVE_MMS", "POST_NOTIFICATIONS")) {
    if ($dump -match "$permission\s*:\s*granted=true") {
        Write-Result "PASS" "permission $permission"
    } else {
        Write-Result "FAIL" "permission $permission not granted"
    }
}
if ($dump -match "POST_PROMOTED_NOTIFICATIONS") {
    Write-Result "PASS" "declares POST_PROMOTED_NOTIFICATIONS"
} else {
    Write-Result "WARN" "POST_PROMOTED_NOTIFICATIONS not declared (no fluid cloud)"
}

$airplane = (Invoke-Adb @("shell", "settings", "get", "global", "airplane_mode_on") | Out-String).Trim()
if ($airplane -eq "1") {
    Write-Result "WARN" "airplane mode is ON - real SMS/MMS cannot be tested"
} else {
    $telephony = (Invoke-Adb @("shell", "dumpsys", "telephony.registry") | Out-String)
    $inService = ([regex]::Matches($telephony, "mVoiceRegState=0\(IN_SERVICE\)")).Count
    if ($inService -gt 0) {
        Write-Result "PASS" "$inService SIM(s) in service"
    } else {
        Write-Result "WARN" "no SIM reports IN_SERVICE"
    }
}

$notifications = (Invoke-Adb @("shell", "dumpsys", "notification", "--noredact") | Out-String)
if ($notifications -match "pkg=$([regex]::Escape($Package))") {
    Write-Result "PASS" "has posted notifications"
} else {
    Write-Result "WARN" "no active Qingniao notifications"
}
if ($notifications -match "PROMOTED_ONGOING") {
    Write-Result "PASS" "promoted (fluid cloud) notification present"
} else {
    Write-Result "WARN" "no PROMOTED_ONGOING flag right now"
}

& adb -s $Serial logcat -c 2>&1 | Out-Null
Invoke-Adb @("shell", "am", "broadcast", "-n", "$Package/.DebugNotifyReceiver", "-a", "$Package.DEBUG_ACCESS") | Out-Null
Start-Sleep -Seconds 2
$debugLog = (Invoke-Adb @("logcat", "-d", "-s", "QingniaoDebug") | Out-String)
if ($debugLog -match "access=\{(.*)\}") {
    Write-Result "PASS" "debug self-check: $($Matches[1])"
} elseif ($debugLog -match "QingniaoDebug") {
    Write-Result "WARN" "debug receiver ran but no access line"
} else {
    Write-Result "WARN" "debug receiver unavailable (release build or disabled)"
}

Write-Host ""
Write-Host "Remaining manual step (real inbound wake):" -ForegroundColor Cyan
Write-Host "  1. turn off airplane mode, keep cellular on"
Write-Host "  2. from another phone send an SMS to this SIM"
Write-Host "  3. expect a notification/fluid cloud capsule within ~1s, even if the app was killed"
Write-Host ""
Write-Host ("Summary: PASS={0} WARN={1} FAIL={2}" -f $script:pass, $script:warn, $script:fail)
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
