/*
	11/29/2022 Jeff McClure - Lakepointe Church - Created
	This trigger is designed to prevent staff emails from being updated to a non-staff email address.  
	To change the email	of a staff member to a non-staff email, you must first remove the Staff tag from their person profile.

	Trigger can be disabled/enabled at any time. Scripts below.
		Disable Trigger dbo._org_Lakepointe_trgStaffEmailChangePrevention On dbo.Person
		Enable Trigger dbo._org_Lakepointe_trgStaffEmailChangePrevention On dbo.Person

	Trigger History:
		SELECT Count(*)
		FROM dbo.history h
		WHERE EntityTypeID = 15
		And Caption like 'SQL Trigger%'
		And Verb = 'Modify'
		And Valuename = 'Email'
*/
CREATE OR ALTER TRIGGER dbo._org_Lakepointe_trgStaffEmailChangePrevention
ON dbo.Person
AFTER UPDATE AS
BEGIN 

	--If email address isn't changing, no need to keep going.
	IF NOT UPDATE (Email)
	RETURN;

	DECLARE @Id INT,
			@OrigEmail NVARCHAR(75),
			@NewEmail NVARCHAR(75);

	--Set some working variables
	SELECT @Id = Id, @OrigEmail = Email FROM deleted;
	SELECT @NewEmail = Email FROM inserted;
	
	--If the New and Orig emails are the same, no reason to continue.
	IF (@OrigEmail = @NewEmail)
	RETURN;

	--If the email is changing, AND they are staff, go ahead and process
	IF EXISTS (
		SELECT *
		FROM inserted i
		JOIN dbo.PersonAlias pa ON pa.PersonId = i.Id
		JOIN dbo.TaggedItem ti ON ti.EntityGuid = pa.AliasPersonGuid
		WHERE ti.EntityTypeID = 15 --Person Entity
		AND ti.TagId = 1 --Staff
	)
	BEGIN
		--If setting to any Lakepointe email address, allow it.
		IF SUBSTRING(@NewEmail, (CHARINDEX(N'@', @NewEmail)+1), LEN(@NewEmail)) = N'lakepointe.church'
		RETURN;

		--If updating to non-lakepointe email, and orig email is lakepointe, preserve the lakepointe email.
		IF SUBSTRING(@NewEmail, (CHARINDEX(N'@', @NewEmail)+1), LEN(@NewEmail)) <> N'lakepointe.church'
		AND SUBSTRING(@OrigEmail, (CHARINDEX(N'@', @OrigEmail)+1), LEN(@OrigEmail)) = N'lakepointe.church'
		BEGIN
			--Update the Email address in the person record back to the Lakepointe.church value
			UPDATE p
			SET Email = @OrigEmail
			FROM dbo.Person p
			INNER JOIN inserted i ON i.Id = p.Id
			WHERE p.Id = @Id;

			--Write history record to make it easy to follow (200 chars max)
			INSERT dbo.History(IsSystem, CategoryId, EntityTypeId, EntityId, Caption, Guid, CreatedDateTime, ModifiedDateTime, Verb, ChangeType, ValueName, NewValue, OldValue, IsSensitive)
			SELECT 0, 133, 15, @Id, N'SQL Trigger: Preserved Lakepointe Staff Email Address.  Remove staff tag to update to a non-Lakepointe email address. (Person._org_Lakepointe_trgStaffEmailChangePrevention)', NEWID(), DATEADD(SECOND, 1, GETDATE()), GETDATE(), 'MODIFY', 'Property', 'Email', @OrigEmail, @NewEmail, 0;
		END
	END
END

GO


/* 
Test Scripts

SELECT email, *
FROM dbo.Person
WHERE id = 319854

--Success
UPDATE dbo.Person
SET email = 'qwerty2@Lakepointe.church'
WHERE id = 319854
SELECT email, * FROM dbo.Person WHERE id = 319854

--Fails to update email and preserves the original
UPDATE dbo.Person
SET email = 'dork@adsf.test'
WHERE id = 319854
SELECT email, * FROM dbo.Person WHERE id = 319854

--View History
SELECT TOP 20 * 
FROM history h
WHERE entityid = 319854 
And EntityTypeID = 15
ORDER BY 1 desc

--How many times has it fired and preserved the Lakepointe Email?
SELECT count(*)
FROM dbo.history h
WHERE EntityTypeID = 15
And Caption like 'SQL Trigger%'
And Verb = 'Modify'
And Valuename = 'Email'

*/

