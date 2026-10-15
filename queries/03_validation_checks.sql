-- 03_validation_checks.sql
-- Data-integrity checks, run before any measure is built.
-- Every check returns the same four columns, stacked with UNION ALL into one results table:
--   check_name, rows_checked, rows_failed, pass_rule
-- A check "passes" when rows_failed = 0, unless pass_rule says the failures are expected and explained.
-- PHQ results are found by LOINC code, not by description text: codes are the standard
-- identifiers in every EHR (55758-7 = PHQ-2, 44261-6 = PHQ-9, 89204-2 = PHQ-9 for teens).

CREATE OR REPLACE TABLE validation_results AS

-- 1. Uniqueness: each patient and each encounter should appear exactly once.
SELECT
    '01 Duplicate patient IDs'                     AS check_name,
    COUNT(*)                                       AS rows_checked,
    COUNT(*) - COUNT(DISTINCT Id)                  AS rows_failed,
    'must be 0'                                    AS pass_rule
FROM patients
UNION ALL
SELECT
    '02 Duplicate encounter IDs',
    COUNT(*),
    COUNT(*) - COUNT(DISTINCT Id),
    'must be 0'
FROM encounters

-- 2. Exact duplicate screening results: same patient, same moment, same test, same score.
--    A duplicate would count one screen twice.
UNION ALL
SELECT
    '03 Duplicate PHQ results (same patient, time, test, score)',
    COUNT(*),
    COUNT(*) - (SELECT COUNT(*) FROM (
        SELECT DISTINCT PATIENT, DATE, CODE, VALUE
        FROM observations
        WHERE CODE IN ('55758-7', '44261-6', '89204-2'))),
    'must be 0'
FROM observations
WHERE CODE IN ('55758-7', '44261-6', '89204-2')

-- 3. Valid encounter times: every visit needs an end time that isn't before its start.
UNION ALL
SELECT
    '04 Encounter STOP missing or before START',
    COUNT(*),
    COUNT(*) FILTER (WHERE STOP IS NULL OR STOP < START),
    'must be 0'
FROM encounters

-- 4. Orphans: rows pointing to a patient or encounter that doesn't exist.
UNION ALL
SELECT
    '05 Encounters with no matching patient',
    COUNT(*),
    COUNT(*) FILTER (WHERE p.Id IS NULL),
    'must be 0'
FROM encounters e
LEFT JOIN patients p
    ON p.Id = e.PATIENT
UNION ALL
SELECT
    '06 PHQ results with no matching encounter',
    COUNT(*),
    COUNT(*) FILTER (WHERE e.Id IS NULL),
    'must be 0'
FROM observations o
LEFT JOIN encounters e
    ON e.Id = o.ENCOUNTER
WHERE o.CODE IN ('55758-7', '44261-6', '89204-2')

-- 5. Plausible timeline: no visit before birth or after death.
--    Split in two: Synthea files a "Death Certification" paperwork visit after a death
--    (classed as 'wellness'), which is expected. Anything else after death is an error.
UNION ALL
SELECT
    '07a Death Certification visits dated after death',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE CAST(e.START AS DATE) > p.DEATHDATE
          AND e.DESCRIPTION = 'Death Certification'),
    'expected: paperwork visit; must be kept out of the measure denominator'
FROM encounters e
JOIN patients p
    ON p.Id = e.PATIENT
UNION ALL
SELECT
    '07b Other visits before birth or after death',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE CAST(e.START AS DATE) < p.BIRTHDATE
           OR (CAST(e.START AS DATE) > p.DEATHDATE AND e.DESCRIPTION <> 'Death Certification')),
    'must be 0'
FROM encounters e
JOIN patients p
    ON p.Id = e.PATIENT

-- 6. Score ranges. PHQ-2 is scored 0-6; PHQ-9 and the teen version 0-27.
--    TRY_CAST returns NULL for text that isn't a number, so non-numeric scores fail too.
UNION ALL
SELECT
    '08 PHQ-2 score missing or outside 0-6',
    COUNT(*),
    COUNT(*) FILTER (WHERE NOT (TRY_CAST(VALUE AS DOUBLE) BETWEEN 0 AND 6) OR TRY_CAST(VALUE AS DOUBLE) IS NULL),
    'must be 0'
FROM observations
WHERE CODE = '55758-7'
UNION ALL
SELECT
    '09 PHQ-9 / PHQ-9 teen score missing or outside 0-27',
    COUNT(*),
    COUNT(*) FILTER (WHERE NOT (TRY_CAST(VALUE AS DOUBLE) BETWEEN 0 AND 27) OR TRY_CAST(VALUE AS DOUBLE) IS NULL),
    'must be 0'
FROM observations
WHERE CODE IN ('44261-6', '89204-2')

-- 7. Right tool for the age: the adult PHQ-9 is for 18+, the teen version for 12-17.
UNION ALL
SELECT
    '10 PHQ-9 adult form used under 18, or teen form used 18+',
    COUNT(*),
    COUNT(*) FILTER (
        WHERE (o.CODE = '44261-6' AND date_sub('year', p.BIRTHDATE, CAST(o.DATE AS DATE)) < 18)
           OR (o.CODE = '89204-2' AND date_sub('year', p.BIRTHDATE, CAST(o.DATE AS DATE)) >= 18)),
    'expected 0; any failures are listed in the log'
FROM observations o
JOIN patients p
    ON p.Id = o.PATIENT
WHERE o.CODE IN ('44261-6', '89204-2')

-- 8. Screening documented but no score recorded. In a real EHR this is a classic reason
--    a measure fails: the screen was done, but the result never reached a structured field.
UNION ALL
SELECT
    '11 Depression-screening procedures with no PHQ score in the same visit',
    COUNT(*),
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1
        FROM observations o
        WHERE o.ENCOUNTER = pr.ENCOUNTER
          AND o.CODE IN ('55758-7', '44261-6', '89204-2'))),
    'finding, not an error: measures must count a screen only when a score exists'
FROM procedures pr
WHERE pr.CODE IN (171207006, 715252007)

-- 9. The two-step screening pathway: a PHQ-9 is supposed to follow a positive PHQ-2 (3+).
--    Checks how many PHQ-9s have no positive PHQ-2 in the same visit.
UNION ALL
SELECT
    '12 PHQ-9 without a positive PHQ-2 in the same visit',
    COUNT(*),
    COUNT(*) FILTER (WHERE NOT EXISTS (
        SELECT 1
        FROM observations o2
        WHERE o2.ENCOUNTER = o.ENCOUNTER
          AND o2.CODE = '55758-7'
          AND TRY_CAST(o2.VALUE AS DOUBLE) >= 3)),
    'finding: shows how the simulated pathway works'
FROM observations o
WHERE o.CODE = '44261-6'

-- 10. Measure 2025 needs a payer on visits for the payer breakdown.
UNION ALL
SELECT
    '13 2025 outpatient visits with no payer',
    COUNT(*),
    COUNT(*) FILTER (WHERE PAYER IS NULL),
    'must be 0'
FROM encounters
WHERE ENCOUNTERCLASS IN ('ambulatory', 'outpatient', 'wellness', 'virtual')
  AND year(START) = 2025

-- 11. One code, one meaning: each PHQ LOINC code should have one description.
UNION ALL
SELECT
    '14 PHQ codes with more than one description',
    COUNT(DISTINCT CODE),
    COUNT(DISTINCT CODE || '|' || DESCRIPTION) - COUNT(DISTINCT CODE),
    'must be 0'
FROM observations
WHERE CODE IN ('55758-7', '44261-6', '89204-2');
