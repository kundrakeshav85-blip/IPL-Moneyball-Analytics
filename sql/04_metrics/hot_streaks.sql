/* =============================================================================
   hot_streaks.sql
   Metric  : Longest run of consecutive 30+ scores (form / consistency)
   Pattern : GAPS AND ISLANDS

   The idea
   --------
   Franchises care about reliability, not just averages. A player who scores
   35, 40, 32, 38 is a different asset from one who scores 0, 0, 145, 0 — same
   average, wildly different planning value. Streak length captures that.

   The technique — read this carefully, it is the crux
   ---------------------------------------------------
   1. Number EVERY innings for a player in date order              -> rn_all
   2. Number ONLY the good innings, separately, in date order      -> rn_grp
   3. For any run of CONSECUTIVE good innings, (rn_all - rn_grp) is
      CONSTANT. The moment a bad innings interrupts the run, rn_all
      advances but rn_grp does not, so the difference jumps.
   4. Grouping on that difference collapses each streak to one row.

   Worked example for one player:
     innings:  50   40   10   60   70   80
     is_good:   1    1    0    1    1    1
     rn_all:    1    2    3    4    5    6
     rn_grp:    1    2    -    3    4    5
     diff:      0    0    -    1    1    1     <- two islands: {1,2} and {4,5,6}

   Why not a recursive CTE
   -----------------------
   A recursive CTE would produce the same answer but walks the data row by row.
   This is two window functions and a GROUP BY — fully set-based, and on 260k
   rows the difference is large. Being able to explain WHY you rejected the
   recursive approach is worth more in an interview than the query itself.
   ============================================================================= */

WITH innings AS (
    SELECT
        b.batter_id,
        b.match_id,
        m.match_date,
        SUM(b.batsman_runs) AS runs
    FROM fact_ball b
    JOIN dim_match m ON m.match_id = b.match_id
    GROUP BY b.batter_id, b.match_id, m.match_date
),
flagged AS (
    SELECT
        i.*,
        CASE WHEN i.runs >= 30 THEN 1 ELSE 0 END AS is_good,
        ROW_NUMBER() OVER (PARTITION BY i.batter_id
                           ORDER BY i.match_date, i.match_id) AS rn_all,
        ROW_NUMBER() OVER (PARTITION BY i.batter_id,
                                        CASE WHEN i.runs >= 30 THEN 1 ELSE 0 END
                           ORDER BY i.match_date, i.match_id) AS rn_grp
    FROM innings i
),
islands AS (
    SELECT
        batter_id,
        rn_all - rn_grp AS island_key,
        COUNT(*)        AS streak_length,
        MIN(match_date) AS streak_start,
        MAX(match_date) AS streak_end,
        SUM(runs)       AS streak_runs
    FROM flagged
    WHERE is_good = 1
    GROUP BY batter_id, rn_all - rn_grp
)
SELECT
    p.player_name,
    s.streak_length AS consecutive_30plus_scores,
    s.streak_runs,
    ROUND(s.streak_runs::NUMERIC / s.streak_length, 1) AS avg_in_streak,
    s.streak_start,
    s.streak_end
FROM islands s
JOIN dim_player p ON p.player_id = s.batter_id
WHERE s.streak_length >= 3
ORDER BY s.streak_length DESC, s.streak_runs DESC
LIMIT 25;
