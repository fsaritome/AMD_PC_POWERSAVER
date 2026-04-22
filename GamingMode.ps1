#Requires -RunAsAdministrator
<#
.SYNOPSIS
    GAMING MEGA MODE - Maximum performance, all limits removed
    Restores full CPU boost, disables power saving, re-enables NICs if needed
.DESCRIPTION
    - Re-enables Intel X520-2 10GbE NICs (if you need them)
    - CPU max state 100% (full Precision Boost to 4.8GHz)
    - CPU min state 100% (all cores stay at max - prevents frametime spikes)
    - SMU: Restores stock PPT=142W, TDC=95A, EDC=140A, HTC=90C
    - Core parking disabled (all cores active)
    - PCIe ASPM off (no link power saving = lowest latency)
    - USB selective suspend disabled (no input device dropouts)
    - HDD spin-down disabled (no stutter from HDD wake)
    - Display timeout disabled (no screen off mid-session)
.NOTES
    Run as Administrator. Revert with PowerSaver.ps1
#>

param(
    [string]$NetioHost = "192.168.178.118",
    [string]$NetioUser = "netio",
    [string]$NetioPass = "netio",
    [switch]$EnableX520
)

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  GAMING MEGA MODE - Activating..." -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
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

# --- 1. Re-enable Intel X520-2 (only with -EnableX520 flag) ---
if ($EnableX520) {
    Write-Host "[NIC]   Re-enabling Intel X520-2 10GbE adapters..." -ForegroundColor White
    $x520 = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like "*X520*" -and $_.Status -eq "Disabled" }
    if ($x520) {
        $x520 | Enable-NetAdapter -Confirm:$false
        Write-Host "        Enabled $($x520.Count) adapter(s)" -ForegroundColor Green
    } else {
        Write-Host "        Already enabled or not found" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[NIC]   X520-2 stays disabled (use -EnableX520 to re-enable, +31W)" -ForegroundColor DarkGray
}

# --- 2. CPU: Full boost unlocked, min state 100% (park no cores) ---
Write-Host "[CPU]   Unlocking full boost (100% max), pinning min to 100%..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100

# --- 2b. SMU: Restore stock PPT/TDC/EDC limits via ZenControl ---
$zenExe = "$PSScriptRoot\ZenControl\bin\Release\net8.0-windows\ZenControl.exe"
if (Test-Path $zenExe) {
    Write-Host "[SMU]   Restoring stock PPT=142W, TDC=95A, EDC=140A, HTC=90C..." -ForegroundColor White
    & $zenExe ppt 142 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe tdc 95 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe edc 140 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe htc 90 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[SMU]   ZenControl not found at $zenExe - skipping SMU restore" -ForegroundColor Yellow
}

# --- 2c. Core parking: Disabled (all cores active) ---
Write-Host "[PARK]  Disabling core parking (all cores active)..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES 100
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100

# --- 3. PCIe ASPM: Off (lowest latency) ---
Write-Host "[PCIe]  Disabling ASPM (lowest latency)..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0

# --- 4. USB selective suspend: Disabled (no input dropout) ---
Write-Host "[USB]   Disabling selective suspend..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0

# --- 5. HDD spin-down: Never ---
Write-Host "[HDD]   Disabling spin-down..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0

# --- 6. Display off: Never ---
Write-Host "[DISP]  Display timeout disabled..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 0

# --- Apply ---
powercfg /setactive SCHEME_CURRENT
Write-Host ""
Write-Host "[OK]    All settings applied!" -ForegroundColor Green

# --- Read AFTER power ---
if ($pcBefore) {
    Start-Sleep -Seconds 5
    try {
        $after = Invoke-RestMethod -Uri "http://${NetioHost}/netio.json" -Headers @{Authorization="Basic $cred"}
        $pcAfter = ($after.Outputs | Where-Object { $_.Name -eq "PC RIG" }).Load
        $diff = $pcAfter - $pcBefore
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "  BEFORE: ${pcBefore}W  ->  AFTER: ${pcAfter}W" -ForegroundColor Cyan
        Write-Host "  EXTRA:  +${diff}W (performance overhead)" -ForegroundColor Yellow
        Write-Host "========================================" -ForegroundColor Red
    } catch {
        Write-Host "[NETIO] Could not read after-power" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "PERFORMANCE TIPS:" -ForegroundColor Yellow
Write-Host "  - Close Discord, Steam overlay, Chrome if not needed" -ForegroundColor DarkGray
Write-Host "  - NGENUITY uses significant CPU - minimize if possible" -ForegroundColor DarkGray
Write-Host "  - GPU will draw 250-300W+ under gaming load" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To revert, run: .\PowerSaver.ps1" -ForegroundColor DarkGray
Write-Host ""
