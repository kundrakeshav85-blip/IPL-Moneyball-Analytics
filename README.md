# IPL Moneyball — Player Recruitment & Auction Value Analytics

> **A franchise has ₹95 crore to spend at auction. Which players are underpriced
> relative to the value they actually generate — and which of the current squad
> are being overpaid?**

An end-to-end analytics project on 260,000 IPL deliveries (2008–2024) that builds
context-adjusted player valuation metrics in PostgreSQL and surfaces them as a
Power BI decision tool.

![Dashboard](docs/screenshots/dashboard_overview.png)

---

## The problem

IPL auction prices are driven by reputation, recent viral performances and
bidding-war dynamics. Raw statistics don't correct for this, because they ignore
context:

- **Totals reward availability.** Most runs in a season often just means most matches played.
- **Rates ignore situation.** A strike rate of 140 is *elite* in the powerplay and
  *below average* at the death. Comparing players on raw strike rate
  systematically overvalues death-overs batters.

So this project rebuilds the measurement from the ball up.

## The approach

| Metric | What it does |
|---|---|
| **True Strike Rate** | Player strike rate minus the league average for the *same phase and same season* |
| **Runs Added Above Average** | Converts that rate into a volume: how many extra runs the player generated versus a league-average replacement off the same balls |
| **Economy Saved** | Bowling equivalent, also denominated in runs — which is what lets all-rounders be valued on one scale |
| **Pressure Index** | Strike rate uplift when the required run rate is ≥ 10, separating finishers from flat-track accumulators |
| **Value per Crore** | Total impact ÷ auction price. The headline output |
| **Matchup Delta** | Batter strike rate vs each bowling family, normalised against their own baseline |

Full definitions and rationale: [`docs/methodology.md`](docs/methodology.md)

## Key findings

> *Replace these with your own numbers once you run the analysis.*

- Roughly **30% of total auction spend** goes to players producing below-league-average impact in their primary role.
- **Death-overs specialists are systematically underpriced** relative to middle-order batters with larger reputations.
- A cluster of uncapped domestic players in the **₹0.2–1 crore band** produce top-quartile impact — the clearest market inefficiency in the dataset.

## Tech stack

**PostgreSQL 14** — star schema, window functions, materialised views, stored
procedures, query optimisation
**Power BI** — role-playing dimensions with `USERELATIONSHIP`, context-transition
DAX for league baselines, bookmark navigation

## Data model

```
                    dim_player  ─┬─→ fact_ball[batter_id]   (active)
                                 ├─→ fact_ball[bowler_id]   (inactive)
                                 ├─→ fact_ball[fielder_id]  (inactive)
                                 └─→ fact_auction

     dim_venue ──→ dim_match ──→ fact_ball
```

`dim_player` is a role-playing dimension. In Power BI only the batting
relationship is active; bowling measures activate theirs with `USERELATIONSHIP`.
The alternative — three copies of the player table — bloats the model and forces
users to pick the right slicer.

Full column reference: [`docs/data_dictionary.md`](docs/data_dictionary.md)

## Repository structure

```
├── data/
│   └── README.md                      Download instructions + known data issues
├── sql/
│   ├── 01_schema.sql                  Star schema DDL
│   ├── 02_load_and_transform.sql      Staging → dimensions → facts, name resolution
│   ├── 03_data_quality_checks.sql     8-query validation suite
│   ├── 04_metrics/
│   │   ├── true_strike_rate.sql       Window-function league baselines
│   │   ├── pressure_index.sql         Running totals + LAG for required run rate
│   │   ├── hot_streaks.sql            Gaps-and-islands streak detection
│   │   ├── matchup_engine.sql         Batter × bowling family
│   │   └── player_value.sql           Full outer join valuation model
│   ├── 05_materialized_views.sql      Pre-computed dashboard source
│   ├── 06_stored_procedures.sql       Parameterised shortlist + matchup report
│   └── 07_performance_indexes.sql     Indexes with EXPLAIN ANALYZE method
├── powerbi/
│   ├── README.md                      Page-by-page dashboard design
│   └── dax_measures.md                All DAX, commented
└── docs/
    ├── methodology.md                 Metric definitions, thresholds, limitations
    ├── data_dictionary.md             Full column reference
    └── screenshots/
```

## Reproducing

```bash
# 1. Download the raw data — see data/README.md
# 2. Create the database
createdb ipl_analytics

# 3. Run the pipeline in order
psql -d ipl_analytics -f sql/01_schema.sql
psql -d ipl_analytics -f sql/02_load_and_transform.sql   # uncomment the \copy lines first
psql -d ipl_analytics -f sql/03_data_quality_checks.sql  # read the output before continuing
psql -d ipl_analytics -f sql/07_performance_indexes.sql
psql -d ipl_analytics -f sql/05_materialized_views.sql
psql -d ipl_analytics -f sql/06_stored_procedures.sql

# 4. Try it
psql -d ipl_analytics -c "SELECT * FROM build_shortlist(2024, 95.0, NULL, 4);"
```

Then connect Power BI to the database and add the measures from
[`powerbi/dax_measures.md`](powerbi/dax_measures.md).

## Limitations

Stated plainly, because a model whose weaknesses aren't documented shouldn't be
trusted:

- **No venue or pitch adjustment** — players at high-scoring grounds are flattered
- **No opposition-quality adjustment** — runs off a weak attack count the same
- **No fielding value** — a real component of worth, absent entirely
- **Backward-looking** — franchises buy future performance; this measures past
- **The squad builder is a greedy heuristic**, not an optimal knapsack solution
- **Impact ≠ wins** — a Win Probability Added model would be the honest next step

This is a **screening tool**, not a replacement for scouting. It narrows a
600-player auction pool to a 40-player shortlist so human judgement is spent
where it matters.

## Licence

MIT — see [LICENSE](LICENSE). IPL data belongs to its respective sources;
Cricsheet data is CC BY 4.0.
## Contribution

**Keshav Kundra**  
📧 kundrakkeshav85@gmail.com
