-- 08_levers.sql
-- SIMULATED DATA. "What if we fixed it?" For each root cause, a concrete fix (lever), how many
-- patients it reaches, and the measure rate it would produce at 50% and 100% adoption.
--
-- Formula, measure 134:
--   new rate = (current passes + adoption x patients reached x pass probability) / denominator
--   pass probability for newly screened patients = the pass rate already seen among screened
--   patients (most screens are negative; positive adults already get follow-up).
-- Formula, measure 370:
--   new rate = (current remissions + adoption x patients reached x r) / denominator
--   r = chance a re-measured patient is in remission. Unknown, so three scenarios:
--     floor   = 15.6%, adults who WERE re-measured (biased low: they only got a PHQ-9
--               because their PHQ-2 was positive again)
--     middle  = 50%
--     ceiling = 88.6%, teens, who get a PHQ-9 routinely whatever their PHQ-2
--   A recommendation is "robust" only if it wins even at the floor.

CREATE OR REPLACE TABLE levers AS
WITH

base_134 AS (
    SELECT
        COUNT(*)                                                   AS denominator,
        SUM(numerator_met::INT)                                    AS passes,
        SUM(numerator_met::INT) * 1.0
            / COUNT(*) FILTER (WHERE result_reason NOT IN ('Fail: not screened', 'Fail: screen documented, no score recorded'))
                                                                   AS pass_prob_if_screened
    FROM rc_134
),
base_370 AS (
    SELECT
        COUNT(*)                   AS denominator,
        SUM(numerator_met::INT)    AS passes
    FROM rc_370
),
reach AS (
    SELECT measure, root_cause, patients
    FROM pareto
),

-- The levers, matched to the root cause each one fixes. Effort, time and risk are judgment
-- calls with the reason stated, so a reviewer can disagree with a specific line.
lever_list AS (
    SELECT * FROM (VALUES
        ('134', 'A.', 'L1', 'Hard-stop PHQ-2 at every annual wellness exam (EHR alert)',
            'Low',    'One alert rule; the visit type already exists',              '1-3 months', 'Alert fatigue if not limited to overdue patients'),
        ('134', 'B.', 'L2', 'Screen at any visit when the yearly screen is overdue (Health Maintenance)',
            'Medium', 'Adds about 2 minutes to problem visits; needs staff buy-in',  '3-6 months', 'Pushback from busy problem visits'),
        ('134', 'C.', 'L3', 'Structured score field in prenatal/postnatal templates',
            'Low',    'Template change; screening is already being done',           '1-2 months', 'Low'),
        ('134', 'D.', 'L4', 'Teen positive-screen pathway: behavioral health referral within 2 days',
            'Medium', 'Needs pediatric behavioral health capacity',                 '3-6 months', 'Referral wait times'),
        ('370', 'A.', 'M1', 'Registry rule: prior PHQ-9 of 10+ gets a PHQ-9 (not a PHQ-2) at 10-14 months',
            'Low',    'Swap one questionnaire for flagged patients at visits that already happen', '1-3 months', 'Low; adds about 2 minutes for a few patients'),
        ('370', 'B.', 'M2', 'Same registry alert fires at ANY visit in the 10-14 month window',
            'Low',    'Extends M1 to all visit types',                              '1-3 months', 'Alert fatigue'),
        ('370', 'C.', 'M3', 'Outreach: patient-portal or phone PHQ-9 when no visit is booked at 10-14 months',
            'Medium', 'Staff time for outreach; portal questionnaire build',         '3-6 months', 'Low response rates'),
        ('370', 'D.', 'M4', 'Care management for patients re-measured and still depressed',
            'High',   'Clinical staffing (e.g. collaborative care)',               '6-12 months', 'Effect not estimable from this data')
    ) AS t(measure, cause_prefix, lever_id, lever, effort, effort_reason, time_to_results, main_risk)
),

scenarios AS (
    SELECT * FROM (VALUES
        ('134', 'n/a',     NULL::DOUBLE),
        ('370', 'floor',   0.156),
        ('370', 'middle',  0.50),
        ('370', 'ceiling', 0.886)
    ) AS t(measure, r_scenario, r)
)

SELECT
    l.measure,
    l.lever_id,
    l.lever,
    rc.root_cause,
    rc.patients                                             AS patients_reached,
    s.r_scenario,
    ROUND(100.0 * CASE l.measure WHEN '134' THEN b1.passes * 1.0 / b1.denominator
                                            ELSE b3.passes * 1.0 / b3.denominator END, 1)  AS current_rate,
    -- 'D.' for 370 is treatment: its effect can't be estimated from this data, so no rate.
    CASE WHEN l.lever_id = 'M4' THEN NULL ELSE ROUND(100.0 * CASE l.measure
        WHEN '134' THEN (b1.passes + 0.5 * rc.patients * CASE WHEN l.lever_id = 'L4' THEN 1 ELSE b1.pass_prob_if_screened END) / b1.denominator
        ELSE            (b3.passes + 0.5 * rc.patients * s.r) / b3.denominator
    END, 1) END                                             AS rate_at_50pct_adoption,
    CASE WHEN l.lever_id = 'M4' THEN NULL ELSE ROUND(100.0 * CASE l.measure
        WHEN '134' THEN (b1.passes + 1.0 * rc.patients * CASE WHEN l.lever_id = 'L4' THEN 1 ELSE b1.pass_prob_if_screened END) / b1.denominator
        ELSE            (b3.passes + 1.0 * rc.patients * s.r) / b3.denominator
    END, 1) END                                             AS rate_at_100pct_adoption,
    l.effort,
    l.effort_reason,
    l.time_to_results,
    l.main_risk
FROM lever_list l
JOIN reach rc
    ON  rc.measure = l.measure
    AND starts_with(rc.root_cause, l.cause_prefix)
JOIN scenarios s
    ON s.measure = l.measure
CROSS JOIN base_134 b1
CROSS JOIN base_370 b3
ORDER BY l.measure, l.lever_id, s.r;

-- The recommended package: the three LOW-effort levers together (L1 + L3 for measure 134,
-- M1 for measure 370). They fix different patients, so their gains simply add up.
CREATE OR REPLACE TABLE lever_package AS
SELECT
    measure,
    r_scenario,
    MAX(current_rate)                                                       AS current_rate,
    ROUND(MAX(current_rate) + SUM(rate_at_50pct_adoption - current_rate), 1)  AS rate_at_50pct_adoption,
    ROUND(MAX(current_rate) + SUM(rate_at_100pct_adoption - current_rate), 1) AS rate_at_100pct_adoption,
    string_agg(lever_id, ' + ' ORDER BY lever_id)                           AS levers
FROM levers
WHERE lever_id IN ('L1', 'L3', 'M1')
GROUP BY measure, r_scenario
ORDER BY measure, r_scenario;
