# SQL Server DBA & Automation Toolkit

A collection of **read-only T-SQL diagnostic queries** and **PowerShell operational health-check scripts** designed for routine Microsoft SQL Server administration, performance triage, and compliance auditing.

> **Disclaimer:** All scripts in this repository are generic, vendor-neutral administrative utilities built for lab testing and demonstration. They contain no proprietary code, schemas, credentials, or organizational data.

---

## Repository Structure

```text
sql-server-dba-toolkit/
├── sql/
│   ├── 01_index_health_audit.sql          # Missing, unused, and fragmented index diagnostics
│   ├── 02_wait_stats_and_blocking.sql     # Top wait stats & live blocking chain analysis
│   └── 03_backup_and_storage_audit.sql    # Backup recency (msdb) & database file space audit
├── powershell/
│   ├── Invoke-SqlHealthCheck.ps1          # Automated instance health check -> Markdown report
│   └── Test-FailoverClusterReadiness.ps1  # Read-only Windows Failover Cluster & SQL service check
├── docs/
│   └── sample_health_report.md            # Example synthetic report output
├── LICENSE
└── README.md
```

---

## Quick Start

### 1. Run Read-Only T-SQL Diagnostics
Open any script in `sql/` via SQL Server Management Studio (SSMS) or `sqlcmd` against a non-production/lab instance:
- `01_index_health_audit.sql` — Identifies high-impact missing index suggestions, zero-read/high-write unused indexes, and fragmentation candidates.
- `02_wait_stats_and_blocking.sql` — Surfaces non-benign SQL Server wait statistics and active blocking chains.
- `03_backup_and_storage_audit.sql` — Audits full/diff/log backup recency from `msdb.dbo.backupset` and data/log file space usage.

### 2. Run PowerShell Automated Health Check
```powershell
.\powershell\Invoke-SqlHealthCheck.ps1 `
    -SqlInstance "localhost\SQLEXPRESS" `
    -OutputPath ".\health-report.md"
```
Supports Windows Integrated Authentication (`-TrustedConnection`, default) or explicit `PSCredential` (`-Credential`). See [docs/sample_health_report.md](docs/sample_health_report.md) for sample output.

### 3. Check Failover Cluster & SQL Service Readiness (Windows Server)
```powershell
.\powershell\Test-FailoverClusterReadiness.ps1 -ClusterName "SQL-CLU-01"
```

---

## Safety & Design Principles
- **Read-only by default:** Diagnostic T-SQL scripts only query DMVs and catalog views (`sys.dm_*`, `msdb.dbo.backupset`, `sys.master_files`).
- **No hardcoded credentials:** Uses Windows Integrated Security by default or explicit `PSCredential` objects.
- **Idempotent & auditable:** Generates timestamped Markdown summaries suitable for operational handovers and change logs.
