SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
<doc>
	<summary>
 		This stored procedure rebuilds the database indexes for those that need it.
	</summary>

	<returns>
	</returns>
	<param name='PageCountLimit' datatype='int'>The number of page counts the index must have in order to be considered for re-indexing (default 100).</param>
	<param name='MinFragmentation' datatype='int'>The minimum amount of fragmentation a index must have to be considered for re-indexing (default 10).</param>
	<param name='MinFragmentationRebuild' datatype='int'>The minimum amount of fragmentation a index must have to be considered for a full rebuild. Otherwise a reorganize will be done. (default 30).</param>
	<remarks>	
		12/23/2023 Jeff McClure Lakepointe Church:
			- Added logic to adjust to higher fillfactor for certain indexes and index key columns.  See add'l comments below.
			- Fixed bug where @CommandOption was being appended with Fillfactor = NN with each pass through the loop when @UseOnlineIndexRebuild was set to 1.
			- Improved Cursor name and logic.
            - Added Option to LogRebuild history to allow for analysis on whether fill factors need adjustment.  For example, if they are being rebuilt often, you should consider a lower fill factor. Data in _org_lakepointe_IndexRebuildLog is kept for 365 days.
        NOTE: For the first run, it would be good to set the MinimumFragmentation Percentage and the Rebuild Threshold to the same value (i.e. 10) so that everything needing it actually gets rebuilt 
              with the new fillfactor rather than just getting reorganized (which doesn't affect fillfactor).  ALSO, manually rebuilding all of your PKs (usually the Id column) to 95% will 
              be helpful in getting a head start and will free up a lot of space.  This freed space won't be noticable in the overall database size but the table will be smaller occupying fewer
              data pages which should translate into slightly better I/O performance
	</remarks>
	<code>
		EXEC [dbo].[spDbaRebuildIndexes]
		EXEC [dbo].[spDbaRebuildIndexes] @PageCountLimit = default, @MinFragmentation = default, @MinFragmentationRebuild = default, @UseONLINEIndexRebuild = 1
		EXEC [dbo].[_org_lakepointe_spDbaRebuildIndexes] @PageCountLimit = 10, @MinFragmentation = 5, @MinFragmentationRebuild = 5, @UseONLINEIndexRebuild = 1, @LogIndexRebuildHistory = 1

        Select Top 1000 * from _org_lakepointe_IndexRebuildLog
	</code>
</doc>

-- Identify Id indexes with fillfactor = 80 - This will generate a script you can use to manually update the PKs to a higher Fill Factor and use fewer data pages, less disk space and improve performance.
SELECT N'ALTER INDEX [' + si.Name + N'] ON [dbo].[' + t.Name + '] REBUILD WITH (FILLFACTOR = 95, ONLINE=ON, MAXDOP=2);', si.fill_factor
FROM sys.indexes si
	INNER JOIN sys.index_columns sic ON sic.object_id = si.object_id AND sic.index_id = si.index_id
	INNER JOIN sys.columns sc ON sc.object_id = sic.object_id AND sc.column_id = sic.column_id
	INNER JOIN sys.types st ON st.system_type_id = sc.system_type_id
    INNER JOIN sys.tables t ON t.object_id = si.object_id
WHERE 
    sic.[key_ordinal] = 1 --Only look at the first column in the index
    AND sc.name = 'id'
    AND si.fill_factor > 0 
    AND si.fill_factor < 95

*/

CREATE OR ALTER PROCEDURE [dbo].[_org_lakepointe_spDbaRebuildIndexes]
	  @PageCountLimit BIGINT = 100
	, @MinFragmentation TINYINT = 10 --Index must have this Fragmentation % or more to be rebuilt
	, @MinFragmentationRebuild TINYINT = 20
	, @UseONLINEIndexRebuild BIT = 1 --Always 0 for On-Prem SQL Standard, but typically 1 for SQL Enterprise or Azure SQL (prevents long blocking while index being rebuilt)
    , @LogIndexRebuildHistory BIT = 0
AS
SET NOCOUNT ON;
BEGIN

DECLARE @SchemaName AS NVARCHAR(128);
DECLARE @TableName AS NVARCHAR(128);
DECLARE @IndexName AS NVARCHAR(128);
DECLARE @IndexType AS NVARCHAR(60);
DECLARE @FragmentationPercent AS TINYINT;
DECLARE @PageCount AS BIGINT;
DECLARE @CurrentFillFactor AS TINYINT;
DECLARE @NewFillFactor AS TINYINT;
DECLARE @DurationMS INT;
DECLARE @CommandOption NVARCHAR(100);
DECLARE @SqlCommand AS NVARCHAR(2000);
DECLARE @Now DATETIME2;

IF @LogIndexRebuildHistory = 1 AND NOT EXISTS (SELECT [Name] FROM sys.tables WHERE [name] = '_org_lakepointe_IndexRebuildLog')
BEGIN 
    --Create Logging table the first time the proc runs
	CREATE TABLE dbo._org_lakepointe_IndexRebuildLog (
		  [Id] INT IDENTITY(1,1) NOT NULL
        , [CreatedDateTime] DATETIME NOT NULL 
		, [SchemaName] NVARCHAR(128) NOT NULL
        , [TableName] NVARCHAR(128) NOT NULL
        , [IndexName] NVARCHAR(128) NOT NULL
        , [FragmentationPercent] TINYINT NOT NULL
        , [PageCount] BIGINT NOT NULL
        , [CurrentFillFactor] TINYINT NOT NULL
        , [NewFillFactor] TINYINT NOT NULL
        , [DurationMS] INT NOT NULL
        , SQLCommand NVARCHAR(2000) NULL
    )
    ALTER TABLE dbo._org_lakepointe_IndexRebuildLog ADD CONSTRAINT [PK_dbo._org_lakepointe_IndexRebuildLog] PRIMARY KEY ( Id ) WITH(FILLFACTOR = 100) ON [PRIMARY];
    ALTER TABLE dbo._org_lakepointe_IndexRebuildLog ADD CONSTRAINT [df__org_lakepointe_IndexRebuildLog_CreatedDatetime] DEFAULT CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME) FOR CreatedDateTime;
    CREATE NONCLUSTERED INDEX IX__org_lakepointe_IndexRebuildLog_CreatedDateTime ON dbo._org_lakepointe_IndexRebuildLog ( CreatedDateTime ) WITH( FILLFACTOR = 100 ) ON [PRIMARY];
    CREATE NONCLUSTERED INDEX IX__org_lakepointe_IndexRebuildLog_TableName ON dbo._org_lakepointe_IndexRebuildLog ( TableName, IndexName, CreatedDateTime ) WITH( FILLFACTOR = 100 ) ON [PRIMARY];
END

--Do the Main Work of Rebuilding/Reorganizing Indexes
DECLARE MaintenanceCursor INSENSITIVE CURSOR FOR
		SELECT
			dbschemas.[name] as 'Schema', 
			dbtables.[name] as 'Table', 
			dbindexes.[name] as 'Index',
			dbindexes.[type_desc] as 'IndexType',
			CONVERT(TINYINT, indexstats.avg_fragmentation_in_percent),
			indexstats.page_count,
            dbindexes.fill_factor
		FROM 
			sys.dm_db_index_physical_stats (DB_ID(), NULL, NULL, NULL, NULL) AS indexstats
			INNER JOIN sys.tables dbtables on dbtables.[object_id] = indexstats.[object_id]
			INNER JOIN sys.schemas dbschemas on dbtables.[schema_id] = dbschemas.[schema_id]
			INNER JOIN sys.indexes AS dbindexes ON dbindexes.[object_id] = indexstats.[object_id]
			AND indexstats.index_id = dbindexes.index_id
		WHERE 
			indexstats.database_id = DB_ID() 
			AND indexstats.page_count > @PageCountLimit
			AND indexstats.avg_fragmentation_in_percent > @MinFragmentation
			AND dbindexes.type_desc <> 'HEAP'
		ORDER BY 
			indexstats.avg_fragmentation_in_percent DESC
 
OPEN MaintenanceCursor;
 
WHILE 1=1
BEGIN
	SET @CommandOption = ''; --Must be reset for each pass through the loop
	FETCH NEXT FROM MaintenanceCursor INTO @SchemaName, @TableName, @IndexName, @IndexType, @FragmentationPercent, @PageCount, @CurrentFillFactor;
	IF @@FETCH_STATUS <> 0 BREAK;

	IF (@FragmentationPercent > @MinFragmentationRebuild)
	BEGIN
		/*	
			12/20/2023 Jeff McClure Lakepointe Church - Identify data type of first column in the index key for non-heaps and set set Fillfactor = 95 for most non-text data types.  
			This will prevent wasted space in indexes that generally don't fragment much.  The net result should be fewer pages in database, which means 
			fewer pages to read into memory, reduced i/o, and generally better performance.  This will have the biggest effect on tables where the PrimaryKey is 
			an auto-incrementing identity value.
		*/
		SELECT @NewFillFactor = CASE 
			WHEN (st.Name in ('int', 'smallint', 'tinyint', 'bigint') AND sc.name = 'Id') THEN 95 --For PK Identity "id" Columns
			WHEN (st.Name in ('date', 'datetime', 'datetime2', 'smalldatetime')) THEN 95 --For Date fields in first key column
			WHEN (st.Name in ('int', 'smallint', 'tinyint', 'bigint')) THEN 90 --For Integer Keys not named Id (generally these are not primary keys)
			ELSE 80 END --For all other index key types (text, guid, etc.)
		FROM sys.indexes si
			INNER JOIN sys.index_columns sic ON sic.object_id = si.object_id AND sic.index_id = si.index_id
			INNER JOIN sys.columns sc ON sc.object_id = sic.object_id AND sc.column_id = sic.column_id
			INNER JOIN sys.types st ON st.system_type_id = sc.system_type_id
		WHERE 
			si.OBJECT_ID = OBJECT_ID(CONCAT(@SchemaName,'.',@TableName)) --Table Name Here
			AND si.[name] = @IndexName
			AND sic.[key_ordinal] = 1 --Only look at the first column in the index
		ORDER BY si.index_id, sic.[key_ordinal]

        SELECT @CommandOption = CONCAT(N'FILLFACTOR = ', @NewFillFactor)
        --SELECT @CommandOption AS DebugCommandOption

		/*Fail-Safe*/ 
		IF @CommandOption IS NULL SET @CommandOption = N'FILLFACTOR = 80' --Make sure we don't get a NULL.  

		IF ( @UseONLINEIndexRebuild = 1 AND @IndexType NOT IN (N'SPATIAL',N'XML') )
		BEGIN
			SELECT @CommandOption += N', ONLINE = ON';
		END

		SET @SqlCommand = N'ALTER INDEX [' + @IndexName + N'] ON [' +  @SchemaName + N'].[' + @TableName + '] REBUILD WITH (' + @CommandOption + ');';
	END
	ELSE BEGIN
		SET @SqlCommand = N'ALTER INDEX [' + @IndexName + N'] ON [' +  @SchemaName + N'].[' + @TableName + '] REORGANIZE;';
	END

	PRINT @SqlCommand; --Used for Job History Output
	
	BEGIN TRY
        SET @Now = SYSDATETIME();

        --Run the Command
        EXECUTE sp_executeSQL @SqlCommand;
        
        SET @DurationMS = DATEDIFF(MILLISECOND, @Now, SYSDATETIME())

        --Log the Info
        IF @LogIndexRebuildHistory = 1
        BEGIN   
            INSERT dbo._org_lakepointe_IndexRebuildLog( SchemaName, TableName, IndexName, FragmentationPercent, PageCount, CurrentFillFactor, NewFillFactor, DurationMS, SQLCommand )
            VALUES ( @SchemaName, @TableName, @IndexName, @FragmentationPercent, @PageCount, @CurrentFillFactor, @NewFillFactor, @DurationMS, @SqlCommand );
        END
    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(1000);
        SET @ErrorMessage = CONCAT('Proc_Name: ', ERROR_PROCEDURE(), '; Error_Number: ', ERROR_NUMBER(), '; Error_Message: ', ERROR_MESSAGE());
        RAISERROR(@ErrorMessage, 10, 1); --Non-breaking Informational
    END CATCH
END
 
CLOSE MaintenanceCursor;
DEALLOCATE MaintenanceCursor;

--Trim _org_lakepointe_IndexRebuildLog keeping only the most recent 365 days
DELETE dbo._org_lakepointe_IndexRebuildLog WHERE CreatedDateTime < DATEADD(DAY, -365, CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME))

END
GO


