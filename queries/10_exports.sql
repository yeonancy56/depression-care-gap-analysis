-- 10_exports.sql
-- Writes the CSVs Tableau reads into data/. Only counts, rates and labels leave the
-- database: no patient IDs, names, dates of birth or addresses (checked in Step 5).

-- 1. REAL: Torrance Memorial's ACO vs. all ACOs.
COPY (
    SELECT
        quality_id,
        measure_name,
        CASE WHEN higher_is_better THEN 'Higher is better' ELSE 'Lower is better' END AS direction,
        tmip_value,
        national_median,
        acos_reporting,
        pct_acos_worse_than_tmip,
        'Real: CMS Shared Savings Program PY2024' AS source
    FROM aco_benchmark
) TO 'data/aco_benchmark.csv' (HEADER);

-- 2. SIMULATED: the rebuilt measures, with denominators.
COPY (
    SELECT
        '134' AS quality_id,
        'Depression Screening & Follow-Up Plan' AS measure_name,
        COUNT(*) FILTER (WHERE NOT excluded) AS denominator,
        COUNT(*) FILTER (WHERE numerator_met) AS numerator,
        ROUND(100.0 * COUNT(*) FILTER (WHERE numerator_met) / COUNT(*) FILTER (WHERE NOT excluded), 1) AS rate,
        'Simulated (Synthea), measurement year 2025' AS source
    FROM m134
    UNION ALL
    SELECT
        '370',
        'Depression Remission at 12 Months (broad version)',
        COUNT(*) FILTER (WHERE exclusion_reason IS NULL),
        COUNT(*) FILTER (WHERE numerator_met),
        ROUND(100.0 * COUNT(*) FILTER (WHERE numerator_met) / COUNT(*) FILTER (WHERE exclusion_reason IS NULL), 1),
        'Simulated (Synthea), index Nov 2023 - Oct 2024'
    FROM m370
    WHERE version = 'BROAD'
) TO 'data/measure_rates.csv' (HEADER);

-- 3. SIMULATED: the headline. Patients who scored 10+ on a PHQ-9, followed to 12 months,
--    teens vs. adults. Each step is a subset of the one before, so it draws as a funnel.
COPY (
    WITH steps AS (
        SELECT
            age_group,
            COUNT(*)                                                    AS s1_scored_10_plus,
            COUNT(*) FILTER (WHERE visit_in_window)                     AS s2_had_visit_at_12_months,
            COUNT(*) FILTER (WHERE visit_in_window AND (negative_phq2_in_window OR followup_score IS NOT NULL))
                                                                        AS s3_screened_at_12_months,
            COUNT(*) FILTER (WHERE followup_score IS NOT NULL)          AS s4_given_phq9_at_12_months,
            COUNT(*) FILTER (WHERE numerator_met)                       AS s5_in_remission
        FROM rc_370
        GROUP BY age_group
    )
    SELECT
        age_group,
        step_order,
        step,
        patients,
        ROUND(100.0 * patients / MAX(patients) OVER (PARTITION BY age_group), 1) AS pct_of_start
    FROM steps
    UNPIVOT (patients FOR step IN (
        s1_scored_10_plus          AS '1. Scored 10+ on PHQ-9',
        s2_had_visit_at_12_months  AS '2. Had a visit at 12 months',
        s3_screened_at_12_months   AS '3. Screened at 12 months',
        s4_given_phq9_at_12_months AS '4. Given a PHQ-9 at 12 months',
        s5_in_remission            AS '5. In remission (PHQ-9 < 5)'
    ))
    CROSS JOIN LATERAL (SELECT CAST(left(step, 1) AS INTEGER) AS step_order)
    ORDER BY age_group, step_order
) TO 'data/cascade.csv' (HEADER);

-- 4. SIMULATED: root causes ranked (Pareto).
COPY (SELECT * FROM pareto) TO 'data/pareto.csv' (HEADER);

-- 5. SIMULATED: rates by payer, age band, social isolation, teen vs adult.
COPY (SELECT * FROM by_group) TO 'data/by_group.csv' (HEADER);

-- 6. SIMULATED: what-if levers (decision matrix) and the recommended package.
COPY (SELECT * FROM levers) TO 'data/levers.csv' (HEADER);
COPY (SELECT * FROM lever_package) TO 'data/lever_package.csv' (HEADER);

-- 7. SIMULATED: where screens happen, by visit type.
COPY (SELECT * FROM rc_screen_by_visit_type) TO 'data/screen_by_visit_type.csv' (HEADER);

-- 8. SIMULATED: monthly run chart, the leading indicator for fix L1: share of wellness
--    exams (patients 12+) with a scored depression screen, by month, 2023-2025.
COPY (
    SELECT
        date_trunc('month', e.START)::DATE                       AS month,
        COUNT(*)                                                 AS wellness_exams,
        COUNT(*) FILTER (WHERE s.ENCOUNTER IS NOT NULL)          AS exams_with_screen,
        ROUND(100.0 * COUNT(*) FILTER (WHERE s.ENCOUNTER IS NOT NULL) / COUNT(*), 1) AS pct_screened
    FROM encounters e
    JOIN patients_deid p
        ON p.Id = e.PATIENT
    LEFT JOIN (
        SELECT DISTINCT ENCOUNTER
        FROM observations
        WHERE CODE IN ('55758-7', '44261-6', '89204-2')
    ) s
        ON s.ENCOUNTER = e.Id
    WHERE e.ENCOUNTERCLASS = 'wellness'
      AND e.DESCRIPTION <> 'Death Certification'
      AND year(e.START) BETWEEN 2023 AND 2025
      AND date_sub('year', p.BIRTHDATE, CAST(e.START AS DATE)) >= 12
    GROUP BY 1
    ORDER BY 1
) TO 'data/monthly.csv' (HEADER);

-- 9. Validation results.
COPY (SELECT * FROM validation_results ORDER BY check_name) TO 'data/validation_log.csv' (HEADER);
