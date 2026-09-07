<#
.SYNOPSIS
    01_Basic_CRUD.ps1 — Fundamental CRUD operations using SQLite in PowerShell
.DESCRIPTION
    Demonstrates:
      1. Importing bundled PSSQLite library
      2. Creating an SQLite database and a table with constraints
      3. Secure parameterized INSERT queries (preventing SQL injection)
      4. SELECT queries mapped to PowerShell PSCustomObjects
      5. Parameterized UPDATE queries
      6. Parameterized DELETE queries
      7. SQLite Upsert (INSERT ... ON CONFLICT DO UPDATE)
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\crud_demo.db'
}

#region 1. Import SQLite Module
$modulePath = Join-Path $PSScriptRoot 'SQLiteHelper.psd1'
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
}
else {
    Import-Module (Join-Path $PSScriptRoot 'lib\PSSQLite\PSSQLite.psd1') -Force
}

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "   SQLite PowerShell Example 01: Basic CRUD Operations   " -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target Database: $DatabasePath`n" -ForegroundColor Gray

# Ensure target folder exists and initialize database connection
Connect-SqliteDb -DataSource $DatabasePath | Out-Null
#endregion

#region 2. Create Schema (Table & Index)
Write-Host "[1/6] Creating 'Employees' table and unique index..." -ForegroundColor Yellow

$createTableSql = @"
CREATE TABLE IF NOT EXISTS Employees (
    Id          INTEGER PRIMARY KEY AUTOINCREMENT,
    Username    TEXT NOT NULL UNIQUE,
    FullName    TEXT NOT NULL,
    Email       TEXT NOT NULL,
    Department  TEXT NOT NULL,
    Salary      REAL NOT NULL,
    HireDate    TEXT NOT NULL,
    IsActive    INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_employees_dept ON Employees(Department);
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $createTableSql | Out-Null
Write-Host "  -> Table 'Employees' and index 'idx_employees_dept' ready.`n" -ForegroundColor Green
#endregion

#region 3. Parameterized INSERT
Write-Host "[2/6] Inserting records using parameterized queries..." -ForegroundColor Yellow

# Clean table for repeatable demo
Invoke-SqliteCmd -DataSource $DatabasePath -Query "DELETE FROM Employees;" | Out-Null

$sampleUsers = @(
    @{ Username = 'amnich';   FullName = 'Adam Mnich';     Email = 'amnich@example.com';   Department = 'IT Infrastructure'; Salary = 9500.00; HireDate = '2020-03-01' },
    @{ Username = 'jkowalski';FullName = 'Jan Kowalski';   Email = 'jkowalski@example.com';Department = 'Logistics';         Salary = 6200.00; HireDate = '2021-06-15' },
    @{ Username = 'anowak';   FullName = 'Anna Nowak';     Email = 'anowak@example.com';   Department = 'Finance';           Salary = 7800.00; HireDate = '2019-11-01' },
    @{ Username = 'pzielinski';FullName = 'Piotr Zielinski';Email = 'pzielinski@example.com';Department = 'IT Infrastructure'; Salary = 8400.00; HireDate = '2022-01-10' }
)

$insertSql = @"
INSERT INTO Employees (Username, FullName, Email, Department, Salary, HireDate)
VALUES (@Username, @FullName, @Email, @Department, @Salary, @HireDate);
"@

foreach ($user in $sampleUsers) {
    Invoke-SqliteCmd -DataSource $DatabasePath -Query $insertSql -SqlParameters $user | Out-Null
}

$count = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT COUNT(*) FROM Employees;" -AsScalar
Write-Host "  -> Successfully inserted $count employees.`n" -ForegroundColor Green
#endregion

#region 4. SELECT Query (PSCustomObject Mapping)
Write-Host "[3/6] Reading records back as PowerShell PSCustomObjects..." -ForegroundColor Yellow

$querySql = @"
SELECT Id, Username, FullName, Department, Salary, HireDate
FROM Employees
WHERE Department = @Dept
ORDER BY Salary DESC;
"@

$itTeam = Invoke-SqliteCmd -DataSource $DatabasePath -Query $querySql -SqlParameters @{ Dept = 'IT Infrastructure' }
$itTeam | Format-Table -AutoSize
Write-Host "  -> Found $($itTeam.Count) employees in 'IT Infrastructure'.`n" -ForegroundColor Green
#endregion

#region 5. Parameterized UPDATE
Write-Host "[4/6] Updating record (Salary increase for 'amnich')..." -ForegroundColor Yellow

$updateSql = @"
UPDATE Employees
SET Salary = Salary * @RaiseMultiplier
WHERE Username = @Username;
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $updateSql -SqlParameters @{
    Username        = 'amnich'
    RaiseMultiplier = 1.10
} | Out-Null

$updatedUser = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT FullName, Salary FROM Employees WHERE Username = 'amnich';"
Write-Host "  -> Updated Salary for $($updatedUser.FullName): $($updatedUser.Salary)`n" -ForegroundColor Green
#endregion

#region 6. SQLite Upsert / Replace (INSERT OR REPLACE)
Write-Host "[5/6] Demonstrating Upsert (INSERT OR REPLACE INTO)..." -ForegroundColor Yellow

<#
    NOTE ON UPSERT SYNTAX:
    - 'INSERT OR REPLACE INTO table ...' works in all SQLite versions (including SQLite 3.8+ bundled in .NET Framework).
    - 'INSERT INTO table ... ON CONFLICT(col) DO UPDATE ...' was introduced in SQLite 3.24.0 (present in .NET Core).
    For maximum cross-PowerShell compatibility, 'INSERT OR REPLACE' is recommended.
#>
$upsertSql = @"
INSERT OR REPLACE INTO Employees (Username, FullName, Email, Department, Salary, HireDate)
VALUES (@Username, @FullName, @Email, @Department, @Salary, @HireDate);
"@

# Updating existing 'jkowalski' to a new department and salary via replace/upsert
$upsertData = @{
    Username   = 'jkowalski'
    FullName   = 'Jan Kowalski'
    Email      = 'jan.kowalski@newdomain.com'
    Department = 'Supply Chain Management'
    Salary     = 6900.00
    HireDate   = '2021-06-15'
}

Invoke-SqliteCmd -DataSource $DatabasePath -Query $upsertSql -SqlParameters $upsertData | Out-Null

$checkUpsert = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT Username, Department, Email, Salary FROM Employees WHERE Username = 'jkowalski';"
$checkUpsert | Format-Table -AutoSize
Write-Host "  -> Upsert successfully updated existing user without error.`n" -ForegroundColor Green
#endregion

#region 7. Parameterized DELETE
Write-Host "[6/6] Deleting record by Username..." -ForegroundColor Yellow

$deleteSql = "DELETE FROM Employees WHERE Username = @Username;"
Invoke-SqliteCmd -DataSource $DatabasePath -Query $deleteSql -SqlParameters @{ Username = 'pzielinski' } | Out-Null

$remaining = Invoke-SqliteCmd -DataSource $DatabasePath -Query "SELECT COUNT(*) FROM Employees;" -AsScalar
Write-Host "  -> Deleted 'pzielinski'. Total remaining employees: $remaining`n" -ForegroundColor Green

Write-Host "Demo 01 (Basic CRUD) completed successfully!" -ForegroundColor Cyan
#endregion
