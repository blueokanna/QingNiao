#!/usr/bin/env pwsh
# End-to-end smoke test for qingniao-sync.
#
# Builds the server, starts it on a local port, then:
#   health -> create space -> join with pairing code -> rotate pairing code
#   -> push one envelope -> pull it as the second device -> verify counts.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File server-rs\scripts\smoke.ps1
#   powershell ... -Port 8899 -SkipBuild

[CmdletBinding()]
param(
    [int]$Port = 8790,
    [switch]$SkipBuild,
    [string]$DataDir = "build/verification"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$serverDir = Join-Path $root "server-rs"
$exe = Join-Path $serverDir "target/debug/qingniao-sync.exe"
if (-not (Test-Path $exe) -and (Test-Path (Join-Path $serverDir "target/debug/qingniao-sync"))) {
    $exe = Join-Path $serverDir "target/debug/qingniao-sync"
}

$dataDirPath = Join-Path $root $DataDir
New-Item -ItemType Directory -Force -Path $dataDirPath | Out-Null
$data = Join-Path $dataDirPath ("sync-smoke-{0}.json" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)))

if (-not $SkipBuild) {
    Write-Host "==> cargo build (debug)" -ForegroundColor Cyan
    Push-Location $serverDir
    try {
        & cargo build --offline
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}
if (-not (Test-Path $exe)) { throw "server binary not found: $exe" }

$base = "http://127.0.0.1:$Port"
$log = Join-Path $dataDirPath "sync-smoke-server.log"
$proc = Start-Process -FilePath $exe -ArgumentList @("--bind", "127.0.0.1:$Port", "--data", $data) `
    -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru
try {
    $healthy = $false
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        try {
            $health = Invoke-RestMethod "$base/v1/health" -TimeoutSec 2
            if ($health.ok) { $healthy = $true; break }
        } catch { }
    }
    if (-not $healthy) { throw "server did not become healthy; see $log" }
    Write-Host "PASS health (protocol=$($health.protocol))" -ForegroundColor Green

    $keyA = "A" * 43
    $keyB = "B" * 43
    $created = Invoke-RestMethod -Method Post -Uri "$base/v1/spaces" -ContentType "application/json" `
        -Body (@{ name = "Device A"; publicKey = $keyA } | ConvertTo-Json)
    if ($created.devices.Count -ne 1 -or [string]::IsNullOrWhiteSpace($created.pairingCode)) {
        throw "unexpected create-space response"
    }
    Write-Host "PASS create space ($($created.spaceId.Substring(0, 8))..., 1 device)" -ForegroundColor Green

    $joined = Invoke-RestMethod -Method Post -Uri "$base/v1/spaces/join" -ContentType "application/json" `
        -Body (@{ pairingCode = $created.pairingCode; name = "Device B"; publicKey = $keyB } | ConvertTo-Json)
    if ($joined.devices.Count -ne 2 -or -not [string]::IsNullOrEmpty($joined.pairingCode)) {
        throw "unexpected join response"
    }
    Write-Host "PASS join with pairing code (2 devices, code consumed)" -ForegroundColor Green

    $authA = @{ Authorization = "Bearer $($created.token)" }
    $authB = @{ Authorization = "Bearer $($joined.token)" }

    $rotated = Invoke-RestMethod -Method Post -Uri "$base/v1/pairing-code" -Headers $authA `
        -ContentType "application/json" -Body "{}"
    if ([string]::IsNullOrWhiteSpace($rotated.pairingCode)) { throw "pairing code not rotated" }
    Write-Host "PASS rotate pairing code" -ForegroundColor Green

    $pushed = Invoke-RestMethod -Method Post -Uri "$base/v1/envelopes" -Headers $authA -ContentType "application/json" `
        -Body (@{
            to                 = $joined.deviceId
            ephemeralPublicKey = "E" * 43
            nonce              = "N" * 16
            ciphertext         = "Q" * 88
            messageId          = "smoke-1"
        } | ConvertTo-Json)
    if ($pushed.id -lt 1 -or $pushed.cursor -lt 1) { throw "unexpected push response" }
    Write-Host "PASS push envelope (id=$($pushed.id))" -ForegroundColor Green

    $pulled = Invoke-RestMethod -Uri "$base/v1/envelopes?after=0&wait=0" -Headers $authB
    if ($pulled.envelopes.Count -ne 1) { throw "expected 1 envelope, got $($pulled.envelopes.Count)" }
    if ($pulled.envelopes[0].messageId -ne "smoke-1") { throw "messageId round-trip failed" }
    if ($pulled.envelopes[0].ciphertext.Length -ne 88) { throw "ciphertext round-trip failed" }
    Write-Host "PASS pull envelope as device B (cursor=$($pulled.cursor))" -ForegroundColor Green

    $self = Invoke-RestMethod -Uri "$base/v1/envelopes?after=0&wait=0" -Headers $authA
    if ($self.envelopes.Count -ne 0) { throw "sender should not pull its own envelope" }
    Write-Host "PASS sender does not receive its own envelope" -ForegroundColor Green

    $final = Invoke-RestMethod "$base/v1/health"
    Write-Host ("PASS health after: spaces={0} devices={1} envelopes={2}" -f $final.spaces, $final.devices, $final.envelopes) -ForegroundColor Green
    Write-Host ""
    Write-Host "ALL PASS" -ForegroundColor Green
    exit 0
} catch {
    Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if (Test-Path $log) { Get-Content $log -Tail 20 | ForEach-Object { Write-Host "  $_" } }
    exit 1
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $data -ErrorAction SilentlyContinue
}
