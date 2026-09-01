/* =============================================================================
   06_stored_procedures.sql
   Purpose : Reusable, parameterised analytics — SQL as software, not one-offs.
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- build_shortlist()
--
-- Given a budget and constraints, return a shortlist of players ranked by
-- value per crore, with a running spend total and the overseas cap enforced.
--
-- HONEST LIMITATION — say this out loud in an interview:
-- This is a GREEDY heuristic, not an optimal solution. Real squad selection is
-- a constrained knapsack problem, and greedy algorithms do not solve knapsack
-- optimally. Taking the best value-per-crore player first can exhaust budget
-- that a different combination would have used better.
-- It is fast, transparent, and good enough for a shortlist that a human scout
-- then works from. A true optimum needs integer programming, which is outside
-- what SQL should be asked to do.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION build_shortlist(
    p_season       INT,
    p_budget_cr    NUMERIC,
    p_role         TEXT DEFAULT NULL,
    p_max_overseas INT  DEFAULT 4
)
RETURNS TABLE (
    player_name     TEXT,
    primary_role    TEXT,
    is_overseas     BOOLEAN,
    price_cr        NUMERIC,
    total_impact    NUMERIC,
    value_per_crore NUMERIC,
    running_spend   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH ranked AS (
        SELECT v.player_name, v.primary_role, v.is_overseas,
               v.final_price_cr, v.total_impact, v.value_per_crore,
               ROW_NUMBER() OVER (ORDER BY v.value_per_crore DESC) AS greedy_rank
        FROM mv_player_value v
        WHERE v.season = p_season
          AND (p_role IS NULL OR v.primary_role = p_role)
          AND v.final_price_cr IS NOT NULL
          AND v.total_impact > 0
    ),
    cumulative AS (
        SELECT r.*,
               SUM(r.final_price_cr) OVER (ORDER BY r.greedy_rank
                                           ROWS UNBOUNDED PRECEDING) AS spend,
               SUM(CASE WHEN r.is_overseas THEN 1 ELSE 0 END)
                   OVER (ORDER BY r.greedy_rank
                         ROWS UNBOUNDED PRECEDING)                   AS overseas_count
        FROM ranked r
    )
    SELECT c.player_name, c.primary_role, c.is_overseas,
           c.final_price_cr, c.total_impact, c.value_per_crore, c.spend
    FROM cumulative c
    WHERE c.spend <= p_budget_cr
      AND c.overseas_count <= p_max_overseas
    ORDER BY c.greedy_rank;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example: SELECT * FROM build_shortlist(2024, 95.0, NULL, 4);


-- -----------------------------------------------------------------------------
-- get_matchup_report()
-- Bowling plan for a given batter: which families to attack them with.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION get_matchup_report(p_player_name TEXT)
RETURNS TABLE (
    bowling_family TEXT,
    balls          BIGINT,
    sr_vs_family   NUMERIC,
    matchup_delta  NUMERIC,
    verdict        TEXT
) AS $$
BEGIN
    RETURN QUERY
    WITH m AS (
        SELECT bp.bowling_family AS fam,
               SUM(b.batsman_runs)                                           AS runs,
               COUNT(*) FILTER (WHERE b.extra_type IS DISTINCT FROM 'wides') AS bls
        FROM fact_ball  b
        JOIN dim_player bt ON bt.player_id = b.batter_id
        JOIN dim_player bp ON bp.player_id = b.bowler_id
        WHERE bt.player_name = p_player_name
          AND bp.bowling_family IS NOT NULL
        GROUP BY bp.bowling_family
    ),
    o AS (SELECT 100.0 * SUM(runs) / NULLIF(SUM(bls),0) AS overall_sr FROM m)
    SELECT m.fam,
           m.bls,
           ROUND(100.0 * m.runs / NULLIF(m.bls,0), 1),
           ROUND(100.0 * m.runs / NULLIF(m.bls,0) - o.overall_sr, 1),
           CASE WHEN 100.0*m.runs/NULLIF(m.bls,0) - o.overall_sr <= -20 THEN 'ATTACK — clear weakness'
                WHEN 100.0*m.runs/NULLIF(m.bls,0) - o.overall_sr >=  20 THEN 'AVOID — clear strength'
                ELSE 'Neutral' END
    FROM m CROSS JOIN o
    WHERE m.bls >= 30
    ORDER BY 4 ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Example: SELECT * FROM get_matchup_report('Virat Kohli');
