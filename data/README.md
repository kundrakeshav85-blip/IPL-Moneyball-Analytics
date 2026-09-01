# Data

Raw data files are **not** committed to this repository because of their size.
Download them yourself using the instructions below, then place them in `data/raw/`.

## Required files

| File | Source | Notes |
|---|---|---|
| `matches.csv` | Kaggle — *IPL Complete Dataset (2008–2024)* | One row per match |
| `deliveries.csv` | Kaggle — *IPL Complete Dataset (2008–2024)* | Ball-by-ball, ~260k rows |
| `ipl_auction.csv` | Kaggle — *IPL Auction Dataset* | Player prices by season |
| `player_attributes.csv` | Compiled manually from ESPNcricinfo profiles | Batting hand, bowling style, role, nationality |

## Alternative source

[Cricsheet](https://cricsheet.org/downloads/) publishes higher-quality ball-by-ball
data as JSON under a CC BY 4.0 licence. It requires a parsing step but includes
fields the Kaggle set omits (bowling style, exact delivery outcomes).

## Expected schema of the raw files

`deliveries.csv`
```
match_id, inning, batting_team, bowling_team, over, ball,
batter, bowler, non_striker, batsman_runs, extra_runs, total_runs,
extras_type, is_wicket, player_dismissed, dismissal_kind, fielder
```

`matches.csv`
```
id, season, city, date, match_type, player_of_match, venue,
team1, team2, toss_winner, toss_decision, winner, result,
result_margin, target_runs, target_overs, super_over, method,
umpire1, umpire2
```

## Known data quality issues

1. **Player name inconsistency** across seasons ("MS Dhoni" vs "M.S. Dhoni").
   Handled via a name-mapping table in `sql/02_load_and_transform.sql`.
2. **Rain-affected matches** have fewer than 120 balls per innings. These are
   flagged rather than dropped, since dropping them would bias against players
   who feature at high-rainfall venues.
3. **Auction data is incomplete before 2018.** The value analysis is scoped to
   2018 onwards and this is stated on the dashboard.
4. **Over numbering** differs between sources: Cricsheet is 0-indexed, the Kaggle
   set is 1-indexed. All SQL in this repo assumes **1-indexed** (overs 1–20).
