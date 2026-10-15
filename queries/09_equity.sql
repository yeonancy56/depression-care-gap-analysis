-- 09_equity.sql
-- SIMULATED DATA. Who falls through? Measure 134 and 370 rates by payer, age band and
-- social isolation, so the fix can be checked for fairness, not just the average.
-- Payer = the insurer on the patient's latest 2025 visit, grouped the way CMS reports.
-- Social isolation = the finding was active at some point in 2025.

CREATE OR REPLACE TABLE by_group AS
WITH isolated AS (
    SELECT DISTINCT
        PATIENT AS patient_id
    FROM conditions
    WHERE DESCRIPTION = 'Social isolation (finding)'
      AND START <= DATE '2025-12-31'
      AND (STOP IS NULL OR STOP >= DATE '2025-01-01')
),
m134_groups AS (
    SELECT
        r.numerator_met,
        CASE
            WHEN py.NAME = 'Dual Eligible'  THEN 'Dual (Medicare + Medicaid)'
            WHEN py.NAME = 'NO_INSURANCE'   THEN 'Uninsured'
            WHEN py.OWNERSHIP = 'PRIVATE'   THEN 'Private'
            ELSE py.NAME
        END                                                     AS payer_group,
        CASE
            WHEN r.age < 18 THEN '12-17'
            WHEN r.age < 35 THEN '18-34'
            WHEN r.age < 50 THEN '35-49'
            WHEN r.age < 65 THEN '50-64'
            ELSE '65+'
        END                                                     AS age_band,
        CASE WHEN i.patient_id IS NOT NULL THEN 'Socially isolated' ELSE 'Not isolated' END AS isolation
    FROM rc_134 r
    LEFT JOIN payers py
        ON py.Id = r.payer_id
    LEFT JOIN isolated i
        ON i.patient_id = r.patient_id
)
SELECT '134' AS measure, 'Payer' AS dimension, payer_group AS grp,
       COUNT(*) AS patients, SUM(numerator_met::INT) AS passed,
       ROUND(100.0 * AVG(numerator_met::INT), 1) AS rate
FROM m134_groups GROUP BY ALL
UNION ALL
SELECT '134', 'Age band', age_band, COUNT(*), SUM(numerator_met::INT), ROUND(100.0 * AVG(numerator_met::INT), 1)
FROM m134_groups GROUP BY ALL
UNION ALL
SELECT '134', 'Social isolation', isolation, COUNT(*), SUM(numerator_met::INT), ROUND(100.0 * AVG(numerator_met::INT), 1)
FROM m134_groups GROUP BY ALL
UNION ALL
SELECT '370', 'Age group', age_group, COUNT(*), SUM(numerator_met::INT), ROUND(100.0 * AVG(numerator_met::INT), 1)
FROM rc_370 GROUP BY ALL
ORDER BY measure, dimension, rate;
