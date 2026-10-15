# Validation Log

**Simulated data:** Synthea, 10 runs × 1,000 Torrance residents, seeds 42–51, reference date 2026-10-01.
**Run:** 2026-10-12. Query: [`queries/03_validation_checks.sql`](queries/03_validation_checks.sql) → table `validation_results`.

Synthea is far cleaner than real EHR data: no duplicates, orphans or out-of-range scores. The checks still matter. They prove the pipeline would catch these problems in Epic data, and three of them changed how the measures are built.

## Results

| # | Check | Rows checked | Rows failed | Result | Action taken |
| --- | --- | ---: | ---: | --- | --- |
| 01 | Duplicate patient IDs | 11,291 | 0 | Pass | — |
| 02 | Duplicate encounter IDs | 373,688 | 0 | Pass | — |
| 03 | Duplicate PHQ results (same patient, time, test, score) | 49,261 | 0 | Pass | — |
| 04 | Encounter end time missing or before start | 373,688 | 0 | Pass | — |
| 05 | Encounters with no matching patient | 373,688 | 0 | Pass | — |
| 06 | PHQ results with no matching encounter | 49,261 | 0 | Pass | — |
| 07a | "Death Certification" visits dated after death | 373,688 | 1,159 | **Explained** | Synthea files death paperwork as a *wellness* visit 1–10+ days after death. 54 fall in 2025. **Excluded from the qualifying-visit list**, or deceased patients would enter the measure 134 denominator. |
| 07b | Any other visit before birth or after death | 373,688 | 0 | Pass | — |
| 08 | PHQ-2 score missing or outside 0–6 | 42,893 | 0 | Pass | — |
| 09 | PHQ-9 / PHQ-9 teen score missing or outside 0–27 | 6,368 | 0 | Pass | — |
| 10 | Adult PHQ-9 used under 18, or teen form used 18+ | 6,368 | 0 | Pass | — |
| 11 | Depression-screening procedure with no PHQ score in the same visit | 98,526 | 2,674 | **Finding** | Screen was documented, but no score was recorded (about 500 a year, all outpatient). **A screen counts for measure 134 only when a score exists**, which matches how eCQMs read structured results. |
| 12 | PHQ-9 without a positive PHQ-2 (3+) in the same visit | 2,636 | 1 | **Finding** | Confirms the simulated pathway: PHQ-2 first, then PHQ-9 only when PHQ-2 is positive. So the PHQ-9 is the "further assessment" step of the follow-up plan. |
| 13 | 2025 outpatient visits with no payer | 40,239 | 0 | Pass | — |
| 14 | PHQ codes with more than one description | 3 | 0 | Pass | PHQ results are found by LOINC code (55758-7, 44261-6, 89204-2), not by description text. |

## Other data decisions

| Issue | What was found | Action taken |
| --- | --- | --- |
| Time zones | Synthea stores times in UTC. Converting a time to a date in UTC can move an evening visit to the next day. | `run_sql.py` fixes the time zone to America/Los_Angeles, so dates match Torrance and results are identical on any computer. |
| Same seed, different data | Seed 42 gave 1,147 patients in one run and 1,148 in a later run on the same day. Synthea's clock is part of the simulation. | `generate_data.sh` fixes the reference and end date (`-r 20261001 -e 20261001`). |
| Breast cancer screening | Only 129 patients have a mammogram. | Not used. Too sparse to measure. |
| **Readmissions (first plan, dropped)** | 87% of raw 30-day "readmissions" were scheduled chemotherapy cycles and staged heart surgery (diagnostic stay → bypass or valve surgery 1–2 days later). After removing planned care, 24 of 2,259 stays (1.1%) were readmitted, against 12–16% in real hospitals. *(Counts from the v1 readmissions queries, 2026-10-12.)* | Readmissions dropped as the topic: Synthea doesn't simulate unplanned returns. |

## Hand check: 10 patients (Step 3)

Query: [`queries/06_hand_check.sql`](queries/06_hand_check.sql). One patient was picked per result type (the first patient ID in each group, so the same 10 come back on every run). Every visit, PHQ score, screening procedure, depression diagnosis, care plan and antidepressant was listed in date order, and the measure's answer was re-derived by hand. This is the simulated version of chart abstraction.

| Case | Measure | Measure said | By hand | Match |
| --- | --- | --- | --- | --- |
| 1 | 134 | Excluded: depression diagnosed before 2025 | Major depressive disorder diagnosed 1986, on fluoxetine | ✅ |
| 2 | 134 | Fail: not screened | One 2025 visit (a symptom visit), no PHQ score anywhere in 2025 | ✅ |
| 3 | 134 | Fail: positive screen, no follow-up | Teen PHQ-9 = 18 at a well-child visit; no care plan, antidepressant or referral afterwards | ✅ |
| 4 | 134 | Fail: screen documented, no score | Prenatal visit has a "Depression screening" procedure but no PHQ score | ✅ |
| 5 | 134 | Pass: negative screen (PHQ-2) | PHQ-2 = 1 at a wellness visit | ✅ |
| 6 | 134 | Pass: negative screen (teen PHQ-9) | Teen PHQ-9 = 1 on Dec 31, 2024; qualifying visit Jan 14, 2025 (within 14 days) | ✅ |
| 7 | 134 | Pass: positive screen with follow-up | PHQ-2 = 5, then PHQ-9 = 10 the same day (further assessment) | ✅ |
| 8 | 370 | Fail: never re-measured | PHQ-9 = 23 in Nov 2023; later visits only had PHQ-2 (2, then 0), no PHQ-9 | ✅ |
| 9 | 370 | Fail: re-measured, not in remission | Teen PHQ-9 17 → 6 at 12 months (improved, but remission needs < 5) | ✅ |
| 10 | 370 | Pass: in remission | Teen PHQ-9 26 → 0 at 12 months | ✅ |

**Two bugs were found by checking failures before this final run, and both are fixed:**

1. **A later visit "stole" an earlier screen.** The first version judged each patient's latest visit. A later visit's 14-day window could reach back to an earlier screen whose same-day PHQ-9 follow-up then fell *before* the judged visit, so 174 patients were wrongly failed. **Fix:** judge the patient's latest *screen*, at the visit where it happened.
2. **Midnight split.** A long evening wellness visit was dated May 11, but its PHQ scores were timestamped just after midnight on May 12. Date matching missed that they belong together. **Fix:** a screen is first matched to a visit by encounter ID, which is how the EHR actually links them, and only then by date.

**One interpretation, documented:** CMS words the follow-up window as "the visit date to 2 days after." Some screens happen at an urgent-care visit 1–14 days *before* the qualifying visit, with a PHQ-9 the same night. Read literally, those patients fail even though they were followed up. The measure counts follow-up **from the screen date** to 2 days after the visit, a choice to confirm against the CMS2 eCQM logic with the quality team.

## Denominator reconciliation (Step 3)

**Measure 134, 2025** ([`04_measure_134.sql`](queries/04_measure_134.sql))

| Step | Patients |
| --- | ---: |
| Aged 12+ with a qualifying outpatient visit in 2025 (Death Certification visits removed) | 7,495 |
| − Depression or bipolar diagnosed before 2025 | 36 |
| = **Denominator** | **7,459** |
| Pass: negative screen | 5,006 |
| Pass: positive screen with follow-up | 274 |
| = **Numerator** | **5,280 (70.8%)** |
| Fail: not screened | 1,805 |
| Fail: screen documented, no score | 335 |
| Fail: positive screen, no follow-up (all 39 are teens 12–17) | 39 |
| Check: 5,280 + 1,805 + 335 + 39 | = 7,459 ✅ |

**Measure 370** ([`05_measure_370.sql`](queries/05_measure_370.sql)), index period Nov 1, 2023 – Oct 31, 2024

| Step | Patients |
| --- | ---: |
| CMS version (needs an active depression diagnosis at the index PHQ-9) | **0**. Only 61 simulated patients ever get the diagnosis, and none had one active at an index PHQ-9 in the period. |
| Broad version: first PHQ-9 > 9 in the period, aged 12+ | 328 |
| − Died before the remission window closed | 7 |
| − Hospice or palliative care | 3 |
| = **Denominator** | **318** |
| Pass: in remission (PHQ-9 < 5 at 12 months ± 60 days) | 44 (13.8%) |
| Fail: never re-measured | 195 |
| Fail: re-measured, but outside the window | 47 |
| Fail: re-measured, not in remission | 32 |
| Check: 44 + 195 + 47 + 32 | = 318 ✅ |
