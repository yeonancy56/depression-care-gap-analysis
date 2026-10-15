-- 02_aco_benchmark.sql
-- REAL DATA. How Torrance Memorial Integrated Physicians (ACO ID A4964) compares with
-- every other ACO in Medicare's Shared Savings Program, performance year 2024.
--
-- Step 1 (long_format): the CMS file has one column per measure. UNPIVOT turns those
--   columns into rows (one row per ACO per measure), so every measure can be handled
--   by the same logic instead of ten copies of it.
-- Step 2 (scored): TRY_CAST turns text into a number; CMS's "-" (not reported) becomes NULL.
-- Step 3: for each measure, pull TMIP's value, the national median, and the share of
--   reporting ACOs that did WORSE than TMIP. "Worse" depends on direction: for most
--   measures higher is better; for A1c poor control and readmissions, lower is better.

CREATE OR REPLACE VIEW aco_benchmark AS
WITH long_format AS (
    UNPIVOT (
        SELECT
            ACO_ID,
            QualityID_236_WI,
            QualityID_134_WI,
            QualityID_370,
            QualityID_113,
            QualityID_112,
            QualityID_110,
            QualityID_318,
            QualityID_438,
            QualityID_001_WI,
            Measure_479
        FROM aco_results
    )
    ON COLUMNS(* EXCLUDE (ACO_ID))
    INTO NAME measure_col VALUE raw_value
),
scored AS (
    SELECT
        ACO_ID,
        measure_col,
        TRY_CAST(raw_value AS DOUBLE) AS value
    FROM long_format
),
measure_info AS (
    SELECT * FROM (VALUES
        ('QualityID_236_WI', '236', 'Controlling High Blood Pressure',            TRUE),
        ('QualityID_134_WI', '134', 'Depression Screening & Follow-Up Plan',      TRUE),
        ('QualityID_370',    '370', 'Depression Remission at 12 Months',          TRUE),
        ('QualityID_113',    '113', 'Colorectal Cancer Screening',                TRUE),
        ('QualityID_112',    '112', 'Breast Cancer Screening',                    TRUE),
        ('QualityID_110',    '110', 'Influenza Immunization',                     TRUE),
        ('QualityID_318',    '318', 'Falls: Screening for Future Fall Risk',      TRUE),
        ('QualityID_438',    '438', 'Statin Therapy for Cardiovascular Disease',  TRUE),
        ('QualityID_001_WI', '001', 'Diabetes: A1c Poor Control (>9%)',           FALSE),
        ('Measure_479',      '479', 'Hospital-Wide Readmission (per CMS, rate)',  FALSE)
    ) AS t(measure_col, quality_id, measure_name, higher_is_better)
),
tmip AS (
    SELECT
        measure_col,
        value AS tmip_value
    FROM scored
    WHERE ACO_ID = 'A4964'
)
SELECT
    m.quality_id,
    m.measure_name,
    m.higher_is_better,
    t.tmip_value,
    ROUND(MEDIAN(s.value), 2)                                         AS national_median,
    COUNT(s.value)                                                    AS acos_reporting,
    ROUND(100.0 * AVG(
        CASE
            WHEN m.higher_is_better     AND s.value < t.tmip_value THEN 1
            WHEN NOT m.higher_is_better AND s.value > t.tmip_value THEN 1
            ELSE 0
        END
    ) FILTER (WHERE s.value IS NOT NULL), 0)                          AS pct_acos_worse_than_tmip
FROM measure_info m
JOIN tmip t
    ON t.measure_col = m.measure_col
JOIN scored s
    ON s.measure_col = m.measure_col
GROUP BY ALL
ORDER BY pct_acos_worse_than_tmip;
