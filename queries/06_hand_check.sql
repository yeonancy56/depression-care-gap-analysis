-- 06_hand_check.sql
-- The simulated version of chart abstraction: pick 10 patients covering every result type,
-- then list their raw records so a person can re-check the measure's answer by eye.
-- Picks are fixed (first patient ID in each group), so the same 10 come back every run.

CREATE OR REPLACE TABLE hand_check_sample AS
WITH picks_134 AS (
    SELECT
        '134'            AS measure,
        result_reason,
        tool,
        patient_id,
        judged_visit_date AS anchor_date
    FROM m134
    QUALIFY ROW_NUMBER() OVER (PARTITION BY result_reason, tool ORDER BY patient_id) = 1
),
picks_370 AS (
    SELECT
        '370'            AS measure,
        result_reason,
        NULL             AS tool,
        patient_id,
        index_date       AS anchor_date
    FROM m370
    WHERE version = 'BROAD'
      AND result_reason IN ('Fail: never re-measured after index', 'Pass: in remission (PHQ-9 below 5)',
                            'Fail: re-measured, not in remission')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY result_reason ORDER BY patient_id) = 1
)
SELECT
    ROW_NUMBER() OVER (ORDER BY measure, result_reason, tool) AS case_no,
    *
FROM (
    SELECT * FROM picks_134
    UNION ALL
    SELECT * FROM picks_370
);

-- Every relevant raw record for those patients, in date order.
CREATE OR REPLACE TABLE hand_check_timeline AS
SELECT h.case_no, CAST(e.START AS DATE) AS event_date, 'visit' AS source,
       e.ENCOUNTERCLASS || ': ' || e.DESCRIPTION AS detail
FROM hand_check_sample h
JOIN encounters e
    ON e.PATIENT = h.patient_id
WHERE e.ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness', 'virtual', 'hospice')
  AND year(e.START) BETWEEN 2023 AND 2026
UNION ALL
SELECT h.case_no, CAST(o.DATE AS DATE), 'PHQ score',
       CASE o.CODE WHEN '55758-7' THEN 'PHQ-2' WHEN '44261-6' THEN 'PHQ-9' ELSE 'PHQ-9 teen' END || ' = ' || o.VALUE
FROM hand_check_sample h
JOIN observations o
    ON o.PATIENT = h.patient_id
WHERE o.CODE IN ('55758-7', '44261-6', '89204-2')
UNION ALL
SELECT h.case_no, CAST(pr.START AS DATE), 'screen procedure', pr.DESCRIPTION
FROM hand_check_sample h
JOIN procedures pr
    ON pr.PATIENT = h.patient_id
WHERE pr.CODE IN (171207006, 715252007)
UNION ALL
SELECT h.case_no, c.START, 'care plan', c.DESCRIPTION
FROM hand_check_sample h
JOIN careplans c
    ON c.PATIENT = h.patient_id
WHERE c.REASONDESCRIPTION ILIKE '%depress%'
UNION ALL
SELECT h.case_no, c.START, 'diagnosis', c.DESCRIPTION
FROM hand_check_sample h
JOIN conditions c
    ON c.PATIENT = h.patient_id
WHERE regexp_matches(lower(c.DESCRIPTION), 'depress|bipolar')
UNION ALL
SELECT h.case_no, CAST(m.START AS DATE), 'medication', m.DESCRIPTION
FROM hand_check_sample h
JOIN medications m
    ON m.PATIENT = h.patient_id
WHERE regexp_matches(lower(m.DESCRIPTION), 'sertraline|fluoxetine|duloxetine');
