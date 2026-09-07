<#
.SYNOPSIS
    05_Database_Maintenance.ps1 — SQLite Health Checks, Migrations, and VACUUM
.DESCRIPTION
    Demonstrates:
      1. Running database integrity checks (PRAGMA integrity_check)
      2. Automated schema migration tracking using PRAGMA user_version
      3. Applying non-destructive schema upgrades (ALTER TABLE ADD COLUMN)
      4. Database defragmentation and page compaction via VACUUM
      5. Safe online backup of active database
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\maint_demo.db'
}

#region 1. Import Module & Prepare Database
Import-Module (Join-Path $PSScriptRoot 'SQLiteHelper.psd1') -Force

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " SQLite PowerShell Example 05: Maintenance & Migrations  " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target Database: $DatabasePath`n" -ForegroundColor Gray

Connect-SqliteDb -DataSource $DatabasePath | Out-Null
#endregion

#region 2. Schema Migration via PRAGMA user_version
Write-Host "[1/4] Checking and applying schema migrations..." -ForegroundColor Yellow

$currentVersion = [int](Invoke-SqliteCmd -DataSource $DatabasePath -Query "PRAGMA user_version;" -AsScalar)
Write-Host "  -> Current database schema version: $currentVersion" -ForegroundColor Gray

# Migration Step 1: Initial Schema (Version 0 -> 1)
if ($currentVersion -lt 1) {
    Write-Host "  -> Applying Migration v1: Creating SystemAuditLog table..." -ForegroundColor Cyan
    Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
        param($conn)
        $v1Sql = @"
        CREATE TABLE IF NOT EXISTS SystemAuditLog (
            LogId       INTEGER PRIMARY KEY AUTOINCREMENT,
            EventType   TEXT NOT NULL,
            Description TEXT NOT NULL,
            LoggedAt    TEXT NOT NULL
        );
"@
        Invoke-SqliteCmd -SQLiteConnection $conn -Query $v1Sql | Out-Null
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "PRAGMA user_version = 1;" | Out-Null
    }
    Write-Host "  -> Migration v1 applied successfully." -ForegroundColor Green
}

# Migration Step 2: Alter Table (Version 1 -> 2)
$currentVersion = [int](Invoke-SqliteCmd -DataSource $DatabasePath -Query "PRAGMA user_version;" -AsScalar)
if ($currentVersion -lt 2) {
    Write-Host "  -> Applying Migration v2: Adding 'Severity' and 'UserId' columns..." -ForegroundColor Cyan
    Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
        param($conn)
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "ALTER TABLE SystemAuditLog ADD COLUMN Severity TEXT DEFAULT 'Info';" | Out-Null
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "ALTER TABLE SystemAuditLog ADD COLUMN UserId TEXT DEFAULT 'SYSTEM';" | Out-Null
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "PRAGMA user_version = 2;" | Out-Null
    }
    Write-Host "  -> Migration v2 applied successfully." -ForegroundColor Green
}

$finalVersion = [int](Invoke-SqliteCmd -DataSource $DatabasePath -Query "PRAGMA user_version;" -AsScalar)
Write-Host "  -> Final verified schema version: $finalVersion`n" -ForegroundColor Green
#endregion

#region 3. Seed & Populate Data for Compaction Test
Write-Host "[2/4] Populating audit log rows for defragmentation test..." -ForegroundColor Yellow

Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
    param($conn)
    for ($i = 1; $i -le 1000; $i++) {
        $p = @{
            EventType   = "AUDIT_EVENT"
            Description = "Audit log event payload #$i padding with text string data " + ("X" * 100)
            LoggedAt    = (Get-Date -Format 'o')
            Severity    = if ($i % 10 -eq 0) { 'Warning' } else { 'Info' }
            UserId      = "USER_$($i % 5)"
        }
        Invoke-SqliteCmd -SQLiteConnection $conn -Query "INSERT INTO SystemAuditLog (EventType, Description, LoggedAt, Severity, UserId) VALUES (@EventType, @Description, @LoggedAt, @Severity, @UserId);" -SqlParameters $p | Out-Null
    }
}

$initialSize = (Get-Item $DatabasePath).Length
Write-Host "  -> Database file size after 1,000 rows: $([Math]::Round($initialSize / 1KB, 2)) KB" -ForegroundColor Gray

# Delete 80% of rows (creates fragmented free pages in SQLite)
Invoke-SqliteCmd -DataSource $DatabasePath -Query "DELETE FROM SystemAuditLog WHERE LogId > 200;" | Out-Null
$sizeAfterDelete = (Get-Item $DatabasePath).Length
Write-Host "  -> Database file size after DELETE (pages held internally): $([Math]::Round($sizeAfterDelete / 1KB, 2)) KB" -ForegroundColor Gray
#endregion

#region 4. VACUUM (Compaction & Defragmentation)
Write-Host "`n[3/4] Running VACUUM to reclaim disk space..." -ForegroundColor Yellow

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Invoke-SqliteCmd -DataSource $DatabasePath -Query "VACUUM;" | Out-Null
$sw.Stop()

$sizeAfterVacuum = (Get-Item $DatabasePath).Length
$savedBytes = $sizeAfterDelete - $sizeAfterVacuum
Write-Host "  -> VACUUM completed in $($sw.ElapsedMilliseconds) ms." -ForegroundColor Green
Write-Host "  -> File size after VACUUM: $([Math]::Round($sizeAfterVacuum / 1KB, 2)) KB (Reclaimed $([Math]::Round($savedBytes / 1KB, 2)) KB)`n" -ForegroundColor Green
#endregion

#region 5. Integrity Check & Online Backup
Write-Host "[4/4] Verifying database integrity & performing backup..." -ForegroundColor Yellow

$checkResult = Invoke-SqliteCmd -DataSource $DatabasePath -Query "PRAGMA integrity_check;" -AsScalar
if ($checkResult -eq 'ok') {
    Write-Host "  -> PRAGMA integrity_check: OK (No page corruption or index errors)" -ForegroundColor Green
}
else {
    Write-Warning "Database integrity check reported issue: $checkResult"
}

# Create backup copy in backups subfolder
$backupFolder = Join-Path $PSScriptRoot 'data\backups'
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}
$backupFile = Join-Path $backupFolder ("maint_demo_backup_{0}.db" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))

# Copy-Item while database is quiescent
Copy-Item -Path $DatabasePath -Destination $backupFile -Force
Write-Host "  -> Backup created: $backupFile`n" -ForegroundColor Green

Write-Host "Demo 05 (Maintenance & Migrations) completed successfully!" -ForegroundColor Cyan
#endregion
