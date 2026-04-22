#Requires -RunAsAdministrator
<#
.SYNOPSIS
    POWER SAVER MODE - Max power savings for normal work (coding, browsing, etc.)
    Estimated savings: ~55-75W from wall vs stock settings
.DESCRIPTION
    - Disables unused Intel X520-2 10GbE NICs (~31W savings)
    - Caps CPU to 99% (disables boost, ~15W savings)
    - Sets CPU min state to 5% (deeper idle)
    - SMU: PPT=45W, TDC=35A, EDC=50A, HTC=70C (firmware-level power cap)
    - GPU: Max 1000MHz, 825mV, power limit -10% via ADLX (~14W savings)
    - Aggressive core parking (50% max cores)
    - PCIe ASPM to maximum power savings
    - USB selective suspend enabled
    - HDD spin-down after 3 minutes
    - Display off after 5 minutes
.NOTES
    Run as Administrator. Revert with GamingMode.ps1
#>

param(
    [string]$NetioHost = "192.168.178.118",
    [string]$NetioUser = "netio",
    [string]$NetioPass = "netio"
)

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  POWER SAVER MODE - Activating..." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# --- Read BEFORE power ---
try {
    $cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${NetioUser}:${NetioPass}"))
    $before = Invoke-RestMethod -Uri "http://${NetioHost}/netio.json" -Headers @{Authorization="Basic $cred"}
    $pcBefore = ($before.Outputs | Where-Object { $_.Name -eq "PC RIG" }).Load
    Write-Host "[NETIO] Current power: ${pcBefore}W" -ForegroundColor Cyan
} catch {
    Write-Host "[NETIO] Could not read power socket (offline?)" -ForegroundColor Yellow
    $pcBefore = $null
}

# --- 1. Disable Intel X520-2 10GbE NICs ---
Write-Host "[NIC]   Disabling Intel X520-2 10GbE adapters..." -ForegroundColor White
$x520 = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*X520*" -and $_.Status -ne "Disabled" }
if ($x520) {
    $x520 | Disable-NetAdapter -Confirm:$false
    Write-Host "        Disabled $($x520.Count) adapter(s)" -ForegroundColor Green
} else {
    Write-Host "        Already disabled or not found" -ForegroundColor DarkGray
}

# --- 2. CPU: Cap to 99% (no boost), min state 5% ---
Write-Host "[CPU]   Capping max to 99% (no boost), min to 5%..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 99
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5

# --- 2b. SMU: Set aggressive PPT/TDC/EDC limits via ZenControl ---
$zenExe = "$PSScriptRoot\ZenControl\bin\Release\net8.0-windows\ZenControl.exe"
if (Test-Path $zenExe) {
    Write-Host "[SMU]   Setting PPT=45W, TDC=35A, EDC=50A, HTC=70C via SMU..." -ForegroundColor White
    & $zenExe ppt 45 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe tdc 35 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe edc 50 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe htc 70 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[SMU]   ZenControl not found at $zenExe - skipping SMU limits" -ForegroundColor Yellow
}

# --- 2c. GPU: Downclock + undervolt via GpuControl (ADLX) ---
$gpuExe = "$PSScriptRoot\GpuControl\GpuControl.exe"
if (Test-Path $gpuExe) {
    Write-Host "[GPU]   Setting max 1000MHz, 825mV, power limit -10% via ADLX..." -ForegroundColor White
    & $gpuExe powerlimit -10 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $gpuExe maxfreq 1000 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $gpuExe voltage 825 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[GPU]   GpuControl not found at $gpuExe - skipping GPU limits" -ForegroundColor Yellow
}

# --- 2d. Core parking: Aggressive (50% max cores) ---
Write-Host "[PARK]  Setting aggressive core parking (50% max cores)..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES 50
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 5

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
        $after = Invoke-RestMethod -Uri "http://${NetioHost}/netio.json" -Headers @{Authorization="Basic $cred"}
        $pcAfter = ($after.Outputs | Where-Object { $_.Name -eq "PC RIG" }).Load
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
