# Builds a 2-page charts appendix (static SVG) from the exported CSVs.
import csv, sys, html
D = sys.argv[1]
def rows(name):
    with open(D + "/data/" + name, newline="") as f:
        return list(csv.DictReader(f))
BLUE, RED, GRAY, INK, MUTED = "#1F4E79", "#b3261e", "#a9b5c2", "#222", "#666"
esc = html.escape

def hbars(items, width=700, label_w=250, max_v=100, ref=None, ref_label="", value_w=110, bar_h=13, gap=6, fs=9.5):
    """items: (label, value, color, text)"""
    h = len(items) * (bar_h + gap) + (22 if ref is not None else 6)
    plot_w = width - label_w - value_w
    sx = lambda v: plot_w * v / max_v
    out = ['<svg viewBox="0 0 %d %d" width="100%%">' % (width, h)]
    if ref is not None:
        x = label_w + sx(ref)
        out.append('<line x1="%.1f" x2="%.1f" y1="0" y2="%d" stroke="#888" stroke-dasharray="3 3"/>' % (x, x, h - 14))
        out.append('<text x="%.1f" y="%d" font-size="9" fill="%s" text-anchor="middle">%s</text>' % (x, h - 2, MUTED, esc(ref_label)))
    for i, (lab, v, col, txt) in enumerate(items):
        y = i * (bar_h + gap)
        out.append('<text x="%d" y="%.1f" font-size="%s" fill="%s" text-anchor="end">%s</text>' % (label_w - 8, y + bar_h - 3, fs, INK, esc(lab)))
        w = max(2, sx(v))
        out.append('<rect x="%d" y="%d" width="%.1f" height="%d" rx="3" fill="%s"/>' % (label_w, y, w, bar_h, col))
        out.append('<text x="%.1f" y="%.1f" font-size="%s" fill="%s" font-weight="%s">%s</text>' % (label_w + w + 6, y + bar_h - 3, fs, INK, "700" if col != GRAY else "400", esc(txt)))
    out.append("</svg>")
    return "".join(out)

# 1. ACO benchmark (real)
aco = sorted(rows("aco_benchmark.csv"), key=lambda r: float(r["pct_acos_worse_than_tmip"]))
PLAIN = {"370": "Depression: recovered after a year", "134": "Depression: checked and followed up", "113": "Colon cancer screening",
         "112": "Breast cancer screening", "318": "Fall-risk screening", "438": "Heart patients on statins", "110": "Flu shots",
         "479": "Hospital readmissions", "001": "Diabetes poorly controlled", "236": "Blood pressure under control"}
c1 = hbars([(PLAIN[r["quality_id"]], float(r["pct_acos_worse_than_tmip"]), BLUE if r["quality_id"] in ("134", "370") else GRAY,
             "%d%%" % round(float(r["pct_acos_worse_than_tmip"]))) for r in aco], label_w=270, value_w=50, ref=50, ref_label="National middle (50%)")
a370 = next(r for r in aco if r["quality_id"] == "370"); a236 = next(r for r in aco if r["quality_id"] == "236")

# 2. Cascade (simulated)
cas = rows("cascade.csv")
def cascade(group):
    rs = sorted([r for r in cas if r["age_group"] == group], key=lambda r: int(r["step_order"]))
    drops = [float(rs[i-1]["pct_of_start"]) - float(rs[i]["pct_of_start"]) if i else -1 for i in range(len(rs))]
    worst = drops.index(max(drops))
    items = []
    for i, r in enumerate(rs):
        col = RED if (group.startswith("Adult") and i == worst) else (BLUE if i == len(rs) - 1 else GRAY)
        STEP = {"1": "Had a high score", "2": "Came back a year later", "3": "Checked again", "4": "Got the full survey", "5": "Counted as recovered"}
        items.append((STEP[r["step_order"]], float(r["pct_of_start"]), col, "%s%%  (%s)" % (r["pct_of_start"], format(int(r["patients"]), ","))))
    return hbars(items, label_w=150, value_w=95, width=340, fs=9)
c2a, c2t = cascade("Adult 18+"), cascade("Teen 12-17")
cv = {(r["age_group"], r["step_order"]): r["pct_of_start"] for r in cas}

# 3. Pareto
par = rows("pareto.csv")
def pareto(m):
    rs = sorted([r for r in par if r["measure"] == m], key=lambda r: -int(r["patients"]))
    CAUSE = {"134A": "Had a yearly checkup, but wasn't checked", "134B": "Skipped the yearly checkup", "134C": "Checked, but score not recorded (pregnancy visits)",
             "134D": "Teen with a high score, no follow-up", "370A": "Got only the short survey, so recovery couldn't be shown", "370B": "Came in, but wasn't checked",
             "370C": "Didn't come in that year", "370D": "Got the full survey, still depressed"}
    return hbars([(CAUSE[m + r["root_cause"][0]], float(r["pct_of_failures"]), BLUE if i == 0 else GRAY,
                   "%s · %s%%" % (format(int(r["patients"]), ","), r["pct_of_failures"])) for i, r in enumerate(rs)], label_w=330, value_w=95, fs=9)
c3a, c3b = pareto("134"), pareto("370")
p134 = sum(int(r["patients"]) for r in par if r["measure"] == "134")
pa = next(r for r in par if r["measure"] == "134" and r["root_cause"].startswith("A."))

# 4. Groups
grp = rows("by_group.csv")
order = ["12-17", "18-34", "35-49", "50-64", "65+"]
ages = sorted([r for r in grp if r["measure"] == "134" and r["dimension"] == "Age band"], key=lambda r: order.index(r["grp"]))
c4a = hbars([(r["grp"], float(r["rate"]), BLUE if r["grp"] == "18-34" else GRAY, r["rate"] + "%") for r in ages], label_w=70, value_w=50, width=330)
pays = sorted([r for r in grp if r["measure"] == "134" and r["dimension"] == "Payer"], key=lambda r: -float(r["rate"]))
c4b = hbars([(r["grp"], float(r["rate"]), GRAY, r["rate"] + "%") for r in pays], label_w=150, value_w=50, width=330)
age = {r["grp"]: r["rate"] for r in ages}

# 5. Decision matrix
lev = [r for r in rows("levers.csv") if r["r_scenario"] in ("n/a", "floor") and r["lever_id"] != "M4"]
FIX = {"L1": "Require a depression check at every yearly checkup", "L2": "Check at any visit if it's been a year", "L3": "Add a box to record the score at pregnancy visits",
       "L4": "Fast mental-health referral for teens with a high score", "M1": "Give the full survey a year later to past high scorers", "M2": "Same, at any visit that year",
       "M3": "Send the full survey by phone or patient portal"}
WHAT = {"L1": "Checked", "L2": "Checked", "L3": "Checked", "L4": "Checked", "M1": "Recovered", "M2": "Recovered", "M3": "Recovered"}
lev.sort(key=lambda r: (r["lever_id"] not in ("M1", "L1", "L3"), r["lever_id"]))
trs = "".join('<tr class="%s"><td>%s</td><td>%s</td><td class="nw">%s</td><td class="n">%s</td><td>%s</td><td class="n">%s%%</td><td class="n">%s%%</td></tr>' % (
    "hl" if r["lever_id"] in ("L1", "L3", "M1") else "", esc(FIX[r["lever_id"]]), r["effort"], r["time_to_results"],
    format(int(r["patients_reached"]), ","), WHAT[r["lever_id"]], r["current_rate"], r["rate_at_50pct_adoption"]) for r in lev)
pk = {(r["measure"], r["r_scenario"]): r for r in rows("lever_package.csv")}

# 6. Run chart
mon = rows("monthly.csv")
vals = [float(r["pct_screened"]) for r in mon]
sv = sorted(vals); n = len(sv); med = (sv[n//2] if n % 2 else (sv[n//2-1] + sv[n//2]) / 2); hi = max(vals)
W, H, ml, mr, mt, mb = 700, 190, 40, 90, 10, 24
sx = lambda i: ml + (W - ml - mr) * i / (n - 1)
sy = lambda v: mt + (H - mt - mb) * (85 - v) / 20
c6 = ['<svg viewBox="0 0 %d %d" width="100%%">' % (W, H)]
for t in (65, 70, 75, 80, 85):
    c6.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#e6e9ee"/><text x="%d" y="%.1f" font-size="9" fill="%s" text-anchor="end">%d%%</text>' % (ml, W - mr, sy(t), sy(t), ml - 5, sy(t) + 3, MUTED, t))
for v, lab in ((med, "Median %.1f%%" % med), (hi, "High %.1f%%" % hi)):
    c6.append('<line x1="%d" x2="%d" y1="%.1f" y2="%.1f" stroke="#888" stroke-dasharray="3 3"/><text x="%d" y="%.1f" font-size="9" fill="%s">%s</text>' % (ml, W - mr, sy(v), sy(v), W - mr + 5, sy(v) + 3, MUTED, lab))
c6.append('<polyline fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" points="%s"/>' % (BLUE, " ".join("%.1f,%.1f" % (sx(i), sy(v)) for i, v in enumerate(vals))))
for i, r in enumerate(mon):
    if r["month"].endswith("-01-01") or r["month"].endswith("-07-01"):
        lab = ("Jan " if r["month"][5:7] == "01" else "Jul ") + r["month"][:4]
        c6.append('<text x="%.1f" y="%d" font-size="9" fill="%s" text-anchor="middle">%s</text>' % (sx(i), H - 6, MUTED, lab))
c6.append("</svg>"); c6 = "".join(c6)

doc = """<!doctype html><html><head><meta charset="utf-8"><title>Charts Appendix</title><style>
@page { size: 8.5in 11in; margin: 0.5in 0.55in; }
body { margin:0; font-family:"Helvetica Neue",Helvetica,Arial,sans-serif; font-size:9.2pt; color:#222; line-height:1.35; }
.top { border-bottom:2.5px solid #1F4E79; padding-bottom:5px; margin-bottom:8px; }
h1 { font-size:14pt; margin:0; color:#1F4E79; } .sub { font-size:8.4pt; color:#555; margin-top:2px; }
.fig { border:1px solid #c9d3de; border-radius:3px; padding:6px 10px 6px; margin-bottom:7px; break-inside:avoid; }
.fig h2 { font-size:10pt; margin:0 0 2px; color:#1F4E79; }
.cap { margin:0 0 6px; font-size:8.8pt; }
.tag { font-size:7pt; font-weight:600; padding:0 5px; border-radius:6px; margin-left:6px; vertical-align:1px; }
.real { background:#e3f1e6; color:#1e6b33; } .sim { background:#eceff3; color:#555; }
.two { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
.lab { font-size:8.4pt; font-weight:700; color:#444; margin:4px 0 2px; }
table { width:100%%; border-collapse:collapse; font-size:8.2pt; font-variant-numeric:tabular-nums; }
th, td { text-align:left; padding:2.5px 4px; border-bottom:1px solid #e3e8ee; vertical-align:top; }
th { color:#555; font-weight:600; } td.n, th.n, td.nw { text-align:right; white-space:nowrap; } td.nw { text-align:left; }
.hl td { font-weight:700; color:#1F4E79; }
.page2 { break-before:page; }
.foot { font-size:7.4pt; color:#666; border-top:1px solid #ccc; padding-top:3px; margin-top:4px; }
svg text { font-family:inherit; }
</style></head><body>
<div class="top"><h1>Charts: Why Depression Scores Are Low, and the Fix</h1>
<div class="sub">Nancy Yeo · Clinical Quality Analyst candidate, Torrance Memorial · The same charts as the online dashboard</div></div>

<div class="fig"><h2>1. Torrance Memorial vs. other networks<span class="tag real">REAL DATA, 2024</span></h2>
<p class="cap">How many of the country's doctor networks Torrance Memorial beats on each Medicare quality score. It beats %(a236)s%% on blood pressure but only %(a370)s%% on depression. Longer bar = better.</p>%(c1)s</div>

<div class="fig"><h2>2. The main finding<span class="tag sim">SIMULATED DATA</span></h2>
<p class="cap"><b>Patients may be getting better, but they aren't given the survey that proves it.</b> We followed patients with a high depression score for a year. Most adults came back and were checked, but only %(ad4)s%% got the full 9-question survey, the only one that can show recovery (red bar). Teens get the full survey at every checkup.</p>
<div class="two"><div><div class="lab">Adults (short survey first)</div>%(c2a)s</div><div><div class="lab">Teens (full survey at checkups)</div>%(c2t)s</div></div></div>

<div class="fig"><h2>3. Why patients are missed<span class="tag sim">SIMULATED DATA</span></h2>
<p class="cap">Half of the patients missed for depression checks (%(pa)s of %(p134)s) came in for a yearly checkup and still weren't checked. Bars show the share of missed patients for each reason.</p>
<div class="lab">Why patients weren't checked for depression</div>%(c3a)s<div class="lab">Why patients weren't counted as recovered</div>%(c3b)s</div>

<div class="page2">
<div class="fig"><h2>4. Who gets missed<span class="tag sim">SIMULATED DATA</span></h2>
<p class="cap">Share of patients checked for depression in 2025. Young adults (18–34) are checked least, %(a1834)s%% vs. %(a65)s%% for 65+, because many skip yearly checkups.</p>
<div class="two"><div><div class="lab">By age band</div>%(c4a)s</div><div><div class="lab">By insurance</div>%(c4b)s</div></div></div>

<div class="fig"><h2>5. Every possible fix, compared<span class="tag sim">SIMULATED DATA</span></h2>
<p class="cap">The three recommended changes are highlighted: cheap, fast, and no new staff. Together they raise the share checked from %(k1c)s%% to <b>%(k1)s%%</b>. "After" assumes half of visits use the change; recovery numbers use the most cautious estimate.</p>
<table><tr><th>Change</th><th>Effort</th><th>Time</th><th class="n">Patients helped</th><th>Measure</th><th class="n">Now</th><th class="n">After</th></tr>%(trs)s</table></div>

<div class="fig"><h2>6. How we'll know it's working<span class="tag sim">SIMULATED DATA</span></h2>
<p class="cap">Share of yearly checkups that include a depression check, by month. It has stayed around %(med).0f%% for three years and never gone above %(hi).1f%%. After the changes, a month above that line is the first sign they're working.</p>%(c6)s</div>

<div class="foot"><b>Real:</b> CMS Medicare Shared Savings Program, performance year 2024. <b>Simulated:</b> fake patient records built to look real (real records are private); a lead to confirm, not Torrance Memorial's actual numbers. Full survey = PHQ-9; short survey = PHQ-2. Full SQL and validation: github.com/yeonancy56/depression-care-gap-analysis</div>
</div></body></html>""" % dict(
    c1=c1, c2a=c2a, c2t=c2t, c3a=c3a, c3b=c3b, c4a=c4a, c4b=c4b, c6=c6, trs=trs,
    a236=round(float(a236["pct_acos_worse_than_tmip"])), a370=round(float(a370["pct_acos_worse_than_tmip"])), a370v=a370["tmip_value"], a370m=a370["national_median"],
    ad3=cv[("Adult 18+", "3")], ad4=cv[("Adult 18+", "4")], pa=format(int(pa["patients"]), ","), p134=format(p134, ","),
    a1834=age["18-34"], a65=age["65+"], med=med, hi=hi,
    k1c=pk[("134", "n/a")]["current_rate"], k1=pk[("134", "n/a")]["rate_at_50pct_adoption"],
    k2c=pk[("370", "floor")]["current_rate"], k2=pk[("370", "floor")]["rate_at_50pct_adoption"],
    k3=pk[("370", "middle")]["rate_at_50pct_adoption"], k4=pk[("370", "ceiling")]["rate_at_50pct_adoption"])
open(sys.argv[2], "w").write(doc)
