/****************************************************************************************************

NOTE: THIS SCRIPT IS HERE AS AN EXAMPLE ONLY 
THIS IS JUST ONE POSSIBLE WAY OF DOING THIS

Rock has a built in way to purge Page Views from interactions that should be used instead.
****************************************************************************************************/

--Identify and Purge Page Views older than 1 year from Interaction table.  (Almost half the table)

--SELECT COUNT(*) --28871848
--FROM dbo.Interaction i
--JOIN dbo.InteractionComponent ic ON ic.Id = i.InteractionComponentId
--JOIN dbo.InteractionChannel ich ON ich.Id = ic.InteractionChannelId
--WHERE ich.ChannelTypeMediumValueId IN (3046, 3051)
--AND I.InteractionDateTime < '2023-06-05'

--Build work table
DROP TABLE IF EXISTS #ids
CREATE TABLE #ids (RowId INT NOT NULL PRIMARY KEY IDENTITY(1,1), Id INT NOT NULL);
SELECT TOP 1000 * FROM #ids ORDER BY 1

--Populate work table with the data to process
INSERT INTO #ids SELECT i.Id
FROM dbo.Interaction i
JOIN dbo.InteractionComponent ic ON ic.Id = i.InteractionComponentId
JOIN dbo.InteractionChannel ich ON ich.Id = ic.InteractionChannelId
WHERE ich.ChannelTypeMediumValueId IN (3046, 3051)
AND I.InteractionDateTime < DATEADD(DAY, -(365), CAST(SYSDATETIMEOFFSET() AT TIME ZONE 'Central Standard Time' AS DATETIME))
ORDER BY Id

--BEGIN tran
SET XACT_ABORT ON;
SET NOCOUNT ON;
DECLARE @CurrId INT = (SELECT MIN(RowId) FROM #Ids)
DECLARE @RowsToDelete INT = 1000
DECLARE @TotalRowsToDelete INT = (SELECT COUNT(*) FROM #ids)
DECLARE @TotalRowsDeleted INT = 0
DECLARE @msg NVARCHAR(1000) = ''
DECLARE @DoIt Bit = 0 --<-- Set this to 1 to actually delete records - Safety Check!
SELECT 'Debug', @CurrId AS CurrId, @RowsToDelete AS RowsPerBatch, @TotalRowsToDelete AS TotalRowsToDelete

WHILE (@CurrId <= @TotalRowsToDelete AND @DoIt = 1)
BEGIN

    BEGIN TRAN

    DELETE i
    --SELECT c.Id
    FROM dbo.Interaction i
    JOIN #Ids ids ON ids.Id = i.Id
    WHERE ids.RowID >= @currid
    AND ids.RowId < @currId + @RowsToDelete

    DELETE #Ids
    WHERE RowID >= @currid
    AND RowId < @currId + @RowsToDelete
    
    COMMIT 

    SET @TotalRowsDeleted += @RowsToDelete;
    SET @CurrId += @RowsToDelete;
    
    IF @TotalRowsDeleted % 100000 = 0
    Begin
        SET @Msg = CONCAT(SYSDATETIME(), ' | ', 'Deleted ', @TotalRowsDeleted, ' of ', @TotalRowsToDelete, ' records from Interaction.');
        RAISERROR(@msg, 10, 1) WITH NOWAIT;
    End
    --BREAK;

END

--rollback
/*
--Before


--After

*/
