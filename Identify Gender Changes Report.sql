--Identify When non-staff changes Gender, BirthDate, Nickname, or FirstName 
select
	h.EntityID as PersonID,
	h.CreatedDateTime As ChangeDateTime,
	h.Caption as Name,
	h.ValueName As WhatChanged,
	h.OldValue,
	h.NewValue,
	Case When h.ValueName = 'Birth Date' Then Cast(Datediff(year, try_cast(h.OldValue as Date), Cast(Getdate() as Date)) as Varchar(10)) Else '-' End as OldAge,
	Case When h.ValueName = 'Birth Date' Then Cast(Datediff(year, try_cast(h.NewValue as Date), Cast(Getdate() as Date)) as Varchar(10)) Else '-' End as NewAge,
	Case p.Gender When 1 Then 'Male' When 2 Then 'Female' Else 'Unknown' End As CurrGender,
	p.Birthdate As CurrBirthDate,
	p.NickName As CurrNickName,
	p.FirstName As CurrFirstName,
	Concat (WhoDunnit.nickname, ' ', WhoDunnit.LastName) as WhoDoneIt
From dbo.History h
Inner Join dbo.Person p on p.Id = h.EntityId
Inner Join dbo.PersonAlias pa on pa.id = h.CreatedByPersonAliasId
Inner Join dbo.Person WhoDunnit on whodunnit.id = pa.PersonId
Where 
	h.CreatedDateTime >= Cast(Dateadd(Day, -8, Getdate()) As Datetime)
	And h.CreatedDateTime < Cast(Cast(Getdate() as Date) As Datetime)
	And Verb = 'MODIFY'
	And EntityTypeId = 15 --Person
	And ChangeType = 'Property'
	And Valuename in ('Nick Name','First Name','Birth Date','Gender')
	And OldValue Is Not Null
	And OldValue <> 'Unknown'
	And NewValue <> OldValue
	And Not Exists (Select * from dbo.TaggedItem ti Where ti.TagID = 1 and ti.EntityGuid = WhoDunnit.Guid) --Not changed by Staff
Order By Case ValueName
		When 'Gender' Then 1
		When 'Birth Date' Then 2
		When 'Nick Name' Then 3
		Else 4 End,
		h.CreatedDateTime
		
--Create NonClustered Index IX_History_CreatedDateTime_JAM_20221020 On dbo.History (CreatedDateTime, EntityTypeID) With (FillFactor=100) On [Primary]

--select top 100 * from tag
--select top 100 * from TaggedItem


--Select * from attribute where id = 107658 or name = 'coach'
