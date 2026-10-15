-- 04_measure_134.sql
-- SIMULATED DATA. Rebuilds CMS Quality ID 134 / eCQM CMS2:
-- "Preventive Care and Screening: Screening for Depression and Follow-Up Plan"
-- Measurement period: calendar year 2025. One row per patient in the eligible population.
--
-- The CMS logic, in plain words:
--   Denominator: patients 12+ with at least one outpatient-type visit in 2025.
--   Exclusion:   patients already diagnosed with depression or bipolar disorder before 2025
--                (they're in treatment, so screening them again isn't the point).
--   Numerator:   screened with a standardized tool (PHQ-2, PHQ-9, PHQ-9 teen) on the visit
--                date or up to 14 days before it, AND, if the screen is positive, a follow-up
--                plan documented on the visit date or up to 2 days after.
-- Simplifications (documented in the README):
--   * The screen judged is the patient's most recent 2025 screen, at the visit where it happened.
--   * Follow-up plan = a further depression assessment (PHQ-9 after a positive PHQ-2), a
--     depression care plan, or an antidepressant start. Synthea has no mental-health referrals.
--   * Screening "procedures" with no recorded score don't count (validation check 11).
--   * Follow-up is counted from the screen date (CMS says from the visit date); see below.

CREATE OR REPLACE TABLE m134 AS
WITH

-- Visits that can put a patient in the measure: outpatient-type, in 2025, and not the
-- "Death Certification" paperwork visit that Synthea files after a death (validation check 07a).
qualifying_visits AS (
    SELECT
        e.Id                    AS encounter_id,
        e.PATIENT               AS patient_id,
        CAST(e.START AS DATE)   AS visit_date,
        e.PAYER                 AS payer_id
    FROM encounters e
    JOIN patients_deid p
        ON p.Id = e.PATIENT
    WHERE e.ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness', 'virtual')
      AND e.DESCRIPTION <> 'Death Certification'
      AND CAST(e.START AS DATE) BETWEEN DATE '2025-01-01' AND DATE '2025-12-31'
      AND date_sub('year', p.BIRTHDATE, DATE '2025-01-01') >= 12
),

-- Every scored depression screen. PHQ-2 positive at 3+, PHQ-9 / teen PHQ-9 positive at 10+.
-- tool_rank lets us prefer the PHQ-2 as "the screen" when both happen at one visit:
-- in this pathway the PHQ-9 is the follow-up assessment for a positive PHQ-2 (check 12).
screens AS (
    SELECT
        ENCOUNTER                       AS screen_encounter_id,
        PATIENT                         AS patient_id,
        CAST(DATE AS DATE)              AS screen_date,
        DATE                            AS screen_ts,
        CASE CODE WHEN '55758-7' THEN 'PHQ-2' ELSE 'PHQ-9' END AS tool,
        CASE CODE WHEN '55758-7' THEN 1 ELSE 2 END             AS tool_rank,
        TRY_CAST(VALUE AS DOUBLE)       AS score,
        CASE
            WHEN CODE = '55758-7' THEN TRY_CAST(VALUE AS DOUBLE) >= 3
            ELSE TRY_CAST(VALUE AS DOUBLE) >= 10
        END                             AS positive
    FROM observations
    WHERE CODE IN ('55758-7', '44261-6', '89204-2')
),

-- Pair each qualifying visit with a screen: one recorded IN that visit (matched by encounter
-- ID), or one dated up to 14 days before it. Matching by ID first matters: the hand check
-- found a long evening visit whose scores were timestamped just after midnight, the next day.
-- Keep one screen per visit: the PHQ-2 if there is one, otherwise the latest PHQ-9.
visit_screens AS (
    SELECT
        v.*,
        s.screen_date,
        s.tool,
        s.score,
        s.positive
    FROM qualifying_visits v
    JOIN screens s
        ON  s.patient_id = v.patient_id
        AND (s.screen_encounter_id = v.encounter_id
             OR s.screen_date BETWEEN v.visit_date - 14 AND v.visit_date)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY v.encounter_id
        ORDER BY s.tool_rank, s.screen_ts DESC
    ) = 1
),

-- The visit we judge for each patient: their most recent screen of 2025, evaluated at the
-- first qualifying visit on or after it (normally the same visit). Ordering by the latest
-- VISIT instead was a bug caught in checking: a later visit's 14-day window could reach back
-- to an earlier screen whose same-day PHQ-9 follow-up then fell before the judged visit.
judged_visit AS (
    SELECT *
    FROM visit_screens
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY patient_id
        ORDER BY screen_date DESC, visit_date ASC, encounter_id
    ) = 1
),

-- Anything that counts as a follow-up plan, with its date.
follow_ups AS (
    SELECT PATIENT AS patient_id, CAST(DATE AS DATE) AS fu_date, 'Further assessment (PHQ-9)' AS fu_type
    FROM observations
    WHERE CODE IN ('44261-6', '89204-2')
    UNION ALL
    SELECT PATIENT, START, 'Depression care plan'
    FROM careplans
    WHERE CODE IN (718347000, 736254008, 737434004)
       OR REASONDESCRIPTION ILIKE '%depress%'
    UNION ALL
    SELECT PATIENT, CAST(START AS DATE), 'Antidepressant started'
    FROM medications
    WHERE regexp_matches(lower(DESCRIPTION), 'sertraline|fluoxetine|duloxetine|citalopram|escitalopram|paroxetine|bupropion|venlafaxine|mirtazapine')
),

-- Exclusion: depression or bipolar diagnosis that started before 2025.
excluded AS (
    SELECT DISTINCT
        PATIENT AS patient_id
    FROM conditions
    WHERE regexp_matches(lower(DESCRIPTION), 'depress|bipolar')
      AND START < DATE '2025-01-01'
),

-- Patients who had a "Depression screening" procedure in a 2025 qualifying window but
-- no recorded score: used only to label the failure reason.
unscored_screen AS (
    SELECT DISTINCT
        v.patient_id
    FROM qualifying_visits v
    JOIN procedures pr
        ON  pr.PATIENT = v.patient_id
        AND pr.CODE IN (171207006, 715252007)
        AND CAST(pr.START AS DATE) BETWEEN v.visit_date - 14 AND v.visit_date
),

-- One row per eligible patient, with the payer from their latest 2025 visit.
eligible AS (
    SELECT
        patient_id,
        MAX(visit_date)                       AS last_visit_date,
        arg_max(payer_id, visit_date)         AS payer_id,
        COUNT(*)                              AS visits_2025
    FROM qualifying_visits
    GROUP BY patient_id
)

SELECT
    el.patient_id,
    el.visits_2025,
    el.payer_id,
    date_sub('year', p.BIRTHDATE, DATE '2025-01-01')  AS age,
    p.GENDER                                          AS gender,
    x.patient_id IS NOT NULL                          AS excluded,
    j.encounter_id                                    AS judged_encounter_id,
    j.visit_date                                      AS judged_visit_date,
    j.tool,
    j.score,
    j.positive,
    fu.fu_type                                        AS follow_up_type,
    fu.fu_date                                        AS follow_up_date,
    -- Numerator: screened, and either negative or positive with a follow-up in 0-2 days.
    (x.patient_id IS NULL
        AND j.encounter_id IS NOT NULL
        AND (NOT j.positive OR fu.fu_type IS NOT NULL))  AS numerator_met,
    CASE
        WHEN x.patient_id IS NOT NULL               THEN 'Excluded: depression/bipolar diagnosed before 2025'
        WHEN j.encounter_id IS NULL AND u.patient_id IS NOT NULL
                                                    THEN 'Fail: screen documented, no score recorded'
        WHEN j.encounter_id IS NULL                 THEN 'Fail: not screened'
        WHEN j.positive AND fu.fu_type IS NULL      THEN 'Fail: positive screen, no follow-up plan in 2 days'
        WHEN j.positive                             THEN 'Pass: positive screen with follow-up plan'
        ELSE                                             'Pass: negative screen'
    END                                               AS result_reason
FROM eligible el
JOIN patients_deid p
    ON p.Id = el.patient_id
LEFT JOIN excluded x
    ON x.patient_id = el.patient_id
LEFT JOIN judged_visit j
    ON j.patient_id = el.patient_id
LEFT JOIN unscored_screen u
    ON u.patient_id = el.patient_id
-- First follow-up dated from the screen date to 2 days after the visit (only matters if
-- positive). CMS words it as "the visit date to 2 days after"; counting from the screen date
-- is our interpretation, so a same-day PHQ-9 after a screen 1-14 days before the visit
-- (e.g. at an urgent care visit) still counts. Documented in the README.
LEFT JOIN LATERAL (
    SELECT
        f.fu_type,
        f.fu_date
    FROM follow_ups f
    WHERE f.patient_id = j.patient_id
      AND f.fu_date BETWEEN j.screen_date AND j.visit_date + 2
      AND NOT (f.fu_type = 'Further assessment (PHQ-9)' AND j.tool = 'PHQ-9')
    ORDER BY f.fu_date
    LIMIT 1
) fu ON TRUE;
