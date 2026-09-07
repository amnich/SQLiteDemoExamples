---
script_name: Invoke-SqliteBulkCopy.ps1
relative_path: Zarządzanie Samochodami SQLite/lib/PSSQLite/Invoke-SqliteBulkCopy.ps1
category: PSSQLite
webjea_enabled: true
parameters:
  - None
---

# Invoke-SqliteBulkCopy.ps1

## Purpose
Invoke-SqliteBulkCopy.ps1

## Parameters
| Parameter | Type | Mandatory | Default |
| :--- | :--- | :--- | :--- |
| None | N/A | N/A | N/A |

## Execution & Cmdlets Used
* `CleanUp`
* `ForEach-Object`
* `Get-ParameterName`
* `New-Object`
* `New-SqliteBulkQuery`
* `Out-String`
* `Select-Object`
* `Test-Path`
* `Where-Object`
* `Write-Debug`
* `Write-Verbose`
* WebJEA detection signals: CmdletBinding attribute.

## Security & Impact Notes
* Impact level: Medium - state-changing operations detected.
* Delegation/permission guidance: No explicit permissions guidance was found in comment-based help; validate the WebJEA/JEA run identity and apply least privilege.

## Extracted Examples
```powershell
Create a table
        Invoke-SqliteQuery -DataSource "C:\Names.SQLite" -Query "CREATE TABLE NAMES (
            fullname VARCHAR(20) PRIMARY KEY,
            surname TEXT,
            givenname TEXT,
            BirthDate DATETIME)" 
Build up some fake data to bulk insert, convert it to a datatable
        $DataTable = 1..10000 | %{
            [pscustomobject]@{
                fullname = "Name $_"
                surname = "Name"
                givenname = "$_"
                BirthDate = (Get-Date).Adddays(-$_)
            }
        } | Out-DataTable
Copy the data in within a single transaction (SQLite is faster this way)
        Invoke-SQLiteBulkCopy -DataTable $DataTable -DataSource $Database -Table Names -NotifyAfter 1000 -ConflictClause Ignore -Verbose
```
