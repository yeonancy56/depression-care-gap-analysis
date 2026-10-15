# Significance tests for every group difference the project claims.
# Reads the result tables from tmmc.duckdb; prints each test and saves data/stats_tests.csv.
# Chi-square for large groups; Fisher's exact test when any expected count is small (< 5).
import csv
import os
import duckdb
from scipy.stats import chi2_contingency, fisher_exact

con = duckdb.connect("tmmc.duckdb", read_only=True)
results = []


def test(name, rows):
    """rows = list of (group, passed, total). Returns the p-value and records the result."""
    table = [[p, t - p] for _, p, t in rows]
    chi2, p_chi, dof, expected = chi2_contingency(table)
    method = "chi-square"
    p_value = p_chi
    if len(rows) == 2 and min(min(r) for r in expected) < 5:
        _, p_value = fisher_exact(table)
        method = "Fisher exact"
    verdict = "significant" if p_value < 0.05 else "directional only (p >= 0.05)"
    rates = "; ".join("%s %d/%d = %.1f%%" % (g, p, t, 100.0 * p / t) for g, p, t in rows)
    p_text = "< 0.001" if p_value < 0.001 else "%.3f" % p_value
    print("%s\n  %s\n  %s p %s -> %s\n" % (name, rates, method, p_text, verdict))
    results.append({"test": name, "groups": rates, "method": method,
                    "p_value": p_text, "verdict": verdict})


test("134: screened-and-followed-up rate, had a 2025 wellness exam vs not",
     con.execute("SELECT CASE WHEN had_wellness_2025 THEN 'wellness exam' ELSE 'no wellness exam' END, "
                 "SUM(numerator_met::INT), COUNT(*) FROM rc_134 GROUP BY 1 ORDER BY 1").fetchall())

test("370: remission rate, teens (routine PHQ-9) vs adults (PHQ-2 first)",
     con.execute("SELECT age_group, SUM(numerator_met::INT), COUNT(*) FROM rc_370 GROUP BY 1 ORDER BY 1").fetchall())

for dim in ["Payer", "Age band", "Social isolation"]:
    test("134 by " + dim.lower(),
         con.execute("SELECT grp, passed, patients FROM by_group WHERE measure = '134' AND dimension = ? "
                     "ORDER BY rate", [dim]).fetchall())

os.makedirs("data", exist_ok=True)
with open("data/stats_tests.csv", "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["test", "groups", "method", "p_value", "verdict"])
    writer.writeheader()
    writer.writerows(results)
