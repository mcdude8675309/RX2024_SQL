--Row_Number() Window Function 
--Example for finding most recent group attendance for a list of people
--DECLARE @StartDate DATETIME = '2024-08-01' --Would use this, but easier to demo with hard coded
;WITH groupattendance AS(
    SELECT pa.PersonId, g.name, a.StartDateTime, ROW_NUMBER() OVER(PARTITION BY pa.PersonId ORDER BY a.StartDateTime DESC) AS Rowid
    FROM dbo.[group] g 
    JOIN dbo.AttendanceOccurrence ao ON ao.GroupId = g.Id
    JOIN dbo.Attendance a ON a.OccurrenceId = ao.Id
    JOIN dbo.PersonAlias pa ON pa.Id = a.PersonAliasId
    WHERE a.DidAttend = 1
    AND a.StartDateTime >= '2024-08-01'
)
SELECT p.firstname, p.lastname, groupattendance.Name, groupattendance.StartDateTime
FROM Person p 
LEFT OUTER JOIN groupattendance ON groupattendance.PersonId = p.id AND groupattendance.Rowid = 1
WHERE p.createddatetime >= '2024-08-01'
AND p.RecordTypeValueId <> 4550
