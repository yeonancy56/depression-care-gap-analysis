# Tableau Build Guide

**Story title:** Patients May Be Getting Better, but They Aren't Given the Survey That Proves It

You build this in **Tableau Public** (the free desktop app). There are 6 dashboards, one per story point, and they're joined into one Story at the end. Every number in a caption below comes from a CSV in `data/`. If you regenerate the data, re-check the captions.

---

## 0. Set up once

### Connect the data
Each CSV is its own data source. Don't join them.
1. Open Tableau Public, then **Connect → To a File → Text file**. Pick `data/aco_benchmark.csv`.
2. For each additional CSV: **Data → New Data Source → Text file**.
3. You need `aco_benchmark`, `measure_rates`, `cascade`, `pareto`, `by_group`, `levers`, `lever_package` and `monthly`.
4. In each data source, check the types. `quality_id` should be a **String** (so "001" keeps its zeros), `month` a **Date**, and all rates and counts **Numbers (decimal / whole)**.

### Rates are already percentages
Values like `70.8` mean 70.8%. **Don't** use Tableau's "Percentage" format, which would show 7,080%. Instead, use **Format → Numbers → Custom: `0.0"%"`**.

### Design rules (apply to every view)
| Rule | How |
| --- | --- |
| One message per view | The caption states it; the chart proves it |
| One accent color for what matters | Accent **#1F6FB2** (blue). Everything else **#B5B5B5** (gray). Text **#333333** |
| Sort bars largest first | Except funnels and Pareto (fixed order) and the age band chart (age order) |
| Label values directly on the marks | Then hide the axis it duplicates (right-click axis → uncheck **Show Header**) |
| No gridlines, no borders | **Format → Lines → Grid Lines: None**; **Format → Borders: None** |
| Font | Tableau Book, titles 15 pt bold, captions 11 pt, footnote 8 pt gray |

### Footnote, on every dashboard
Add a **Text** object at the bottom of each dashboard:
> Real: Medicare quality data, 2024. Simulated: fake patient records built to look real (Synthea, seeds 42–51), because real records are private; not Torrance Memorial's actual numbers. Full survey = PHQ-9; short survey = PHQ-2; counted as recovered = remission.

### Dashboard size
**Dashboard → Size: Fixed, 1200 × 800.** Put the caption in a text box at the top under the title, 1–2 sentences.

---

## View 1: The gap (REAL data)

**CSV:** `aco_benchmark.csv`
**Chart:** horizontal bar chart of percentile rank

**Build:**
1. **Rows:** `measure_name`. **Columns:** `pct_acos_worse_than_tmip` (SUM).
2. Sort **ascending** by `pct_acos_worse_than_tmip`, so the depression measures sit at the top (this is an intentional exception to "largest first": the weak spots lead).
3. Create a calculated field `Highlight`:
   ```
   IF CONTAINS([Measure Name], "Depression") THEN "Depression" ELSE "Other" END
   ```
   Drag it to **Color**: Depression = #1F6FB2, Other = #B5B5B5.
4. **Label:** `pct_acos_worse_than_tmip`, custom format `0"%"`.
5. **Analytics pane → Reference Line** on the axis, constant **50**, label "National middle", dashed gray.
6. **Tooltip:** "TMIP: <tmip_value> · National median: <national_median> · <acos_reporting> ACOs reporting".
7. Add a text annotation on the blood pressure bar: **"Bright spot: proof the team can close a gap."**

**Title:** Torrance Memorial vs. other networks
**Caption:**
> Torrance Memorial's doctors' network beats 95% of networks nationally on blood pressure, but only 19% on depression. Only 7 in 100 depressed patients are counted as recovered after a year; a typical network counts 14 (real Medicare data, 2024).

---

## View 2: The measures, rebuilt from the EHR (SIMULATED)

**CSV:** `measure_rates.csv`
**Chart:** two KPI tiles plus a small "how it was built" text block

**Build:**
1. Make a sheet for each measure: **Text** mark, `rate` big (36 pt, #1F6FB2), with `numerator` "of" `denominator` "patients" underneath (12 pt gray). Filter `quality_id` = 134, then = 370.
2. Beside the tiles, a text box with each measure's logic in plain words:
   - **134:** Patients 12+ with a 2025 outpatient visit → screened with PHQ-2/PHQ-9 within 14 days before the visit → if positive, follow-up within 2 days.
   - **370:** Patients who scored 10+ on PHQ-9 (Nov 2023 – Oct 2024) → PHQ-9 below 5 at 12 months ± 60 days.
3. Small gray line: "Validated: 14 data checks, 10-patient hand check (10/10 after 2 bugs fixed), denominators reconcile exactly. See validation_log.md."

**Title:** The two depression scores, rebuilt from patient records
**Caption:**
> Rebuilt from simulated patient records: 70.8% of 7,459 patients were checked for depression, and 13.8% of 318 patients with a high score were counted as recovered.

---

## View 3: The headline: where patients drop out (SIMULATED)

**CSV:** `cascade.csv`
**Chart:** side-by-side funnel bars, adults vs. teens

**Build:**
1. **Columns:** `age_group`, then `step` (sort `step` by `step_order` ascending: right-click → **Sort → Field: step_order, Ascending**).
2. **Rows:** `pct_of_start` (SUM). Custom format `0.0"%"`.
3. Calculated field `Gap`:
   ```
   IF [Age Group] = "Adult 18+" AND [Step Order] = 4 THEN "Gap" ELSE "Other" END
   ```
   Drag to **Color**: Gap = #1F6FB2, Other = #B5B5B5.
4. **Label:** `pct_of_start` plus `patients` (e.g. "12.3%  (32)").
5. Put **Adult 18+** first. Hide the step axis titles; the step names are the labels.
6. Annotate the gap between Adult step 3 and step 4: **"Screened, but given the short PHQ-2, not the PHQ-9 that can show remission."**

**Title:** The main finding
**Caption:**
> Patients may be getting better, but they aren't given the survey that proves it. 70.8% of adults came back and were checked a year later, but only 12.3% got the full 9-question survey, so only 1.9% could be counted as recovered. Teens get the full survey at every checkup: 67.2% counted as recovered.

---

## View 4: Root causes, ranked (SIMULATED, Lean Pareto)

**CSV:** `pareto.csv`
**Chart:** Pareto chart, with bars for share of failures and a line for the cumulative share. Make one sheet per measure (filter `measure`).

**Build (repeat for 134 and 370):**
1. **Columns:** `root_cause`, sorted by `patients` **descending**.
2. **Rows:** `pct_of_failures` and `cumulative_pct`.
3. On the second axis: **Dual Axis**, then **Synchronize Axis** (both are 0–100%).
4. Marks: `pct_of_failures` = **Bar** (first bar #1F6FB2, the rest #B5B5B5, using a calculated field `INDEX() = 1` or by coloring `root_cause` manually), `cumulative_pct` = **Line** with circle markers, dark gray.
5. **Label** the bars with `patients`.
6. Reference line at **80%** on the cumulative axis, label "80%".
7. Wrap the long `root_cause` labels: right-click the header → **Format → Alignment → Wrap**.

**Title:** Why patients are missed
**Caption (134 sheet):**
> Half of the patients missed for depression checks (1,118 of 2,179) came in for a yearly checkup and still weren't checked.

**Caption (370 sheet):**
> 59% of patients not counted as recovered (161 of 274) got only the short survey a year later, so their recovery couldn't be shown.

---

## View 5: Who falls through (SIMULATED)

**CSV:** `by_group.csv`
**Chart:** bar chart of rate by age band (main), plus a smaller payer bar chart

**Build:**
1. Main sheet, filter `measure` = 134 and `dimension` = Age band. **Columns:** `grp` (order manually: 12-17, 18-34, 35-49, 50-64, 65+). **Rows:** `rate`.
2. Color 18-34 #1F6FB2, others #B5B5B5. Label `rate` (`0.0"%"`).
3. **Tooltip:** "<passed> of <patients> patients".
4. Second, smaller sheet: `dimension` = Payer, sorted descending, all gray. It's context, not the message.
5. Don't build a social isolation chart. In this data, isolated patients actually screen *more* (75.7% vs 68.4%), probably because the isolation finding is recorded *at* wellness exams. That's a confounder, not a gap. Mention it in the README limitations instead.

**Title:** Who gets missed
**Caption:**
> Young adults skip yearly checkups and miss the depression check with them: only 53.6% of 18–34-year-olds are checked, against 86.0% of those 65 and older.

---

## View 6: The fix and how to monitor it (SIMULATED)

**CSVs:** `levers.csv`, `lever_package.csv`, `monthly.csv`
**Chart:** decision-matrix table, two "before → after" tiles, and a run chart

**Build:**
1. **Decision matrix** (`levers.csv`): filter `r_scenario` to **n/a** and **floor**, and exclude `lever_id` M4. **Rows:** `lever_id`, `lever`, `effort`, `time_to_results`. **Text:** `patients_reached`, `current_rate`, `rate_at_50pct_adoption`, `rate_at_100pct_adoption`. Color the L1, L3 and M1 rows' text #1F6FB2 (the recommended package), everything else #333333.
2. **Package tiles** (`lever_package.csv`): "Screening 70.8% → 80.4%" (134, 50% adoption) and "Remission 13.8% → 17.8%+" (370, floor, 50% adoption). Tooltip on the remission tile: "Middle scenario 26.5%, optimistic 36.3%".
3. **Run chart** (`monthly.csv`): **Columns:** `month` (continuous month). **Rows:** `pct_screened`. Gray line with dots. Add a **Reference Line** at the **median** (Analytics pane → Reference Line → Per Table → Median), labeled "Median". Add a text annotation: **"Go-live here: a month above 80.5% (the 3-year high) is the first sign L1 is working."**

**Title:** The fix, and how we'll know it's working
**Caption:**
> Three small changes to the medical-records system: require a depression check at every yearly checkup, add a box to record the score at pregnancy visits, and give the full survey a year later to past high scorers. Together they raise the share checked from 70.8% to 80.4%, even if only half of visits use them. Checkup screening has stayed around 77% for three years and never gone above 80.5%, so a month above that line is the first sign the changes are working.

---

## Assemble the Story

1. **Story → New Story.** Size: same as the dashboards (1200 × 800 plus story bar).
2. Drag in dashboards 1–6 in order. Edit each story point's caption box to a short version (e.g. "1. The gap (real)", "2. The measures", "3. The headline", "4. Root causes", "5. Who falls through", "6. The fix").
3. **Story title:** Patients May Be Getting Better, but They Aren't Given the Survey That Proves It
4. **Format → Story:** navigator style **Caption boxes**, story title 18 pt.

## Publish

1. **File → Save to Tableau Public As…** Name: "Depression Care Gap: Screening Tool vs. Remission".
2. Tableau Public data is always public. That's fine here, because every CSV is either simulated or already-public CMS data. **Never** publish a workbook connected to real patient data.
3. On the Tableau Public page: **Edit Details**, then paste the README's 3-sentence summary and the GitHub link. Turn **off** "Show sheets as tabs".
4. Take a screenshot of each story point (1200 × 800) into `images/` (`view1_gap.png` … `view6_fix.png`) for the README.
5. Add the Tableau Public link to the top of the README and to the one-page summary.

## Check before you share
- [ ] Every view has its footnote, and REAL / SIMULATED appears in each title area
- [ ] Each caption number matches the CSV (re-check after any data change)
- [ ] Only one accent color per view
- [ ] Percent formats show "70.8%", not "7,080%" or "0.708"
- [ ] Story opens on View 1, and the headline is View 3
