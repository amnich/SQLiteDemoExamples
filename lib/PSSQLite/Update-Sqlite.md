---
script_name: Update-Sqlite.ps1
relative_path: Zarządzanie Samochodami SQLite/lib/PSSQLite/Update-Sqlite.ps1
category: PSSQLite
webjea_enabled: true
parameters:
  - None
---

# Update-Sqlite.ps1

## Purpose
Update-Sqlite.ps1

## Parameters
| Parameter | Type | Mandatory | Default |
| :--- | :--- | :--- | :--- |
| None | N/A | N/A | N/A |

## Execution & Cmdlets Used
* `copy-item`
* `Expand-Archive`
* `get-module`
* `Invoke-WebRequest`
* `New-Item`
* `remove-item`
* `Set-location`
* `write-verbose`
* `Write-Warning`
* WebJEA detection signals: CmdletBinding attribute.

## Security & Impact Notes
* Impact level: High - potentially destructive, service-affecting, or remote execution operations detected.
* Delegation/permission guidance: No explicit permissions guidance was found in comment-based help; validate the WebJEA/JEA run identity and apply least privilege.
