@{
    RootModule           = 'SQLiteHelper.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'b94e771c-321a-4d22-805c-e58f0d86b71f'
    Author               = 'Adam Mnich'
    CompanyName          = 'BGH'
    Copyright            = '(c) Adam Mnich. All rights reserved.'
    Description          = 'Portable SQLite helper module for Windows PowerShell 5.1 and PowerShell 7+'
    PowerShellVersion    = '5.1'
    FunctionsToExport    = @(
        'Connect-SqliteDb'
        'Invoke-SqliteCmd'
        'Invoke-SqliteTransaction'
        'Get-SqliteSchema'
        'Get-SqliteTableColumns'
        'Invoke-SqliteBulkCopy'
        'Out-DataTable'
        'New-SqliteConnection'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags = @('SQLite', 'Database', 'PowerShell', 'PSSQLite', 'Storage')
        }
    }
}
