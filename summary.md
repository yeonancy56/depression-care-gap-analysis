# Why Torrance Memorial's Depression Scores Are Low, and an Easy Fix

**Nancy Yeo · Clinical Quality Analyst candidate · October 2026**
PDF version: [`Summary_Depression_Care_Gap_Nancy_Yeo.pdf`](Summary_Depression_Care_Gap_Nancy_Yeo.pdf) · Dashboard: https://claude.ai/artifact/YaLXFSWQqR4bV7pUkPseua

> **Patients may be getting better, but they aren't given the survey that proves it.**

## 1. The problem (real Medicare data, 2024)
Torrance Memorial's doctors' network is scored by Medicare on quality. It does great on blood pressure, but poorly on depression.

| | |
| --- | --- |
| **Top 5%** | in the country for blood pressure control |
| **7 in 100** | depressed patients counted as recovered after a year (typical network nationally: 14 in 100) |

## 2. Why it happens
Doctors check for depression with a survey. There's a **short 2-question survey** and a **full 9-question survey**. Only the full survey can show that a patient recovered.

Adults usually get only the short survey. If they're doing better, they never get the full one, so **they can't be counted as recovered.** Teens get the full survey at every checkup.

| | Got the full survey a year later | Counted as recovered |
| --- | ---: | ---: |
| **Adults** (short survey first) | 12 in 100 | **2 in 100** |
| **Teens** (full survey at every checkup) | 76 in 100 | **67 in 100** |

*From simulated patient records (real records are private), so this is a strong lead to confirm with Torrance Memorial's own data.*

## 3. The fix: three small changes to the medical-records system
- **A. Give the full survey a year later** to anyone who had a high score before.
- **B. Require a depression check at every yearly checkup.** Half of all missed checks happened at checkups.
- **C. Add a box to record the score** at pregnancy visits.

In the simulation, these raise the share of patients checked from **71% to 80%**, even if only half of visits use them.

## 4. Why this is the right move
- **Cheap:** no new staff, just system settings.
- **Fast:** results in 1 to 3 months.
- **Easy to track:** if more than about 80% of checkups include the depression check in a month, it's working.
- **First step:** one query on Torrance Memorial's real records to confirm adults mostly get the short survey.

---
*Real data: Medicare Shared Savings Program results, 2024. Patient data is simulated (no real patients). The 9-question survey is the PHQ-9; the 2-question survey is the PHQ-2; "recovered" means remission (PHQ-9 score below 5). Full details: [README](README.md).*
