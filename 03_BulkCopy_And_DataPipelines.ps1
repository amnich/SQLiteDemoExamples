<#
.SYNOPSIS
    03_BulkCopy_And_DataPipelines.ps1 — Streaming PowerShell Objects into SQLite with BulkCopy
.DESCRIPTION
    Demonstrates:
      1. Converting live PowerShell objects into a System.Data.DataTable using Out-DataTable
      2. Ingesting hundreds/thousands of records in milliseconds with Invoke-SqliteBulkCopy
      3. Aggregating and querying ingested data directly with SQL
      4. Cross-platform compatibility (Windows PowerShell 5.1 and PowerShell 7+)
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\pipeline_demo.db'
}

#region 1. Import Module & Prepare Database
Import-Module (Join-Path $PSScriptRoot 'SQLiteHelper.psd1') -Force

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " SQLite PowerShell Example 03: Bulk Copy & Pipelines    " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target Database: $DatabasePath`n" -ForegroundColor Gray

Connect-SqliteDb -DataSource $DatabasePath -EnableWal | Out-Null
#endregion

#region 2. Create Schema for Ingested Data
Write-Host "[1/3] Creating 'SystemServices' table..." -ForegroundColor Yellow

$createTableSql = @"
DROP TABLE IF EXISTS SystemServices;
CREATE TABLE SystemServices (
    ServiceName  TEXT PRIMARY KEY,
    DisplayName  TEXT,
    Status       TEXT NOT NULL,
    StartType    TEXT,
    CapturedAt   TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_services_status ON SystemServices(Status);
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $createTableSql | Out-Null
Write-Host "  -> Table 'SystemServices' initialized.`n" -ForegroundColor Green
#endregion

#region 3. Capture PowerShell Objects and Bulk Copy
Write-Host "[2/3] Collecting Windows Services and Bulk-Copying to SQLite..." -ForegroundColor Yellow

$sw = [System.Diagnostics.Stopwatch]::StartNew()

# Collect system services and normalize properties to simple strings
$services = Get-Service | Select-Object @{ Name = 'ServiceName'; Expression = { $_.Name } },
                                        @{ Name = 'DisplayName'; Expression = { $_.DisplayName } },
                                        @{ Name = 'Status';      Expression = { $_.Status.ToString() } },
                                        @{ Name = 'StartType';   Expression = { $_.StartType.ToString() } },
                                        @{ Name = 'CapturedAt';  Expression = { (Get-Date -Format 'o') } }

$serviceCount = $services.Count
Write-Host "  -> Gathered $serviceCount service objects from system." -ForegroundColor Gray

# Convert PowerShell objects to System.Data.DataTable
$dataTable = $services | Out-DataTable

# Stream DataTable into SQLite via Bulk Copy (single transaction under the hood)
Invoke-SqliteBulkCopy -DataTable $dataTable -DataSource $DatabasePath -Table 'SystemServices' -ConflictClause Replace -NotifyAfter 0 -Force

$sw.Stop()
Write-Host "  -> Ingested $serviceCount records in $($sw.ElapsedMilliseconds) ms! ($([Math]::Round($serviceCount / ($sw.ElapsedMilliseconds / 1000), 1)) rows/sec)`n" -ForegroundColor Green
#endregion

#region 4. Analytical SQL Queries on Ingested Data
Write-Host "[3/3] Running Analytical Queries on Ingested Data..." -ForegroundColor Yellow

Write-Host "--- Service Count by Status ---" -ForegroundColor Cyan
$statusSummary = Invoke-SqliteCmd -DataSource $DatabasePath -Query @"
SELECT Status, COUNT(*) AS TotalServices
FROM SystemServices
GROUP BY Status
ORDER BY TotalServices DESC;
"@
$statusSummary | Format-Table -AutoSize

Write-Host "--- Running Windows & Network Services (Sample) ---" -ForegroundColor Cyan
$sampleQuery = @"
SELECT ServiceName, DisplayName, StartType
FROM SystemServices
WHERE Status = 'Running' AND (ServiceName LIKE '%Net%' OR ServiceName LIKE '%Win%')
ORDER BY ServiceName
LIMIT 5;
"@
$sample = Invoke-SqliteCmd -DataSource $DatabasePath -Query $sampleQuery
$sample | Format-Table -AutoSize

Write-Host "Demo 03 (Bulk Copy & Pipelines) completed successfully!" -ForegroundColor Cyan
#endregion
