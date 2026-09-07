<#
.SYNOPSIS
    04_Advanced_Queries_And_Reporting.ps1 — Relational Joins, Aggregations & Export
.DESCRIPTION
    Demonstrates:
      1. Relational schema with Foreign Key constraints (PRAGMA foreign_keys = ON)
      2. Multi-table JOIN queries (INNER JOIN and LEFT OUTER JOIN)
      3. Aggregations using GROUP BY, SUM, AVG, and HAVING
      4. Exporting structured query results directly to CSV and JSON files
      5. Preserving UTF-8 with BOM on generated reports
.NOTES
    Compatible with Windows PowerShell 5.1 and PowerShell 7+.
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $DatabasePath = Join-Path $PSScriptRoot 'data\reporting_demo.db'
}

#region 1. Import Module & Connect
Import-Module (Join-Path $PSScriptRoot 'SQLiteHelper.psd1') -Force

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " SQLite PowerShell Example 04: Advanced Queries & Export" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "Target Database: $DatabasePath`n" -ForegroundColor Gray

Connect-SqliteDb -DataSource $DatabasePath -EnableWal | Out-Null
#endregion

#region 2. Relational Schema Creation
Write-Host "[1/4] Initializing Relational Tables (Departments & Projects)..." -ForegroundColor Yellow

$schemaSql = @"
DROP TABLE IF EXISTS Projects;
DROP TABLE IF EXISTS Departments;

CREATE TABLE Departments (
    DepartmentId   INTEGER PRIMARY KEY AUTOINCREMENT,
    DepartmentName TEXT NOT NULL UNIQUE,
    CostCenter     TEXT NOT NULL,
    AnnualBudget   REAL NOT NULL
);

CREATE TABLE Projects (
    ProjectId      INTEGER PRIMARY KEY AUTOINCREMENT,
    ProjectName    TEXT NOT NULL,
    DepartmentId   INTEGER NOT NULL,
    Budget         REAL NOT NULL,
    SpentAmount    REAL NOT NULL DEFAULT 0.0,
    Status         TEXT NOT NULL CHECK (Status IN ('Planned', 'Active', 'Completed', 'OnHold')),
    FOREIGN KEY (DepartmentId) REFERENCES Departments(DepartmentId) ON DELETE RESTRICT
);

CREATE INDEX IF NOT EXISTS idx_projects_dept ON Projects(DepartmentId);
"@

Invoke-SqliteCmd -DataSource $DatabasePath -Query $schemaSql | Out-Null
Write-Host "  -> Tables 'Departments' and 'Projects' created with Foreign Key constraints.`n" -ForegroundColor Green
#endregion

#region 3. Seed Relational Data
Write-Host "[2/4] Seeding relational records..." -ForegroundColor Yellow

Invoke-SqliteTransaction -DataSource $DatabasePath -ScriptBlock {
    param($conn)

    # Insert Departments
    $depts = @(
        @{ Name = 'Infrastructure & Cloud'; CC = 'CC-101'; Budget = 450000.00 },
        @{ Name = 'Business Central ERP';   CC = 'CC-102'; Budget = 380000.00 },
        @{ Name = 'Production Planning';    CC = 'CC-103'; Budget = 250000.00 },
        @{ Name = 'Quality Assurance';      CC = 'CC-104'; Budget = 150000.00 }
    )
    foreach ($d in $depts) {
        $q = "INSERT INTO Departments (DepartmentName, CostCenter, AnnualBudget) VALUES (@Name, @CC, @Budget);"
        Invoke-SqliteCmd -SQLiteConnection $conn -Query $q -SqlParameters $d | Out-Null
    }

    # Insert Projects
    $projects = @(
        @{ Name = 'Server 2025 Baseline Migration'; DeptId = 1; Budget = 85000.00;  Spent = 62000.00; Status = 'Active' },
        @{ Name = 'Hyper-V Cluster Expansion';      DeptId = 1; Budget = 120000.00; Spent = 118000.00; Status = 'Active' },
        @{ Name = 'Business Central 2026 Upgrade';  DeptId = 2; Budget = 190000.00; Spent = 95000.00;  Status = 'Active' },
        @{ Name = 'LVS Barcode Matrix Deployment';  DeptId = 3; Budget = 45000.00;  Spent = 44500.00; Status = 'Completed' },
        @{ Name = 'Automated Regression Framework'; DeptId = 4; Budget = 60000.00;  Spent = 12000.00;  Status = 'Active' },
        @{ Name = 'Legacy Access DB Retirement';    DeptId = 2; Budget = 30000.00;  Spent = 5000.00;   Status = 'Planned' }
    )
    foreach ($p in $projects) {
        $q = "INSERT INTO Projects (ProjectName, DepartmentId, Budget, SpentAmount, Status) VALUES (@Name, @DeptId, @Budget, @Spent, @Status);"
        Invoke-SqliteCmd -SQLiteConnection $conn -Query $q -SqlParameters $p | Out-Null
    }
}
Write-Host "  -> Seeded 4 departments and 6 projects successfully.`n" -ForegroundColor Green
#endregion

#region 4. Analytical Relational Queries
Write-Host "[3/4] Executing JOIN and Aggregation Queries..." -ForegroundColor Yellow

$reportQuery = @"
SELECT
    d.DepartmentName,
    d.CostCenter,
    COUNT(p.ProjectId) AS TotalProjects,
    ROUND(SUM(p.Budget), 2) AS TotalAllocatedBudget,
    ROUND(SUM(p.SpentAmount), 2) AS TotalSpent,
    ROUND(SUM(p.Budget) - SUM(p.SpentAmount), 2) AS RemainingBudget,
    ROUND((SUM(p.SpentAmount) / SUM(p.Budget)) * 100, 1) AS UtilizationPercent
FROM Departments d
LEFT JOIN Projects p ON d.DepartmentId = p.DepartmentId
GROUP BY d.DepartmentId, d.DepartmentName, d.CostCenter
ORDER BY TotalAllocatedBudget DESC;
"@

$reportData = Invoke-SqliteCmd -DataSource $DatabasePath -Query $reportQuery
$reportData | Format-Table -AutoSize
#endregion

#region 5. Export Results to CSV and JSON
Write-Host "[4/4] Exporting Report Data to CSV and JSON..." -ForegroundColor Yellow

$exportFolder = Join-Path $PSScriptRoot 'exports'
if (-not (Test-Path $exportFolder)) {
    New-Item -ItemType Directory -Path $exportFolder -Force | Out-Null
}

$csvPath = Join-Path $exportFolder 'Department_Project_Budget_Report.csv'
$jsonPath = Join-Path $exportFolder 'Department_Project_Budget_Report.json'

# Helper to write UTF-8 with BOM across PS 5.1 and 7+
$utf8Bom = New-Object System.Text.UTF8Encoding($true)

# 1. Export CSV with BOM
$csvContent = $reportData | ConvertTo-Csv -NoTypeInformation -Delimiter ';'
[System.IO.File]::WriteAllLines($csvPath, [string[]]$csvContent, $utf8Bom)
Write-Host "  -> Exported CSV:  $csvPath" -ForegroundColor Green

# 2. Export JSON with BOM
$jsonContent = $reportData | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($jsonPath, $jsonContent, $utf8Bom)
Write-Host "  -> Exported JSON: $jsonPath" -ForegroundColor Green

Write-Host "`nDemo 04 (Advanced Queries & Reporting) completed successfully!" -ForegroundColor Cyan
#endregion
