/* =============================================================================
   05_materialized_views.sql
   Purpose : Pre-compute the heavy aggregate that Power BI hits on every page.

   Why materialise
   ---------------
   mv_player_value involves a FULL OUTER JOIN across two separate multi-level
   window aggregations over the whole fact table. Recomputing that on every
   dashboard interaction was the single biggest source of latency. Since the
   underlying data only changes when a new season is loaded, computing it once
   per load is the obvious trade.

   The trade-off, stated honestly: the view is stale between refreshes. That is
   acceptable here because IPL data updates in batches, not continuously. For a
   live-scoring use case this would be the wrong choice.
   ============================================================================= */

DROP MATERIALIZED VIEW IF EXISTS mv_player_value;

CREATE MATERIALIZED VIEW mv_player_value AS
-- body is identical to 04_metrics/player_value.sql
-- (kept in sync manually; see docs/methodology.md for the refresh procedure)
WITH ball_phase AS (
    SELECT b.*, m.season,
           CASE WHEN b.over_number BETWEEN 1 AND 6  THEN 'Powerplay'
                WHEN b.over_number BETWEEN 7 AND 15 THEN 'Middle'
                ELSE 'Death' END AS phase
    FROM fact_ball b
    JOIN dim_match m ON m.match_id = b.match_id
),
bat_phase AS (
    SELECT season, phase, batter_id,
           SUM(batsman_runs)                                           AS runs,
           COUNT(*) FILTER (WHERE extra_type IS DISTINCT FROM 'wides') AS balls
    FROM ball_phase GROUP BY season, phase, batter_id
),
bat_raa AS (
    SELECT DISTINCT batter_id AS player_id, season,
           SUM( (100.0 * runs / NULLIF(balls,0)
               - 100.0 * SUM(runs)  OVER (PARTITION BY season, phase)
                       / NULLIF(SUM(balls) OVER (PARTITION BY season, phase),0)
                ) * balls / 100.0 ) OVER (PARTITION BY batter_id, season) AS raa,
           SUM(balls) OVER (PARTITION BY batter_id, season)              AS balls_faced
    FROM bat_phase
),
bowl_phase AS (
    SELECT season, phase, bowler_id,
           SUM(total_runs)                                          AS runs_conceded,
           COUNT(*) FILTER (WHERE extra_type IS NULL
                               OR extra_type IN ('legbyes','byes'))  AS legal_balls
    FROM ball_phase GROUP BY season, phase, bowler_id
),
bowl_saved AS (
    SELECT DISTINCT bowler_id AS player_id, season,
           SUM( ( 6.0 * SUM(runs_conceded) OVER (PARTITION BY season, phase)
                      / NULLIF(SUM(legal_balls) OVER (PARTITION BY season, phase),0)
                - 6.0 * runs_conceded / NULLIF(legal_balls,0)
                ) * legal_balls / 6.0 ) OVER (PARTITION BY bowler_id, season)
                                                                 AS economy_saved,
           SUM(legal_balls) OVER (PARTITION BY bowler_id, season) AS balls_bowled
    FROM bowl_phase
),
combined AS (
    SELECT COALESCE(b.player_id, w.player_id) AS player_id,
           COALESCE(b.season, w.season)       AS season,
           COALESCE(b.raa, 0)                 AS bat_impact,
           COALESCE(w.economy_saved, 0)       AS bowl_impact,
           COALESCE(b.balls_faced, 0)         AS balls_faced,
           COALESCE(w.balls_bowled, 0)        AS balls_bowled
    FROM bat_raa b
    FULL OUTER JOIN bowl_saved w
      ON w.player_id = b.player_id AND w.season = b.season
)
SELECT p.player_name, p.primary_role, p.is_overseas, c.season, a.team,
       a.final_price_cr,
       ROUND(c.bat_impact,1)                  AS bat_impact,
       ROUND(c.bowl_impact,1)                 AS bowl_impact,
       ROUND(c.bat_impact + c.bowl_impact,1)  AS total_impact,
       ROUND((c.bat_impact + c.bowl_impact) / NULLIF(a.final_price_cr,0),1)
                                              AS value_per_crore,
       c.balls_faced, c.balls_bowled,
       CASE WHEN c.bat_impact + c.bowl_impact >  0 AND a.final_price_cr <  4 THEN 'Bargain'
            WHEN c.bat_impact + c.bowl_impact >  0 AND a.final_price_cr >= 4 THEN 'Fair Premium'
            WHEN c.bat_impact + c.bowl_impact <= 0 AND a.final_price_cr <  4 THEN 'Low Risk'
            ELSE 'Overpaid' END               AS value_segment
FROM combined c
JOIN dim_player p ON p.player_id = c.player_id
LEFT JOIN fact_auction a ON a.player_id = c.player_id AND a.season = c.season
WHERE c.season >= 2018
  AND (c.balls_faced >= 60 OR c.balls_bowled >= 120);

-- A UNIQUE index is REQUIRED for REFRESH ... CONCURRENTLY, which lets the
-- dashboard keep reading the old data while the refresh runs.
CREATE UNIQUE INDEX idx_mv_player_value_pk ON mv_player_value (player_name, season);
CREATE INDEX idx_mv_value_segment ON mv_player_value (season, value_segment);

-- Refresh after each data load:
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_player_value;
