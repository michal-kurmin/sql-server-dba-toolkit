/*
===============================================================================
Script:      02_wait_stats_and_blocking.sql
Description: Read-only diagnostics for SQL Server cumulative wait statistics
             (filtering benign background waits) and active blocking chains.
===============================================================================
*/

-- 1. Top Non-Benign Wait Statistics
WITH FilteredWaits AS (
    SELECT
        wait_type,
        wait_time_ms / 1000.0 AS WaitSec,
        (wait_time_ms - signal_wait_time_ms) / 1000.0 AS ResourceWaitSec,
        signal_wait_time_ms / 1000.0 AS SignalWaitSec,
        waiting_tasks_count,
        100.0 * wait_time_ms / NULLIF(SUM(wait_time_ms) OVER (), 0) AS WaitPct
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        N'BROKER_EVENTHANDLER', N'BROKER_RECEIVE_WAITFOR', N'BROKER_TASK_STOP',
        N'BROKER_TO_FLUSH', N'BROKER_TRANSMITTER', N'CHECKPOINT_QUEUE',
        N'CHKPT', N'CLR_AUTO_EVENT', N'CLR_MANUAL_EVENT', N'CLR_SEMAPHORE',
        N'DIRTY_PAGE_POLL', N'DISPATCHER_QUEUE_SEMAPHORE', N'EXECSYNC',
        N'FSAGENT', N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_FILESTREAM_IOMGR_IOCOMPLETION', N'HADR_LOGCAPTURE_WAIT',
        N'HADR_NOTIFICATION_DEQUEUE', N'HADR_TIMER_TASK', N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP', N'LAZYWRITER_SLEEP', N'LOGMGR_QUEUE',
        N'MEMORY_ALLOCATION_EXT', N'ONDEMAND_TASK_QUEUE',
        N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_ASYNC_QUEUE', N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE', N'SERVER_IDLE_CHECK',
        N'SLEEP_BPOOL_FLUSH', N'SLEEP_DBSTARTUP', N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY', N'SLEEP_MASTERMDREADY', N'SLEEP_MASTERUPGRADED',
        N'SLEEP_MSDBSTARTUP', N'SLEEP_SYSTEMTASK', N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP', N'SNI_HTTP_ACCEPT', N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH', N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES', N'WAIT_FOR_RESULTS', N'WAITFOR',
        N'WAITFOR_TASKSHUTDOWN', N'WAIT_XTP_CKPT_CLOSE', N'XE_DISPATCHER_JOIN',
        N'XE_DISPATCHER_WAIT', N'XE_TIMER_EVENT'
    )
      AND waiting_tasks_count > 0
)
SELECT TOP (20)
    wait_type,
    CAST(WaitSec AS DECIMAL(18, 2)) AS WaitSec,
    CAST(ResourceWaitSec AS DECIMAL(18, 2)) AS ResourceWaitSec,
    CAST(SignalWaitSec AS DECIMAL(18, 2)) AS SignalWaitSec,
    waiting_tasks_count,
    CAST(WaitPct AS DECIMAL(5, 2)) AS WaitPct
FROM FilteredWaits
ORDER BY WaitSec DESC;

-- 2. Active Blocking Sessions Right Now
SELECT
    r.session_id AS BlockedSessionId,
    r.blocking_session_id AS BlockingSessionId,
    DB_NAME(r.database_id) AS DatabaseName,
    r.wait_type,
    r.wait_time / 1000.0 AS WaitSeconds,
    r.wait_resource,
    s_blocked.login_name AS BlockedLogin,
    s_blocked.host_name AS BlockedHost,
    s_blocked.program_name AS BlockedProgram,
    SUBSTRING(
        t_blocked.text,
        (r.statement_start_offset / 2) + 1,
        ((CASE r.statement_end_offset
            WHEN -1 THEN DATALENGTH(t_blocked.text)
            ELSE r.statement_end_offset
          END - r.statement_start_offset) / 2) + 1
    ) AS BlockedStatement,
    s_blocker.login_name AS BlockerLogin,
    t_blocker.text AS BlockerBatchText
FROM sys.dm_exec_requests AS r
INNER JOIN sys.dm_exec_sessions AS s_blocked
    ON r.session_id = s_blocked.session_id
LEFT JOIN sys.dm_exec_sessions AS s_blocker
    ON r.blocking_session_id = s_blocker.session_id
LEFT JOIN sys.dm_exec_connections AS c_blocker
    ON r.blocking_session_id = c_blocker.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) AS t_blocked
OUTER APPLY sys.dm_exec_sql_text(c_blocker.most_recent_sql_handle) AS t_blocker
WHERE r.blocking_session_id <> 0
ORDER BY r.wait_time DESC;
