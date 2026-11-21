# SQL Server Health Check Report *(Synthetic Example)*

- **Generated:** 2026-11-20 09:00:00 +00:00
- **Instance:** `SQL-LAB-01\MSSQLSERVER`
- **Edition:** Developer Edition (64-bit) (16.0.4175.1)
- **Clustered:** True | **Always On AG Enabled:** True
- **Last SQL Service Start:** 2026-11-01 03:15:12

## Database State & Backup Audit (Threshold: 24h)

| Database | Recovery Model | State | Last Full Backup | Last Log Backup | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| master | SIMPLE | ONLINE | 2026-11-20 02:00 | N/A | OK |
| model | FULL | ONLINE | 2026-11-20 02:00 | 2026-11-20 08:45 | OK |
| msdb | SIMPLE | ONLINE | 2026-11-20 02:01 | N/A | OK |
| AppCoreDB | FULL | ONLINE | 2026-11-20 02:10 | 2026-11-20 08:45 | OK |
| ReportingWarehouse | FULL | ONLINE | 2026-11-18 02:15 | 2026-11-20 08:45 | WARN: Full backup overdue |
