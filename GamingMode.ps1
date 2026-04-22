#Requires -RunAsAdministrator
<#
.SYNOPSIS
    GAMING MEGA MODE - Maximum performance, all limits removed
.DESCRIPTION
    All tuning values are loaded from config.json (copy config.example.json to get started).
    - Re-enables NICs matching configured pattern (only with -EnableX520 flag)
    - CPU max/min state to configured gaming values (full boost)
    - SMU: Restores stock PPT/TDC/EDC/HTC via ZenControl
    - GPU: Reset to factory defaults via GpuControl
    - Core parking disabled, ASPM off, USB suspend off, no timeouts
.NOTES
    Run as Administrator. Revert with PowerSaver.ps1
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [switch]$EnableX520
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
$g = $cfg.profiles.gamingMode

$ErrorActionPreference = "Continue"
Write-Host ""
Write-Host "========================================" -ForegroundColor Red
Write-Host "  GAMING MEGA MODE - Activating..." -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red
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

# --- 1. Re-enable NICs (only with -EnableX520 flag) ---
if ($EnableX520 -and $hw.nicPattern) {
    Write-Host "[NIC]   Re-enabling adapters matching '$($hw.nicPattern)'..." -ForegroundColor White
    $nics = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like $hw.nicPattern -and $_.Status -eq "Disabled" }
    if ($nics) {
        $nics | Enable-NetAdapter -Confirm:$false
        Write-Host "        Enabled $($nics.Count) adapter(s)" -ForegroundColor Green
    } else {
        Write-Host "        Already enabled or not found" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[NIC]   NICs stay disabled (use -EnableX520 to re-enable)" -ForegroundColor DarkGray
}

# --- 2. CPU: Full boost, min state to configured values ---
Write-Host "[CPU]   Unlocking full boost ($($g.cpuMax)% max), pinning min to $($g.cpuMin)%..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX $g.cpuMax
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $g.cpuMin

# --- 2b. SMU: Restore stock PPT/TDC/EDC/HTC via ZenControl ---
$zenExe = "$PSScriptRoot\ZenControl\bin\Release\net8.0-windows\ZenControl.exe"
if (Test-Path $zenExe) {
    Write-Host "[SMU]   Restoring PPT=$($g.ppt)W, TDC=$($g.tdc)A, EDC=$($g.edc)A, HTC=$($g.htc)C..." -ForegroundColor White
    & $zenExe ppt $g.ppt 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe tdc $g.tdc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe edc $g.edc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
    & $zenExe htc $g.htc 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[SMU]   ZenControl not found at $zenExe - skipping SMU restore" -ForegroundColor Yellow
}

# --- 2c. GPU: Reset to factory defaults via GpuControl (ADLX) ---
$gpuExe = "$PSScriptRoot\GpuControl\GpuControl.exe"
if (Test-Path $gpuExe) {
    Write-Host "[GPU]   Resetting GPU to factory defaults (full boost)..." -ForegroundColor White
    & $gpuExe default 2>$null | ForEach-Object { Write-Host "        $_" -ForegroundColor DarkCyan }
} else {
    Write-Host "[GPU]   GpuControl not found at $gpuExe - skipping GPU reset" -ForegroundColor Yellow
}

# --- 2d. Core parking: Disabled ---
Write-Host "[PARK]  Setting core parking (max $($g.coreParkMax)%, min $($g.coreParkMin)%)..." -ForegroundColor White
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMAXCORES $g.coreParkMax
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES $g.coreParkMin

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
        $after = Invoke-RestMethod -Uri "http://$($netio.host)/netio.json" -Headers @{Authorization="Basic $cred"}
        $pcAfter = ($after.Outputs | Where-Object { $_.Name -eq $netio.outputName }).Load
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
