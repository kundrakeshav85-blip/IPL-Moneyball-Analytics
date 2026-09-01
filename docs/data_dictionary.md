# Data Dictionary

## dim_player
| Column | Type | Description |
|---|---|---|
| player_id | SERIAL PK | Surrogate key |
| player_name | TEXT | Canonical name after normalisation |
| batting_hand | TEXT | RHB / LHB |
| bowling_style | TEXT | RF, RFM, RM, OB, LB, LF, SLA, LC |
| bowling_family | TEXT | Right Pace, Left Pace, Off Spin, Leg Spin, Left Arm Spin |
| primary_role | TEXT | Batter / Bowler / All-rounder / Wicketkeeper |
| country | TEXT | Nationality |
| is_overseas | BOOLEAN | TRUE when country ≠ India |

## dim_venue
| Column | Type | Description |
|---|---|---|
| venue_id | SERIAL PK | Surrogate key |
| venue_name | TEXT | Ground name |
| city | TEXT | City |
| avg_first_inn_score | NUMERIC | Derived from data, not hand-entered |
| venue_type | TEXT | High Scoring / Balanced / Bowler Friendly / Insufficient Data |

## dim_match
| Column | Type | Description |
|---|---|---|
| match_id | INT PK | From source data |
| season | INT | 4-digit year |
| match_date | DATE | Match date |
| venue_id | INT FK | → dim_venue |
| team_bat_first / team_bat_second | TEXT | Derived from toss winner and decision |
| toss_winner, toss_decision | TEXT | |
| winner | TEXT | NULL if no result |
| result_margin | INT | Runs or wickets |
| target_runs | INT | Second-innings target |
| match_stage | TEXT | League / Playoff / Final |
| is_rain_affected | BOOLEAN | TRUE when any innings < 108 legal balls |

## fact_ball
**Grain: one row per delivery bowled.** ~260,000 rows for 2008–2024.

| Column | Type | Description |
|---|---|---|
| ball_id | BIGSERIAL PK | Surrogate key |
| match_id | INT FK | → dim_match |
| inning | SMALLINT | 1 or 2 |
| over_number | SMALLINT | **1–20, 1-indexed** |
| ball_number | SMALLINT | Within the over |
| batting_team / bowling_team | TEXT | |
| batter_id, bowler_id, non_striker_id | INT FK | → dim_player (role-playing) |
| batsman_runs | SMALLINT | Runs off the bat |
| extra_runs | SMALLINT | Extras |
| total_runs | SMALLINT | batsman_runs + extra_runs |
| extra_type | TEXT | wides / noballs / legbyes / byes / NULL |
| is_wicket | SMALLINT | 0 or 1 |
| dismissal_kind | TEXT | bowled, caught, lbw, run out, ... |
| player_out_id | INT FK | → dim_player. May differ from batter_id on a run out |
| fielder_id | INT FK | → dim_player |

**Important:** wides do not count as balls faced. Every strike-rate calculation
filters `extra_type IS DISTINCT FROM 'wides'`. Legal balls for bowling economy
exclude wides and no-balls but include leg-byes and byes.

## fact_auction
**Grain: one row per player per season signing.**

| Column | Type | Description |
|---|---|---|
| auction_id | SERIAL PK | Surrogate key |
| season | INT | Auction year |
| player_id | INT FK | → dim_player |
| team | TEXT | Franchise |
| base_price_cr | NUMERIC | Reserve price, ₹ crore |
| final_price_cr | NUMERIC | Sold price, ₹ crore |
| acquisition | TEXT | Auction / Retained / RTM / Replacement |

## Derived (mv_player_value)
| Column | Description |
|---|---|
| bat_impact | Runs Added Above Average |
| bowl_impact | Economy Saved, in runs |
| total_impact | bat_impact + bowl_impact |
| value_per_crore | total_impact / final_price_cr |
| impact_quartile / price_quartile | NTILE(4) within season |
| value_segment | Bargain / Fair Premium / Low Risk / Overpaid |
