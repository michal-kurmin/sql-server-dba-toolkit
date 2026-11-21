<#
.SYNOPSIS
    Read-only readiness check for a Windows Server Failover Cluster hosting SQL Server.

.DESCRIPTION
    Queries FailoverClusters module cmdlets (Cluster nodes, Cluster groups, and
    Cluster resources) plus SQL Server Windows services to produce a concise
    operational readiness summary without modifying cluster state.

.PARAMETER ClusterName
    Name of the Windows Failover Cluster to inspect.

.EXAMPLE
    .\Test-FailoverClusterReadiness.ps1 -ClusterName "SQL-CLU-01"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ClusterName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable -Name FailoverClusters)) {
    throw "The 'FailoverClusters' PowerShell module is required (RSAT-Clustering-PowerShell)."
}

Import-Module FailoverClusters

Write-Verbose "Checking cluster nodes for $ClusterName..."
$nodes = Get-ClusterNode -Cluster $ClusterName | Select-Object Name, State, NodeWeight
$groups = Get-ClusterGroup -Cluster $ClusterName | Select-Object Name, OwnerNode, State
$resources = Get-ClusterResource -Cluster $ClusterName |
    Where-Object { $_.State -ne 'Online' } |
    Select-Object Name, ResourceType, OwnerGroup, State

$sqlServices = foreach ($node in $nodes) {
    if ($node.State -eq 'Up') {
        Get-Service -ComputerName $node.Name -Name 'MSSQLSERVER', 'SQLSERVERAGENT' -ErrorAction SilentlyContinue |
            Select-Object @{ Name = 'Node'; Expression = { $node.Name } }, Name, Status, StartType
    }
}

[PSCustomObject]@{
    ClusterName          = $ClusterName
    CheckedAt            = (Get-Date).ToString('u')
    Nodes                = $nodes
    ClusterGroups        = $groups
    NonOnlineResources   = $resources
    SqlServices          = $sqlServices
    AllNodesUp           = (@($nodes | Where-Object { $_.State -ne 'Up' }).Count -eq 0)
    AnyOfflineResources  = (@($resources).Count -gt 0)
}
