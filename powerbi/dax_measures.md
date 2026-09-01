# DAX Measures

Copy these into the Power BI model. Grouped by measure table.

## Model setup

Import the star schema tables. Relationships:

| From | To | Cardinality | Active |
|---|---|---|---|
| `dim_player[player_id]` | `fact_ball[batter_id]` | 1:* | **Yes** |
| `dim_player[player_id]` | `fact_ball[bowler_id]` | 1:* | **No** |
| `dim_player[player_id]` | `fact_ball[fielder_id]` | 1:* | **No** |
| `dim_match[match_id]` | `fact_ball[match_id]` | 1:* | Yes |
| `dim_venue[venue_id]` | `dim_match[venue_id]` | 1:* | Yes |
| `dim_player[player_id]` | `fact_auction[player_id]` | 1:* | Yes |

`dim_player` is a **role-playing dimension** — it plays three roles against the
fact table. Power BI only allows one active relationship between a pair of
tables, so the batting one is active and the bowling measures switch to their
relationship with `USERELATIONSHIP`. The alternative (three copies of the player
table) bloats the model and forces users to pick the right slicer.

---

## Batting

```dax
Total Runs = SUM ( fact_ball[batsman_runs] )

Balls Faced =
CALCULATE (
    COUNTROWS ( fact_ball ),
    fact_ball[extra_type] <> "wides" || ISBLANK ( fact_ball[extra_type] )
)

Dismissals =
CALCULATE (
    COUNTROWS ( fact_ball ),
    fact_ball[is_wicket] = 1,
    fact_ball[player_out_id] = fact_ball[batter_id]
)

Strike Rate = DIVIDE ( [Total Runs], [Balls Faced] ) * 100

Batting Average = DIVIDE ( [Total Runs], [Dismissals] )
```

## The baseline measures — the core of the model

```dax
-- League strike rate for the CURRENT phase and season, ignoring the player filter.
-- ALL(dim_player) removes only the player context; phase and season stay intact.
League SR =
CALCULATE (
    [Strike Rate],
    ALL ( dim_player )
)

True Strike Rate = [Strike Rate] - [League SR]

Runs Added Above Avg = DIVIDE ( [True Strike Rate] * [Balls Faced], 100 )
```

## Bowling — activating the inactive relationship

```dax
Runs Conceded =
CALCULATE (
    SUM ( fact_ball[total_runs] ),
    USERELATIONSHIP ( dim_player[player_id], fact_ball[bowler_id] )
)

Legal Balls Bowled =
CALCULATE (
    COUNTROWS ( fact_ball ),
    USERELATIONSHIP ( dim_player[player_id], fact_ball[bowler_id] ),
    fact_ball[extra_type] IN { BLANK (), "legbyes", "byes" }
)

Overs Bowled = DIVIDE ( [Legal Balls Bowled], 6 )

Wickets =
CALCULATE (
    COUNTROWS ( fact_ball ),
    USERELATIONSHIP ( dim_player[player_id], fact_ball[bowler_id] ),
    fact_ball[is_wicket] = 1,
    NOT fact_ball[dismissal_kind]
        IN { "run out", "retired hurt", "obstructing the field" }
)

Economy = DIVIDE ( [Runs Conceded], [Overs Bowled] )

League Economy = CALCULATE ( [Economy], ALL ( dim_player ) )

Economy Saved = ( [League Economy] - [Economy] ) * [Overs Bowled]
```

## Valuation

```dax
Total Impact = [Runs Added Above Avg] + [Economy Saved]

Auction Price = SUM ( fact_auction[final_price_cr] )

Value per Crore = DIVIDE ( [Total Impact], [Auction Price] )

-- Share of league spend going to below-average players.
-- This is the headline KPI on page 1.
Overpaid Spend % =
VAR TotalSpend = CALCULATE ( [Auction Price], ALL ( dim_player ) )
VAR WastedSpend =
    CALCULATE (
        [Auction Price],
        FILTER ( ALL ( dim_player ), [Total Impact] <= 0 )
    )
RETURN DIVIDE ( WastedSpend, TotalSpend )
```

## Form and dynamic labels

```dax
Form (Last 10 Innings) =
VAR Last10 =
    TOPN ( 10,
           FILTER ( ALLSELECTED ( dim_match ), [Total Runs] > 0 ),
           dim_match[match_date], DESC )
RETURN CALCULATE ( AVERAGEX ( Last10, [Total Runs] ) )

Page Title =
"Scouting Report — "
    & SELECTEDVALUE ( dim_player[player_name], "Select a player" )

-- Conditional formatting driver for the quadrant chart
Value Segment Colour =
SWITCH (
    SELECTEDVALUE ( mv_player_value[value_segment] ),
    "Bargain",      "#2E7D32",
    "Fair Premium", "#1565C0",
    "Low Risk",     "#9E9E9E",
    "Overpaid",     "#C62828",
    "#9E9E9E"
)

-- Sample-size guard: blanks out any visual where the sample is too small,
-- so a 12-ball cameo can never top a leaderboard.
Impact (Guarded) =
IF ( [Balls Faced] >= 60 || [Legal Balls Bowled] >= 120, [Total Impact], BLANK () )
```
