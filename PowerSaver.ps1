#Requires -RunAsAdministrator
<#
.SYNOPSIS
    POWER SAVER MODE - Max power savings for normal work (coding, browsing, etc.)
.DESCRIPTION
    All tuning values are loaded from config.json (copy config.example.json to get started).
    - Disables NICs matching configured pattern
    - Caps CPU max/min state (disables boost)
    - SMU: Sets PPT/TDC/EDC/HTC limits via ZenControl
    - GPU: Sets power limit, max frequency, voltage via GpuControl
    - Aggressive core parking, ASPM max, USB suspend, HDD/display timeouts
.NOTES
    Run as Administrator. Revert with GamingMode.ps1
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json"
)

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] config.json not found at $ConfigPath" -ForegroundColor Red
    Write-Host "        Copy config.example.json to config.json and fill in your values." -ForegroundColor Yellow
    exit 1
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$netio = $cfg.netio
$hw = $cfg.hardware
$p = $cfg.profiles.powerSaver

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  POWER SAVER MODE - Activating..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# --- Read BEFORE power ---
$pcBefore = $null
$cred = $null
if ($netio.host) {
    try {
        $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($netio.user):$($netio.pass)"))
        $before = Invoke-RestMethod -Uri "http://$($netio.host)/netio.json" -Headers @{Authorization="Basic $cred"}
        $pcBefore = ($before.Outputs | Where-Object { $_.Name -eq $netio.outputName }).Load
        Write-Host "[NETIO] Current power: ${pcBefore}W" -ForegroundColor Cyan
    } catch {
        Write-Host "[NETIO] Could not read power socket (offline?)" -ForegroundColor Yellow
    }
} else {
    Write-Host "[NETIO] Not configured (set netio.host in config.json)" -ForegroundColor DarkGray
}

# --- 1. Disable NICs matching pattern ---
if ($hw.nicPattern) {
    Write-Host "[NIC]   Disabling adapters matching '$($hw.nicPattern)'..." -ForegroundColor White
    $nics = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like $hw.nicPattern -and $_.Status -ne "Disabled" }
    if ($nics) {
        $nics | Disable-NetAdapter -Confirm:$false
        Write-Host "        Disabled $($nics.Count) adapter(s)" -ForegroundColor Green
    } else {
        Write-Host "        Already disabled or not found" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[NIC]   No NIC pattern configured - skipping" -ForegroundColor DarkGray
}

# --- 2. CPU: Cap max/min state ---
Write-Host "[CPU]   Capping max to $($p.cpuMax)%, min to $($p.cpuMin)%..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $p.cpuMax
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $p.cpuMin

# --- 2b. SMU: Set PPT/TDC/EDC/HTC limits via ZenControl ---
$zenExe = "$PSScriptRoot\ZenControl\bin\Release\net8.0-windows\ZenControl.exe"
if (Test-Path $zenExe) {
    Write-Host "[SMU]   Setting PPT=$($p.ppt)W, TDC=$($p.tdc)A, EDC=$($p.edc)A, HTC=$($p.htc)C via SMU..." -ForegroundColor White
    & $zenExe ppt $p.ppt 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe tdc $p.tdc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe edc $p.edc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe htc $p.htc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[SMU]   ZenControl not found at $zenExe - skipping SMU limits" -ForegroundColor Yellow
}

# --- 2c. GPU: Downclock + undervolt via GpuControl (ADLX) ---
$gpuExe = "$PSScriptRoot\GpuControl\GpuControl.exe"
if (Test-Path $gpuExe) {
    Write-Host "[GPU]   Setting power limit $($p.gpuPowerLimit)%, max $($p.gpuMaxFreq)MHz, $($p.gpuVoltage)mV via ADLX..." -ForegroundColor White
    & $gpuExe powerlimit $p.gpuPowerLimit 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $gpuExe maxfreq $p.gpuMaxFreq 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $gpuExe voltage $p.gpuVoltage 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[GPU]   GpuControl not found at $gpuExe - skipping GPU limits" -ForegroundColor Yellow
}

# --- 2d. Core parking ---
Write-Host "[PARK]  Setting core parking (max $($p.coreParkMax)%, min $($p.coreParkMin)%)..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES $p.coreParkMax
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $p.coreParkMin

# --- 3. PCIe ASPM: Maximum power savings ---
Write-Host "[PCIe]  Setting ASPM to maximum savings..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 2

# --- 4. USB selective suspend: Enabled ---
Write-Host "[USB]   Enabling selective suspend..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 1

# --- 5. HDD spin-down: 3 minutes ---
Write-Host "[HDD]   Spin-down after 3 minutes..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 180

# --- 6. Display off: 5 minutes ---
Write-Host "[DISP]  Display off after 5 minutes..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 300

# --- Apply ---
powercfg /setactive SCHEME_CURRENT
Write-Host ""
Write-Host "[OK]    All settings applied!" -ForegroundColor Green

# --- Read AFTER power (wait for settling) ---
if ($pcBefore) {
    Start-Sleep -Seconds 5
    try {
        $after = Invoke-RestMethod -Uri "http://$($netio.host)/netio.json" -Headers @{Authorization="Basic $cred"}
        $pcAfter = ($after.Outputs | Where-Object { $_.Name -eq $netio.outputName }).Load
        $saved = $pcBefore - $pcAfter
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  BEFORE: ${pcBefore}W  ->  AFTER: ${pcAfter}W" -ForegroundColor Cyan
        Write-Host "  SAVED:  ${saved}W" -ForegroundColor $(if ($saved -gt 0) { "Green" } else { "Yellow" })
        Write-Host "========================================" -ForegroundColor Green
    } catch {
        Write-Host "[NETIO] Could not read after-power" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "To revert, run: .\GamingMode.ps1" -ForegroundColor DarkGray
Write-Host ""
