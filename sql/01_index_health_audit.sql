/*
===============================================================================
Script:      01_index_health_audit.sql
Description: Read-only diagnostics for SQL Server index usage, missing index
             recommendations, and fragmentation in the current database.
Notes:       DMV stats reset on SQL Server service restart. Evaluate over a
             representative workload window before dropping or creating indexes.
===============================================================================
*/

-- 1. Top 20 High-Impact Missing Index Candidates
SELECT TOP (20)
    OBJECT_SCHEMA_NAME(mid.[object_id]) + N'.' + OBJECT_NAME(mid.[object_id]) AS TableName,
    CAST(migs.avg_total_user_cost * (migs.avg_user_impact / 100.0) * (migs.user_seeks + migs.user_scans) AS DECIMAL(18, 2)) AS ImprovementMeasure,
    migs.user_seeks,
    migs.user_scans,
    CAST(migs.avg_user_impact AS DECIMAL(5, 2)) AS AvgImpactPct,
    mid.equality_columns,
    mid.inequality_columns,
    mid.included_columns
FROM sys.dm_db_missing_index_groups AS mig
INNER JOIN sys.dm_db_missing_index_group_stats AS migs
    ON mig.index_group_handle = migs.group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid
    ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY ImprovementMeasure DESC;

-- 2. Unused Non-Unique Indexes (High Write Overhead, Zero Reads Since Restart)
SELECT
    OBJECT_SCHEMA_NAME(i.[object_id]) + N'.' + OBJECT_NAME(i.[object_id]) AS TableName,
    i.name AS IndexName,
    i.type_desc AS IndexType,
    ISNULL(ius.user_seeks, 0) + ISNULL(ius.user_scans, 0) + ISNULL(ius.user_lookups, 0) AS TotalReads,
    ISNULL(ius.user_updates, 0) AS TotalWrites,
    SUM(ps.used_page_count) * 8.0 / 1024.0 AS SizeMB
FROM sys.indexes AS i
INNER JOIN sys.objects AS o
    ON i.[object_id] = o.[object_id]
LEFT JOIN sys.dm_db_index_usage_stats AS ius
    ON i.[object_id] = ius.[object_id]
   AND i.index_id = ius.index_id
   AND ius.database_id = DB_ID()
INNER JOIN sys.dm_db_partition_stats AS ps
    ON i.[object_id] = ps.[object_id]
   AND i.index_id = ps.index_id
WHERE o.is_ms_shipped = 0
  AND i.type > 0                  -- Exclude heaps
  AND i.is_primary_key = 0
  AND i.is_unique = 0
  AND i.is_unique_constraint = 0
  AND ISNULL(ius.user_seeks, 0) = 0
  AND ISNULL(ius.user_scans, 0) = 0
  AND ISNULL(ius.user_lookups, 0) = 0
GROUP BY
    i.[object_id], i.name, i.type_desc,
    ius.user_seeks, ius.user_scans, ius.user_lookups, ius.user_updates
ORDER BY TotalWrites DESC, SizeMB DESC;

-- 3. Fragmented Indexes (> 10% Fragmentation, >= 1000 Pages)
SELECT
    OBJECT_SCHEMA_NAME(ips.[object_id]) + N'.' + OBJECT_NAME(ips.[object_id]) AS TableName,
    i.name AS IndexName,
    ips.index_type_desc,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5, 2)) AS FragmentationPct,
    ips.page_count,
    CASE
        WHEN ips.avg_fragmentation_in_percent >= 30.0 THEN N'REBUILD'
        ELSE N'REORGANIZE'
    END AS RecommendedAction
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') AS ips
INNER JOIN sys.indexes AS i
    ON ips.[object_id] = i.[object_id]
   AND ips.index_id = i.index_id
WHERE ips.index_id > 0
  AND ips.page_count >= 1000
  AND ips.avg_fragmentation_in_percent >= 10.0
ORDER BY ips.avg_fragmentation_in_percent DESC;
