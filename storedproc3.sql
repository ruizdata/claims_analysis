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

Files to be imported: initial patient list, exclusions, providers' information, devices' information.
D.	Utilize the Query Tool to execute the SQL code.

*/

-- Standardize the column names

DO $$ 
DECLARE
    column_changes text[][];
    i int;
BEGIN
    column_changes := ARRAY[
        ['Patient Chart Number', 'mrn'],
        ['Pat First Name', 'first_name'],
        ['Pat Last Name', 'last_name'],
		['Pat Cv1 Plan Name', 'primary_insurance'],
        ['Pat Cv2 Plan Name', 'secondary_insurance'],
        ['Pat Home Phone', 'home_phone'],
        ['Pat Mobile Phone Num', 'mobile_phone'],
        ['Pat Email', 'email'],
        ['Pat Home Addr Line1', 'address_line1'],
        ['Pat Home Addr Line2', 'address_line2'],
        ['Pat Home Addr City', 'city'],
        ['Pat Home Addr St', 'state'],
        ['Pat Home Addr Zip', 'zip']
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
WHERE "mrn" IS NULL;

-- 4.	Remove patients whose primary insurance is not Medicare, Medicare Part A and B, or Medicare Part B.

DELETE FROM newberry_import
WHERE "primary_insurance" NOT LIKE 'MEDICARE%';

-- 5.	Remove patients whose secondary insurance contain Tricare, ChampVA, BCBS of South Carolina, or blank.

DELETE FROM newberry_import
WHERE "secondary_insurance" LIKE '%TRICARE%'
   OR "secondary_insurance" LIKE '%ChampVA%'
   OR "secondary_insurance" LIKE '%MEDICAID%'
   OR "secondary_insurance" LIKE '%BCBS of South Carolina%'
   OR "secondary_insurance" IS NULL;

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

-- 9.   Fill blank patient emails using the format mockdata+<MRN>@healthsnap.io

UPDATE newberry_import
SET "email" = CONCAT('newberry+', "mrn", '@healthsnap.io')
WHERE "email" IS NULL OR "email" = '';


-- 10.  Check for duplicate emails

SELECT "email", COUNT(*) AS DuplicateCount
FROM newberry_import
WHERE "email" IS NOT NULL AND "email" <> ''
GROUP BY "email"
HAVING COUNT(*) > 1;

-- 11. Create Stannp import.

SELECT "first_name", "last_name", "address_line1", "address_line2", "city", "state", "zip"
FROM newberry_import;

$BODY$;

ALTER PROCEDURE public.newberry_script()
    OWNER TO rey;
