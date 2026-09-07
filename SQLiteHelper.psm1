<#
.SYNOPSIS
    SQLiteHelper Module — Portable, High-Performance SQLite Helper for PowerShell
.DESCRIPTION
    Provides reusable helper functions for working with SQLite databases in PowerShell 5.1 and 7+.
    Bundles and loads PSSQLite with zero external dependencies.
    Demonstrates best practices for connection management, parameterized queries, transactions,
    WAL journal mode, and schema reflection.
.AUTHOR
    Adam Mnich / Antigravity
.VERSION
    1.0.0
#>

#region Module Initialization & Dependency Loading
$script:ModuleRoot = $PSScriptRoot
$script:LocalLibPath = Join-Path $script:ModuleRoot 'lib\PSSQLite\PSSQLite.psd1'

if (Test-Path $script:LocalLibPath) {
    Import-Module $script:LocalLibPath -DisableNameChecking -ErrorAction Stop
}
elseif (Get-Module -ListAvailable -Name PSSQLite) {
    Import-Module PSSQLite -DisableNameChecking -ErrorAction Stop
}
else {
    throw "Cannot locate PSSQLite module in '$script:LocalLibPath' or system PSModulePath."
}

# Default database path: demo.db in the module folder
$script:DefaultDbPath = Join-Path $script:ModuleRoot 'data\demo.db'
#endregion

#region Connection & Configuration Functions

<#
.SYNOPSIS
    Returns an open or reusable SQLite connection or connection string.
.PARAMETER DataSource
    File path to the SQLite database or ':memory:' for an in-memory database.
.PARAMETER EnableWal
    Enables Write-Ahead Logging (WAL) mode for better concurrent performance.
#>
function Connect-SqliteDb {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$DataSource = $script:DefaultDbPath,

        [switch]$EnableWal
    )

    if ($DataSource -ne ':memory:') {
        $parentFolder = Split-Path -Parent $DataSource
        if ($parentFolder -and -not (Test-Path $parentFolder)) {
            New-Item -ItemType Directory -Path $parentFolder -Force | Out-Null
        }
    }

    # Enable foreign keys by default for relational integrity
    Invoke-SqliteQuery -DataSource $DataSource -Query 'PRAGMA foreign_keys = ON;' | Out-Null

    if ($EnableWal -and $DataSource -ne ':memory:') {
        Invoke-SqliteQuery -DataSource $DataSource -Query 'PRAGMA journal_mode = WAL;' | Out-Null
        Invoke-SqliteQuery -DataSource $DataSource -Query 'PRAGMA synchronous = NORMAL;' | Out-Null
    }

    return $DataSource
}

<#
.SYNOPSIS
    Executes an SQLite query and returns results as PSCustomObject array or scalar value.
.PARAMETER Query
    SQL statement (SELECT, INSERT, UPDATE, DELETE, CREATE, etc.).
.PARAMETER DataSource
    Database path or ':memory:'.
.PARAMETER SQLiteConnection
    An existing open SQLiteConnection to use (required for transactions).
.PARAMETER SqlParameters
    Hashtable of parameters for parameterized queries (e.g. @{ Name = 'Alice'; Age = 30 }).
.PARAMETER AsScalar
    Returns only the first column of the first row.
#>
function Invoke-SqliteCmd {
    [CmdletBinding(DefaultParameterSetName = 'BySource')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Query,

        [Parameter(ParameterSetName = 'BySource', Position = 1)]
        [string]$DataSource = $script:DefaultDbPath,

        [Parameter(ParameterSetName = 'ByConnection', Position = 1, Mandatory = $true)]
        [System.Data.SQLite.SQLiteConnection]$SQLiteConnection,

        [Parameter(Position = 2)]
        [hashtable]$SqlParameters = @{},

        [switch]$AsScalar,
        [switch]$AsDataTable
    )

    try {
        $splat = @{
            Query = $Query
        }
        if ($AsDataTable) {
            $splat['As'] = 'DataTable'
        }
        if ($PSCmdlet.ParameterSetName -eq 'ByConnection') {
            $splat['SQLiteConnection'] = $SQLiteConnection
        }
        else {
            $splat['DataSource'] = $DataSource
        }
        if ($SqlParameters -and $SqlParameters.Count -gt 0) {
            $splat['SqlParameters'] = $SqlParameters
        }

        $results = Invoke-SqliteQuery @splat

        if ($AsScalar) {
            if ($null -eq $results) { return $null }
            $first = $results | Select-Object -First 1
            if ($first -is [System.Management.Automation.PSCustomObject]) {
                $prop = $first.PSObject.Properties | Select-Object -First 1
                if ($prop) {
                    return $prop.Value
                }
            }
            return $first
        }

        if ($AsDataTable) {
            return ,$results
        }

        return $results
    }
    catch {
        Write-Error "SQLite Query Failed: $_`nQuery: $Query"
        throw
    }
}

<#
.SYNOPSIS
    Executes a script block within an atomic SQLite transaction using a dedicated connection.
.PARAMETER ScriptBlock
    PowerShell ScriptBlock receiving the open $conn object as an argument. Automatically committed on success, rolled back on error.
.PARAMETER DataSource
    Database path or ':memory:'.
#>
function Invoke-SqliteTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,

        [string]$DataSource = $script:DefaultDbPath
    )

    $conn = New-SqliteConnection -DataSource $DataSource
    try {
        Invoke-SqliteQuery -SQLiteConnection $conn -Query 'BEGIN TRANSACTION;' | Out-Null
        $result = & $ScriptBlock $conn
        Invoke-SqliteQuery -SQLiteConnection $conn -Query 'COMMIT;' | Out-Null
        return $result
    }
    catch {
        try {
            Invoke-SqliteQuery -SQLiteConnection $conn -Query 'ROLLBACK;' | Out-Null
        }
        catch { }
        Write-Error "Transaction rolled back due to error: $_"
        throw
    }
    finally {
        if ($conn -and $conn.State -eq 'Open') {
            $conn.Close()
            $conn.Dispose()
        }
    }
}

<#
.SYNOPSIS
    Retrieves the list of tables, views, or indexes defined in the SQLite database.
#>
function Get-SqliteSchema {
    [CmdletBinding()]
    param(
        [string]$DataSource = $script:DefaultDbPath,
        [ValidateSet('table', 'view', 'index', 'all')]
        [string]$Type = 'table'
    )

    $query = "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'"
    if ($Type -ne 'all') {
        $query += " AND type = '$Type'"
    }
    $query += " ORDER BY type, name;"

    return Invoke-SqliteCmd -DataSource $DataSource -Query $query
}

<#
.SYNOPSIS
    Retrieves column definitions for a specific table.
#>
function Get-SqliteTableColumns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,

        [string]$DataSource = $script:DefaultDbPath
    )

    $query = "PRAGMA table_info([$TableName]);"
    return Invoke-SqliteCmd -DataSource $DataSource -Query $query
}

#endregion

Export-ModuleMember -Function Connect-SqliteDb,
                             Invoke-SqliteCmd,
                             Invoke-SqliteTransaction,
                             Get-SqliteSchema,
                             Get-SqliteTableColumns,
                             Invoke-SqliteBulkCopy,
                             Out-DataTable,
                             New-SqliteConnection
