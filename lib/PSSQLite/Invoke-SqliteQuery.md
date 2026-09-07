---
script_name: Invoke-SqliteQuery.ps1
relative_path: Zarządzanie Samochodami SQLite/lib/PSSQLite/Invoke-SqliteQuery.ps1
category: PSSQLite
webjea_enabled: true
parameters:
  - None
---

# Invoke-SqliteQuery.ps1

## Purpose
Invoke-SqliteQuery.ps1

## Parameters
| Parameter | Type | Mandatory | Default |
| :--- | :--- | :--- | :--- |
| None | N/A | N/A | N/A |

## Execution & Cmdlets Used
* `Add-Type`
* `ForEach-Object`
* `New-Object`
* `Out-String`
* `Resolve-Path`
* `Select-Object`
* `Split-Path`
* `Test-Path`
* `Write-Debug`
* `Write-Error`
* `Write-Verbose`
* `Write-Warning`
* WebJEA detection signals: CmdletBinding attribute.

## Security & Impact Notes
* Impact level: Medium - state-changing operations detected.
* Delegation/permission guidance: No explicit permissions guidance was found in comment-based help; validate the WebJEA/JEA run identity and apply least privilege.

## Extracted Examples
```powershell
First, we create a database and a table
            $Query = "CREATE TABLE NAMES (fullname VARCHAR(20) PRIMARY KEY, surname TEXT, givenname TEXT, BirthDate DATETIME)"
            $Database = "C:\Names.SQLite"
        
            Invoke-SqliteQuery -Query $Query -DataSource $Database
We have a database, and a table, let's view the table info
            Invoke-SqliteQuery -DataSource $Database -Query "PRAGMA table_info(NAMES)"
                
                cid name      type         notnull dflt_value pk
                --- ----      ----         ------- ---------- --
                  0 fullname  VARCHAR(20)        0             1
                  1 surname   TEXT               0             0
                  2 givenname TEXT               0             0
                  3 BirthDate DATETIME           0             0
Insert some data, use parameters for the fullname and birthdate
            $query = "INSERT INTO NAMES (fullname, surname, givenname, birthdate) VALUES (@full, 'Cookie', 'Monster', @BD)"
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster"
                BD   = (get-date).addyears(-3)
            }
Check to see if we inserted the data:
            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"
                
                fullname       surname givenname BirthDate            
                --------       ------- --------- ---------            
                Cookie Monster Cookie  Monster   3/14/2012 12:27:13 PM
Insert another entry with too many characters in the fullname.
Illustrate that SQLite data types may be misleading:
            Invoke-SqliteQuery -DataSource $Database -Query $query -SqlParameters @{
                full = "Cookie Monster$('!' * 20)"
                BD   = (get-date).addyears(-3)
            }

            Invoke-SqliteQuery -DataSource $Database -Query "SELECT * FROM NAMES"

                fullname              surname givenname BirthDate            
                --------              ------- --------- ---------            
                Cookie Monster        Cookie  Monster   3/14/2012 12:27:13 PM
                Cookie Monster![...]! Cookie  Monster   3/14/2012 12:29:32 PM
```
```powershell
Invoke-SqliteQuery -DataSource C:\NAMES.SQLite -Query "SELECT * FROM NAMES" -AppendDataSource

            fullname       surname givenname BirthDate             Database       
            --------       ------- --------- ---------             --------       
            Cookie Monster Cookie  Monster   3/14/2012 12:55:55 PM C:\Names.SQLite
Append Database column (path) to each result
```
```powershell
Invoke-SqliteQuery -DataSource C:\Names.SQLite -InputFile C:\Query.sql
Invoke SQL from an input file
```
```powershell
$Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "PRAGMA STATS"
Execute a query against an existing SQLiteConnection
Create a connection to a SQLite data source in memory
Create a table in the memory based datasource, verify it exists with PRAGMA STATS
```
```powershell
$Connection = New-SQLiteConnection -DataSource :MEMORY: 
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "CREATE TABLE OrdersToNames (OrderID INT PRIMARY KEY, fullname TEXT);"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID, fullname) VALUES (1,'Cookie Monster');"
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "INSERT INTO OrdersToNames (OrderID) VALUES (2);"
We now have two entries, only one has a fullname.  Despite this, the following command returns both; very un-PowerShell!
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" -As DataRow | Where{$_.fullname}

            OrderID fullname      
            ------- --------      
                  1 Cookie Monster
                  2               
Using the default -As PSObject, we can get PowerShell-esque behavior:
        Invoke-SqliteQuery -SQLiteConnection $Connection -Query "SELECT * FROM OrdersToNames" | Where{$_.fullname}

            OrderID fullname                                                                         
            ------- --------                                                                         
                  1 Cookie Monster
```
