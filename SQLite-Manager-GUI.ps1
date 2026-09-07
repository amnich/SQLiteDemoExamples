<#
.SYNOPSIS
    SQLite-Manager-GUI.ps1 — Modern Dark-Themed WPF GUI for SQLite in PowerShell
.DESCRIPTION
    Provides a rich, interactive WPF desktop interface for exploring and managing SQLite databases:
      - Live interactive DataGrid with column header sorting (Ascending / Descending)
      - Real-time text search and row filtering across all columns
      - Record management: Add, Update, and Delete records with parameterized queries
      - Multi-table browser (switch between any table in the database)
      - Custom SQL Query Console with execution time metrics and quick snippet buttons
      - DWM Dark Mode Titlebar and Catppuccin Mocha themed controls
      - Compatible with Windows PowerShell 5.1 and PowerShell 7+
.PARAMETER DatabasePath
    Optional path to the SQLite database file. Defaults to .\data\crud_demo.db.
.NOTES
    Encoding: UTF-8 with BOM
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = ''
)

$ErrorActionPreference = 'Stop'

# Ensure STA Mode (Required for WPF)
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    Write-Verbose "Re-launching in STA apartment state..."
    $psExe = if ($PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $scriptFile = $MyInvocation.MyCommand.Path
    Start-Process -FilePath $psExe -ArgumentList "-NoProfile -STA -File `"$scriptFile`""
    return
}

# Load Required Assemblies
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Data

# Register DWM Dark Mode API
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class DwmDarkWindow {
    [DllImport("dwmapi.dll", PreserveSig = true)]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@ -ErrorAction SilentlyContinue

# Import SQLite Helper Module
$script:ModuleDir = if ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    'D:\Skrypty\Mnich_Adam_Skrypty\!Daily\PowerShell_SQLite_Example'
}
$script:HelperManifest = Join-Path $script:ModuleDir 'SQLiteHelper.psd1'
if (Test-Path $script:HelperManifest) {
    Import-Module $script:HelperManifest -Force
}
else {
    Import-Module (Join-Path $script:ModuleDir 'lib\PSSQLite\PSSQLite.psd1') -Force
}

# Resolve Initial Database Path
if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
    $script:CurrentDb = Join-Path $script:ModuleDir 'data\crud_demo.db'
}
else {
    $script:CurrentDb = $DatabasePath
}

# Ensure Database directory exists
$dbDir = Split-Path -Parent $script:CurrentDb
if ($dbDir -and -not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}

# Ensure connection & foreign keys
Connect-SqliteDb -DataSource $script:CurrentDb -EnableWal | Out-Null

# Global State
$script:CurrentTable = 'Employees'
$script:CurrentDataTable = $null

#region XAML Definition
[xml]$xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="SQLite Database Explorer &amp; Manager"
    Height="750" Width="1120"
    MinHeight="600" MinWidth="900"
    WindowStartupLocation="CenterScreen"
    Background="#1E1E2E"
    Foreground="#CDD6F4"
    FontFamily="Segoe UI"
    FontSize="13">

    <Window.Resources>
        <!-- Dark Theme Brushes -->
        <SolidColorBrush x:Key="BgDark" Color="#1E1E2E"/>
        <SolidColorBrush x:Key="BgPanel" Color="#252538"/>
        <SolidColorBrush x:Key="BgCard" Color="#2A2A3E"/>
        <SolidColorBrush x:Key="BgInput" Color="#313244"/>
        <SolidColorBrush x:Key="BorderBrush" Color="#45475A"/>
        <SolidColorBrush x:Key="TextPrimary" Color="#CDD6F4"/>
        <SolidColorBrush x:Key="TextMuted" Color="#A6ADC8"/>
        <SolidColorBrush x:Key="AccentBlue" Color="#89B4FA"/>
        <SolidColorBrush x:Key="AccentGreen" Color="#A6E3A1"/>
        <SolidColorBrush x:Key="AccentRed" Color="#F38BA8"/>
        <SolidColorBrush x:Key="AccentYellow" Color="#F9E2AF"/>
        <SolidColorBrush x:Key="BtnPrimaryBg" Color="#3B82F6"/>
        <SolidColorBrush x:Key="BtnSuccessBg" Color="#10B981"/>
        <SolidColorBrush x:Key="BtnDangerBg" Color="#EF4444"/>

        <!-- Modern Button Style -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,6"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="5">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#45475A"/>
                                <Setter Property="BorderBrush" Value="#89B4FA"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#585B70"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="8,5"/>
            <Setter Property="CaretBrush" Value="#89B4FA"/>
            <Setter Property="VerticalContentAlignment" Value="Center"/>
        </Style>

        <!-- ComboBox Style -->
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#313244"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="6,4"/>
        </Style>

        <!-- DataGrid Dark Style -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="#252538"/>
            <Setter Property="Foreground" Value="#CDD6F4"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="GridLinesVisibility" Value="Horizontal"/>
            <Setter Property="HorizontalGridLinesBrush" Value="#313244"/>
            <Setter Property="RowBackground" Value="#252538"/>
            <Setter Property="AlternatingRowBackground" Value="#2A2A3E"/>
            <Setter Property="HeadersVisibility" Value="Column"/>
            <Setter Property="CanUserAddRows" Value="False"/>
            <Setter Property="CanUserDeleteRows" Value="False"/>
            <Setter Property="IsReadOnly" Value="True"/>
            <Setter Property="SelectionMode" Value="Single"/>
            <Setter Property="SelectionUnit" Value="FullRow"/>
            <Setter Property="RowHeight" Value="32"/>
            <Setter Property="FontSize" Value="12.5"/>
        </Style>

        <Style TargetType="DataGridColumnHeader">
            <Setter Property="Background" Value="#1E1E2E"/>
            <Setter Property="Foreground" Value="#89B4FA"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="BorderBrush" Value="#45475A"/>
            <Setter Property="BorderThickness" Value="0,0,1,1"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>

        <Style TargetType="DataGridCell">
            <Setter Property="Padding" Value="8,2"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="DataGridCell">
                        <Border Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
            <Style.Triggers>
                <Trigger Property="IsSelected" Value="True">
                    <Setter Property="Background" Value="#3B82F6"/>
                    <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <!-- TabControl Dark Style -->
        <Style TargetType="TabItem">
            <Setter Property="Background" Value="#252538"/>
            <Setter Property="Foreground" Value="#A6ADC8"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="16,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border Name="TabBorder" Background="{TemplateBinding Background}" BorderBrush="#45475A" BorderThickness="1,1,1,0" CornerRadius="6,6,0,0" Margin="0,0,4,0">
                            <ContentPresenter ContentSource="Header" Margin="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="TabBorder" Property="Background" Value="#313244"/>
                                <Setter Property="Foreground" Value="#89B4FA"/>
                                <Setter TargetName="TabBorder" Property="BorderBrush" Value="#89B4FA"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/> <!-- Header -->
            <RowDefinition Height="Auto"/> <!-- DB Toolbar -->
            <RowDefinition Height="*"/>    <!-- Tabs Content -->
            <RowDefinition Height="Auto"/> <!-- Status Bar -->
        </Grid.RowDefinitions>

        <!-- 1. Header Banner -->
        <Border Grid.Row="0" Background="#181825" BorderBrush="#313244" BorderThickness="0,0,0,1" Padding="16,12">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <TextBlock Text="⚡" FontSize="20" Margin="0,0,10,0" VerticalAlignment="Center"/>
                    <StackPanel>
                        <TextBlock Text="SQLite Database Manager" FontSize="18" FontWeight="Bold" Foreground="#CDD6F4"/>
                        <TextBlock Text="High-performance, transactional PowerShell SQLite GUI with sorting, CRUD &amp; query console" FontSize="11.5" Foreground="#A6ADC8"/>
                    </StackPanel>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Border Background="#313244" CornerRadius="12" Padding="10,4" Margin="0,0,8,0">
                        <TextBlock Name="TxtEngineVersion" Text="SQLite Engine" FontSize="11.5" Foreground="#89B4FA" FontWeight="SemiBold"/>
                    </Border>
                    <Border Background="#10B981" CornerRadius="12" Padding="10,4">
                        <TextBlock Text="CONNECTED" FontSize="11" Foreground="#FFFFFF" FontWeight="Bold"/>
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!-- 2. Database Selection Toolbar -->
        <Border Grid.Row="1" Background="#252538" BorderBrush="#313244" BorderThickness="0,0,0,1" Padding="14,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Column="0" Text="Database:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#A6ADC8" Margin="0,0,8,0"/>
                <TextBox Grid.Column="1" Name="TxtDbPath" Text="data\crud_demo.db" Margin="0,0,8,0" ToolTip="Active SQLite Database File"/>
                <Button Grid.Column="2" Name="BtnBrowseDb" Content="📂 Browse..." Margin="0,0,12,0"/>

                <TextBlock Grid.Column="3" Text="Table:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#A6ADC8" Margin="0,0,8,0"/>
                <ComboBox Grid.Column="4" Name="CmbTables" Width="170" Margin="0,0,10,0"/>

                <Button Grid.Column="5" Name="BtnRefreshAll" Content="🔄 Refresh" Background="#313244" ToolTip="Reload table data from SQLite"/>
            </Grid>
        </Border>

        <!-- 3. Main Tab Control -->
        <TabControl Grid.Row="2" Background="#1E1E2E" BorderBrush="#313244" Margin="12,10,12,6">
            <!-- TAB 1: Table Explorer & CRUD Manager -->
            <TabItem Header="📋 Table Explorer &amp; CRUD">
                <Grid Margin="0,10,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>        <!-- DataGrid Area -->
                        <ColumnDefinition Width="360"/>      <!-- CRUD Form Area -->
                    </Grid.ColumnDefinitions>

                    <!-- Left: Search Filter & DataGrid -->
                    <Grid Grid.Column="0" Margin="0,0,10,0">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                        </Grid.RowDefinitions>

                        <!-- Live Filter & Count Bar -->
                        <Grid Grid.Row="0" Margin="0,0,0,8">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <TextBlock Grid.Column="0" Text="🔍 Live Filter:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#A6ADC8" Margin="0,0,8,0"/>
                            <TextBox Grid.Column="1" Name="TxtFilter" Margin="0,0,10,0" ToolTip="Type any text to filter the table in real-time"/>
                            <Button Grid.Column="2" Name="BtnClearFilter" Content="Clear" Padding="8,4" FontSize="11"/>
                        </Grid>

                        <!-- DataGrid with Header Sorting -->
                        <Border Grid.Row="1" Background="#252538" BorderBrush="#313244" BorderThickness="1" CornerRadius="6">
                            <DataGrid Name="GridData" AutoGenerateColumns="True" CanUserSortColumns="True" Margin="2"/>
                        </Border>
                    </Grid>

                    <!-- Right: Dynamic Record Details & CRUD Operations Form -->
                    <Border Grid.Column="1" Background="#252538" BorderBrush="#313244" BorderThickness="1" CornerRadius="6" Padding="14">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/> <!-- Title & Table name -->
                                <RowDefinition Height="*"/>    <!-- Scrollable Dynamic Form Fields -->
                                <RowDefinition Height="Auto"/> <!-- Action Buttons -->
                                <RowDefinition Height="Auto"/> <!-- Status Feedback -->
                            </Grid.RowDefinitions>

                            <!-- Header -->
                            <Grid Grid.Row="0" Margin="0,0,0,10">
                                <StackPanel>
                                    <TextBlock Name="TxtEditorHeader" Text="Record Details / Editor" FontSize="15" FontWeight="Bold" Foreground="#89B4FA"/>
                                    <TextBlock Name="TxtEditorSubheader" Text="Dynamic Schema Form" FontSize="11" Foreground="#A6ADC8"/>
                                </StackPanel>
                                <Button Name="BtnSeedDemo" Content="⚡ Seed Demo" HorizontalAlignment="Right" VerticalAlignment="Top" Padding="8,4" FontSize="11" Background="#313244"/>
                            </Grid>

                            <!-- Scrollable Dynamic Controls -->
                            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
                                <StackPanel Name="DynamicFormContainer">
                                    <!-- Dynamically generated controls based on selected table schema -->
                                </StackPanel>
                            </ScrollViewer>

                            <!-- Action Buttons -->
                            <StackPanel Grid.Row="2">
                                <Grid Margin="0,0,0,8">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Grid.Column="0" Name="BtnInsert" Content="➕ Add New" Background="#10B981" Foreground="#FFFFFF" Margin="0,0,4,0" ToolTip="Insert new record into selected table"/>
                                    <Button Grid.Column="1" Name="BtnUpdate" Content="💾 Update" Background="#3B82F6" Foreground="#FFFFFF" Margin="4,0,0,0" ToolTip="Update selected record in selected table"/>
                                </Grid>

                                <Grid Margin="0,0,0,10">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Button Grid.Column="0" Name="BtnDelete" Content="🗑️ Delete" Background="#EF4444" Foreground="#FFFFFF" Margin="0,0,4,0" ToolTip="Delete selected record"/>
                                    <Button Grid.Column="1" Name="BtnClearForm" Content="🧹 Clear Form" Background="#313244" Margin="4,0,0,0" ToolTip="Clear input fields"/>
                                </Grid>
                            </StackPanel>

                            <!-- Status Badge -->
                            <Border Grid.Row="3" Name="FormFeedbackBorder" Background="#2A2A3E" CornerRadius="4" Padding="8,6">
                                <TextBlock Name="TxtFormFeedback" Text="Select a record to view and edit, or enter values and click Add New." FontSize="11" Foreground="#A6ADC8" TextWrapping="Wrap"/>
                            </Border>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <!-- TAB 2: SQL Query Sandbox & Snippets -->
            <TabItem Header="💻 SQL Query Console">
                <Grid Margin="0,10,0,0">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/> <!-- Quick Buttons -->
                        <RowDefinition Height="120"/>  <!-- Query Editor -->
                        <RowDefinition Height="Auto"/> <!-- Run Button Bar -->
                        <RowDefinition Height="*"/>    <!-- Results Grid -->
                    </Grid.RowDefinitions>

                    <!-- Quick Snippet Buttons -->
                    <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
                        <TextBlock Text="Quick Snippets:" VerticalAlignment="Center" FontWeight="SemiBold" Foreground="#A6ADC8" Margin="0,0,8,0"/>
                        <Button Name="BtnQrySelectAll" Content="SELECT All" Margin="0,0,6,0" Padding="8,4" FontSize="11"/>
                        <Button Name="BtnQryHighSalary" Content="Top Salaries" Margin="0,0,6,0" Padding="8,4" FontSize="11"/>
                        <Button Name="BtnQryDeptSummary" Content="Department Summary" Margin="0,0,6,0" Padding="8,4" FontSize="11"/>
                        <Button Name="BtnQryIntegrity" Content="PRAGMA integrity_check" Margin="0,0,6,0" Padding="8,4" FontSize="11"/>
                        <Button Name="BtnQryVacuum" Content="VACUUM" Margin="0,0,6,0" Padding="8,4" FontSize="11"/>
                    </StackPanel>

                    <!-- Query Box -->
                    <TextBox Grid.Row="1" Name="TxtQueryBox" AcceptsReturn="True" AcceptsTab="True" TextWrapping="Wrap"
                             FontFamily="Consolas" FontSize="13" Background="#181825" Foreground="#A6E3A1"
                             Padding="10" Text="SELECT * FROM Employees ORDER BY Salary DESC;"/>

                    <!-- Execution Bar -->
                    <Grid Grid.Row="2" Margin="0,8,0,8">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                            <Button Name="BtnExecuteQuery" Content="▶️ Execute Query (F5)" Background="#3B82F6" Foreground="#FFFFFF" Padding="14,6" FontWeight="Bold"/>
                            <TextBlock Name="TxtQueryTiming" Text="Ready to execute" VerticalAlignment="Center" Foreground="#A6ADC8" Margin="12,0,0,0" FontSize="12"/>
                        </StackPanel>
                        <Button Name="BtnExportQueryCsv" Content="📥 Export Results to CSV" HorizontalAlignment="Right" Padding="10,5"/>
                    </Grid>

                    <!-- Results Grid -->
                    <Border Grid.Row="3" Background="#252538" BorderBrush="#313244" BorderThickness="1" CornerRadius="6">
                        <DataGrid Name="GridQueryResults" AutoGenerateColumns="True" CanUserSortColumns="True" Margin="2"/>
                    </Border>
                </Grid>
            </TabItem>
        </TabControl>

        <!-- 4. Bottom Status Bar -->
        <Border Grid.Row="3" Background="#181825" BorderBrush="#313244" BorderThickness="0,1,0,0" Padding="12,6">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBlock Name="TxtStatusLeft" Text="Status: Initializing..." FontSize="11.5" Foreground="#A6ADC8"/>
                <TextBlock Grid.Column="1" Name="TxtStatusRight" Text="Rows: 0 | Selected: None" FontSize="11.5" Foreground="#89B4FA" FontWeight="SemiBold"/>
            </Grid>
        </Border>
    </Grid>
</Window>
"@
#endregion

# Load XAML
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

#region Apply DWM Dark Titlebar
$window.Add_SourceInitialized({
    try {
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($window)
        $val = 1
        [DwmDarkWindow]::DwmSetWindowAttribute($helper.Handle, 20, [ref]$val, 4) | Out-Null
        [DwmDarkWindow]::DwmSetWindowAttribute($helper.Handle, 19, [ref]$val, 4) | Out-Null
    }
    catch { }
})
#endregion

#region Control Element Bindings
$txtDbPath       = $window.FindName("TxtDbPath")
$btnBrowseDb     = $window.FindName("BtnBrowseDb")
$cmbTables       = $window.FindName("CmbTables")
$btnRefreshAll   = $window.FindName("BtnRefreshAll")
$txtEngineVer    = $window.FindName("TxtEngineVersion")

$txtFilter       = $window.FindName("TxtFilter")
$btnClearFilter  = $window.FindName("BtnClearFilter")
$gridData        = $window.FindName("GridData")

$dynamicFormContainer = $window.FindName("DynamicFormContainer")
$txtEditorHeader      = $window.FindName("TxtEditorHeader")
$txtEditorSubheader   = $window.FindName("TxtEditorSubheader")

$btnInsert       = $window.FindName("BtnInsert")
$btnUpdate       = $window.FindName("BtnUpdate")
$btnDelete       = $window.FindName("BtnDelete")
$btnClearForm    = $window.FindName("BtnClearForm")
$btnSeedDemo     = $window.FindName("BtnSeedDemo")
$txtFormFeedback = $window.FindName("TxtFormFeedback")
$formFeedbackBdr = $window.FindName("FormFeedbackBorder")

$txtQueryBox     = $window.FindName("TxtQueryBox")
$btnExecuteQuery = $window.FindName("BtnExecuteQuery")
$txtQueryTiming  = $window.FindName("TxtQueryTiming")
$gridQueryResults= $window.FindName("GridQueryResults")
$btnExportCsv    = $window.FindName("BtnExportQueryCsv")

$btnQrySelectAll = $window.FindName("BtnQrySelectAll")
$btnQryHighSalary= $window.FindName("BtnQryHighSalary")
$btnQryDeptSumm  = $window.FindName("BtnQryDeptSummary")
$btnQryIntegrity = $window.FindName("BtnQryIntegrity")
$btnQryVacuum    = $window.FindName("BtnQryVacuum")

$txtStatusLeft   = $window.FindName("TxtStatusLeft")
$txtStatusRight  = $window.FindName("TxtStatusRight")
#endregion

# Dynamic Schema State
$script:CurrentTableColumns = @()
$script:DynamicFormControls = [ordered]@{}
$script:PrimaryKeyCols      = @()

# Set initial default values
$txtDbPath.Text = $script:CurrentDb

#region Helper Functions

function Update-EngineVersionBadge {
    try {
        $ver = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query "SELECT sqlite_version() AS Ver;" -AsScalar
        $txtEngineVer.Text = "SQLite v$ver"
    }
    catch {
        $txtEngineVer.Text = "SQLite Engine"
    }
}

function Load-DatabaseTables {
    $cmbTables.Items.Clear()
    try {
        $tables = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"
        if ($tables) {
            foreach ($t in $tables) {
                $cmbTables.Items.Add($t.name) | Out-Null
            }
            if ($cmbTables.Items.Contains($script:CurrentTable)) {
                $cmbTables.SelectedItem = $script:CurrentTable
            }
            elseif ($cmbTables.Items.Count -gt 0) {
                $cmbTables.SelectedIndex = 0
            }
        }
    }
    catch {
        $txtStatusLeft.Text = "Error loading tables: $_"
    }
}

function Set-FormFeedback {
    param([string]$Message, [string]$Color = '#A6ADC8')
    $txtFormFeedback.Text = $Message
    $txtFormFeedback.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
}

function Build-DynamicForm {
    $dynamicFormContainer.Children.Clear()
    $script:DynamicFormControls = [ordered]@{}
    $script:PrimaryKeyCols = @()

    if (-not $script:CurrentTable) {
        $txtEditorHeader.Text = "No Table Selected"
        $txtEditorSubheader.Text = "Select a table to inspect schema and records"
        return
    }

    $txtEditorHeader.Text = "Table: $($script:CurrentTable)"

    # Query schema using PRAGMA table_info
    try {
        $cols = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query "PRAGMA table_info([$($script:CurrentTable)]);"
        if (-not $cols) {
            $txtEditorSubheader.Text = "No columns found for this table"
            return
        }
        if ($cols -isnot [System.Array]) {
            $cols = @($cols)
        }
        $script:CurrentTableColumns = $cols
    }
    catch {
        $txtEditorSubheader.Text = "Error reading schema: $_"
        Set-FormFeedback "Schema error: $_" "#EF4444"
        return
    }

    # Identify primary key columns
    foreach ($col in $script:CurrentTableColumns) {
        if ([int]$col.pk -gt 0) {
            $script:PrimaryKeyCols += [string]$col.name
        }
    }

    $pkInfo = if ($script:PrimaryKeyCols.Count -gt 0) { $script:PrimaryKeyCols -join ', ' } else { 'None' }
    $txtEditorSubheader.Text = "$($script:CurrentTableColumns.Count) columns | PK: $pkInfo"

    $brushConverter = [System.Windows.Media.BrushConverter]::new()
    $cText        = $brushConverter.ConvertFromString("#CAD3F5")
    $cType        = $brushConverter.ConvertFromString("#6E738D")
    $cPkBadge     = $brushConverter.ConvertFromString("#F5A97F")
    $cReqBadge    = $brushConverter.ConvertFromString("#ED8796")
    $cInputBg     = $brushConverter.ConvertFromString("#181825")
    $cInputBorder = $brushConverter.ConvertFromString("#313244")
    $cReadonlyBg  = $brushConverter.ConvertFromString("#14141F")
    $cReadonlyFg  = $brushConverter.ConvertFromString("#89B4FA")

    foreach ($col in $script:CurrentTableColumns) {
        $colName = [string]$col.name
        $colType = if ($col.type) { [string]$col.type.ToUpper() } else { "TEXT" }
        $isPk    = [int]$col.pk -gt 0
        $isReq   = [int]$col.notnull -gt 0
        $dflt    = if ($col.dflt_value) { [string]$col.dflt_value } else { $null }

        $fieldPanel = [System.Windows.Controls.StackPanel]::new()
        $fieldPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 7)

        # Label Row
        $labelPanel = [System.Windows.Controls.StackPanel]::new()
        $labelPanel.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $labelPanel.Margin = [System.Windows.Thickness]::new(0, 0, 0, 3)

        $lblTitle = [System.Windows.Controls.TextBlock]::new()
        $lblTitle.Text = $colName
        $lblTitle.FontWeight = [System.Windows.FontWeights]::SemiBold
        $lblTitle.Foreground = $cText
        $lblTitle.FontSize = 11.5
        $labelPanel.Children.Add($lblTitle) | Out-Null

        if ($isPk) {
            $lblPk = [System.Windows.Controls.TextBlock]::new()
            $lblPk.Text = " [PK]"
            $lblPk.FontWeight = [System.Windows.FontWeights]::Bold
            $lblPk.Foreground = $cPkBadge
            $lblPk.FontSize = 10.5
            $lblPk.Margin = [System.Windows.Thickness]::new(3, 0, 0, 0)
            $labelPanel.Children.Add($lblPk) | Out-Null
        }

        if ($isReq -and -not $isPk) {
            $lblReq = [System.Windows.Controls.TextBlock]::new()
            $lblReq.Text = " *"
            $lblReq.FontWeight = [System.Windows.FontWeights]::Bold
            $lblReq.Foreground = $cReqBadge
            $lblReq.FontSize = 11.5
            $lblReq.ToolTip = "Field is required (NOT NULL)"
            $labelPanel.Children.Add($lblReq) | Out-Null
        }

        $lblType = [System.Windows.Controls.TextBlock]::new()
        $lblType.Text = " ($colType)"
        $lblType.Foreground = $cType
        $lblType.FontSize = 10
        $lblType.Margin = [System.Windows.Thickness]::new(4, 1, 0, 0)
        $labelPanel.Children.Add($lblType) | Out-Null

        $fieldPanel.Children.Add($labelPanel) | Out-Null

        # Control mapping
        if ($isPk -and $colType -match 'INT') {
            # Auto-increment Integer PK
            $txtBox = [System.Windows.Controls.TextBox]::new()
            $txtBox.Height = 26
            $txtBox.IsReadOnly = $true
            $txtBox.Background = $cReadonlyBg
            $txtBox.Foreground = $cReadonlyFg
            $txtBox.BorderBrush = $cInputBorder
            $txtBox.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
            $txtBox.ToolTip = "Primary Key (Auto-assigned by database on Insert)"
            $txtBox.Text = "(Auto)"
            $fieldPanel.Children.Add($txtBox) | Out-Null

            $script:DynamicFormControls[$colName] = @{
                Control = $txtBox
                ColInfo = $col
                Kind    = 'AutoPK'
            }
        }
        elseif ($colType -match 'INT|BOOL' -and $colName -match '^(Is|Has|Active|Enabled|Success)') {
            # Boolean Checkbox
            $chkBox = [System.Windows.Controls.CheckBox]::new()
            $chkBox.Content = "Active / True (1)"
            $chkBox.Foreground = $cText
            $chkBox.Margin = [System.Windows.Thickness]::new(2, 2, 0, 2)
            $chkBox.IsChecked = ($dflt -eq '1' -or $dflt -eq "'1'")
            $fieldPanel.Children.Add($chkBox) | Out-Null

            $script:DynamicFormControls[$colName] = @{
                Control = $chkBox
                ColInfo = $col
                Kind    = 'CheckBox'
            }
        }
        elseif ($colType -match 'TEXT' -and $colName -match '^(Message|Description|Details|Notes|Payload|Log|Body|Sql|Content|Summary)') {
            # Multi-line Text Box
            $txtBox = [System.Windows.Controls.TextBox]::new()
            $txtBox.Height = 65
            $txtBox.AcceptsReturn = $true
            $txtBox.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $txtBox.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
            $txtBox.Background = $cInputBg
            $txtBox.Foreground = $cText
            $txtBox.BorderBrush = $cInputBorder
            $txtBox.Padding = [System.Windows.Thickness]::new(6, 4, 6, 4)
            $txtBox.FontFamily = [System.Windows.Media.FontFamily]::new("Consolas")
            $txtBox.FontSize = 11.5
            $fieldPanel.Children.Add($txtBox) | Out-Null

            $script:DynamicFormControls[$colName] = @{
                Control = $txtBox
                ColInfo = $col
                Kind    = 'MultiLineText'
            }
        }
        elseif ($colName -match 'Date|Time|Created|Timestamp') {
            # Date/Timestamp Box
            $txtBox = [System.Windows.Controls.TextBox]::new()
            $txtBox.Height = 26
            $txtBox.Background = $cInputBg
            $txtBox.Foreground = $cText
            $txtBox.BorderBrush = $cInputBorder
            $txtBox.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
            if ($colName -match 'HireDate|BirthDate') {
                $txtBox.Text = (Get-Date -Format 'yyyy-MM-dd')
            }
            else {
                $txtBox.Text = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }
            $fieldPanel.Children.Add($txtBox) | Out-Null

            $script:DynamicFormControls[$colName] = @{
                Control = $txtBox
                ColInfo = $col
                Kind    = 'DateText'
            }
        }
        else {
            # Standard Text / Number Box
            $txtBox = [System.Windows.Controls.TextBox]::new()
            $txtBox.Height = 26
            $txtBox.Background = $cInputBg
            $txtBox.Foreground = $cText
            $txtBox.BorderBrush = $cInputBorder
            $txtBox.Padding = [System.Windows.Thickness]::new(6, 2, 6, 2)
            if ($dflt -and $dflt -notmatch 'NULL|CURRENT_') {
                $txtBox.Text = $dflt.Trim("'")
            }
            $fieldPanel.Children.Add($txtBox) | Out-Null

            $script:DynamicFormControls[$colName] = @{
                Control = $txtBox
                ColInfo = $col
                Kind    = 'StandardText'
            }
        }

        $dynamicFormContainer.Children.Add($fieldPanel) | Out-Null
    }
}

function Clear-InputForm {
    foreach ($colName in $script:DynamicFormControls.Keys) {
        $item = $script:DynamicFormControls[$colName]
        $ctrl = $item.Control
        $col  = $item.ColInfo
        $dflt = if ($col.dflt_value) { [string]$col.dflt_value } else { $null }

        switch ($item.Kind) {
            'AutoPK' {
                $ctrl.Text = "(Auto)"
            }
            'CheckBox' {
                $ctrl.IsChecked = ($dflt -eq '1' -or $dflt -eq "'1'")
            }
            'DateText' {
                if ($colName -match 'HireDate|BirthDate') {
                    $ctrl.Text = (Get-Date -Format 'yyyy-MM-dd')
                }
                else {
                    $ctrl.Text = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                }
            }
            default {
                if ($dflt -and $dflt -notmatch 'NULL|CURRENT_') {
                    $ctrl.Text = $dflt.Trim("'")
                }
                else {
                    $ctrl.Text = ""
                }
            }
        }
    }
    Set-FormFeedback "Form cleared. Enter values and click 'Add New'." "#A6ADC8"
}

function Load-TableData {
    if (-not $cmbTables.SelectedItem) { return }
    $script:CurrentTable = $cmbTables.SelectedItem.ToString()

    Build-DynamicForm

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $query = "SELECT * FROM [$($script:CurrentTable)];"
        $dt = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $query -AsDataTable
        $sw.Stop()

        $script:CurrentDataTable = $dt
        $gridData.ItemsSource = $dt.DefaultView

        # Clear filter box
        $txtFilter.Text = ""
        Clear-InputForm

        $rowCount = if ($dt) { $dt.Rows.Count } else { 0 }
        $txtStatusLeft.Text = "DB: $([System.IO.Path]::GetFileName($script:CurrentDb)) | Table: $($script:CurrentTable)"
        $txtStatusRight.Text = "Loaded $rowCount rows in $($sw.ElapsedMilliseconds) ms"

        Set-FormFeedback "Table '$($script:CurrentTable)' loaded ($rowCount rows)." "#10B981"
    }
    catch {
        $sw.Stop()
        $txtStatusLeft.Text = "Query error: $_"
        Set-FormFeedback "Error loading table: $_" "#EF4444"
    }
}

#endregion

#region Event Handlers

# Table Selection Change
$cmbTables.Add_SelectionChanged({
    if ($cmbTables.SelectedItem) {
        $script:CurrentTable = $cmbTables.SelectedItem.ToString()
        Load-TableData
    }
})

# Refresh All Button
$btnRefreshAll.Add_Click({
    Load-DatabaseTables
    Load-TableData
})

# Browse Database File
$btnBrowseDb.Add_Click({
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = "SQLite Databases (*.db;*.sqlite;*.sqlite3)|*.db;*.sqlite;*.sqlite3|All Files (*.*)|*.*"
    $dlg.InitialDirectory = Split-Path -Parent $script:CurrentDb
    if ($dlg.ShowDialog() -eq $true) {
        $script:CurrentDb = $dlg.FileName
        $txtDbPath.Text = $script:CurrentDb
        Connect-SqliteDb -DataSource $script:CurrentDb -EnableWal | Out-Null
        Update-EngineVersionBadge
        Load-DatabaseTables
        Load-TableData
    }
})

# Real-Time Filter / Search
$txtFilter.Add_TextChanged({
    if (-not $script:CurrentDataTable) { return }
    $filterText = $txtFilter.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($filterText)) {
        $script:CurrentDataTable.DefaultView.RowFilter = ""
    }
    else {
        # Build dynamic row filter across text and numeric columns
        $conditions = @()
        $escaped = $filterText.Replace("'", "''")
        foreach ($col in $script:CurrentDataTable.Columns) {
            $colName = $col.ColumnName
            if ($col.DataType -eq [string] -or $col.DataType -eq [System.String]) {
                $conditions += "[$colName] LIKE '%$escaped%'"
            }
            elseif ($col.DataType -eq [int] -or $col.DataType -eq [long] -or $col.DataType -eq [double] -or $col.DataType -eq [decimal]) {
                $conditions += "Convert([$colName], 'System.String') LIKE '%$escaped%'"
            }
        }
        if ($conditions.Count -gt 0) {
            try {
                $script:CurrentDataTable.DefaultView.RowFilter = $conditions -join " OR "
            }
            catch { }
        }
    }
    $filteredCount = $script:CurrentDataTable.DefaultView.Count
    $txtStatusRight.Text = "Filter matches: $filteredCount / $($script:CurrentDataTable.Rows.Count) rows"
})

$btnClearFilter.Add_Click({
    $txtFilter.Text = ""
    if ($script:CurrentDataTable) {
        $script:CurrentDataTable.DefaultView.RowFilter = ""
        $txtStatusRight.Text = "Rows: $($script:CurrentDataTable.Rows.Count)"
    }
})

# Row Selection Populates Dynamic Edit Form
$gridData.Add_SelectionChanged({
    if ($gridData.SelectedItem) {
        $row = $null
        if ($gridData.SelectedItem -is [System.Data.DataRowView]) {
            $row = $gridData.SelectedItem.Row
        }
        elseif ($gridData.SelectedItem -is [System.Data.DataRow]) {
            $row = $gridData.SelectedItem
        }

        if ($row) {
            foreach ($colName in $script:DynamicFormControls.Keys) {
                $item = $script:DynamicFormControls[$colName]
                $ctrl = $item.Control
                if ($row.Table.Columns.Contains($colName)) {
                    $val = $row[$colName]
                    if ($item.Kind -eq 'CheckBox') {
                        $ctrl.IsChecked = if ($val -isnot [System.DBNull] -and ($val -eq 1 -or [string]$val -eq 'True' -or [string]$val -eq '1')) { $true } else { $false }
                    }
                    else {
                        if ($val -is [System.DBNull] -or $null -eq $val) {
                            $ctrl.Text = ""
                        }
                        else {
                            $ctrl.Text = $val.ToString()
                        }
                    }
                }
            }

            $pkDisplay = @()
            foreach ($pk in $script:PrimaryKeyCols) {
                if ($row.Table.Columns.Contains($pk)) {
                    $pkDisplay += "$pk=$($row[$pk])"
                }
            }
            $pkText = if ($pkDisplay.Count -gt 0) { $pkDisplay -join ', ' } else { "Row $($gridData.SelectedIndex + 1)" }

            $txtStatusRight.Text = "Selected: $pkText"
            Set-FormFeedback "Viewing record ($pkText). You can edit fields and click Update, or Delete." "#89B4FA"
        }
    }
})

# Clear Form Button
$btnClearForm.Add_Click({
    Clear-InputForm
})

# Dynamic Insert Record
$btnInsert.Add_Click({
    if (-not $script:CurrentTable) {
        [System.Windows.MessageBox]::Show("Please select a table first.", "Validation Error", "OK", "Warning")
        return
    }

    $insertCols = @()
    $paramPlaceholders = @()
    $sqlParams = @{}
    $missingFields = @()

    foreach ($colName in $script:DynamicFormControls.Keys) {
        $item = $script:DynamicFormControls[$colName]
        $ctrl = $item.Control
        $col  = $item.ColInfo

        # Skip auto-increment integer PK
        if ($item.Kind -eq 'AutoPK') {
            continue
        }

        $val = $null
        if ($item.Kind -eq 'CheckBox') {
            $val = if ($ctrl.IsChecked) { 1 } else { 0 }
        }
        else {
            $rawText = $ctrl.Text.Trim()
            if ([int]$col.notnull -gt 0 -and [string]::IsNullOrWhiteSpace($rawText) -and [string]::IsNullOrEmpty($col.dflt_value)) {
                $missingFields += $colName
            }
            if ([string]::IsNullOrWhiteSpace($rawText)) {
                $val = [System.DBNull]::Value
            }
            else {
                if ($col.type -match 'INT') {
                    $numVal = 0
                    if ([long]::TryParse($rawText, [ref]$numVal)) { $val = $numVal } else { $val = $rawText }
                }
                elseif ($col.type -match 'REAL|FLOAT|DOUBLE|NUMERIC') {
                    $dblVal = 0.0
                    if ([double]::TryParse($rawText, [ref]$dblVal)) { $val = $dblVal } else { $val = $rawText }
                }
                else {
                    $val = $rawText
                }
            }
        }

        $paramKey = "p_" + ($colName -replace '[^a-zA-Z0-9_]', '_')
        $insertCols += "[$colName]"
        $paramPlaceholders += "@$paramKey"
        $sqlParams[$paramKey] = $val
    }

    if ($missingFields.Count -gt 0) {
        [System.Windows.MessageBox]::Show("The following required (NOT NULL) fields are empty:`n- $($missingFields -join "`n- ")", "Validation Error", "OK", "Warning")
        return
    }

    if ($insertCols.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No columns available to insert.", "Validation Error", "OK", "Warning")
        return
    }

    $colStr    = $insertCols -join ", "
    $valStr    = $paramPlaceholders -join ", "
    $insertSql = "INSERT INTO [$($script:CurrentTable)] ($colStr) VALUES ($valStr);"

    try {
        Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $insertSql -SqlParameters $sqlParams | Out-Null
        Set-FormFeedback "✅ Inserted new record into '$($script:CurrentTable)' successfully!" "#10B981"
        Load-TableData
        Clear-InputForm
    }
    catch {
        Set-FormFeedback "❌ Insert failed: $_" "#EF4444"
        [System.Windows.MessageBox]::Show("Insert failed: $_", "Database Error", "OK", "Error")
    }
})

# Dynamic Update Record
$btnUpdate.Add_Click({
    if (-not $script:CurrentTable) {
        [System.Windows.MessageBox]::Show("Please select a table first.", "Validation Error", "OK", "Warning")
        return
    }

    if ($script:PrimaryKeyCols.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Table '$($script:CurrentTable)' has no Primary Key defined. Direct updates via GUI require a Primary Key.", "No Primary Key", "OK", "Warning")
        return
    }

    $whereClauses = @()
    $sqlParams = @{}
    foreach ($pk in $script:PrimaryKeyCols) {
        if (-not $script:DynamicFormControls.Contains($pk)) {
            [System.Windows.MessageBox]::Show("Primary Key column '$pk' not found in form controls.", "Update Error", "OK", "Error")
            return
        }
        $ctrl = $script:DynamicFormControls[$pk].Control
        $val = $ctrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val) -or $val -eq "(Auto)") {
            [System.Windows.MessageBox]::Show("Please select an existing record from the grid first to update.", "Selection Required", "OK", "Information")
            return
        }
        $paramKey = "pk_" + ($pk -replace '[^a-zA-Z0-9_]', '_')
        $whereClauses += "[$pk] = @$paramKey"
        $sqlParams[$paramKey] = $val
    }

    $setClauses = @()
    $missingFields = @()

    foreach ($colName in $script:DynamicFormControls.Keys) {
        if ($script:PrimaryKeyCols -contains $colName) {
            continue
        }

        $item = $script:DynamicFormControls[$colName]
        $ctrl = $item.Control
        $col  = $item.ColInfo

        $val = $null
        if ($item.Kind -eq 'CheckBox') {
            $val = if ($ctrl.IsChecked) { 1 } else { 0 }
        }
        else {
            $rawText = $ctrl.Text.Trim()
            if ([int]$col.notnull -gt 0 -and [string]::IsNullOrWhiteSpace($rawText) -and [string]::IsNullOrEmpty($col.dflt_value)) {
                $missingFields += $colName
            }
            if ([string]::IsNullOrWhiteSpace($rawText)) {
                $val = [System.DBNull]::Value
            }
            else {
                if ($col.type -match 'INT') {
                    $numVal = 0
                    if ([long]::TryParse($rawText, [ref]$numVal)) { $val = $numVal } else { $val = $rawText }
                }
                elseif ($col.type -match 'REAL|FLOAT|DOUBLE|NUMERIC') {
                    $dblVal = 0.0
                    if ([double]::TryParse($rawText, [ref]$dblVal)) { $val = $dblVal } else { $val = $rawText }
                }
                else {
                    $val = $rawText
                }
            }
        }

        $paramKey = "set_" + ($colName -replace '[^a-zA-Z0-9_]', '_')
        $setClauses += "[$colName] = @$paramKey"
        $sqlParams[$paramKey] = $val
    }

    if ($missingFields.Count -gt 0) {
        [System.Windows.MessageBox]::Show("The following required (NOT NULL) fields are empty:`n- $($missingFields -join "`n- ")", "Validation Error", "OK", "Warning")
        return
    }

    if ($setClauses.Count -eq 0) {
        [System.Windows.MessageBox]::Show("No non-primary key columns available to update.", "Validation Error", "OK", "Warning")
        return
    }

    $setStr    = $setClauses -join ", "
    $whereStr  = $whereClauses -join " AND "
    $updateSql = "UPDATE [$($script:CurrentTable)] SET $setStr WHERE $whereStr;"

    try {
        Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $updateSql -SqlParameters $sqlParams | Out-Null
        Set-FormFeedback "✅ Record updated successfully!" "#10B981"
        Load-TableData
    }
    catch {
        Set-FormFeedback "❌ Update failed: $_" "#EF4444"
        [System.Windows.MessageBox]::Show("Update failed: $_", "Database Error", "OK", "Error")
    }
})

# Dynamic Delete Record
$btnDelete.Add_Click({
    if (-not $script:CurrentTable) {
        [System.Windows.MessageBox]::Show("Please select a table first.", "Validation Error", "OK", "Warning")
        return
    }

    if ($script:PrimaryKeyCols.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Table '$($script:CurrentTable)' has no Primary Key defined. Deletes via GUI require a Primary Key.", "No Primary Key", "OK", "Warning")
        return
    }

    $whereClauses = @()
    $sqlParams = @{}
    $pkDisplay = @()

    foreach ($pk in $script:PrimaryKeyCols) {
        if (-not $script:DynamicFormControls.Contains($pk)) {
            [System.Windows.MessageBox]::Show("Primary Key column '$pk' not found in form controls.", "Delete Error", "OK", "Error")
            return
        }
        $ctrl = $script:DynamicFormControls[$pk].Control
        $val = $ctrl.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($val) -or $val -eq "(Auto)") {
            [System.Windows.MessageBox]::Show("Please select a record from the grid to delete.", "Selection Required", "OK", "Information")
            return
        }
        $paramKey = "pk_" + ($pk -replace '[^a-zA-Z0-9_]', '_')
        $whereClauses += "[$pk] = @$paramKey"
        $sqlParams[$paramKey] = $val
        $pkDisplay += "$pk = $val"
    }

    $pkStr = $pkDisplay -join ", "
    $confirm = [System.Windows.MessageBox]::Show(
        "Are you sure you want to delete record ($pkStr) from table '$($script:CurrentTable)'?`nThis operation cannot be undone.",
        "Confirm Delete",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )

    if ($confirm -eq [System.Windows.MessageBoxResult]::Yes) {
        try {
            $whereStr = $whereClauses -join " AND "
            $deleteSql = "DELETE FROM [$($script:CurrentTable)] WHERE $whereStr;"
            Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $deleteSql -SqlParameters $sqlParams | Out-Null
            Set-FormFeedback "🗑️ Record ($pkStr) deleted." "#F38BA8"
            Load-TableData
            Clear-InputForm
        }
        catch {
            Set-FormFeedback "❌ Delete failed: $_" "#EF4444"
            [System.Windows.MessageBox]::Show("Delete failed: $_", "Database Error", "OK", "Error")
        }
    }
})

# Seed Demo Records (Table-Aware)
$btnSeedDemo.Add_Click({
    try {
        if ($script:CurrentTable -eq 'Employees' -or -not $script:CurrentTable) {
            $initSql = @"
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
            Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $initSql | Out-Null

            $demoSeed = @(
                @{ Username = "amnich_$(Get-Random -Min 100 -Max 999)"; FullName = "Adam Mnich"; Email = "amnich@bgh.pl"; Department = "IT Infrastructure"; Salary = 11500.00; HireDate = "2020-03-01"; IsActive = 1 },
                @{ Username = "jkowalski_$(Get-Random -Min 100 -Max 999)"; FullName = "Jan Kowalski"; Email = "j.kowalski@bgh.pl"; Department = "Logistics"; Salary = 6500.00; HireDate = "2022-04-15"; IsActive = 1 },
                @{ Username = "anowak_$(Get-Random -Min 100 -Max 999)"; FullName = "Anna Nowak"; Email = "a.nowak@bgh.pl"; Department = "Finance"; Salary = 8200.00; HireDate = "2021-08-01"; IsActive = 1 },
                @{ Username = "twagner_$(Get-Random -Min 100 -Max 999)"; FullName = "Thomas Wagner"; Email = "t.wagner@bgh.de"; Department = "Business Central ERP"; Salary = 12500.00; HireDate = "2019-10-01"; IsActive = 1 }
            )

            Invoke-SqliteTransaction -DataSource $script:CurrentDb -ScriptBlock {
                param($conn)
                $q = "INSERT INTO Employees (Username, FullName, Email, Department, Salary, HireDate, IsActive) VALUES (@Username, @FullName, @Email, @Department, @Salary, @HireDate, @IsActive);"
                foreach ($item in $demoSeed) {
                    Invoke-SqliteCmd -SQLiteConnection $conn -Query $q -SqlParameters $item | Out-Null
                }
            }
            Set-FormFeedback "⚡ Seeded demo employees successfully!" "#10B981"
        }
        elseif ($script:CurrentTable -eq 'SystemServices') {
            $services = Get-Service | Select-Object -First 10
            Invoke-SqliteTransaction -DataSource $script:CurrentDb -ScriptBlock {
                param($conn)
                $q = "INSERT OR REPLACE INTO SystemServices (ServiceName, DisplayName, Status, StartType, CapturedAt) VALUES (@ServiceName, @DisplayName, @Status, @StartType, @CapturedAt);"
                foreach ($s in $services) {
                    $p = @{
                        ServiceName = $s.Name
                        DisplayName = $s.DisplayName
                        Status      = $s.Status.ToString()
                        StartType   = $s.StartType.ToString()
                        CapturedAt  = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
                    }
                    Invoke-SqliteCmd -SQLiteConnection $conn -Query $q -SqlParameters $p | Out-Null
                }
            }
            Set-FormFeedback "⚡ Seeded top 10 Windows Services!" "#10B981"
        }
        elseif ($script:CurrentTable -eq 'ApplicationEvents') {
            $nowStr = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            $q = "INSERT INTO ApplicationEvents (EventId, Level, LevelDisplayName, ProviderName, TimeCreated, Message) VALUES (@EventId, @Level, @LevelDisplayName, @ProviderName, @TimeCreated, @Message);"
            Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $q -SqlParameters @{
                EventId = 1001; Level = 4; LevelDisplayName = "Information"; ProviderName = "PowerShell-Demo"; TimeCreated = $nowStr; Message = "Sample benchmark application event logged from GUI seed."
            } | Out-Null
            Set-FormFeedback "⚡ Seeded demo application event!" "#10B981"
        }
        else {
            Set-FormFeedback "💡 Use '➕ Add New' button to add custom records to '$($script:CurrentTable)'." "#89B4FA"
        }

        Load-DatabaseTables
        Load-TableData
    }
    catch {
        Set-FormFeedback "❌ Seeding failed: $_" "#EF4444"
    }
})

# Custom Query Execution
$btnExecuteQuery.Add_Click({
    $sql = $txtQueryBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($sql)) { return }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $dt = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $sql -AsDataTable
        $sw.Stop()

        if ($dt) {
            $gridQueryResults.ItemsSource = $dt.DefaultView
            $txtQueryTiming.Text = "Executed in $($sw.ElapsedMilliseconds) ms | $($dt.Rows.Count) rows returned"
            $txtQueryTiming.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#A6E3A1")
        }
        else {
            $gridQueryResults.ItemsSource = $null
            $txtQueryTiming.Text = "Statement executed in $($sw.ElapsedMilliseconds) ms (no rows returned)"
            $txtQueryTiming.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#89B4FA")
        }
    }
    catch {
        $sw.Stop()
        $gridQueryResults.ItemsSource = $null
        $txtQueryTiming.Text = "Error: $($_.Exception.Message)"
        $txtQueryTiming.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString("#F38BA8")
    }
})

# Query Snippet Buttons
$btnQrySelectAll.Add_Click({
    $tbl = if ($script:CurrentTable) { $script:CurrentTable } else { "Employees" }
    $txtQueryBox.Text = "SELECT * FROM [$tbl] LIMIT 100;"
    $btnExecuteQuery.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})

$btnQryHighSalary.Add_Click({
    $txtQueryBox.Text = "SELECT FullName, Department, Salary FROM Employees WHERE Salary >= 8000 ORDER BY Salary DESC;"
    $btnExecuteQuery.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})

$btnQryDeptSumm.Add_Click({
    $txtQueryBox.Text = @"
SELECT
    Department,
    COUNT(*) AS Headcount,
    ROUND(AVG(Salary), 2) AS AvgSalary,
    ROUND(SUM(Salary), 2) AS TotalPayroll
FROM Employees
GROUP BY Department
ORDER BY TotalPayroll DESC;
"@
    $btnExecuteQuery.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})

$btnQryIntegrity.Add_Click({
    $txtQueryBox.Text = "PRAGMA integrity_check;"
    $btnExecuteQuery.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})

$btnQryVacuum.Add_Click({
    $txtQueryBox.Text = "VACUUM;"
    $btnExecuteQuery.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent)))
})

# Export Results to CSV
$btnExportCsv.Add_Click({
    $sql = $txtQueryBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($sql)) { return }

    try {
        $exportData = Invoke-SqliteCmd -DataSource $script:CurrentDb -Query $sql
        if (-not $exportData) {
            [System.Windows.MessageBox]::Show("Query produced no data to export.", "Empty Result", "OK", "Information")
            return
        }

        $sfd = New-Object Microsoft.Win32.SaveFileDialog
        $sfd.Filter = "CSV Files (*.csv)|*.csv"
        $sfd.FileName = "QueryResult_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        if ($sfd.ShowDialog() -eq $true) {
            $utf8Bom = New-Object System.Text.UTF8Encoding($true)
            $csvContent = $exportData | ConvertTo-Csv -NoTypeInformation -Delimiter ';'
            [System.IO.File]::WriteAllLines($sfd.FileName, [string[]]$csvContent, $utf8Bom)
            [System.Windows.MessageBox]::Show("Exported successfully to:`n$($sfd.FileName)", "Export Complete", "OK", "Information")
        }
    }
    catch {
        [System.Windows.MessageBox]::Show("Export failed: $_", "Error", "OK", "Error")
    }
})

# Window Loaded Initialization
$window.Add_Loaded({
    Update-EngineVersionBadge
    Load-DatabaseTables
    Load-TableData
    Clear-InputForm
})

#endregion

# Show Window
$window.ShowDialog() | Out-Null
