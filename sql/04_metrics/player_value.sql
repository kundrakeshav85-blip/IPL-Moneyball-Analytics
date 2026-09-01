/* =============================================================================
   player_value.sql
   Metric  : Value per Crore — the headline output of the whole project

   The idea
   --------
   Batting impact (RAA) and bowling impact (Economy Saved) are both expressed in
   RUNS, which means they can simply be added. That common unit is the reason
   the model works for all-rounders as well as specialists.

   Total Impact  = RAA (batting) + Economy Saved (bowling)
   Value/Crore   = Total Impact / auction price

   Scope note: auction data is sparse before 2018, so the value analysis is
   restricted to 2018 onwards. This is documented on the dashboard rather than
   silently ignored.
   ============================================================================= */

WITH ball_phase AS (
    SELECT b.*, m.season,
           CASE WHEN b.over_number BETWEEN 1 AND 6  THEN 'Powerplay'
                WHEN b.over_number BETWEEN 7 AND 15 THEN 'Middle'
                ELSE 'Death' END AS phase
    FROM fact_ball b
    JOIN dim_match m ON m.match_id = b.match_id
),

-- ---------- BATTING SIDE: Runs Added Above Average ----------
bat_phase AS (
    SELECT season, phase, batter_id,
           SUM(batsman_runs)                                           AS runs,
           COUNT(*) FILTER (WHERE extra_type IS DISTINCT FROM 'wides') AS balls
    FROM ball_phase
    GROUP BY season, phase, batter_id
),
bat_raa AS (
    SELECT batter_id AS player_id, season,
           SUM( (100.0 * runs / NULLIF(balls,0)
               - 100.0 * SUM(runs)  OVER (PARTITION BY season, phase)
                       / NULLIF(SUM(balls) OVER (PARTITION BY season, phase),0)
                ) * balls / 100.0 ) OVER (PARTITION BY batter_id, season) AS raa,
           SUM(balls) OVER (PARTITION BY batter_id, season)              AS total_balls_faced
    FROM bat_phase
),
bat_final AS (
    SELECT DISTINCT player_id, season, raa, total_balls_faced FROM bat_raa
),

-- ---------- BOWLING SIDE: Economy Saved ----------
bowl_phase AS (
    SELECT season, phase, bowler_id,
           SUM(total_runs)                                              AS runs_conceded,
           COUNT(*) FILTER (WHERE extra_type IS NULL
                               OR extra_type IN ('legbyes','byes'))     AS legal_balls,
           COUNT(*) FILTER (WHERE is_wicket = 1
                              AND dismissal_kind NOT IN
                                  ('run out','retired hurt','obstructing the field'))
                                                                        AS wickets
    FROM ball_phase
    GROUP BY season, phase, bowler_id
),
bowl_saved AS (
    SELECT bowler_id AS player_id, season,
           -- (league economy - bowler economy) * overs bowled = runs saved
           SUM( ( 6.0 * SUM(runs_conceded) OVER (PARTITION BY season, phase)
                      / NULLIF(SUM(legal_balls) OVER (PARTITION BY season, phase),0)
                - 6.0 * runs_conceded / NULLIF(legal_balls,0)
                ) * legal_balls / 6.0 ) OVER (PARTITION BY bowler_id, season)
                                                                AS economy_saved,
           SUM(legal_balls) OVER (PARTITION BY bowler_id, season) AS total_balls_bowled,
           SUM(wickets)     OVER (PARTITION BY bowler_id, season) AS total_wickets
    FROM bowl_phase
),
bowl_final AS (
    SELECT DISTINCT player_id, season, economy_saved,
           total_balls_bowled, total_wickets
    FROM bowl_saved
),

-- ---------- COMBINE (FULL OUTER JOIN: pure batters and pure bowlers both survive) ----------
combined AS (
    SELECT
        COALESCE(b.player_id, w.player_id)      AS player_id,
        COALESCE(b.season,    w.season)         AS season,
        COALESCE(b.raa, 0)                      AS bat_impact,
        COALESCE(w.economy_saved, 0)            AS bowl_impact,
        COALESCE(b.total_balls_faced, 0)        AS balls_faced,
        COALESCE(w.total_balls_bowled, 0)       AS balls_bowled,
        COALESCE(w.total_wickets, 0)            AS wickets
    FROM bat_final b
    FULL OUTER JOIN bowl_final w
      ON w.player_id = b.player_id AND w.season = b.season
)
SELECT
    p.player_name,
    p.primary_role,
    p.is_overseas,
    c.season,
    a.team,
    a.final_price_cr,
    ROUND(c.bat_impact, 1)                       AS bat_impact,
    ROUND(c.bowl_impact, 1)                      AS bowl_impact,
    ROUND(c.bat_impact + c.bowl_impact, 1)       AS total_impact,
    ROUND((c.bat_impact + c.bowl_impact)
          / NULLIF(a.final_price_cr, 0), 1)      AS value_per_crore,

    NTILE(4) OVER (PARTITION BY c.season
                   ORDER BY (c.bat_impact + c.bowl_impact)) AS impact_quartile,
    NTILE(4) OVER (PARTITION BY c.season
                   ORDER BY a.final_price_cr)               AS price_quartile,

    -- the four quadrants of the signature dashboard visual
    CASE
        WHEN c.bat_impact + c.bowl_impact >  0 AND a.final_price_cr <  4 THEN 'Bargain'
        WHEN c.bat_impact + c.bowl_impact >  0 AND a.final_price_cr >= 4 THEN 'Fair Premium'
        WHEN c.bat_impact + c.bowl_impact <= 0 AND a.final_price_cr <  4 THEN 'Low Risk'
        ELSE 'Overpaid'
    END AS value_segment
FROM combined c
JOIN dim_player p ON p.player_id = c.player_id
LEFT JOIN fact_auction a
       ON a.player_id = c.player_id AND a.season = c.season
WHERE c.season >= 2018
  AND (c.balls_faced >= 60 OR c.balls_bowled >= 120)
ORDER BY value_per_crore DESC NULLS LAST;
