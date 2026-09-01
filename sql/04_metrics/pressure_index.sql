/* =============================================================================
   pressure_index.sql
   Metric  : Pressure Index — performance when the required run rate is high

   The idea
   --------
   Two batters can average 35 at a strike rate of 135 and be completely
   different assets. One accumulates on flat tracks in the first innings; the
   other scores when the chase demands 11 an over. Franchises pay a large
   premium for finishers, so the valuation model needs to separate them.

   Definition: a ball is "under pressure" when the required run rate at that
   point is 10 or more. Pressure uplift = strike rate under pressure minus
   overall strike rate.

   SQL technique
   -------------
   A running total via SUM() OVER (... ROWS UNBOUNDED PRECEDING), then LAG() to
   get the score BEFORE the current ball.

   THE BUG THAT COST ME TWO DAYS: if you compute the required rate from the score
   AFTER the ball, every run the batter just scored has already been subtracted
   from the target. That deflates the apparent pressure on exactly the deliveries
   where the batter scored, so every finisher's numbers get quietly inflated.
   The LAG is not optional.
   ============================================================================= */

WITH targets AS (
    SELECT match_id, SUM(total_runs) + 1 AS target_runs
    FROM fact_ball
    WHERE inning = 1
    GROUP BY match_id
),
chase AS (
    SELECT
        b.match_id,
        b.batter_id,
        b.batsman_runs,
        b.extra_type,
        t.target_runs,
        (b.over_number - 1) * 6 + b.ball_number AS balls_bowled,
        SUM(b.total_runs) OVER (
            PARTITION BY b.match_id
            ORDER BY b.over_number, b.ball_number
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS score_after_ball
    FROM fact_ball b
    JOIN targets   t ON t.match_id = b.match_id
    JOIN dim_match m ON m.match_id = b.match_id
    WHERE b.inning = 2
      AND m.is_rain_affected = FALSE   -- DLS targets break the 120-ball assumption
),
with_rrr AS (
    SELECT
        c.*,
        (c.target_runs
           - LAG(c.score_after_ball, 1, 0) OVER (PARTITION BY c.match_id
                                                 ORDER BY c.balls_bowled)
        ) * 6.0 / NULLIF(120 - c.balls_bowled + 1, 0) AS required_rr
    FROM chase c
)
SELECT
    p.player_name,
    SUM(w.batsman_runs)                                       AS chase_runs,
    COUNT(*) FILTER (WHERE w.extra_type IS DISTINCT FROM 'wides') AS balls_faced,

    SUM(w.batsman_runs) FILTER (WHERE w.required_rr >= 10)    AS runs_under_pressure,
    COUNT(*)            FILTER (WHERE w.required_rr >= 10
                                  AND w.extra_type IS DISTINCT FROM 'wides')
                                                              AS balls_under_pressure,

    ROUND(100.0 * SUM(w.batsman_runs) FILTER (WHERE w.required_rr >= 10)
                / NULLIF(COUNT(*) FILTER (WHERE w.required_rr >= 10
                                            AND w.extra_type IS DISTINCT FROM 'wides'), 0), 1)
                                                              AS sr_under_pressure,
    ROUND(100.0 * SUM(w.batsman_runs)
                / NULLIF(COUNT(*) FILTER (WHERE w.extra_type IS DISTINCT FROM 'wides'), 0), 1)
                                                              AS sr_overall,

    -- the headline number: positive means the player RAISES their gear
    -- when the chase gets hard
    ROUND(
        100.0 * SUM(w.batsman_runs) FILTER (WHERE w.required_rr >= 10)
              / NULLIF(COUNT(*) FILTER (WHERE w.required_rr >= 10
                                          AND w.extra_type IS DISTINCT FROM 'wides'), 0)
      - 100.0 * SUM(w.batsman_runs)
              / NULLIF(COUNT(*) FILTER (WHERE w.extra_type IS DISTINCT FROM 'wides'), 0)
    , 1)                                                      AS pressure_uplift
FROM with_rrr w
JOIN dim_player p ON p.player_id = w.batter_id
GROUP BY p.player_name
HAVING COUNT(*) FILTER (WHERE w.required_rr >= 10) >= 50
ORDER BY pressure_uplift DESC;
