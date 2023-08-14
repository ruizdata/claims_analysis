-- PROCEDURE: public.newberry_script()

-- DROP PROCEDURE IF EXISTS public.newberry_script();

CREATE OR REPLACE PROCEDURE public.newberry_script(
	)
LANGUAGE 'sql'
AS $BODY$
/* Newberry Script

Set-Up

A.	Establish a connection to the VPN using L2TP and provide your Username and Shared Key when prompted.
B.	In pgAdmin, navigate to the following location: Servers > HealthSnap Onboarding > Databases > healthsnap_onboarding > Schemas > public > Tables.
C.	Import the required files as CSV. For each file, create a table and name it accordingly. Add columns with data types set to "character varying". Ensure that the column titles exactly match the headers in the CSV files. Additionally, enable the "Header" option under the import settings.

Required Files: newberry_import, newberry_exclusions, newberry_providers, newberry_devices

D.	Utilize the Query Tool to execute the SQL code.

*/

-- Standardize the column names

DO $$ 
DECLARE
    column_changes text[][];
    i int;
BEGIN
    column_changes := ARRAY[
        ['Patient Chart Nbr', 'mrn'],
        ['Pat First Name', 'first_name'],
        ['Pat Last Name', 'last_name'],
		['Pat Cv1 Plan Name', 'primary_insurance'],
        ['Pat Cv2 Plan Name', 'secondary_insurance'],
        ['Pat Home Phone', 'home_phone'],
		['Pat Home Phone Num', 'cell_phone'],
        ['Pat Email', 'email'],
        ['Pat Home Addr Line1', 'address_line1'],
        ['Pat Home Addr Line2', 'address_line2'],
        ['Pat Home Addr City', 'city'],
        ['Pat Home Addr St', 'state'],
        ['Pat Home Addr Zip', 'zip'],
		['Pat Assigned Prov First Name', 'provider_first_name'],
		['Pat Assigned Prov Last Name', 'provider_last_name']
    ];

    FOR i IN 1..array_length(column_changes, 1)
    LOOP
        IF EXISTS (SELECT * FROM information_schema.columns WHERE table_name = 'newberry_import' AND column_name = column_changes[i][1]) 
           AND NOT EXISTS (SELECT * FROM information_schema.columns WHERE table_name = 'newberry_import' AND column_name = column_changes[i][2]) THEN
            EXECUTE format('ALTER TABLE newberry_import RENAME COLUMN "%s" TO %I', column_changes[i][1], column_changes[i][2]);
        END IF;
    END LOOP;
END $$;

-- 1.	Remove MRNs already in the Exclusions list.

DELETE FROM newberry_import
WHERE "mrn" IN (
    SELECT "MRN" FROM newberry_exclusions
);

-- 2.	Remove duplicate MRNs.

DELETE FROM newberry_import
WHERE ctid NOT IN (
   SELECT min(ctid) 
   FROM newberry_import 
   GROUP BY "mrn"
);

-- 3.	Remove blank MRNs.

DELETE FROM newberry_import
WHERE "mrn" IS NULL OR TRIM("mrn") = '';

-- 4.	Remove patients whose primary insurance is not Medicare, Medicare Part A and B, or Medicare Part B.

DELETE FROM newberry_import
WHERE "primary_insurance" NOT LIKE 'MEDICARE%';

-- 5.	Remove patients whose secondary insurance contain Tricare, ChampVA, BCBS of South Carolina, or blank.

DELETE FROM newberry_import
WHERE "secondary_insurance" LIKE '%TRICARE%'
   OR "secondary_insurance" LIKE '%ChampVA%'
   OR "secondary_insurance" LIKE '%MEDICAID%'
   OR "secondary_insurance" LIKE '%BLUE CROSS BLUE SHIELD SC%'
   OR "secondary_insurance" IS NULL
   OR "secondary_insurance" = '';

-- 6.	Make patients name proper case.

UPDATE newberry_import
SET "first_name" = UPPER(LEFT("first_name", 1)) || LOWER(SUBSTRING("first_name", 2)),
    "last_name" = UPPER(LEFT("last_name", 1)) || LOWER(SUBSTRING("last_name", 2));

-- 7.	Remove dashes from phone numbers.

UPDATE newberry_import
SET "home_phone" = REPLACE(REPLACE(REPLACE(REPLACE("home_phone", '(', ''), ')', ''), '-', ''), ' ', '');

-- 8.   If the home phone is misssing, use the mobile phone.

UPDATE newberry_import
SET "home_phone" = CASE
    WHEN "mobile_phone" IS NOT NULL AND "mobile_phone" <> '' THEN "mobile_phone"
    ELSE "home_phone"
    END;

-- 9.   Fill blank patient emails using the format newberry+<MRN>@healthsnap.io

UPDATE newberry_import
SET "email" = CONCAT('newberry+', "mrn", '@healthsnap.io')
WHERE "email" IS NULL OR "email" = '';

-- 10.  Check for duplicate emails

SELECT "email", COUNT(*) AS DuplicateCount
FROM newberry_import
WHERE "email" IS NOT NULL AND "email" <> ''
GROUP BY "email"
HAVING COUNT(*) > 1;

-- 11. Add provider emails and signatures.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS "provider_full_name" VARCHAR(255);

UPDATE newberry_import
SET provider_full_name = provider_first_name || ' ' || provider_last_name;

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS provider_email VARCHAR(255),
ADD COLUMN IF NOT EXISTS provider_signature VARCHAR(255);

UPDATE newberry_import
SET provider_email = newberry_providers."Email",
    provider_signature = newberry_providers."Signature"
FROM newberry_providers
WHERE newberry_import.provider_full_name = newberry_providers."Name";

-- 12. Set enrollment date to today.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS enrollment_date VARCHAR(255);

UPDATE newberry_import
SET enrollment_date = CURRENT_DATE;

-- 13. Create a column for Combined Diagnoses.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS combined_diagnoses VARCHAR(255);

UPDATE newberry_import
SET combined_diagnoses = "Pat Def Diag 1 Code" || ',' || "Pat Def Diag 2 Code" || ',' || "Pat Def Diag 3 Code" || ',' || "Pat Def Diag 4 Code" || ',' || "Pat Last Vst Diagnosis Codes";

UPDATE newberry_import
SET combined_diagnoses = regexp_replace(combined_diagnoses, ',+', ',', 'g');

UPDATE newberry_import
SET combined_diagnoses = REPLACE(combined_diagnoses, ' ', '');

UPDATE newberry_import
SET combined_diagnoses = (
    SELECT STRING_AGG(DISTINCT diagnosis, ', ' ORDER BY diagnosis)
    FROM (
        SELECT UNNEST(STRING_TO_ARRAY(REPLACE(combined_diagnoses, ' ', ''), ',')) AS diagnosis
    ) AS unique_diagnoses
);

-- 14. Create a column for CCM Filtered Diagnoses.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS ccm_filtered_diagnoses VARCHAR(255);

UPDATE newberry_import
SET ccm_filtered_diagnoses = (
    SELECT STRING_AGG(DISTINCT general_ccm_diagnoses_filters."Diagnoses", ', ')
    FROM general_ccm_diagnoses_filters
    WHERE general_ccm_diagnoses_filters."Diagnoses" = ANY (STRING_TO_ARRAY(newberry_import.combined_diagnoses, ', '))
);

-- 15. Create a column for CCM Qualified (at least 2 codes)

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS ccm_qualified VARCHAR(225);

UPDATE newberry_import
SET ccm_qualified = 'CCM'
WHERE ccm_filtered_diagnoses LIKE '%,%';

-- 16. Create a column for RPM Filtered Diagnoses.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS rpm_filtered_diagnoses VARCHAR(255);

UPDATE newberry_import
SET rpm_filtered_diagnoses = (
    SELECT STRING_AGG(DISTINCT newberry_rpm_diagnoses_filters."Diagnoses", ', ')
    FROM newberry_rpm_diagnoses_filters
    WHERE newberry_rpm_diagnoses_filters."Diagnoses" = ANY (STRING_TO_ARRAY(newberry_import.combined_diagnoses, ', '))
);

-- 17. Create a column for RPM Qualified (at least 1 codes)

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS rpm_qualified VARCHAR(225);

UPDATE newberry_import
SET rpm_qualified = 'RPM'
WHERE rpm_filtered_diagnoses IS NOT NULL;

-- 18. For all RPM qualified, set monitoring reason, device, and data point.

ALTER TABLE IF EXISTS newberry_import
ADD COLUMN IF NOT EXISTS rpm_monitoring_reason VARCHAR(225),
ADD COLUMN IF NOT EXISTS rpm_device VARCHAR(225),
ADD COLUMN IF NOT EXISTS rpm_data_point VARCHAR(225);

UPDATE newberry_import
SET rpm_monitoring_reason = 'Monitoring Physiological Data'
WHERE rpm_qualified = 'RPM';

UPDATE newberry_import
SET rpm_data_point = (
    SELECT newberry_devices."Data Point"
    FROM newberry_devices
    WHERE newberry_devices."Diagnoses" = ANY (STRING_TO_ARRAY(newberry_import.rpm_filtered_diagnoses, ', '))
    LIMIT 1
);

UPDATE newberry_import
SET rpm_device = CASE 
    WHEN rpm_data_point = 'Blood Pressure' THEN 'Blood Pressure Monitor'
    WHEN rpm_data_point = 'Blood Glucose' THEN 'Glucose Meter'
    WHEN rpm_data_point = 'Oxygen Satuation' THEN 'Pulse Oximeter'
	ELSE rpm_device
END;


-- 19. Delete patients who do not qualify for either CCM or RPM.

DELETE FROM newberry_import
WHERE (ccm_qualified IS NULL OR ccm_qualified = '')
  AND (rpm_qualified IS NULL OR rpm_qualified = '');

-- 21. Create Edited List

SELECT
    first_name,
    last_name,
    mrn,
    provider_first_name,
    provider_last_name,
    "Pat DOB",
    email,
    address_line1,
    address_line2,
    city,
    state,
    zip,
    home_phone,
    cell_phone,
    primary_insurance,
    secondary_insurance,
    provider_email,
    provider_signature,
    enrollment_date,
    combined_diagnoses,
    ccm_filtered_diagnoses,
    ccm_qualified,
    rpm_filtered_diagnoses,
    rpm_qualified,
    rpm_monitoring_reason,
    rpm_device,
    rpm_data_point
FROM newberry_import;

-- 20. Create Stannp import.

SELECT
    first_name,
    last_name,
    address_line1,
    address_line2,
    city,
    state,
    zip
FROM newberry_import;

$BODY$;

ALTER PROCEDURE public.newberry_script()
    OWNER TO rey;
