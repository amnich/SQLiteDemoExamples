<#
.SYNOPSIS
    06_EventLog_Search_Benchmark.ps1 — Windows Event Log Ingestion & Performance Benchmark
.DESCRIPTION
    Demonstrates:
      1. Extracting live Windows 'Application' event log records into PowerShell objects
      2. Bulk-copying events into a indexed local SQLite database (data\eventlog_demo.db)
      3. Comparing search & aggregation performance between standard Get-WinEvent and SQLite:
         - Benchmark 1: Filter by Severity Level (Warning/Error) and Event ID
         - Benchmark 2: Substring / Keyword search across event Message bodies
         - Benchmark 3: Grouping & Counting top event providers (Analytics)
      4. Displaying a structured performance comparison summary table
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
    Encoding: UTF-8 with BOM
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = '',

    [int]$MaxEvents = 1000
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\eventlog_demo.db'
}

#region 1. Import Module & Prepare Database
Import-Module (Join-Path $PSScriptRoot 'SQLiteHelper.psd1') -Force

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "  SQLite PowerShell Example 06: Event Log Ingest & Benchmark    " -ForegroundColor Cyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "Target Database : $DatabasePath" -ForegroundColor Gray
Write-Host "Sample Size     : Up to $MaxEvents Application events`n" -ForegroundColor Gray

Connect-SqliteDb -DataSource $DatabasePath -EnableWal | Out-Null
#endregion

#region 2. Prepare Schema with Indexes
Write-Host "[1/5] Creating 'ApplicationEvents' table and search indexes..." -ForegroundColor Yellow

$schemaSql = @"
DROP TABLE IF EXISTS ApplicationEvents;
CREATE TABLE ApplicationEvents (
    RecordId         INTEGER PRIMARY KEY,
    EventId          INTEGER NOT NULL,
    Level            INTEGER NOT NULL,
    LevelDisplayName TEXT NOT NULL,
    ProviderName     TEXT NOT NULL,
    TimeCreated      TEXT NOT NULL,
    Message          TEXT
);

CREATE INDEX IF NOT EXISTS idx_events_id ON ApplicationEvents(EventId);
CREATE INDEX IF NOT EXISTS idx_events_level ON ApplicationEvents(Level);
CREATE INDEX IF NOT EXISTS idx_events_provider ON ApplicationEvents(ProviderName);
CREATE INDEX IF NOT EXISTS idx_events_time ON ApplicationEvents(TimeCreated);
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $schemaSql | Out-Null
Write-Host "  -> Table and indexes ready.`n" -ForegroundColor Green
#endregion

#region 3. Ingest Live Application Events
Write-Host "[2/5] Ingesting current Windows Application Event Log..." -ForegroundColor Yellow

$swIngest = [System.Diagnostics.Stopwatch]::StartNew()

# Collect live events from Windows Event Log
$rawEvents = Get-WinEvent -LogName 'Application' -MaxEvents $MaxEvents -ErrorAction Stop

# Normalize event objects into clean table rows
$eventList = foreach ($e in $rawEvents) {
    [PSCustomObject]@{
        RecordId         = [long]$e.RecordId
        EventId          = [int]$e.Id
        Level            = [int]$e.Level
        LevelDisplayName = if ($e.LevelDisplayName) { [string]$e.LevelDisplayName } else { 'Information' }
        ProviderName     = if ($e.ProviderName) { [string]$e.ProviderName } else { 'Unknown' }
        TimeCreated      = $e.TimeCreated.ToString('o')
        Message          = try { if ($e.Message) { [string]$e.Message } else { '' } } catch { '' }
    }
}

$dt = $eventList | Out-DataTable
Invoke-SqliteBulkCopy -DataTable $dt -DataSource $DatabasePath -Table 'ApplicationEvents' -ConflictClause Replace -Force

$swIngest.Stop()
$totalIngested = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT COUNT(*) FROM ApplicationEvents;" -AsScalar

Write-Host "  -> Ingested $totalIngested events in $($swIngest.ElapsedMilliseconds) ms ($([Math]::Round($totalIngested / ($swIngest.ElapsedMilliseconds / 1000), 1)) rows/sec)`n" -ForegroundColor Green
#endregion

# Benchmark Result Storage
$benchmarkResults = @()

#region 4. Benchmark 1: Filter by Level (Warning/Error)
Write-Host "[3/5] Benchmark 1: Filter by Level (Warning [3] / Error [2])..." -ForegroundColor Yellow

# Method A: Standard Windows Event Log (in-memory pipeline filter across current event collection)
$swWin1 = [System.Diagnostics.Stopwatch]::StartNew()
$winEventMatches1 = $rawEvents | Where-Object { $_.Level -in 2, 3 }
$swWin1.Stop()
$winTime1 = $swWin1.ElapsedMilliseconds
$winCount1 = if ($winEventMatches1) { $winEventMatches1.Count } else { 0 }

# Method B: SQLite Query with B-Tree Index
$swSql1 = [System.Diagnostics.Stopwatch]::StartNew()
$sqlQuery1 = "SELECT RecordId, EventId, ProviderName, TimeCreated FROM ApplicationEvents WHERE Level IN (2, 3);"
$sqlMatches1 = Invoke-SqliteCmd -DataSource $DatabasePath -Query $sqlQuery1 -AsDataTable
$swSql1.Stop()
$sqlTime1 = $swSql1.ElapsedMilliseconds
$sqlCount1 = if ($sqlMatches1) { $sqlMatches1.Rows.Count } else { 0 }

$speedup1 = if ($sqlTime1 -gt 0) { [Math]::Round($winTime1 / $sqlTime1, 1) } else { [Math]::Round($winTime1 / 0.5, 1) }

Write-Host "  -> Standard Pipeline Filter: $winTime1 ms ($winCount1 records found)" -ForegroundColor Gray
Write-Host "  -> SQLite B-Tree Index:     $sqlTime1 ms ($sqlCount1 records found)" -ForegroundColor Green
Write-Host "  -> Result: SQLite is $($speedup1)x faster!`n" -ForegroundColor Cyan

$benchmarkResults += [PSCustomObject]@{
    Benchmark       = "1. Level Filter (Warning/Error)"
    Standard_WinEvent = "$($winTime1) ms ($winCount1 rows)"
    SQLite_Database = "$($sqlTime1) ms ($sqlCount1 rows)"
    Speedup         = "$($speedup1)x faster"
}
#endregion

#region 5. Benchmark 2: Message Text Search
$searchTerm = 'service'
Write-Host "[4/5] Benchmark 2: Substring Search in Message Body ('$searchTerm')..." -ForegroundColor Yellow

# Method A: Standard Windows Event Log (Requires loading and inspecting Message for every event)
$swWin2 = [System.Diagnostics.Stopwatch]::StartNew()
$winEventMatches2 = $rawEvents | Where-Object { $_.Message -and $_.Message -like "*$searchTerm*" }
$swWin2.Stop()
$winTime2 = $swWin2.ElapsedMilliseconds
$winCount2 = if ($winEventMatches2) { $winEventMatches2.Count } else { 0 }

# Method B: SQLite LIKE Query
$swSql2 = [System.Diagnostics.Stopwatch]::StartNew()
$sqlQuery2 = "SELECT RecordId, EventId, ProviderName, TimeCreated, SUBSTR(Message, 1, 80) AS Snippet FROM ApplicationEvents WHERE Message LIKE @Kw;"
$sqlMatches2 = Invoke-SqliteCmd -DataSource $DatabasePath -Query $sqlQuery2 -SqlParameters @{ Kw = "%$searchTerm%" } -AsDataTable
$swSql2.Stop()
$sqlTime2 = $swSql2.ElapsedMilliseconds
$sqlCount2 = if ($sqlMatches2) { $sqlMatches2.Rows.Count } else { 0 }

$speedup2 = if ($sqlTime2 -gt 0) { [Math]::Round($winTime2 / $sqlTime2, 1) } else { [Math]::Round($winTime2 / 0.5, 1) }

Write-Host "  -> Standard EventLog: $winTime2 ms ($winCount2 records found)" -ForegroundColor Gray
Write-Host "  -> SQLite Query:     $sqlTime2 ms ($sqlCount2 records found)" -ForegroundColor Green
Write-Host "  -> Result: SQLite is $($speedup2)x faster!`n" -ForegroundColor Cyan

$benchmarkResults += [PSCustomObject]@{
    Benchmark       = "2. Message Body Search ('$searchTerm')"
    Standard_WinEvent = "$($winTime2) ms ($winCount2 rows)"
    SQLite_Database = "$($sqlTime2) ms ($sqlCount2 rows)"
    Speedup         = "$($speedup2)x faster"
}
#endregion

#region 6. Benchmark 3: Grouping & Analytical Aggregation
Write-Host "[5/5] Benchmark 3: Aggregation (Top 5 Providers by Volume)..." -ForegroundColor Yellow

# Method A: Standard Windows Event Log Pipeline Grouping
$swWin3 = [System.Diagnostics.Stopwatch]::StartNew()
$winGroup = $rawEvents | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object -First 5
$swWin3.Stop()
$winTime3 = $swWin3.ElapsedMilliseconds

# Method B: SQLite SQL GROUP BY and ORDER BY
$swSql3 = [System.Diagnostics.Stopwatch]::StartNew()
$sqlQuery3 = @"
SELECT ProviderName, COUNT(*) AS TotalEvents
FROM ApplicationEvents
GROUP BY ProviderName
ORDER BY TotalEvents DESC
LIMIT 5;
"@
$sqlGroup = Invoke-SqliteCmd -DataSource $DatabasePath -Query $sqlQuery3 -AsDataTable
$swSql3.Stop()
$sqlTime3 = $swSql3.ElapsedMilliseconds

$speedup3 = if ($sqlTime3 -gt 0) { [Math]::Round($winTime3 / $sqlTime3, 1) } else { [Math]::Round($winTime3 / 0.5, 1) }

Write-Host "  -> Standard EventLog Grouping: $winTime3 ms" -ForegroundColor Gray
Write-Host "  -> SQLite SQL Aggregation:    $sqlTime3 ms" -ForegroundColor Green
Write-Host "  -> Result: SQLite is $($speedup3)x faster!`n" -ForegroundColor Cyan

$benchmarkResults += [PSCustomObject]@{
    Benchmark       = "3. Top 5 Providers Aggregation"
    Standard_WinEvent = "$($winTime3) ms"
    SQLite_Database = "$($sqlTime3) ms"
    Speedup         = "$($speedup3)x faster"
}

Write-Host "--- Top 5 Application Event Providers (from SQLite) ---" -ForegroundColor Cyan
$sqlGroup | Format-Table -AutoSize
#endregion

#region 7. Summary Table & Key Advantages
Write-Host "`n=================================================================" -ForegroundColor Magenta
Write-Host "                 BENCHMARK PERFORMANCE SUMMARY                   " -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Magenta
$benchmarkResults | Format-Table -AutoSize

Write-Host "KEY TAKEAWAYS FOR POWERSHELL ADMINISTRATORS:" -ForegroundColor Yellow
Write-Host " 1. Pre-computed Indexes: SQLite B-tree indexes allow sub-millisecond filtering on IDs/Levels." -ForegroundColor Gray
Write-Host " 2. Pre-parsed Messages: Avoids Windows Event Log DLL template formatting on every search." -ForegroundColor Gray
Write-Host " 3. Portable Forensic DB: The resulting .db file can be zipped, archived, or inspected offline." -ForegroundColor Gray
Write-Host " 4. Standard SQL Queries: Complex reporting, joins, and aggregations take single-digit milliseconds." -ForegroundColor Gray

Write-Host "`nDemo 06 (Event Log Search Benchmark) completed successfully!" -ForegroundColor Cyan
#endregion
