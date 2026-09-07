<#
.SYNOPSIS
    Run-All-Demos.ps1 — Master Test & Demonstration Runner for PowerShell SQLite Example
.DESCRIPTION
    Executes all example scripts sequentially:
      01_Basic_CRUD.ps1
      02_Transactions_And_Performance.ps1
      03_BulkCopy_And_DataPipelines.ps1
      04_Advanced_Queries_And_Reporting.ps1
      05_Database_Maintenance.ps1
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [switch]$KeepData
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=================================================================" -ForegroundColor Magenta
Write-Host "      POWERSHELL SQLITE COMPREHENSIVE SUITE RUNNER              " -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Magenta
Write-Host "PowerShell Version : $($PSVersionTable.PSVersion)" -ForegroundColor Cyan
Write-Host "PowerShell Edition : $($PSVersionTable.PSEdition)" -ForegroundColor Cyan
Write-Host "Runtime Bitness    : $([IntPtr]::Size * 8)-bit" -ForegroundColor Cyan
Write-Host "Operating System   : $([System.Environment]::OSVersion.VersionString)" -ForegroundColor Cyan
Write-Host "Current Directory  : $PSScriptRoot`n" -ForegroundColor Cyan

# Clean previous database files unless -KeepData is specified
$dataFolder = Join-Path $PSScriptRoot 'data'
if (-not $KeepData -and (Test-Path $dataFolder)) {
    Write-Host "Resetting test database folder '$dataFolder'..." -ForegroundColor Gray
    Get-ChildItem -Path $dataFolder -Include *.db, *.db-shm, *.db-wal -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

$scripts = @(
    '01_Basic_CRUD.ps1',
    '02_Transactions_And_Performance.ps1',
    '03_BulkCopy_And_DataPipelines.ps1',
    '04_Advanced_Queries_And_Reporting.ps1',
    '05_Database_Maintenance.ps1',
    '06_EventLog_Search_Benchmark.ps1'
)

$results = @()
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($scriptName in $scripts) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path $scriptPath)) {
        Write-Warning "Script not found: $scriptPath"
        continue
    }

    Write-Host "`n-----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ">>> EXECUTING: $scriptName" -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------------------" -ForegroundColor DarkGray

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $status = 'PASSED'
    $errorMsg = ''

    try {
        & $scriptPath
    }
    catch {
        $status = 'FAILED'
        $errorMsg = $_.Exception.Message
        Write-Host "`n[ERROR] $scriptName failed: $errorMsg" -ForegroundColor Red
    }
    finally {
        $sw.Stop()
    }

    $results += [PSCustomObject]@{
        Script   = $scriptName
        Duration = "$([Math]::Round($sw.Elapsed.TotalSeconds, 2))s"
        Status   = $status
        Details  = if ($errorMsg) { $errorMsg } else { 'Completed successfully' }
    }
}

$totalSw.Stop()

Write-Host "`n=================================================================" -ForegroundColor Magenta
Write-Host "                     EXECUTION SUMMARY                          " -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Magenta
$results | Format-Table -AutoSize

$failedCount = ($results | Where-Object { $_.Status -eq 'FAILED' }).Count
if ($failedCount -eq 0) {
    Write-Host "ALL DEMOS PASSED SUCCESSFULLY in $([Math]::Round($totalSw.Elapsed.TotalSeconds, 2))s!`n" -ForegroundColor Green
}
else {
    Write-Host "ATTENTION: $failedCount demos failed. Review output above.`n" -ForegroundColor Red
}
