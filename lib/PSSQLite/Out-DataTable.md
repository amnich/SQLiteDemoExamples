---
script_name: Out-DataTable.ps1
relative_path: Zarządzanie Samochodami SQLite/lib/PSSQLite/Out-DataTable.ps1
category: PSSQLite
webjea_enabled: true
parameters:
  - None
---

# Out-DataTable.ps1

## Purpose
Out-DataTable.ps1

## Parameters
| Parameter | Type | Mandatory | Default |
| :--- | :--- | :--- | :--- |
| None | N/A | N/A | N/A |

## Execution & Cmdlets Used
* `ConvertTo-XML`
* `Get-ODTType`
* `New-Object`
* `out-string`
* `Write-Error`
* `Write-Output`
* `write-verbose`
* WebJEA detection signals: CmdletBinding attribute.

## Security & Impact Notes
* Impact level: Medium - state-changing operations detected.
* Delegation/permission guidance: No explicit permissions guidance was found in comment-based help; validate the WebJEA/JEA run identity and apply least privilege.

## Extracted Examples
```powershell
$dt = Get-psdrive | Out-DataTable
This example creates a DataTable from the properties of Get-psdrive and assigns output to $dt variable
```
```powershell
Get-Process | Select Name, CPU | Out-DataTable | Invoke-SQLBulkCopy -ServerInstance $SQLInstance -Database $Database -Table $SQLTable -force -verbose
Get a list of processes and their CPU, create a datatable, bulk import that data
```
