/* =============================================================================
   03_data_quality_checks.sql
   Purpose : Validation suite. Run after every load. Each query should return
             ZERO rows (or the documented expected value) on clean data.

   Why this file exists
   --------------------
   In an interview, "how did you validate your data?" is the question that
   separates people who ran a tutorial from people who built something. This
   file is the answer.
   ============================================================================= */

-- CHECK 1: orphan foreign keys — deliveries whose player never resolved.
-- Expected: 0 rows. Non-zero means the name map has gaps.
SELECT 'unresolved batter' AS issue, COUNT(*) AS n
FROM fact_ball WHERE batter_id IS NULL
UNION ALL
SELECT 'unresolved bowler', COUNT(*) FROM fact_ball WHERE bowler_id IS NULL
UNION ALL
SELECT 'ball with no match', COUNT(*)
FROM fact_ball b LEFT JOIN dim_match m USING (match_id) WHERE m.match_id IS NULL;


-- CHECK 2: arithmetic integrity — total_runs must equal batsman + extras.
-- Expected: 0 rows.
SELECT match_id, over_number, ball_number, batsman_runs, extra_runs, total_runs
FROM fact_ball
WHERE total_runs <> batsman_runs + extra_runs;


-- CHECK 3: impossible values.
-- Expected: 0 rows.
SELECT 'over out of range' AS issue, COUNT(*) AS n
FROM fact_ball WHERE over_number NOT BETWEEN 1 AND 20
UNION ALL
SELECT 'negative runs', COUNT(*) FROM fact_ball WHERE batsman_runs < 0 OR extra_runs < 0
UNION ALL
SELECT 'wicket with no dismissal kind', COUNT(*)
FROM fact_ball WHERE is_wicket = 1 AND dismissal_kind IS NULL
UNION ALL
SELECT 'dismissal kind with no wicket', COUNT(*)
FROM fact_ball WHERE is_wicket = 0 AND dismissal_kind IS NOT NULL;


-- CHECK 4: innings length sanity.
-- Full innings = 120 legal balls. Anything under 108 should already be flagged
-- as rain-affected by 02_load_and_transform.sql step 8.
-- Expected: 0 rows.
WITH innings_length AS (
    SELECT match_id, inning, COUNT(*) AS legal_balls
    FROM fact_ball
    WHERE extra_type IS NULL OR extra_type IN ('legbyes','byes')
    GROUP BY match_id, inning
)
SELECT il.*, m.match_date, m.is_rain_affected
FROM innings_length il
JOIN dim_match m USING (match_id)
WHERE il.legal_balls < 108
  AND m.is_rain_affected = FALSE;


-- CHECK 5: external reconciliation — season run totals against published records.
-- This is the check that actually catches load errors. Compare the output
-- against the official IPL site before trusting any downstream metric.
SELECT m.season,
       COUNT(DISTINCT m.match_id) AS matches,
       SUM(b.total_runs)          AS total_runs,
       ROUND(SUM(b.total_runs)::NUMERIC / COUNT(DISTINCT m.match_id), 1) AS runs_per_match
FROM fact_ball b
JOIN dim_match m USING (match_id)
GROUP BY m.season
ORDER BY m.season;


-- CHECK 6: duplicate deliveries — same match, innings, over and ball twice.
-- Expected: 0 rows. (Legitimate exception: a ball re-bowled after a no-ball
-- shares over/ball numbering in some sources. Investigate before deleting.)
SELECT match_id, inning, over_number, ball_number, COUNT(*) AS n
FROM fact_ball
GROUP BY match_id, inning, over_number, ball_number
HAVING COUNT(*) > 1
ORDER BY n DESC
LIMIT 20;


-- CHECK 7: auction coverage by season.
-- Documents WHY the value analysis is scoped to 2018+. Expect low coverage
-- before 2018 — that is the finding, not a bug.
SELECT a.season,
       COUNT(*)                                              AS players_with_price,
       COUNT(*) FILTER (WHERE a.final_price_cr IS NULL)      AS missing_price,
       ROUND(AVG(a.final_price_cr), 2)                       AS avg_price_cr
FROM fact_auction a
GROUP BY a.season
ORDER BY a.season;


-- CHECK 8: face validity — the top 10 run scorers should be names any cricket
-- follower recognises. If they are not, something is wrong upstream.
-- This is a HUMAN check. Read the output; do not automate it.
SELECT p.player_name, SUM(b.batsman_runs) AS career_runs
FROM fact_ball b
JOIN dim_player p ON p.player_id = b.batter_id
GROUP BY p.player_name
ORDER BY career_runs DESC
LIMIT 10;
