# Power BI Dashboard

`ipl_moneyball.pbix` is not committed here — add it once built, or link to a
Power BI Service publish URL.

## Pages

**1 — Executive Summary**
KPI cards: total auction spend, total impact generated, spend efficiency,
% of spend on below-average players. One large text visual carrying the headline
insight. Season slicer syncs across all pages.

**2 — Value Quadrant** *(the signature visual)*
Scatter: X = auction price (₹ Cr), Y = Total Impact. Reference lines at the
league-median price and at impact = 0 divide it into four quadrants. Bubble size
= balls faced + balls bowled. Colour by `value_segment`. Tooltip page shows the
full scouting card on hover.

Bottom-right = expensive and ineffective. Top-left = the bargains. This one
chart is the project.

**3 — Player Scouting Report**
Player selector. Phase-wise True Strike Rate bars against a league reference
line. Career trend. Pressure Index gauge. Matchup strengths/weaknesses table.
A second selector enables head-to-head comparison mode.

**4 — Matchup Matrix**
Heatmap: batters (rows) × bowling families (columns), coloured by matchup delta.
Team filter so a user can build a plan for a specific fixture.

**5 — Squad Builder**
Squad composition treemap, spend vs impact by franchise, overseas slot usage,
and the shortlist output from `build_shortlist()`.

**6 — Methodology & Limitations**
Data source, date range, sample thresholds, known limitations. Almost nobody
includes this page. It is the difference between looking like a student project
and looking like professional work.

## Design rules used

- One accent colour plus a grey ramp. Not eight competing colours.
- Consistent formatting: impact to 1 decimal, prices as "₹4.2 Cr".
- A one-line plain-English insight at the top of every page.
- Slicers synced across pages.
- Bookmark-driven navigation buttons instead of default page tabs.
- Every visual with a sample-size dependency uses `[Impact (Guarded)]`.

## Performance notes

- Import mode, not DirectQuery — the data is static between loads and import
  gives far better interaction speed.
- Power BI reads `mv_player_value` (the materialised view), not the raw
  aggregation, which cut initial page load substantially.
- Unused columns removed in Power Query to shrink the model.
