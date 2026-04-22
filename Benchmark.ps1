<#
.SYNOPSIS
    Standalone power benchmark - measures idle wattage for both profiles with screen off.
.DESCRIPTION
    1. Beep to signal start (turn off screen)
    2. Apply PowerSaver profile (elevated)
    3. Wait for settle, then measure idle power for 1 minute
    4. Apply GamingMode profile (elevated)
    5. Wait for settle, then measure idle power for 1 minute
    6. Long beep when done (turn screen back on)
    All results logged to benchmark_results.txt
.NOTES
    Run from non-admin terminal. UAC prompts will appear for each profile switch.
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [int]$SettleSeconds = 15,
    [int]$MeasureSeconds = 60,
    [int]$SampleIntervalSeconds = 5
)

$logFile = "$PSScriptRoot\benchmark_results.txt"

# --- Load config ---
if (-not (Test-Path $ConfigPath)) {
    Write-Host "[ERROR] config.json not found at $ConfigPath" -ForegroundColor Red
    exit 1
}
$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$netio = $cfg.netio
$cred = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($netio.user):$($netio.pass)"))

function Read-Power {
    try {
        $r = Invoke-RestMethod -Uri "http://$($netio.host)/netio.json" -Headers @{Authorization="Basic $cred"}
        $w = ($r.Outputs | Where-Object { $_.Name -eq $netio.outputName }).Load
        return [double]$w
    } catch {
        return $null
    }
}

function Measure-IdlePower {
    param([string]$Label, [int]$Duration, [int]$Interval)

    Write-Host "`n  Measuring idle power for ${Duration}s (sampling every ${Interval}s)..." -ForegroundColor White
    $samples = @()
    $elapsed = 0
    while ($elapsed -lt $Duration) {
        $w = Read-Power
        if ($null -ne $w) {
            $samples += $w
            Write-Host "    [$elapsed s] ${w}W" -ForegroundColor DarkGray
        }
        Start-Sleep -Seconds $Interval
        $elapsed += $Interval
    }

    if ($samples.Count -gt 0) {
        $avg = [math]::Round(($samples | Measure-Object -Average).Average, 1)
        $min = [math]::Round(($samples | Measure-Object -Minimum).Minimum, 1)
        $max = [math]::Round(($samples | Measure-Object -Maximum).Maximum, 1)
        Write-Host "  Result: avg=${avg}W  min=${min}W  max=${max}W  (${($samples.Count)} samples)" -ForegroundColor Cyan
        return @{ Label=$Label; Avg=$avg; Min=$min; Max=$max; Samples=$samples.Count; Raw=$samples }
    } else {
        Write-Host "  No samples collected!" -ForegroundColor Red
        return $null
    }
}

# === START ===
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  POWER BENCHMARK - $timestamp" -ForegroundColor Yellow
Write-Host "  Settle: ${SettleSeconds}s  Measure: ${MeasureSeconds}s" -ForegroundColor Yellow
Write-Host "============================================" -ForegroundColor Yellow

# Beep ascending = start
[Console]::Beep(1000, 300); [Console]::Beep(1200, 300); [Console]::Beep(1400, 300)
Write-Host "`n>>> Turn off your screen NOW! (10s grace period) <<<`n" -ForegroundColor Yellow
Start-Sleep -Seconds 10

# --- 1. PowerSaver ---
Write-Host "========================================" -ForegroundColor Green
Write-Host "  PHASE 1: PowerSaver" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "  Applying PowerSaver profile (elevated)..." -ForegroundColor White
Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\PowerSaver.ps1`""
Write-Host "  Profile applied. Settling for ${SettleSeconds}s..." -ForegroundColor DarkGray
Start-Sleep -Seconds $SettleSeconds

$psResult = Measure-IdlePower -Label "PowerSaver" -Duration $MeasureSeconds -Interval $SampleIntervalSeconds

# --- 2. GamingMode ---
Write-Host "`n========================================" -ForegroundColor Red
Write-Host "  PHASE 2: GamingMode" -ForegroundColor Red
Write-Host "========================================" -ForegroundColor Red

Write-Host "  Applying GamingMode profile (elevated)..." -ForegroundColor White
Start-Process powershell -Verb RunAs -Wait -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\GamingMode.ps1`""
Write-Host "  Profile applied. Settling for ${SettleSeconds}s..." -ForegroundColor DarkGray
Start-Sleep -Seconds $SettleSeconds

$gmResult = Measure-IdlePower -Label "GamingMode" -Duration $MeasureSeconds -Interval $SampleIntervalSeconds

# === RESULTS ===
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  BENCHMARK RESULTS (screen off, idle)" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

$report = @()
$report += "Power Benchmark Results - $timestamp"
$report += "Screen: OFF | Settle: ${SettleSeconds}s | Measure: ${MeasureSeconds}s | Interval: ${SampleIntervalSeconds}s"
$report += "--------------------------------------------"

if ($psResult) {
    $line = "PowerSaver:  avg=$($psResult.Avg)W  min=$($psResult.Min)W  max=$($psResult.Max)W  ($($psResult.Samples) samples)"
    Write-Host "  $line" -ForegroundColor Green
    $report += $line
    $report += "  Raw: $($psResult.Raw -join ', ')W"
}
if ($gmResult) {
    $line = "GamingMode:  avg=$($gmResult.Avg)W  min=$($gmResult.Min)W  max=$($gmResult.Max)W  ($($gmResult.Samples) samples)"
    Write-Host "  $line" -ForegroundColor Red
    $report += $line
    $report += "  Raw: $($gmResult.Raw -join ', ')W"
}
if ($psResult -and $gmResult) {
    $diff = [math]::Round($gmResult.Avg - $psResult.Avg, 1)
    $pct = [math]::Round(($diff / $gmResult.Avg) * 100, 1)
    $line = "Difference:  ${diff}W (${pct}% savings with PowerSaver)"
    Write-Host "  $line" -ForegroundColor Yellow
    $report += $line
}

$report += ""
$report | Out-File -FilePath $logFile -Append -Encoding utf8
Write-Host "`n  Results appended to: $logFile" -ForegroundColor DarkGray

# Long beep = done
Write-Host "`n>>> DONE - Turn on your screen! <<<`n" -ForegroundColor Green
[Console]::Beep(800, 1500)
