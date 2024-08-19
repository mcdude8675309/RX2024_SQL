/****************************************************************************************************

NOTE: THIS SCRIPT IS HERE AS AN EXAMPLE ONLY 
THIS IS JUST ONE POSSIBLE WAY OF DOING THIS TYPE OF ACTION

Rock has a built in way to purge Page Views from interactions that should be used instead, but since
we didn't turn that on until the table had over 50 million rows, we decided to pre-purge it before
enabling the built in process.

Modified the original script to keep the delete doing seeks rather than longer and longer scans
on each pass through the loop. 
****************************************************************************************************/
/*
--Identify and Purge Page Views older than 1 year from Interaction table.  (Almost half the table)
SELECT COUNT(*) AS TotalToDelete--28871848
FROM dbo.Interaction i
JOIN dbo.InteractionComponent ic ON ic.Id = i.InteractionComponentId
JOIN dbo.InteractionChannel ich ON ich.Id = ic.InteractionChannelId
WHERE ich.ChannelTypeMediumValueId IN (3046, 3051)
AND I.InteractionDateTime < DATEADD(DAY, -(450), CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME))
*/

--Build and Populate work table with the data to process
DROP TABLE IF EXISTS #Ids;

SELECT i.Id INTO #Ids 
FROM dbo.Interaction i
JOIN dbo.InteractionComponent ic ON ic.Id = i.InteractionComponentId
JOIN dbo.InteractionChannel ich ON ich.Id = ic.InteractionChannelId
WHERE ich.ChannelTypeMediumValueId IN (3046, 3051)
AND I.InteractionDateTime < DATEADD(DAY, -(450), CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME))
ORDER BY Id;

CREATE CLUSTERED INDEX CX1 ON #Ids (Id);

--Set Statistics Io On
--Set Statistics Io Off
SET XACT_ABORT ON;
SET NOCOUNT ON;
DECLARE @TotalRowsToDelete INT = (SELECT COUNT(*) FROM #ids);
DECLARE @RowsPerBatch INT = 1000;
DECLARE @RowsDeleted INT = 1;
DECLARE @TotalRowsDeleted INT = 0;
DECLARE @Msg NVARCHAR(1000) = ''
DECLARE @DoIt Bit = 0; --<-- Set this to 1 to actually delete records - Safety Check!
DECLARE @IdsToDelete TABLE(Id INT PRIMARY KEY);
SELECT 'Starting Purge', @TotalRowsToDelete AS TotalRowsToDelete;

WHILE (@RowsDeleted > 0 AND @DoIt = 1)
BEGIN

    --Wrap each group of deletes in a transaction so that they succeed (or fail) together.
    BEGIN TRAN

    --Ensure Temp table is empty before each pass through the loop
    DELETE @IdsToDelete;

    --Delete the number of desired records and output the Ids into a temp table variable that will be used to join to Interactions for the actual records to delete
    DELETE TOP (@RowsPerBatch) #Ids
    OUTPUT deleted.Id INTO @IdsToDelete;

    --Do the actual delete from interaction table.  
    DELETE i
    --SELECT c.Id
    FROM dbo.Interaction i
    INNER JOIN @IdsToDelete ids ON ids.Id = i.Id
    SET @RowsDeleted = @@ROWCOUNT

    COMMIT 

    SET @TotalRowsDeleted += @RowsDeleted;
    
    IF @TotalRowsDeleted % 100000 = 0 --Reduce the 100k value to 10k if you want more frequent feedback which is useful when trying to determine how long it's going to take for the whole process to finish.
    Begin
        SET @Msg = CONCAT(SYSDATETIME(), ' | ', 'Deleted ', @TotalRowsDeleted, ' of ', @TotalRowsToDelete, ' records from Interaction.');
        RAISERROR(@Msg, 10, 1) WITH NOWAIT;
    End
    --BREAK; --Uncomment to Break the loop after just one delete batch
    IF @RowsDeleted = 0 BREAK;
END

--Final Report
SET @Msg = CONCAT(SYSDATETIME(), ' | ', 'Script Completed.  Deleted ', @TotalRowsDeleted, ' of ', @TotalRowsToDelete, ' records from Interaction.');
RAISERROR(@Msg, 10, 1) WITH NOWAIT;

/*
exec sp_spaceused Interaction;

Before:
name	    rows	    reserved	data	    index_size	unused
Interaction	57666573    35536112 KB	8279184 KB	22604208 KB	4652720 KB

After:

*/
