/*
	10/20/2022 - Jeff McClure
	Identify When non-staff changes Gender, BirthDate, Nickname, or FirstName 
	This is an opportunity for pastoral care, or to potentially catch mistakes that put people in the wrong groups
    
    Suporting Index:
    Create NonClustered Index IX_History_CreatedDateTime_JAM_20221020 On dbo.History (CreatedDateTime, EntityTypeID) With (FillFactor=100, DATA_COMPRESSION=PAGE) On [Primary]
*/
SELECT
	h.EntityId AS PersonID,
	h.CreatedDateTime AS ChangeDateTime,
	h.Caption AS Name,
	h.ValueName AS WhatChanged,
	h.OldValue,
	h.NewValue,
	CASE WHEN h.ValueName = 'Birth Date' THEN CAST(DATEDIFF(YEAR, TRY_CAST(h.OldValue AS DATE), CAST(GETDATE() AS DATE)) AS VARCHAR(10)) ELSE '-' END AS OldAge,
	CASE WHEN h.ValueName = 'Birth Date' THEN CAST(DATEDIFF(YEAR, TRY_CAST(h.NewValue AS DATE), CAST(GETDATE() AS DATE)) AS VARCHAR(10)) ELSE '-' END AS NewAge,
	CASE p.Gender WHEN 1 THEN 'Male' WHEN 2 THEN 'Female' ELSE 'Unknown' END AS CurrGender,
	p.BirthDate AS CurrBirthDate,
	p.NickName AS CurrNickName,
	p.FirstName AS CurrFirstName,
	CONCAT (WhoDunnit.NickName, ' ', WhoDunnit.LastName) AS WhoDoneIt
FROM dbo.History h
INNER JOIN dbo.Person p ON p.Id = h.EntityId
INNER JOIN dbo.PersonAlias pa ON pa.Id = h.CreatedByPersonAliasId
INNER JOIN dbo.Person WhoDunnit ON WhoDunnit.Id = pa.PersonId
WHERE 
	h.CreatedDateTime >= CAST(DATEADD(DAY, -8, GETDATE()) AS DATETIME)
	AND h.CreatedDateTime < CAST(CAST(GETDATE() AS DATE) AS DATETIME)
	AND Verb = 'MODIFY'
	AND EntityTypeId = 15 --Person
	AND ChangeType = 'Property'
	AND ValueName IN ('Nick Name','First Name','Birth Date','Gender')
	AND OldValue IS NOT NULL
	AND OldValue <> 'Unknown'
	AND NewValue <> OldValue
	AND NOT EXISTS (SELECT * FROM dbo.TaggedItem ti WHERE ti.TagId = 1 AND ti.EntityGuid = WhoDunnit.Guid) --Not changed by Staff
ORDER BY CASE ValueName
		WHEN 'Gender' THEN 1
		WHEN 'Birth Date' THEN 2
		WHEN 'Nick Name' THEN 3
		ELSE 4 END,
		h.CreatedDateTime
