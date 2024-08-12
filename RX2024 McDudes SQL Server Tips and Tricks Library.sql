/*
    SQL Server Tips and Tricks Library
    8/1/2024 Jeff McClure - Lakepointe Church

    Feel free to submit additional tips and tricks to the github repo.
*/

--Space Used for any given table.
--Use this instead of Select Count(*) From Table
EXEC sp_spaceused [TableName]

/********************************************************************************************************************************************************/
--Space Used for All tables
--Use this to document current table space and compare it over time.  Can be sorted in different ways ie. by rowcount or by space used on disk

--Space Used All Tables - Azure SQL 
SET NOCOUNT ON
DROP TABLE IF EXISTS #spaceused
CREATE TABLE #spaceused (name sysname,rows bigint,reserved varchar(50),data varchar(50),index_size varchar(50),unused varchar(50))

DECLARE
	@Schema NVARCHAR(MAX),
	@Name NVARCHAR(MAX),
	@Sql NVARCHAR(MAX)
DECLARE TableCursor INSENSITIVE  CURSOR FOR
	SELECT TABLE_SCHEMA, TABLE_NAME
	FROM INFORMATION_SCHEMA.TABLES t
	WHERE TABLE_TYPE = 'BASE TABLE'
--    AND T.Table_Name not like '%Maydelete%'
OPEN TableCursor
WHILE 1 = 1
BEGIN
	FETCH NEXT FROM TableCursor INTO @Schema, @Name
	IF @@FETCH_STATUS <> 0 BREAK
    SET @Sql = 'Exec sp_spaceused [{Schema}.{Name}]'
	SET @Sql = REPLACE(@SQL, '{Schema}', @Schema);
	SET @Sql = REPLACE(@SQL, '{Name}', @Name);
	--RAISERROR(@Sql, 0, 1) WITH NOWAIT
    INSERT #spaceused
	EXECUTE sp_executesql @Sql
END
CLOSE TableCursor
DEALLOCATE TableCursor
--The report:
SELECT CONCAT(ss.name, '.', su.Name) AS TableName, 
	FORMAT(su.[rows],'N0') AS [Rowcount], 
	Reserved_GB  = FORMAT(CONVERT(INT,REPLACE(Reserved,' KB',''))/1024/1024.0, 'N2'),
	Reserved_MB  = FORMAT(CONVERT(INT,REPLACE(Reserved,' KB',''))/1024.0, 'N0'),
	Data_MB      = FORMAT(CONVERT(INT,REPLACE(Data,' KB',''))/1024.0, 'N0'),
	IndexSize_MB = FORMAT(CONVERT(INT,REPLACE(Index_Size,' KB',''))/1024.0, 'N0'),
	Unused_MB    = FORMAT(CONVERT(INT,REPLACE(Unused,' KB',''))/1024.0, 'N0')
FROM #spaceused su 
JOIN sys.objects so ON so.name = su.name AND type = 'u'
JOIN sys.schemas ss ON ss.schema_id = so.schema_id
Where su.Name like '%%' --<<< Filter here <<<---
ORDER BY TRY_CAST(CONVERT(INT,REPLACE(LTRIM(RTRIM(Rows)),' KB','')) AS NUMERIC) DESC 
--ORDER BY TRY_CAST(CONVERT(INT,REPLACE(LTRIM(RTRIM(Data)),' KB','')) AS NUMERIC) DESC 

/********************************************************************************************************************************************************/
--Index Scripts:

--Tells you how often indexes are used and by what means (seek, scan, update, etc

/* 
    Index Usage Stats - Note, this only shows indexes that have had activity since the last time the SQL Service was started 
    If a known index isn't listed, it hasn't been used (read or write)
*/
Select sc.name, so.name, si.name, i.* 
From sys.dm_db_index_usage_stats i 
Join sys.indexes si On si.object_id = i.object_id And si.index_id = i.index_id
Join sys.objects so On so.object_id = i.object_id
Join sys.schemas sc On sc.schema_id = so.schema_id
Where 1=1
And i.database_id = Db_Id() --This is important!
--And (user_seeks > 0 Or User_Scans > 0 Or User_Lookups > 0 Or User_Updates > 0)
And so.name = 'Person'
And is_ms_shipped = 0
Order By so.name,i.index_id


/* 
    Table rows and usage info - Index level granularity
    Shows all indexes and usage (since last service restart) for any given table
*/
SELECT so.object_id, sc.name AS SchemaName, so.name AS TableName, so.create_date, so.modify_date, so.is_published, sp.TotalRows, si.index_id, si.Name AS IndexName
    , indexcolumns.KeyColumnList, indexcolumns.IncludedColumnList
    , usage.user_seeks, usage.user_scans, usage.last_user_seek, usage.last_user_scan, usage.last_user_lookup, usage.last_user_update
FROM sys.objects so
JOIN sys.schemas sc On sc.schema_id = so.schema_id
LEFT JOIN sys.indexes si On si.object_id = so.object_id
JOIN (
	SELECT DISTINCT object_id, index_id, SUM(Rows) AS TotalRows 
	FROM sys.partitions 
	GROUP BY object_id, index_id
) sp ON sp.object_id = so.object_id AND sp.index_id = si.index_id
LEFT OUTER JOIN (
	--Index Usage stats
	Select so.schema_id, so.name AS tablename, si.name AS IndexName, i.*
	From sys.dm_db_index_usage_stats i 
	Join sys.indexes si On si.object_id = i.object_id And si.index_id = i.index_id
	Join sys.objects so On so.object_id = i.object_id
	Where i.database_id = Db_Id() --This is important!
) usage ON usage.object_id = so.object_id AND si.index_id = usage.index_id
LEFT OUTER JOIN (
    SELECT st.Name AS TableName, si.index_id, si.name AS IndexName, si.fill_factor,
    STRING_AGG(CASE WHEN sc.is_included_column = 0 THEN c.name END,', ') WITHIN GROUP (ORDER BY sc.key_ordinal) AS KeyColumnList,
    STRING_AGG(CASE WHEN sc.is_included_column = 1 THEN c.name END,', ') AS IncludedColumnList
    FROM sys.indexes si
    JOIN sys.index_columns sc ON sc.object_id = si.object_id AND sc.index_id = si.index_id
    JOIN sys.columns c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
    JOIN sys.filegroups sfg ON sfg.data_space_id = si.data_space_id
    JOIN sys.tables st ON st.object_id = si.object_id AND st.type = 'U'
    WHERE st.Name = 'Person' --Table Name Here
    GROUP BY st.Name, si.fill_factor, si.index_id, si.name
) indexcolumns ON indexcolumns.index_id = si.index_id
WHERE so.type = 'u' --User Table
AND so.name = 'Person'
--AND (user_seeks > 0 Or User_Scans > 0 Or User_Lookups > 0 Or User_Updates > 0)						--Uncomment to see only Indexes WITH user activity
--AND (user_seeks IS Null AND  User_Scans IS NULL AND User_Lookups IS NULL And User_Updates IS Null)	--Uncomment to see only Indxes WITHOUT user activity
--AND so.name IN ('ah_AddOnsTest','AH_RenewalRates','AH_ActiveAfterTerm','finPaidMemberActivity')
And is_ms_shipped = 0
ORDER BY so.name, si.index_id

/********************************************************************************************************************************************************/
--Query All Tables with GUID column and generate a script to determine if that GUID is contained in any of the tables.
--Good example of having code write code for you
SELECT CONCAT('SELECT TOP 1 * FROM dbo.', QUOTENAME(so.name), ' WHERE GUID= ''400cc3ae-560e-422d-a372-4ea965e2fce1''') 
FROM sys.columns sc 
JOIN sys.objects so ON so.object_id = sc.object_id AND so.type = 'U'
WHERE sc.name = 'GUID'
ORDER BY so.name

/********************************************************************************************************************************************************/
SELECT  des.login_name AS [Login],
        der.command AS [Command],
        dest.text AS [Command Text] ,
        des.login_time AS [Login Time],
        des.[host_name] AS [Hostname],
        des.[program_name] AS [Program],
        der.session_id AS [Session ID],
        dec.client_net_address [Client Net Address],
        der.status AS [Status],
        DB_NAME(der.database_id) AS [Database Name]
FROM    sys.dm_exec_requests der
        INNER JOIN sys.dm_exec_connections dec
                       ON der.session_id = dec.session_id
        INNER JOIN sys.dm_exec_sessions des
                       ON des.session_id = der.session_id
        CROSS APPLY sys.dm_exec_sql_text(sql_handle) AS dest
WHERE   des.is_user_process = 1

(@p__linq__0 int,@p__linq__1 datetime2(7))  
DELETE  FROM    A   
FROM    [dbo].[Interaction] AS A          
INNER JOIN ( 
    SELECT TOP (1000)       [Extent1].[Id] AS [Id]      
    FROM  [dbo].[Interaction] AS [Extent1]      
    INNER JOIN [dbo].[InteractionComponent] AS [Extent2] ON [Extent1].[InteractionComponentId] = [Extent2].[Id]      
    WHERE ([Extent2].[InteractionChannelId] = @p__linq__0) AND ([Extent1].[InteractionDateTime] < @p__linq__1)                      
) AS B ON A.[Id] = B.[Id]    
SELECT @@ROWCOUNT  

/********************************************************************************************************************************************************/
/********************************************************************************************************************************************************/
/********************************************************************************************************************************************************/
/********************************************************************************************************************************************************/

SELECT  db_name(DTL.[resource_database_id]) AS [Database],
        DTL.[resource_type] AS [Resource Type] ,
        CASE WHEN DTL.[resource_type] IN ( 'DATABASE', 'FILE', 'METADATA' )
             THEN DTL.[resource_type]
             WHEN DTL.[resource_type] = 'OBJECT'
             THEN OBJECT_NAME(DTL.resource_associated_entity_id)
             WHEN DTL.[resource_type] IN ( 'KEY', 'PAGE', 'RID' )
             THEN ( SELECT  OBJECT_NAME([object_id])
                    FROM    sys.partitions
                    WHERE   sys.partitions.[hobt_id] =
                                 DTL.[resource_associated_entity_id]
                  )
             ELSE 'Unidentified'
        END AS [Parent Object] ,
        DTL.[request_mode] AS [Lock Type] ,
        DTL.[request_status] AS [Request Status] ,
        DOWT.[wait_duration_ms] AS [Wait Duration (ms)] ,
        DOWT.[wait_type] AS [Wait Type] ,
        DOWT.[session_id] AS [Blocked Session ID] ,
        DES_Blocked.[login_name] AS [Blocked Login] ,
        SUBSTRING(DEST_Blocked.text, (DER.statement_start_offset / 2) + 1,
                  ( CASE WHEN DER.statement_end_offset = -1 
                         THEN DATALENGTH(DEST_Blocked.text) 
                         ELSE DER.statement_end_offset 
                    END - DER.statement_start_offset ) / 2) 
                                              AS [Blocked Command] , 
        DOWT.[blocking_session_id] AS [Blocking Session ID] ,
        DES_Blocking.[login_name] AS [Blocking Login] ,
        DEST_Blocking.[text] AS [Blocking Command] ,
        DOWT.resource_description AS [Blocking Resource Detail]
FROM    sys.dm_tran_locks DTL
        INNER JOIN sys.dm_os_waiting_tasks DOWT
                    ON DTL.lock_owner_address = DOWT.resource_address
        INNER JOIN sys.[dm_exec_requests] DER
                    ON DOWT.[session_id] = DER.[session_id]
        INNER JOIN sys.dm_exec_sessions DES_Blocked
                    ON DOWT.[session_id] = DES_Blocked.[session_id]
        INNER JOIN sys.dm_exec_sessions DES_Blocking
                    ON DOWT.[blocking_session_id] = DES_Blocking.[session_id]
        INNER JOIN sys.dm_exec_connections DEC
                    ON DOWT.[blocking_session_id] = DEC.[most_recent_session_id]
        CROSS APPLY sys.dm_exec_sql_text(DEC.[most_recent_sql_handle])
                                                         AS DEST_Blocking
        CROSS APPLY sys.dm_exec_sql_text(DER.sql_handle) AS DEST_Blocked

/********************************************************************************************************************************************************/

SELECT  OBJECT_SCHEMA_NAME(ddius.object_id) + '.' + OBJECT_NAME(ddius.object_id) AS [Object Name] ,
       CASE
        WHEN ( SUM(user_updates + user_seeks + user_scans + user_lookups) = 0 )
        THEN NULL
        ELSE CONVERT(DECIMAL(38,2), CAST(SUM(user_seeks + user_scans + user_lookups) AS DECIMAL)
                                    / CAST(SUM(user_updates + user_seeks + user_scans
                                               + user_lookups) AS DECIMAL) )
        END AS [Proportion of Reads] ,
       CASE
        WHEN ( SUM(user_updates + user_seeks + user_scans + user_lookups) = 0 )
        THEN NULL
        ELSE CONVERT(DECIMAL(38,2), CAST(SUM(user_updates) AS DECIMAL)
                                    / CAST(SUM(user_updates + user_seeks + user_scans
                                               + user_lookups) AS DECIMAL) )
        END AS [Proportion of Writes] ,
        SUM(user_seeks + user_scans + user_lookups) AS [Total Read Operations] ,
        SUM(user_updates) AS [Total Write Operations]
FROM    sys.dm_db_index_usage_stats AS ddius
        JOIN sys.indexes AS i ON ddius.object_id = i.object_id
                                 AND ddius.index_id = i.index_id
WHERE   i.type_desc IN ( 'CLUSTERED', 'HEAP' ) --only works in Current db
GROUP BY ddius.object_id
ORDER BY OBJECT_SCHEMA_NAME(ddius.object_id) + '.' + OBJECT_NAME(ddius.object_id)


CREATE INDEX IDX_WithJesus
ON dbo.Person(BirthDate)
WHERE MONTH(BirthDate) = 2 AND DAY(BirthDate) = 29;

Create NonClustered Index FIX_Person_ProbablyWithJesus 
ON dbo.Person (Birthdate) 
INCLUDE(Nickname, LastName)
WHERE IsDeceased = 1
WITH(MAXDOP = 4, ONLINE=ON, DROP_EXISTING = ON) ON [Primary];


SELECT 
    YEAR(Birthdate) AS BirthYear, 
    COUNT(*) AS MetTheLordCount
FROM dbo.Person
WHERE 
GROUP BY YEAR(Birthdate)
ORDER BY 1


CREATE NonClustered Index IX_Person_IsDeceased_Gender_Age On dbo.Person (IsDeceased, Gender, Age Desc) Include(Birthdate, NickName, LastName) with(Online=On) On [Primary];