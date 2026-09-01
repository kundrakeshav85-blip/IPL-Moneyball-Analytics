/* =============================================================================
   matchup_engine.sql
   Metric  : Matchup Delta — batter performance vs each bowling family

   The idea
   --------
   Team selection and in-game bowling changes are matchup decisions. A batter
   with an overall SR of 140 who drops to 105 against left-arm spin is a
   specific, exploitable weakness — and it is invisible in aggregate stats.

   Matchup Delta = (SR against that bowling family) - (that batter's overall SR).
   Negative = weakness. This normalises per batter, so a delta of -30 means the
   same thing for an elite batter and an average one.

   Why FAMILIES rather than individual styles
   ------------------------------------------
   There are 8+ distinct bowling styles in the data. Splitting by all of them
   drops most batter x style cells below the 50-ball threshold, so almost
   nothing survives the sample filter. Rolling up to 5 families keeps the
   matrix populated while preserving the distinction that actually matters
   (pace vs spin, and the arm the ball comes from).

   This query powers the dashboard heatmap — batters on rows, families on
   columns, coloured by delta.
   ============================================================================= */

WITH matchup AS (
    SELECT
        b.batter_id,
        bp.bowling_family,
        SUM(b.batsman_runs)                                           AS runs,
        COUNT(*) FILTER (WHERE b.extra_type IS DISTINCT FROM 'wides') AS balls,
        COUNT(*) FILTER (WHERE b.is_wicket = 1
                           AND b.player_out_id = b.batter_id)         AS outs
    FROM fact_ball b
    JOIN dim_player bp ON bp.player_id = b.bowler_id
    WHERE bp.bowling_family IS NOT NULL
    GROUP BY b.batter_id, bp.bowling_family
),
overall AS (
    SELECT
        batter_id,
        100.0 * SUM(runs) / NULLIF(SUM(balls), 0) AS overall_sr,
        SUM(balls)                                AS total_balls
    FROM matchup
    GROUP BY batter_id
)
SELECT
    p.player_name,
    p.batting_hand,
    m.bowling_family,
    m.balls,
    m.outs,
    ROUND(100.0 * m.runs / NULLIF(m.balls, 0), 1)                 AS sr_vs_family,
    ROUND(o.overall_sr, 1)                                        AS overall_sr,
    ROUND(100.0 * m.runs / NULLIF(m.balls, 0) - o.overall_sr, 1)  AS matchup_delta,
    ROUND(m.runs::NUMERIC / NULLIF(m.outs, 0), 1)                 AS avg_vs_family,
    ROUND(m.balls::NUMERIC / NULLIF(m.outs, 0), 1)                AS balls_per_dismissal,
    CASE
        WHEN 100.0 * m.runs / NULLIF(m.balls,0) - o.overall_sr <= -20 THEN 'Clear Weakness'
        WHEN 100.0 * m.runs / NULLIF(m.balls,0) - o.overall_sr >=  20 THEN 'Clear Strength'
        ELSE 'Neutral'
    END AS matchup_verdict
FROM matchup m
JOIN overall    o ON o.batter_id = m.batter_id
JOIN dim_player p ON p.player_id = m.batter_id
WHERE m.balls >= 50          -- per-cell minimum
  AND o.total_balls >= 500   -- only established batters
ORDER BY matchup_delta ASC;  -- most exploitable weaknesses first
