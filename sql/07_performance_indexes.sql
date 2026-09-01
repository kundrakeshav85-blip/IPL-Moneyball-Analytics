/* =============================================================================
   07_performance_indexes.sql
   Purpose : Indexes for the analytical workload, with before/after measurement.

   Method
   ------
   Every index here was added because a specific query was slow, not
   speculatively. Run the EXPLAIN ANALYZE blocks below before and after
   creating each index and record YOUR OWN numbers in docs/methodology.md.
   Quoting someone else's benchmark in an interview is worse than quoting none.
   ============================================================================= */

-- Baseline: run this BEFORE creating indexes and note the planning + execution time.
/*
EXPLAIN (ANALYZE, BUFFERS)
SELECT b.batter_id, m.season, SUM(b.batsman_runs)
FROM fact_ball b JOIN dim_match m ON m.match_id = b.match_id
GROUP BY b.batter_id, m.season;
*/

-- Nearly every analytical query joins fact_ball to dim_match to get the season.
CREATE INDEX IF NOT EXISTS idx_ball_match ON fact_ball(match_id);

-- Composite, batter-leading: supports per-player-per-match aggregation without
-- a sort. Column order matters — batter_id first because it is the filter/group
-- column and match_id second because it is the join key.
CREATE INDEX IF NOT EXISTS idx_ball_batter ON fact_ball(batter_id, match_id);
CREATE INDEX IF NOT EXISTS idx_ball_bowler ON fact_ball(bowler_id, match_id);

-- Covering index for phase analysis. INCLUDE puts the measure columns in the
-- leaf pages so the phase queries can be answered index-only, without touching
-- the heap at all.
CREATE INDEX IF NOT EXISTS idx_ball_phase
    ON fact_ball(over_number)
    INCLUDE (batsman_runs, is_wicket, extra_type);

-- Partial index: the pressure-index query only ever reads second innings.
-- A partial index is roughly half the size of a full one here.
CREATE INDEX IF NOT EXISTS idx_ball_second_innings
    ON fact_ball(match_id, over_number, ball_number)
    WHERE inning = 2;

CREATE INDEX IF NOT EXISTS idx_match_season  ON dim_match(season, match_date);
CREATE INDEX IF NOT EXISTS idx_auction_player ON fact_auction(player_id, season);

-- Refresh planner statistics so the new indexes are actually chosen.
ANALYZE fact_ball;
ANALYZE dim_match;
ANALYZE fact_auction;

/* Re-run the EXPLAIN ANALYZE above and compare.

   Record in docs/methodology.md:
     - the plan node that changed (typically Seq Scan -> Index Scan)
     - execution time before and after
     - buffer hits before and after

   Talking point: the interesting part is not "it got faster", it is that the
   PLAN CHANGED SHAPE. Being able to point at a Seq Scan becoming an
   Index Only Scan shows you read the plan rather than just timing the query.
*/
