---
script_name: New-SqliteConnection.ps1
relative_path: Zarządzanie Samochodami SQLite/lib/PSSQLite/New-SqliteConnection.ps1
category: PSSQLite
webjea_enabled: true
parameters:
  - None
---

# New-SqliteConnection.ps1

## Purpose
New-SqliteConnection.ps1

## Parameters
| Parameter | Type | Mandatory | Default |
| :--- | :--- | :--- | :--- |
| None | N/A | N/A | N/A |

## Execution & Cmdlets Used
* `New-Object`
* `Out-String`
* `Write-Debug`
* `Write-Error`
* `Write-Verbose`
* WebJEA detection signals: CmdletBinding attribute.

## Security & Impact Notes
* Impact level: Medium - state-changing operations detected.
* Delegation/permission guidance: No explicit permissions guidance was found in comment-based help; validate the WebJEA/JEA run identity and apply least privilege.

## Extracted Examples
```powershell
$Connection = New-SQLiteConnection -DataSource C:\NAMES.SQLite
        Invoke-SQLiteQuery -SQLiteConnection $Connection -query $Query
Connect to C:\NAMES.SQLite, invoke a query against it
```
```powershell
$Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"
Create a connection to a SQLite data source in memory
Create a table in the memory based datasource, verify it exists with PRAGMA STATS

        $Connection.Close()
        $Connection.Open()
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"
Close the connection, open it back up, verify that the ephemeral data no longer exists
```
