/*
    8/6/2024 Jeff McCLure - 
    Rewrote New From Web without contributions.  
    However, this may include people with Event Registration payments
*/
WITH giving AS (
    SELECT adpc.[PersonId], SUM(asft.[Amount]) AS Amt
    FROM  [dbo].[AnalyticsDimPersonCurrent] adpc
    LEFT JOIN [dbo].[AnalyticsSourceFinancialTransaction] AS asft ON adpc.[Id] = asft.[AuthorizedPersonKey]
    WHERE asft.[AuthorizedPersonAliasId] IS NOT NULL
    AND asft.[TransactionTypeValueId] = 53 --Limit to Contributions (exclude Event Registration payments).
    GROUP BY adpc.[PersonId]
)
, notes AS (
    SELECT [EntityId] AS PersonId, n.[Text] AS LastNote, ROW_NUMBER() OVER(PARTITION BY [EntityId] ORDER BY n.[Id] DESC) AS RowNum
    FROM dbo.[Note] n
    JOIN dbo.[NoteType] nt ON nt.Id = n.NoteTypeId
    WHERE nt.[EntityTypeId] = 15 --Person
)
SELECT p.[Id], p.[CreatedDatetime], CONCAT(createdBy.[NickName], ' ', createdBy.[LastName]) AS CreatedBy, CONCAT(p.[NickName], ' ', p.[LastName]) AS Name, p.[Email], pn.[NumberFormatted] AS CellPhone, p.[Birthdate], c.[Name] AS Campus
    , n.[LastNote]
    , Concat('<a class=''btn btn-default'' target="_blank" rel="noopener noreferrer" href="/Person/', p.[Id],'"''><i class=''fas fa-user''></i></a>') as PersonProfile
    , Concat('<a class=''btn btn-default'' target="_blank" rel="noopener noreferrer" href="/PersonDuplicate/', p.[id],'"''><i class=''fas fa-user-friends''></i></a>') as DupeSearch 
    , Concat('<a class=''btn btn-default'' target="_blank" rel="noopener noreferrer" href="/Person/Search/name/?SearchTerm=', p.[Nickname],'%20', p.[LastName],'"''><i class=''fa fa-search-plus''></i></a>') as NameSearch
    , Concat('<a class=''btn btn-default'' target="_blank" rel="noopener noreferrer" href="/Person/Search/phone/?SearchTerm=', pn.[number],'"''><i class=''fas fa-phone''></i></a>') as PhoneSearch
    , Concat('<a class=''btn btn-default'' target="_blank" rel="noopener noreferrer" href="/Person/Search/email/?SearchTerm=', p.[email],'"''><i class=''fas fa-at''></i></a>') as EmailSearch  
FROM [Person] p
    LEFT JOIN dbo.[Campus] c ON c.[Id] = p.[PrimaryCampusId]
    LEFT JOIN giving g ON p.[Id] = g.[PersonId]
    LEFT JOIN dbo.[PhoneNumber] pn ON pn.[PersonId] = p.[Id] AND pn.[NumberTypeValueId] = 12
    LEFT JOIN notes n ON n.[PersonId] = p.[Id] AND n.[RowNum] = 1
    LEFT JOIN dbo.[PersonAlias] pa ON pa.[Id] = p.[CreatedByPersonAliasId]
    LEFT JOIN dbo.[Person] createdBy ON createdBy.[Id] = pa.[PersonId] --Who created the NFW person record?
WHERE p.[ConnectionStatusValueId] = 1572 --NFW
    AND p.[IsDeceased] = 0
    AND p.[RecordTypeValueId] = 1 --Person
    AND p.[RecordStatusValueId] in (3,5) --Active and Pending
    AND (g.[Amt] Is Null OR g.[Amt] = 0) --Exclude those with contributions
ORDER BY [CreatedDateTime] ASC