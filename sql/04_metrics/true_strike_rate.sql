/* =============================================================================
   true_strike_rate.sql
   Metric  : True Strike Rate (TSR) and Runs Added Above Average (RAA)

   The idea
   --------
   Raw strike rate is misleading because T20 cricket is three different games.
   A strike rate of 140 in the powerplay is elite; the same 140 at the death is
   BELOW average. Comparing players on raw SR therefore systematically
   overvalues death-overs batters and undervalues powerplay specialists.

   TSR fixes this by subtracting the league average for the same phase AND the
   same season. Seasons matter too — scoring rates have risen sharply since 2008,
   so a 2010 strike rate is not comparable to a 2024 one.

   RAA then converts that RATE into a VOLUME by multiplying by balls faced.
   A player with +40 TSR over 40 balls contributed less than one with +20 TSR
   over 300 balls. RAA is the currency the whole valuation model runs on.

   SQL technique
   -------------
   The league baseline is computed with a WINDOW AGGREGATE in the same pass —
   no self-join, no correlated subquery. One scan of the aggregated set.
   ============================================================================= */

WITH ball_phase AS (
    SELECT
        b.batter_id,
        b.batsman_runs,
        b.is_wicket,
        b.player_out_id,
        b.extra_type,
        m.season,
        CASE
            WHEN b.over_number BETWEEN 1  AND 6  THEN 'Powerplay'
            WHEN b.over_number BETWEEN 7  AND 15 THEN 'Middle'
            ELSE 'Death'
        END AS phase
    FROM fact_ball b
    JOIN dim_match m ON m.match_id = b.match_id
),
player_phase AS (
    SELECT
        season,
        phase,
        batter_id,
        SUM(batsman_runs)                                            AS runs,
        -- wides are not balls faced by the batter
        COUNT(*) FILTER (WHERE extra_type IS DISTINCT FROM 'wides')  AS balls_faced,
        COUNT(*) FILTER (WHERE is_wicket = 1
                           AND player_out_id = batter_id)            AS dismissals
    FROM ball_phase
    GROUP BY season, phase, batter_id
),
benchmarked AS (
    SELECT
        pp.*,
        100.0 * runs / NULLIF(balls_faced, 0) AS strike_rate,
        100.0 * SUM(runs)              OVER (PARTITION BY season, phase)
              / NULLIF(SUM(balls_faced) OVER (PARTITION BY season, phase), 0)
              AS league_sr
    FROM player_phase pp
)
SELECT
    p.player_name,
    p.primary_role,
    b.season,
    b.phase,
    b.runs,
    b.balls_faced,
    b.dismissals,
    ROUND(b.strike_rate, 1)                                          AS sr,
    ROUND(b.league_sr, 1)                                            AS league_sr,
    ROUND(b.strike_rate - b.league_sr, 1)                            AS true_strike_rate,
    ROUND((b.strike_rate - b.league_sr) * b.balls_faced / 100.0, 1)  AS runs_added_above_avg,
    RANK()   OVER (PARTITION BY b.season, b.phase
                   ORDER BY (b.strike_rate - b.league_sr) * b.balls_faced DESC) AS phase_rank,
    NTILE(4) OVER (PARTITION BY b.season, b.phase
                   ORDER BY (b.strike_rate - b.league_sr) * b.balls_faced DESC) AS impact_quartile
FROM benchmarked b
JOIN dim_player p ON p.player_id = b.batter_id
WHERE b.balls_faced >= 60      -- minimum sample; see docs/methodology.md
ORDER BY b.season DESC, b.phase, phase_rank;


/* MySQL 8 port:
     COUNT(*) FILTER (WHERE cond)   ->  SUM(CASE WHEN cond THEN 1 ELSE 0 END)
     x IS DISTINCT FROM 'wides'     ->  (x IS NULL OR x <> 'wides')
   Window functions, CTEs, RANK and NTILE all work unchanged in MySQL 8.
*/
