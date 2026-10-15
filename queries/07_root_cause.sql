-- 07_root_cause.sql
-- SIMULATED DATA. Why do patients fail each measure? Turns the measure tables into
-- operational causes a clinic could act on, then ranks them (Pareto).

-- A. Which kinds of visit record a depression screen? (2025, patients 12+)
CREATE OR REPLACE TABLE rc_screen_by_visit_type AS
SELECT
    e.ENCOUNTERCLASS                                        AS visit_type,
    COUNT(*)                                                AS visits_2025,
    COUNT(*) FILTER (WHERE s.ENCOUNTER IS NOT NULL)         AS visits_with_screen,
    ROUND(100.0 * COUNT(*) FILTER (WHERE s.ENCOUNTER IS NOT NULL) / COUNT(*), 1) AS pct_with_screen
FROM encounters e
JOIN patients_deid p
    ON p.Id = e.PATIENT
LEFT JOIN (
    SELECT DISTINCT ENCOUNTER
    FROM observations
    WHERE CODE IN ('55758-7', '44261-6', '89204-2')
) s
    ON s.ENCOUNTER = e.Id
WHERE year(e.START) = 2025
  AND e.ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness', 'virtual', 'urgentcare', 'emergency')
  AND e.DESCRIPTION <> 'Death Certification'
  AND date_sub('year', p.BIRTHDATE, CAST(e.START AS DATE)) >= 12
GROUP BY 1
ORDER BY visits_2025 DESC;

-- B. Measure 134 patients, tagged with the visit facts that explain their result.
CREATE OR REPLACE TABLE rc_134 AS
WITH wellness_2025 AS (
    SELECT DISTINCT
        PATIENT AS patient_id
    FROM encounters
    WHERE ENCOUNTERCLASS = 'wellness'
      AND year(START) = 2025
      AND DESCRIPTION <> 'Death Certification'
)
SELECT
    m.*,
    w.patient_id IS NOT NULL AS had_wellness_2025,
    CASE
        WHEN m.result_reason = 'Fail: not screened' AND w.patient_id IS NOT NULL
            THEN 'A. Had a 2025 annual wellness exam, no screen recorded'
        WHEN m.result_reason = 'Fail: not screened'
            THEN 'B. No wellness exam in 2025; only problem or other visits, none screened'
        WHEN m.result_reason = 'Fail: screen documented, no score recorded'
            THEN 'C. Screen documented without a score (mostly prenatal/postnatal visits)'
        WHEN m.result_reason = 'Fail: positive screen, no follow-up plan in 2 days'
            THEN 'D. Teen positive screen, no follow-up plan'
    END AS root_cause
FROM m134 m
LEFT JOIN wellness_2025 w
    ON w.patient_id = m.patient_id
WHERE NOT m.excluded;

-- C. Measure 370 patients, tagged with what happened in their 12-month window
--    (index + 305 to + 425 days), the window in which a PHQ-9 would have counted.
CREATE OR REPLACE TABLE rc_370 AS
WITH window_facts AS (
    SELECT
        m.patient_id,
        EXISTS (
            SELECT 1
            FROM encounters e
            WHERE e.PATIENT = m.patient_id
              AND e.ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness', 'virtual', 'urgentcare')
              AND e.DESCRIPTION <> 'Death Certification'
              AND CAST(e.START AS DATE) BETWEEN m.index_date + 305 AND m.index_date + 425
        ) AS visit_in_window,
        EXISTS (
            SELECT 1
            FROM observations o
            WHERE o.PATIENT = m.patient_id
              AND o.CODE = '55758-7'
              AND TRY_CAST(o.VALUE AS DOUBLE) < 3
              AND CAST(o.DATE AS DATE) BETWEEN m.index_date + 305 AND m.index_date + 425
        ) AS negative_phq2_in_window
    FROM m370 m
    WHERE m.version = 'BROAD'
      AND m.exclusion_reason IS NULL
)
SELECT
    m.*,
    CASE WHEN date_sub('year', p.BIRTHDATE, m.index_date) < 18 THEN 'Teen 12-17' ELSE 'Adult 18+' END AS age_group,
    f.visit_in_window,
    f.negative_phq2_in_window,
    CASE
        WHEN m.numerator_met
            THEN NULL
        WHEN m.followup_score IS NOT NULL
            THEN 'D. Re-measured in the window, still depressed (PHQ-9 5+)'
        WHEN f.negative_phq2_in_window
            THEN 'A. Screened in the window with a negative PHQ-2, so no PHQ-9 was given'
        WHEN f.visit_in_window
            THEN 'B. Had a visit in the window, no depression screen at all'
        ELSE     'C. No visit in the 12-month window'
    END AS root_cause
FROM m370 m
JOIN window_facts f
    ON f.patient_id = m.patient_id
JOIN patients_deid p
    ON p.Id = m.patient_id
WHERE m.version = 'BROAD'
  AND m.exclusion_reason IS NULL;

-- D. Pareto tables: causes ranked largest first, with the running share of all failures.
CREATE OR REPLACE TABLE pareto AS
WITH counts AS (
    SELECT '134' AS measure, root_cause, COUNT(*) AS patients FROM rc_134 WHERE root_cause IS NOT NULL GROUP BY ALL
    UNION ALL
    SELECT '370', root_cause, COUNT(*) FROM rc_370 WHERE root_cause IS NOT NULL GROUP BY ALL
)
SELECT
    measure,
    root_cause,
    patients,
    ROUND(100.0 * patients / SUM(patients) OVER (PARTITION BY measure), 1)          AS pct_of_failures,
    ROUND(100.0 * SUM(patients) OVER (PARTITION BY measure ORDER BY patients DESC)
                / SUM(patients) OVER (PARTITION BY measure), 1)                        AS cumulative_pct
FROM counts
ORDER BY measure, patients DESC;
