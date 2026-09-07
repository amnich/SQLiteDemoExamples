<#
.SYNOPSIS
    02_Transactions_And_Performance.ps1 — SQLite Transactions and Benchmark Demo
.DESCRIPTION
    Demonstrates:
      1. The dramatic performance difference between auto-commit and explicit transactions
      2. Using Invoke-SqliteTransaction for safe, atomic commits and automatic rollbacks
      3. Enabling Write-Ahead Logging (WAL) mode for high-concurrency read/write operations
      4. Measuring execution time with Measure-Command
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\perf_demo.db'
}

#region 1. Import Module
Import-Module (Join-Path $PSScriptRoot 'SQLiteHelper.psd1') -Force

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " SQLite PowerShell Example 02: Transactions & Benchmark " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target Database: $DatabasePath`n" -ForegroundColor Gray

Connect-SqliteDb -DataSource $DatabasePath -EnableWal | Out-Null
#endregion

#region 2. Prepare Schema
$initSql = @"
DROP TABLE IF EXISTS BenchRecords;
CREATE TABLE BenchRecords (
    Id          INTEGER PRIMARY KEY AUTOINCREMENT,
    BatchId     TEXT NOT NULL,
    Timestamp   TEXT NOT NULL,
    Payload     TEXT NOT NULL,
    MetricVal   REAL NOT NULL
);
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $initSql | Out-Null
#endregion

#region 3. Benchmark: Auto-Commit (Without Transaction)
$testCount = 100
Write-Host "[1/3] Benchmarking $testCount inserts WITHOUT an explicit transaction (Auto-Commit)..." -ForegroundColor Yellow
Write-Host "      (Each statement flushes to disk independently)" -ForegroundColor Gray

$sw1 = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 1; $i -le $testCount; $i++) {
    $params = @{
        BatchId   = 'AUTO_COMMIT'
        Timestamp = (Get-Date -Format 'o')
        Payload   = "Measurement payload record #$i"
        MetricVal = [Math]::Round((Get-Random -Minimum 10.0 -Maximum 99.9), 2)
    }
    $query = "INSERT INTO BenchRecords (BatchId, Timestamp, Payload, MetricVal) VALUES (@BatchId, @Timestamp, @Payload, @MetricVal);"
    Invoke-SqliteCmd -DataSource $DatabasePath -Query $query -SqlParameters $params | Out-Null
}
$sw1.Stop()
$autoCommitTime = $sw1.ElapsedMilliseconds
Write-Host "  -> Auto-Commit ($testCount rows): $autoCommitTime ms ($([Math]::Round($testCount / ($autoCommitTime / 1000), 1)) rows/sec)`n" -ForegroundColor Red
#endregion

#region 4. Benchmark: Explicit Transaction (BEGIN ... COMMIT)
$testCountBatch = 500
Write-Host "[2/3] Benchmarking $testCountBatch inserts INSIDE an explicit transaction..." -ForegroundColor Yellow
Write-Host "      (All statements batched into a single atomic disk flush)" -ForegroundColor Gray

$sw2 = [System.Diagnostics.Stopwatch]::StartNew()

Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
    param($conn)
    $insertQuery = "INSERT INTO BenchRecords (BatchId, Timestamp, Payload, MetricVal) VALUES (@BatchId, @Timestamp, @Payload, @MetricVal);"
    for ($i = 1; $i -le $testCountBatch; $i++) {
        $params = @{
            BatchId   = 'TRANSACTION_BATCH'
            Timestamp = (Get-Date -Format 'o')
            Payload   = "Measurement payload record #$i"
            MetricVal = [Math]::Round((Get-Random -Minimum 10.0 -Maximum 99.9), 2)
        }
        Invoke-SqliteCmd -SQLiteConnection $conn -Query $insertQuery -SqlParameters $params | Out-Null
    }
}

$sw2.Stop()
$batchTime = $sw2.ElapsedMilliseconds
$rowsPerSec = if ($batchTime -gt 0) { [Math]::Round($testCountBatch / ($batchTime / 1000), 1) } else { 9999 }
Write-Host "  -> Explicit Transaction ($testCountBatch rows): $batchTime ms ($rowsPerSec rows/sec)`n" -ForegroundColor Green

Write-Host "  -> Comparison: Transaction batching is significantly faster and prevents partial writes!`n" -ForegroundColor Cyan
#endregion

#region 5. Transaction Rollback Safety Test
Write-Host "[3/3] Testing automatic rollback on failure..." -ForegroundColor Yellow

$countBefore = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT COUNT(*) FROM BenchRecords;" -AsScalar

$rollbackTriggered = $false
try {
    Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
        param($conn)
        # Insert a valid row
        $params = @{
            BatchId   = 'ROLLBACK_TEST'
            Timestamp = (Get-Date -Format 'o')
            Payload   = 'Row that should be rolled back'
            MetricVal = 100.0
        }
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "INSERT INTO BenchRecords (BatchId, Timestamp, Payload, MetricVal) VALUES (@BatchId, @Timestamp, @Payload, @MetricVal);" -SqlParameters $params | Out-Null

        # Deliberately throw an error or execute invalid SQL to trigger rollback
        throw "Simulated network or application failure during batch processing!"
    }
}
catch {
    $rollbackTriggered = $true
    Write-Host "  -> Caught simulated exception as expected: $($_.Exception.Message)" -ForegroundColor Yellow
}

$countAfter = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT COUNT(*) FROM BenchRecords;" -AsScalar

if ($countBefore -eq $countAfter -and $rollbackTriggered) {
    Write-Host "  -> Verification PASSED: Count before ($countBefore) matches count after ($countAfter). No dirty data was saved!" -ForegroundColor Green
}
else {
    Write-Error "Rollback failed: count before was $countBefore, after is $countAfter"
}

Write-Host "`nDemo 02 (Transactions & Performance) completed successfully!" -ForegroundColor Cyan
#endregion
