-- 05_measure_370.sql
-- SIMULATED DATA. Rebuilds CMS Quality ID 370 / eCQM CMS159:
-- "Depression Remission at Twelve Months", measurement period 2025.
--
-- The CMS logic, in plain words:
--   Index event: the first PHQ-9 above 9 (moderate depression or worse) during the
--                identification period, 2023-11-01 to 2024-10-31, for a patient 12+ with a
--                major depression or dysthymia diagnosis active at that time.
--   Numerator:   remission = the last PHQ-9 taken 12 months after the index, give or take
--                60 days, scores below 5.
--   Exclusions:  bipolar, personality disorder, schizophrenia/psychosis, pervasive
--                developmental disorder, hospice or palliative care, or death before the
--                remission window closes.
-- Two versions, both one row per patient:
--   'CMS'   = as specified (requires the diagnosis).
--   'BROAD' = every patient with an index PHQ-9 above 9, diagnosed or not. Only 61 simulated
--             patients ever get a depression diagnosis, so the CMS version is too small to
--             analyze; BROAD shows the same process on everyone who screened positive.
-- Synthea has no bipolar/personality/psychosis/developmental diagnoses (checked), so those
-- exclusions remove no one; they are kept in the logic so it would work on real data.

CREATE OR REPLACE TABLE m370 AS
WITH

phq9 AS (
    SELECT
        PATIENT                     AS patient_id,
        CAST(DATE AS DATE)          AS phq_date,
        DATE                        AS phq_ts,
        TRY_CAST(VALUE AS DOUBLE)   AS score
    FROM observations
    WHERE CODE IN ('44261-6', '89204-2')
),

-- First PHQ-9 above 9 in the identification period = the index event.
index_event AS (
    SELECT
        q.patient_id,
        q.phq_date                  AS index_date,
        q.score                     AS index_score
    FROM phq9 q
    JOIN patients_deid p
        ON p.Id = q.patient_id
    WHERE q.score > 9
      AND q.phq_date BETWEEN DATE '2023-11-01' AND DATE '2024-10-31'
      AND date_sub('year', p.BIRTHDATE, q.phq_date) >= 12
    QUALIFY ROW_NUMBER() OVER (PARTITION BY q.patient_id ORDER BY q.phq_ts) = 1
),

-- Diagnosis active on the index date (started on/before it, not ended before it).
diagnosed AS (
    SELECT DISTINCT
        i.patient_id
    FROM index_event i
    JOIN conditions c
        ON  c.PATIENT = i.patient_id
        AND regexp_matches(lower(c.DESCRIPTION), 'major depress|dysthymi')
        AND c.START <= i.index_date
        AND (c.STOP IS NULL OR c.STOP >= i.index_date)
),

-- Exclusions, checked from the index date to the end of the remission window (+425 days).
excluded AS (
    SELECT DISTINCT i.patient_id, 'Excluded: hospice or palliative care' AS reason
    FROM index_event i
    JOIN encounters e
        ON  e.PATIENT = i.patient_id
        AND e.ENCOUNTERCLASS = 'hospice'
        AND CAST(e.START AS DATE) BETWEEN i.index_date AND i.index_date + 425
    UNION ALL
    SELECT DISTINCT i.patient_id, 'Excluded: hospice or palliative care'
    FROM index_event i
    JOIN procedures pr
        ON  pr.PATIENT = i.patient_id
        AND pr.DESCRIPTION ILIKE '%palliative%'
        AND CAST(pr.START AS DATE) BETWEEN i.index_date AND i.index_date + 425
    UNION ALL
    SELECT i.patient_id, 'Excluded: died before the remission window closed'
    FROM index_event i
    JOIN patients_deid p
        ON p.Id = i.patient_id
    WHERE p.DEATHDATE <= i.index_date + 425
    UNION ALL
    SELECT DISTINCT i.patient_id, 'Excluded: bipolar / personality / psychotic / developmental disorder'
    FROM index_event i
    JOIN conditions c
        ON  c.PATIENT = i.patient_id
        AND regexp_matches(lower(c.DESCRIPTION), 'bipolar|personality disorder|schizo|psychot|pervasive developmental|autis')
        AND c.START <= i.index_date + 425
),
first_exclusion AS (
    SELECT
        patient_id,
        MIN(reason) AS exclusion_reason
    FROM excluded
    GROUP BY patient_id
),

-- Last PHQ-9 in the remission window: 12 months after the index, plus or minus 60 days.
remission_check AS (
    SELECT
        i.patient_id,
        q.phq_date                  AS followup_date,
        q.score                     AS followup_score
    FROM index_event i
    JOIN phq9 q
        ON  q.patient_id = i.patient_id
        AND q.phq_date BETWEEN i.index_date + 365 - 60 AND i.index_date + 365 + 60
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.patient_id ORDER BY q.phq_ts DESC) = 1
),

-- Any PHQ-9 at all after the index (to tell "never re-measured" from "re-measured, but
-- outside the window").
any_remeasure AS (
    SELECT DISTINCT
        i.patient_id
    FROM index_event i
    JOIN phq9 q
        ON  q.patient_id = i.patient_id
        AND q.phq_date > i.index_date
)

SELECT
    v.version,
    i.patient_id,
    i.index_date,
    i.index_score,
    d.patient_id IS NOT NULL                        AS has_diagnosis,
    x.exclusion_reason,
    r.followup_date,
    r.followup_score,
    COALESCE(x.exclusion_reason IS NULL AND r.followup_score < 5, FALSE)  AS numerator_met,  -- no follow-up score = FALSE, not unknown
    CASE
        WHEN x.exclusion_reason IS NOT NULL         THEN x.exclusion_reason
        WHEN r.followup_score < 5                   THEN 'Pass: in remission (PHQ-9 below 5)'
        WHEN r.followup_score IS NOT NULL           THEN 'Fail: re-measured, not in remission'
        WHEN a.patient_id IS NOT NULL               THEN 'Fail: re-measured, but outside the 12-month window'
        ELSE                                             'Fail: never re-measured after index'
    END                                             AS result_reason
FROM index_event i
CROSS JOIN (VALUES ('CMS'), ('BROAD')) AS v(version)
LEFT JOIN diagnosed d
    ON d.patient_id = i.patient_id
LEFT JOIN first_exclusion x
    ON x.patient_id = i.patient_id
LEFT JOIN remission_check r
    ON r.patient_id = i.patient_id
LEFT JOIN any_remeasure a
    ON a.patient_id = i.patient_id
WHERE v.version = 'BROAD'
   OR d.patient_id IS NOT NULL;
