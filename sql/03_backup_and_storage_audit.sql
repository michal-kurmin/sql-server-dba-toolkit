/*
===============================================================================
Script:      03_backup_and_storage_audit.sql
Description: Audits backup recency across all online databases and checks
             database file sizes and recovery model settings.
===============================================================================
*/

-- 1. Backup Recency Audit per Database
SELECT
    d.name AS DatabaseName,
    d.recovery_model_desc AS RecoveryModel,
    d.state_desc AS DatabaseState,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS LastFullBackup,
    MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS LastDiffBackup,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS LastLogBackup,
    DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) AS HoursSinceFullBackup
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
    ON d.name = b.database_name
WHERE d.name <> N'tempdb'
  AND d.state_desc = N'ONLINE'
GROUP BY d.name, d.recovery_model_desc, d.state_desc
ORDER BY HoursSinceFullBackup DESC, d.name;

-- 2. Database File Sizes & Autogrowth Configuration
SELECT
    DB_NAME(mf.database_id) AS DatabaseName,
    mf.name AS LogicalFileName,
    mf.type_desc AS FileType,
    CAST(mf.size * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS AllocatedSizeMB,
    CASE
        WHEN mf.max_size = -1 THEN N'UNLIMITED'
        WHEN mf.max_size = 0 THEN N'NO GROWTH'
        ELSE CAST(CAST(mf.max_size * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS NVARCHAR(30)) + N' MB'
    END AS MaxSize,
    CASE
        WHEN mf.is_percent_growth = 1 THEN CAST(mf.growth AS NVARCHAR(10)) + N'%'
        ELSE CAST(CAST(mf.growth * 8.0 / 1024.0 AS DECIMAL(18, 2)) AS NVARCHAR(20)) + N' MB'
    END AS GrowthIncrement,
    mf.physical_name
FROM sys.master_files AS mf
ORDER BY AllocatedSizeMB DESC;
