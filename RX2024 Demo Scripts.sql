/*
    RX2024 A SQL Server Love Store
    08/12/2024 Jeff McClure
    Demo Scripts
*/

/**************************************************************************************************************************************************
Viewing Who is active on the server.  (hint - set a hotkey for this!) For me it's Ctrl-4
**************************************************************************************************************************************************/
EXEC sp_who2 Active;

--Alternatively: https://whoisactive.com/downloads/
EXEC dbo.sp_WhoIsActive 

/**************************************************************************************************************************************************
Connecting to the Read-Only Replica
Requires a change your connection string
--Can offload Analytics and Reporting Queries
--Still have access to TempDB and #objects
**************************************************************************************************************************************************/
 --First Where are we now?
 SELECT DATABASEPROPERTYEX(DB_NAME(), 'Updateability');

--If still unsure, try to create a table and see what happens
CREATE TABLE dbo.JeffTest_MayDelete_20240812(Id INT);

/**************************************************************************************************************************************************
Viewing IO for a Query - Super useful for helping to hint at the problem
**************************************************************************************************************************************************/
SET STATISTICS IO ON
--SET STATISTICS IO OFF

/*************************************************************************************************************************************************
Demo - Reading Query Plans - Bubba's Cell Phone Number
Bottom to top, and right to left
--> Enable Actual Query Plan (button)
Some Things to Look for:
    Missing Index Scripts
    Clustered Index Scan OR Table Scan (the latter applies only to Heaps)
    Thick Arrows (bad)
    Parallelism (Not necessarily bad, but expensive)
    Actual Rows Read (Hover over operation to see)
    Cost Comparisons of multiple queries
**************************************************************************************************************************************************/

SELECT FirstName, LastName, pn.NumberFormatted
FROM dbo.Person p
INNER JOIN PhoneNumber pn ON pn.PersonId = p.Id
WHERE p.FirstName = 'Bubba'
AND p.LastName = 'McDude'

--We have an index - why isn't it used?
--  CREATE NONCLUSTERED INDEX [IX_IsDeceased_FirstName_LastName]
--  ON [dbo].[Person] ([IsDeceased], [FirstName], [LastName]) WITH (FILLFACTOR=80) ON [PRIMARY]

--Now we are using the index: NOTICE order or filters in the where clause isn't typically important
SELECT FirstName, LastName, pn.NumberFormatted
FROM dbo.Person p
INNER JOIN PhoneNumber pn ON pn.PersonId = p.Id
WHERE p.FirstName = 'Bubba'
AND p.LastName = 'McDude'
AND p.IsDeceased = 0

/* --Note Two very similar indexes on Person table.  This is to support name search from either direction - first/last
CREATE NONCLUSTERED INDEX [IX_IsDeceased_FirstName_LastName] ON [dbo].[Person] ([IsDeceased], [FirstName], [LastName]) WITH (FILLFACTOR=80) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_IsDeceased_LastName_FirstName] ON [dbo].[Person] ([IsDeceased], [LastName], [FirstName]) WITH (FILLFACTOR=80) ON [PRIMARY]
GO
*/


/**************************************************************************************************************************************************
Pseudo-Cartesian Products - Seeing Multiple rows when there only 1 Bubba McDude In the Database
What are we missing, or how do we fix this? - Remove the joins to GroupMember and Group
*Notice in the execution Plan it doesn't show the Group Table!!!  
What does Statistics IO Show?
--Cross Join
**************************************************************************************************************************************************/
SELECT FirstName, LastName, pn.NumberFormatted
FROM dbo.Person p
INNER JOIN dbo.PhoneNumber pn ON pn.PersonId = p.Id
INNER JOIN dbo.GroupMember gm ON gm.PersonId = p.Id
INNER JOIN dbo.[Group] g ON g.Id = gm.GroupId
WHERE p.FirstName = 'Bubba'
AND LastName = 'McDude'
AND p.IsDeceased = 0


/**************************************************************************************************************************************************
Join Examples
[Inner] JOIN, 
Left [OUTER], 
CROSS JOIN
**************************************************************************************************************************************************/
--Inner Join 
--Select All Bubba's with Cell #s
SELECT CONCAT(NickName, ' ', LEFT(LastName, 1), '.') AS NAME, NumberFormatted
FROM dbo.Person p
INNER JOIN dbo.PhoneNumber pn ON pn.PersonId = p.Id
WHERE pn.NumberTypeValueId = 12 --Cell
AND p.NickName = 'Bubba'
AND p.IsDeceased = 0
ORDER BY Name

--Outer Join
--What if I want to see all Bubbas even if they don't have a cell number?
--Switch to Left Outer Join 
--Move filter on the Outer Join Table into the Join stmt
SELECT CONCAT(NickName, ' ', LEFT(LastName, 1), '.') AS NAME, NumberFormatted
FROM dbo.Person p
LEFT OUTER JOIN dbo.PhoneNumber pn ON pn.PersonId = p.Id 
    AND pn.NumberTypeValueId = 12 --Cell --<<<--NOTE, I had to move this into the OUTER JOIN otherwise it was forcing existence in the Where same as an Inner Join
WHERE p.NickName = 'Bubba'
AND p.IsDeceased = 0
ORDER BY Name

--Cross Join
--Believe it or not there are some very practical uses for Cross Join, but I rarely use them
SELECT Campus.Name, Site.Name
FROM dbo.Campus
CROSS JOIN dbo.Site


/**************************************************************************************************************************************************
Windowing Function Example
Complex Query Plan with Parallelism and Missing Index Suggestion
**************************************************************************************************************************************************/
--Row_Number Patition Function for finding most recent group attendance for a list of people
--DECLARE @StartDate DATETIME = '2024-07-01'
;WITH groupattendance AS(
    SELECT pa.PersonId, g.name AS GroupName, a.StartDateTime
        , ROW_NUMBER() OVER(PARTITION BY pa.PersonId ORDER BY a.StartDateTime DESC) AS Rowid
        , SUM(CAST(a.DidAttend AS INT)) OVER(PARTITION BY g.Name) AS TotalGroupAttendences
    FROM dbo.[group] g 
    JOIN dbo.AttendanceOccurrence ao ON ao.GroupId = g.Id
    JOIN dbo.Attendance a ON a.OccurrenceId = ao.Id
    JOIN dbo.PersonAlias pa ON pa.Id = a.PersonAliasId
    WHERE a.DidAttend = 1
    AND a.StartDateTime >= '2024-08-01'
    --ORDER BY g.name
)
SELECT p.firstname, groupattendance.GroupName, groupattendance.StartDateTime, TotalGroupAttendences
FROM Person p 
LEFT OUTER JOIN groupattendance ON groupattendance.PersonId = p.id AND groupattendance.Rowid = 1
WHERE p.createddatetime >= '2024-08-01'
AND p.RecordTypeValueId <> 4550
ORDER BY groupattendance.GroupName

--To see only people that have been created AND have attended any group, change the join above from LEFT OUTER to INNER


/**************************************************************************************************************************************************
Scalar Function on Column in Where Clause
Complex Query Plan with Parallelism and Missing Index Suggestion
**************************************************************************************************************************************************/

--Saw a lot of this a few years ago.
SELECT COUNT(*)
FROM dbo.Person
WHERE [dbo].[ufnCrm_GetAge](Birthdate) = 55

--Why not just use the Age column?  Better, but...
SELECT COUNT(*)
FROM dbo.Person
WHERE Age = 55

--Is this really the best option?
SELECT COUNT(*)
FROM dbo.Person
WHERE Birthdate >= DATEADD(YEAR, -56, GETDATE())
AND Birthdate <= DATEADD(YEAR, -55, GETDATE())

--What do the query plans say?
--Statistics IO?

/**************************************************************************************************************************************************
Viewing indexes on a table.  
You could always use the GUI, or....
**************************************************************************************************************************************************/

--T-SQL: One problem, it only shows key columns but it doesn't show you the included columns if they exist
EXEC sp_helpIndex Person;

-- Index Columns Info --Much Better
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
ORDER BY st.Name, si.index_id


/* 
    MEGA INDEX INFO SCRIPT -- Mega Better
    Table rows and usage info - Index level granularity
    Shows ALL indexes and usage (since last service restart) for any given table
*/
SELECT so.object_id, sc.name AS SchemaName, so.name AS TableName, so.create_date, so.modify_date, so.is_published, sp.TotalRows, si.index_id, si.Name AS IndexName
    , indexcolumns.KeyColumnList, indexcolumns.IncludedColumnList
    , usage.user_seeks, usage.user_scans, usage.user_lookups, usage.last_user_seek, usage.last_user_scan, usage.last_user_lookup, usage.last_user_update
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
    WHERE 1=1
    --AND st.Name = 'Person' --Table Name Here
    GROUP BY st.Name, si.fill_factor, si.index_id, si.name
) indexcolumns ON indexcolumns.TableName = so.name 
    AND indexcolumns.index_id = si.index_id
WHERE so.type = 'u' --User Table
AND so.name = 'AttributeValue' ---<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< Table name goes here!
--AND (user_seeks = 0 AND User_Scans = 0 AND User_Lookups = 0) --<<<<<<<<<<<<<<<<<<<<<< Uncomment to see only Indxes WITHOUT user activity --Candidates for deletion BE CAREFUL!
AND is_ms_shipped = 0
ORDER BY so.name, si.index_id


/**************************************************************************************************************************************************
Space Used All Tables
Recently rewrote for Azure but haven't tested it OnPrem.  LMK if you need an on prem version
**************************************************************************************************************************************************/
--Space Used All Tables - Azure SQL 
SET NOCOUNT ON
DROP TABLE IF EXISTS #spaceused
CREATE TABLE #spaceused (name sysname,rows bigint,reserved varchar(50),data varchar(50),index_size varchar(50),unused varchar(50))

DECLARE
	@Schema NVARCHAR(MAX),
	@Name NVARCHAR(MAX),
	@Sql NVARCHAR(MAX)
DECLARE TableCursor CURSOR FOR
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
ORDER BY TRY_CAST(CONVERT(INT,REPLACE(LTRIM(RTRIM(Data)),' KB','')) AS NUMERIC) DESC 



/**************************************************************************************************************************************************
Chunky Data Processing
For Updates or Deletes
**************************************************************************************************************************************************/

SET NOCOUNT OFF;

--Quickly build a backup of the data in a table:
SELECT * 
INTO dbo.PersonBackup_MAYDELETE --Bulk Logged operation
FROM dbo.Person;

CREATE CLUSTERED INDEX CX_PersonBackup_Birthdate ON dbo.PersonBackup_MAYDELETE (BirthDate)

--Simple Cleanup of some records
DECLARE @Rows INT = 1
WHILE @Rows > 0 
BEGIN

    DELETE TOP(1000) pb --select count(*)
    FROM dbo.PersonBackup_MAYDELETE pb
    WHERE Birthdate >= '1/1/2000'
    SELECT @Rows = @@ROWCOUNT

END

--Drop Table dbo.PersonBackup_MAYDELETE --Reset

--Nicer - Let's remove all the Nameless Person Records
DECLARE @RowsDeleted INT = 1,
        @TotalRowsDeleted INT = 0,
        @Msg NVARCHAR(1000) = '';

WHILE @RowsDeleted > 0
BEGIN
    
    DELETE TOP(1000) pb --Select Count(*)
    FROM dbo.PersonBackup_MAYDELETE pb
    WHERE pb.RecordTypeValueId = 4550 --Improtant that this column have an index if you are going to have a lot of iterations over this loop
    SELECT @RowsDeleted = @@ROWCOUNT

    IF @RowsDeleted = 0
        BREAK;

    SET @TotalRowsDeleted += @RowsDeleted;

    IF @TotalRowsDeleted % 100000 = 0
    BEGIN
        SET @Msg = CONCAT(CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME2(7)), ' | Rows Deleted so far: ', @TotalRowsDeleted, '. Good job keeping your transactions small!! :)')
        RAISERROR (@Msg, 10, 1) WITH NOWAIT;
    END
END

--Drop Table dbo.PersonBackup_MAYDELETE


/**************************************************************************************************************************************************
Explicit Transactions Example - How to save your bacon
**************************************************************************************************************************************************/
SET NOCOUNT OFF;
SELECT TOP 100 a.Name, av.* 
FROM dbo.AttributeValue av
JOIN dbo.Attribute a ON a.Id = av.AttributeId
WHERE EntityId = 319854
AND av.AttributeId = 741

BEGIN TRAN
    UPDATE av
    SET Value = 'Chief Mugwump', av.IsPersistedValueDirty = 1
    FROM dbo.AttributeValue av
    JOIN dbo.Attribute a ON a.Id = av.AttributeId
    WHERE EntityId = 319854
    AND av.AttributeId = 741

    --Validate
    SELECT TOP 100 a.Name, av.* 
    FROM dbo.AttributeValue av
    JOIN dbo.Attribute a ON a.Id = av.AttributeId
    WHERE EntityId = 319854
    AND av.AttributeId = 741
    
--Run one or the other!
ROLLBACK
COMMIT  

/**************************************************************************************************************************************************
Performance Hack on AttributeValue - ValueChecksum  
ValueChecksum is a Computed column meaning is shows up in the table but its actually computed at runtime so it doesn't really exist...or does it?
Is also has a NonClustered Index built on the column that actually persists the value to disk, so while it doesn't exist in the base table, it
does exist in an index and can be safely used in a query.

Note: CHECKSUM is designed for speed, not uniqueness. If uniqueness is required, a more reliable method, such as HASHBYTES with SHA-256 
should be used, although it doesn't guarantee no collisions, the probability is much lower.

Note 2: Watch for datatype pitfall here...
**************************************************************************************************************************************************/

SELECT TOP 100 a.Name, av.* 
FROM dbo.AttributeValue av
JOIN dbo.Attribute a ON a.Id = av.AttributeId
WHERE EntityId = 319854

--> But what if all we know is the value and we have to find all the rows with that value in the massive junk drawer?? c143ca2f-ab2d-418f-87ea-5beeacb75f06
Set Statistics Io ON;
--Set Statistics Io Off
SELECT COUNT(*) AS Cnt
FROM dbo.AttributeValue
WHERE Value = '800d6025-d35e-4833-8376-ccdad717f215'

/*
Yuck!
Table 'AttributeValue'. Scan count 7, logical reads 107301, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 36676, lob physical reads 0, lob page server reads 0, lob read-ahead reads 1805, lob page server read-ahead reads 0.
Table 'Worktable'. Scan count 0, logical reads 0, physical reads 0, page server reads 0, read-ahead reads 0, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.
*/
--Note the index used in the query plan is from the DTA (Database Tuning Advisor)  Google it...

--Now, let's leverage the power of Checksum to find the answer much quicker! 
SELECT COUNT(*) AS Cnt
FROM dbo.AttributeValue
WHERE ValueChecksum = CHECKSUM('800d6025-d35e-4833-8376-ccdad717f215')
AND Value = '800d6025-d35e-4833-8376-ccdad717f215'

---Sure was fast, but NO Records!! But we know they are there. What happened?

--Since Value is store as NVARCHAR, you have to run the checksum against that correct dataype
SELECT COUNT(*) AS Cnt
FROM dbo.AttributeValue
WHERE ValueChecksum = CHECKSUM(N'800d6025-d35e-4833-8376-ccdad717f215')
AND Value = N'800d6025-d35e-4833-8376-ccdad717f215'


--(1 row affected)
--Table 'AttributeValue'. Scan count 1, logical reads 847, physical reads 12, page server reads 0, read-ahead reads 9, page server read-ahead reads 0, lob logical reads 0, lob physical reads 0, lob page server reads 0, lob read-ahead reads 0, lob page server read-ahead reads 0.

/**************************************************************************************************************************************************
Case Sensitive Searching
    CS: Case-Sensitive. Uppercase and lowercase letters are treated as different characters.
    CI: Case-Insensitive. Uppercase and lowercase letters are treated as the same.
    AS: Accent-Sensitive. Accented characters are treated as distinct from their non-accented counterparts.
    AI: Accent-Insensitive. Accented characters are treated as the same as their non-accented counterparts.
    BIN: Binary. Sorting and comparison are done based on the numeric value of the characters, which is case-sensitive and accent-sensitive by default.
**************************************************************************************************************************************************/

--See all Groups with HIGH as the first 4 letters
SELECT Id, Name, Description
FROM dbo.[GROUP]
WHERE Name LIKE N'HIGH%'

--Same, except only where HIGH is Capitalized
SELECT Id, Name, Description
FROM dbo.[GROUP]
WHERE Name LIKE N'HIGH%' COLLATE Latin1_General_CS_AS


-- Creating a table with a case-sensitive collation
CREATE TABLE #ExampleTable (
    Name VARCHAR(100) COLLATE Latin1_General_CS_AS
);
INSERT #ExampleTable VALUES ('test')

--Query assumes column definition and finds nothing
SELECT * FROM #ExampleTable
WHERE Name = 'Test';

--We see it here:
SELECT * FROM #ExampleTable
WHERE Name = 'test';

--We also see it here if we override the collation
SELECT * FROM #ExampleTable
WHERE Name = 'Test' COLLATE Latin1_General_CI_AS;


/**************************************************************************************************************************************************
Extended Events Demo - If time allows.  
If we can't do this in the session, I can schedule a webinar to demo this powerful tool
Let me know in the survey, or hit me up on RocketChat
**************************************************************************************************************************************************/


/**************************************************************************************************************************************************
BONUS:

Missing Indexs By Index Advantage
--Thanks Glenn Berry!

-- Look at index advantage, last user seek time, number of user seeks to help determine source and importance
-- SQL Server is overly eager to add included columns, so beware
-- Do not just blindly add indexes that show up from this query!!!!!!!!!!!!!!!!!!!!!!!!!!!
**************************************************************************************************************************************************/
-- Missing Indexes for current database by Index Advantage  (Query 37) (Missing Indexes)
SELECT CONVERT(decimal(18,2), migs.user_seeks * migs.avg_total_user_cost * (migs.avg_user_impact * 0.01)) AS [index_advantage], 
CONVERT(nvarchar(25), migs.last_user_seek, 20) AS [last_user_seek],
mid.[statement] AS [Database.Schema.Table], 
COUNT(1) OVER(PARTITION BY mid.[statement]) AS [missing_indexes_for_table], 
COUNT(1) OVER(PARTITION BY mid.[statement], mid.equality_columns) AS [similar_missing_indexes_for_table], 
mid.equality_columns, mid.inequality_columns, mid.included_columns, migs.user_seeks, 
CONVERT(decimal(18,2), migs.avg_total_user_cost) AS [avg_total_user_,cost], migs.avg_user_impact,
REPLACE(REPLACE(LEFT(st.[text], 255), CHAR(10),''), CHAR(13),'') AS [Short Query Text],
OBJECT_NAME(mid.[object_id]) AS [Table Name], p.rows AS [Table Rows]
FROM sys.dm_db_missing_index_groups AS mig WITH (NOLOCK) 
INNER JOIN sys.dm_db_missing_index_group_stats_query AS migs WITH(NOLOCK) 
ON mig.index_group_handle = migs.group_handle 
CROSS APPLY sys.dm_exec_sql_text(migs.last_sql_handle) AS st 
INNER JOIN sys.dm_db_missing_index_details AS mid WITH (NOLOCK) 
ON mig.index_handle = mid.index_handle
INNER JOIN sys.partitions AS p WITH (NOLOCK)
ON p.[object_id] = mid.[object_id]
WHERE mid.database_id = DB_ID()
AND p.index_id < 2 
ORDER BY index_advantage DESC OPTION (RECOMPILE);

/*
THE END
*/
