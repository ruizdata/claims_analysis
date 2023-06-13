-- Check for Exclusions and remove any patients that show as an Exclusion on the Exclusions tab

DELETE FROM PatientData
WHERE id IN (
    SELECT Exclusions FROM Exclusions
);

-- Check for and remove duplicate MRNs (patient IDs)

WITH CTE AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY id) AS RowNum
    FROM PatientData
)
DELETE FROM CTE
WHERE RowNum > 1;

-- Remove patients who are not Medicare (or Medicare Part A AND B, or Medicare Part B) primary

DELETE FROM PatientData
WHERE "Insurance Name" NOT LIKE 'Medicare%'

-- Remove patients who have any insurance containing "Tricare", ChampVA, Medicaid, or BCBS of South Carolina as a secondary or tertiary insurance (if one is in file) insurance. Also remove patients with a blank secondary insurance.

DELETE FROM PatientData
WHERE "Secondary Insurance Name" LIKE '%Tricare%'
   OR "Secondary Insurance Name" LIKE '%ChampVA%'
   OR "Secondary Insurance Name" LIKE '%Medicaid%'
   OR "Secondary Insurance Name" LIKE '%BCBS of South Carolina%'
   OR "Secondary Insurance Name" IS NULL;

-- Use the tab called “Diagnosis” and cross reference the patients for their Diagnosis codes using their patient account number to cross reference and combine diagnosis codes for the same MRN/Patient ID and then add them as a column to the MOCK_PATIENT_DATA comma separated.

ALTER TABLE PatientData
ADD DiagnosisCodes VARCHAR(MAX);

UPDATE PatientData
SET DiagnosisCodes = (
    SELECT STRING_AGG(Diagnosis, ', ')
    FROM Diagnosis
    WHERE Diagnosis."Medical Record Number" = PatientData.id
    GROUP BY Diagnosis."Medical Record Number"
	);

-- Delete any patients with less than 2 codes as a result of the above step.

DELETE FROM PatientData
WHERE LEN(DiagnosisCodes) - LEN(REPLACE(DiagnosisCodes, ',', '')) + 1 < 2;

-- Split Provider Names into First and Last Names

ALTER TABLE PatientData
ADD ProviderFirstName VARCHAR(50),
    ProviderLastName VARCHAR(50);

UPDATE PatientData
SET ProviderFirstName = SUBSTRING("Provider Name", 1, CHARINDEX(' ', "Provider Name") - 1),
    ProviderLastName = SUBSTRING("Provider Name", CHARINDEX(' ', "Provider Name") + 1, LEN("Provider Name"));

-- Convert patient names to proper case (first letter uppercase, the rest lowercase)

UPDATE PatientData
SET first_name = UPPER(LEFT(first_name, 1)) + LOWER(SUBSTRING(first_name, 2, LEN(first_name) - 1)),
    last_name = UPPER(LEFT(last_name, 1)) + LOWER(SUBSTRING(last_name, 2, LEN(last_name) - 1));

-- Clean up Phone #s to be only digits with no extra characters.

UPDATE PatientData
SET "Home Phone"= REPLACE(REPLACE(REPLACE(REPLACE("Home Phone", '(', ''), ')', ''), '-', ''), ' ', '');

-- Check for missing main phone and use alternate if available - Cell phone is best, Home phone otherwise

UPDATE PatientData
SET "Main Phone" = CASE
    WHEN "Cell Phone" IS NOT NULL AND "Cell Phone" <> '' THEN "Cell Phone"
    ELSE "Home Phone"
    END;

-- Create a combined address column and combine address 1 and address 2 with a line break separating them

ALTER TABLE PatientData
ADD CombinedAddress NVARCHAR(MAX);

UPDATE PatientData
SET CombinedAddress = CONCAT("Address 1", CHAR(13) + CHAR(10), "Address 2");

-- Fill blank patient emails using the format mockdata+<MRN>@healthsnap.io

UPDATE PatientData
SET Email = CONCAT('mockdata+', "id", '@healthsnap.io')
WHERE Email IS NULL OR Email = '';

-- Check for duplicate emails

SELECT Email, COUNT(*) AS DuplicateCount
FROM PatientData
WHERE Email IS NOT NULL AND Email <> ''
GROUP BY Email
HAVING COUNT(*) > 1;

-- Add Provider Emails from the ProviderEmails tab

ALTER TABLE PatientData
ADD ProviderEmail VARCHAR(255);

UPDATE PatientData
SET PatientData.ProviderEmail = ProviderEmails.[Provider Email]
FROM PatientData
INNER JOIN ProviderEmails ON PatientData.[ProviderFirstName] = ProviderEmails.[Provider First Name]
AND PatientData.[ProviderLastName] = ProviderEmails.[Provider Last Name];

-- For any blank Insurance Member IDs (Primary or Secondary), enter N/A

UPDATE PatientData
SET [Insurance ID] = CASE WHEN [Insurance ID] = '' OR [Insurance ID] IS NULL THEN 'N/A' ELSE [Insurance ID] END,
    [Secondary Insurance ID] = CASE WHEN [Secondary Insurance ID] = '' OR [Secondary Insurance ID] IS NULL THEN 'N/A' ELSE [Secondary Insurance ID] END
WHERE [Insurance ID] = '' OR [Secondary Insurance ID] = '' OR [Insurance ID] IS NULL OR [Secondary Insurance ID] IS NULL;

-- Create a copy of the data on a new tab called "Mail" and only include Patient First Name, Patient Last Name, Patient Address 1, Patient Address 2, Patient City, Patient State, Patient Zip.

SELECT first_name, last_name, [Address 1], [Address 2], city, state, zip
FROM PatientData;

-- Transformed PatientData table

SELECT *
FROM PatientData
