# Methodology

## The question

> A franchise has roughly ₹95 crore to spend at auction. Which players are
> underpriced relative to the value they actually generate, and which of the
> current squad are being overpaid?

Auction prices are set by reputation, recent viral performances and bidding
dynamics. Raw statistics do not answer the question because they ignore context:
totals reward players who simply played more matches, and rates ignore *when*
those runs came.

## Metric definitions

### Phase
| Phase | Overs |
|---|---|
| Powerplay | 1–6 |
| Middle | 7–15 |
| Death | 16–20 |

T20 cricket is three different games. Fielding restrictions in the powerplay,
containment in the middle, and all-out hitting at the death produce completely
different scoring environments. Aggregating across them hides everything that
matters.

### True Strike Rate (TSR)
```
TSR = (player SR in phase P, season S) − (league SR in phase P, season S)
```
Both dimensions are necessary. Phase, because 140 is elite in the powerplay and
below average at the death. Season, because league scoring rates have risen
substantially since 2008 — a 2010 strike rate is not comparable to a 2024 one.

### Runs Added Above Average (RAA)
```
RAA = (TSR / 100) × balls faced
```
Converts a rate into a volume. +40 TSR over 40 balls is worth less than +20 TSR
over 300 balls. RAA is the currency the entire valuation runs on, because it is
denominated in **runs** — which means it can be added to the bowling equivalent.

### Economy Saved
```
Economy Saved = (league economy in phase − bowler economy in phase) × overs bowled
```
The bowling analogue of RAA, also denominated in runs. This shared unit is why
all-rounders can be valued on the same scale as specialists.

### Pressure Index
Share of chase runs scored when the required run rate is ≥ 10, plus the strike
rate uplift under those conditions. Separates genuine finishers from flat-track
accumulators.

**Implementation warning:** the required rate must be computed from the score
*before* the current ball, via `LAG`. Computing it after the ball subtracts the
runs the batter just scored, which deflates apparent pressure on exactly the
deliveries where they scored — silently inflating every finisher's numbers. This
bug took two days to find.

### Value per Crore
```
VPC = (RAA + Economy Saved) / auction price in crore
```
The headline output: impact per rupee.

### Matchup Delta
```
Delta = (batter SR vs bowling family) − (batter's overall SR)
```
Normalised per batter, so −30 means the same thing for an elite batter and an
average one.

## Sample-size thresholds

| Context | Minimum |
|---|---|
| Batting, per phase-season | 60 balls faced |
| Bowling, per phase-season | 120 balls bowled (20 overs) |
| Matchup cell | 50 balls |
| Matchup — batter overall | 500 balls |
| Pressure Index | 50 balls under pressure |
| Venue classification | 10 matches |

These are applied in SQL **and** enforced again in DAX via `[Impact (Guarded)]`,
so no small-sample outlier can reach a visual. An unfiltered 12-ball cameo
topping a leaderboard destroys credibility in everything else on the page.

## Data quality decisions

**Player name resolution.** The same person appears under multiple spellings
across seasons and files. Unresolved, one career splits into three and every
per-player metric is wrong. Handled with a normalisation function plus a manual
override map.

**Rain-affected matches are flagged, not dropped.** Dropping them would bias the
dataset against players who feature at high-rainfall venues. They are excluded
only from the Pressure Index, where DLS targets break the 120-ball assumption.

**Auction analysis scoped to 2018+.** Price data before 2018 is patchy. Stating
the scope limit is better than silently interpolating.

**Over indexing.** Cricsheet is 0-indexed, Kaggle is 1-indexed. The whole project
uses 1-indexed (overs 1–20); the load script adds 1.

## Query performance

Record your own `EXPLAIN ANALYZE` results here after running
`sql/07_performance_indexes.sql`:

| Query | Before | After | Plan change |
|---|---|---|---|
| Player-season aggregation | _ ms | _ ms | Seq Scan → Index Scan |
| Phase analysis | _ ms | _ ms | Seq Scan → Index Only Scan |

The interesting part is not that it got faster — it is that the plan changed
shape. Being able to point at a `Seq Scan` becoming an `Index Only Scan` shows
you read the plan rather than just timing the query.

## Limitations

1. **No venue adjustment.** A player at a high-scoring ground is flattered. The
   `dim_venue.venue_type` column exists to fix this but is not yet wired into the
   impact metrics.
2. **No opposition-quality adjustment.** Runs off a weak attack count the same as
   runs off a strong one.
3. **No fielding value.** A real component of player worth, absent entirely.
4. **Backward-looking.** Franchises buy future performance; this measures past
   performance. Ageing curves and injury history are not modelled.
5. **The squad builder is greedy, not optimal.** Squad selection is a constrained
   knapsack problem, and greedy algorithms do not solve knapsack optimally. A true
   optimum needs integer programming, outside what SQL should do.
6. **Impact ≠ wins.** Runs above average correlate with winning but are not the
   same thing. A win-probability-added model would be the honest next step.

## Next steps

- Venue and opposition adjustments in the impact metrics
- Win Probability Added rather than runs above average
- Fielding value from the dismissal data
- A forward-looking projection model with ageing curves
