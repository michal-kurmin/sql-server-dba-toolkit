<#
.SYNOPSIS
    Runs a read-only SQL Server health check and writes a Markdown report.

.DESCRIPTION
    Connects to a target Microsoft SQL Server instance using Windows Integrated
    Authentication (default) or a supplied PSCredential, gathers instance info,
    database states, and backup recency, and outputs a clean Markdown summary.

.PARAMETER SqlInstance
    Target SQL Server instance (e.g. "localhost\SQLEXPRESS" or "sql01.corp.local").

.PARAMETER Credential
    Optional SQL Authentication PSCredential. When omitted, Integrated Security is used.

.PARAMETER FullBackupThresholdHours
    Flag databases whose last FULL backup is older than this threshold (default: 24 hours).

.PARAMETER OutputPath
    File path for the generated Markdown report.

.EXAMPLE
    .\Invoke-SqlHealthCheck.ps1 -SqlInstance "localhost\SQLEXPRESS" -OutputPath ".\health-report.md"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlInstance,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential]$Credential,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 720)]
    [int]$FullBackupThresholdHours = 24,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".\health-report.md"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-SqlQuery {
    param (
        [string]$Server,
        [string]$Query,
        [System.Management.Automation.PSCredential]$SqlCred
    )

    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new()
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = 'master'
    $builder['Connect Timeout'] = 10
    $builder['Application Name'] = 'SqlServerDbaToolkit'

    if ($null -ne $SqlCred) {
        $builder['Integrated Security'] = $false
        $builder['User ID'] = $SqlCred.UserName
        $builder['Password'] = $SqlCred.GetNetworkCredential().Password
    } else {
        $builder['Integrated Security'] = $true
    }

    $conn = [System.Data.SqlClient.SqlConnection]::new($builder.ConnectionString)
    try {
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 30

        $adapter = [System.Data.SqlClient.SqlDataAdapter]::new($cmd)
        $table = [System.Data.DataTable]::new()
        [void]$adapter.Fill($table)
        return $table
    }
    finally {
        $conn.Dispose()
    }
}

$instanceQuery = @"
SELECT
    CAST(SERVERPROPERTY('ServerName') AS NVARCHAR(128)) AS ServerName,
    CAST(SERVERPROPERTY('ProductVersion') AS NVARCHAR(128)) AS ProductVersion,
    CAST(SERVERPROPERTY('ProductLevel') AS NVARCHAR(128)) AS ProductLevel,
    CAST(SERVERPROPERTY('Edition') AS NVARCHAR(128)) AS Edition,
    CAST(SERVERPROPERTY('IsClustered') AS INT) AS IsClustered,
    CAST(SERVERPROPERTY('IsHadrEnabled') AS INT) AS IsHadrEnabled,
    sqlserver_start_time AS LastStartTime
FROM sys.dm_os_sys_info;
"@

$backupQuery = @"
SELECT
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    d.state_desc AS State,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceFull
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
    ON d.name = b.database_name
WHERE d.name <> N'tempdb'
GROUP BY d.name, d.recovery_model_desc, d.state_desc
ORDER BY d.name;
"@

Write-Verbose "Collecting diagnostics from $SqlInstance..."
$instanceInfo = Invoke-SqlQuery -Server $SqlInstance -Query $instanceQuery -SqlCred $Credential
$backups = Invoke-SqlQuery -Server $SqlInstance -Query $backupQuery -SqlCred $Credential

$infoRow = $instanceInfo.Rows[0]
$timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("# SQL Server Health Check Report")
$lines.Add("")
$lines.Add("- **Generated:** $timestamp")
$lines.Add("- **Instance:** ``$($infoRow['ServerName'])``")
$lines.Add("- **Edition:** $($infoRow['Edition']) ($($infoRow['ProductVersion']) $($infoRow['ProductLevel']))")
$lines.Add("- **Clustered:** $([bool]$infoRow['IsClustered']) | **Always On AG Enabled:** $([bool]$infoRow['IsHadrEnabled'])")
$lines.Add("- **Last SQL Service Start:** $($infoRow['LastStartTime'])")
$lines.Add("")
$lines.Add("## Database State & Backup Audit (Threshold: ${FullBackupThresholdHours}h)")
$lines.Add("")
$lines.Add("| Database | Recovery Model | State | Last Full Backup | Last Log Backup | Status |")
$lines.Add("| :--- | :--- | :--- | :--- | :--- | :--- |")

foreach ($row in $backups.Rows) {
    $dbName = $row['DatabaseName']
    $rec = $row['RecoveryModel']
    $state = $row['State']
    $lastFull = if ($row['LastFullBackup'] -is [System.DBNull]) { 'NEVER' } else { ([datetime]$row['LastFullBackup']).ToString('yyyy-MM-dd HH:mm') }
    $lastLog = if ($row['LastLogBackup'] -is [System.DBNull]) { 'N/A' } else { ([datetime]$row['LastLogBackup']).ToString('yyyy-MM-dd HH:mm') }
    $hours = $row['HoursSinceFull']

    $status = if ($state -ne 'ONLINE') {
        "ALERT: $state"
    } elseif ($hours -is [System.DBNull] -or [int]$hours -gt $FullBackupThresholdHours) {
        "WARN: Full backup overdue"
    } else {
        "OK"
    }

    $lines.Add("| $dbName | $rec | $state | $lastFull | $lastLog | $status |")
}

$lines | Set-Content -Path $OutputPath -Encoding UTF8
Write-Output "Health report written to $OutputPath"
