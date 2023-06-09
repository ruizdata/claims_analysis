/* Top 5 most common valid procedure codes:
   
   88175, 87591, 87491, 85049, 88798
   
   Code retrieves the top 5 most common valid procedure codes along with the count of occurrences for each code, by joining the dbo.Claims table with the 
   dbo.valid_cpt_codes table and grouping the result by the procedure codes. The final result set is sorted in descending order based on the count of occurrence.
*/

SELECT TOP 5 procedure_code, count(*) as count_procedure_code
FROM dbo.Claims
INNER JOIN dbo.valid_cpt_codes
ON dbo.Claims.procedure_code = dbo.valid_cpt_codes.code
WHERE procedure_code IS NOT NULL
GROUP BY procedure_code
ORDER BY count_procedure_code DESC

/* Patients associated with at least one of the top 5 procedures:

   42
   
   Code calculates the count of distinct patient IDs associated with the top 5 most common procedure codes by filtering the data in the Claims table based on 
   the subquery's results.
*/

SELECT COUNT(DISTINCT patient_id) as patient_count
FROM dbo.Claims
WHERE procedure_code IN (
    SELECT TOP 5 procedure_code
    FROM dbo.Claims
    INNER JOIN dbo.valid_cpt_codes
    ON dbo.Claims.procedure_code = dbo.valid_cpt_codes.code
    WHERE procedure_code IS NOT NULL
    GROUP BY procedure_code
    ORDER BY COUNT(*) DESC
    )

/* 2. Top 5 most common valid diagnosis codes:

   J45, R05, C20, I10, A64
   
   Code first adds a new column to the Claims table to store the parsed principal diagnosis code. It then updates the new column with the parsed values from 
   the diagnosis_codes column. Finally, it retrieves the top 5 most common principal diagnosis codes and their respective counts, joining with the valid_icd_10_codes table.
*/

ALTER TABLE dbo.Claims
ADD principal_diagnosis_code VARCHAR(255)
UPDATE dbo.Claims
SET principal_diagnosis_code = LEFT(diagnosis_codes, CHARINDEX('^', diagnosis_codes + '^') - 1)

SELECT TOP 5 principal_diagnosis_code, count(*) as count_principal_diagnosis_code
FROM dbo.Claims
INNER JOIN dbo.valid_icd_10_codes
ON dbo.Claims.principal_diagnosis_code = dbo.valid_icd_10_codes.code
WHERE principal_diagnosis_code IS NOT NULL
GROUP BY principal_diagnosis_code
ORDER BY count_principal_diagnosis_code DESC

/* Errors

   The Date_service column in the Claims table contains incorrect data types (strings) and needs to be updated with values from Untitled column 7. Additionally, there 
   are chronological inconsistencies between the Date_received and Date_service columns, where the Date_received values precede the corresponding Date_service values. 
*/

SELECT CONVERT(date, date_service)
FROM dbo.Claims

SELECT claim_id
FROM dbo.Claims
WHERE date_received < date_service

/* Approximately 25% of these claims are missing procedure codes.
*/

SELECT (COUNT(*) * 100.0 / (SELECT COUNT(*) FROM dbo.Claims)) AS percentage_null_procedure_codes
FROM dbo.Claims
WHERE procedure_code IS NULL

/* Review the data entry processes for the procedure code 99999. Although it is the most frequently used procedure code, it does not exist in the valid code list.
*/

SELECT TOP 1 procedure_code, count(*) as count_procedure_code
FROM dbo.Claims
WHERE procedure_code IS NOT NULL
GROUP BY procedure_code
ORDER BY count_procedure_code DESC
