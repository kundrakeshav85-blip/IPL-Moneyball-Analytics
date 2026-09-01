/* =============================================================================
   02_load_and_transform.sql
   Purpose : Load raw CSVs into staging, resolve player names, populate the
             star schema.
   Engine  : PostgreSQL 14+

   Run order: 01_schema.sql -> THIS FILE -> 03_data_quality_checks.sql
   ============================================================================= */

-- -----------------------------------------------------------------------------
-- STEP 1: staging tables that mirror the raw CSVs exactly
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_matches, stg_deliveries, stg_auction, stg_player_attr;

CREATE TABLE stg_matches (
    id INT, season TEXT, city TEXT, date DATE, match_type TEXT,
    player_of_match TEXT, venue TEXT, team1 TEXT, team2 TEXT,
    toss_winner TEXT, toss_decision TEXT, winner TEXT, result TEXT,
    result_margin INT, target_runs INT, target_overs NUMERIC,
    super_over TEXT, method TEXT, umpire1 TEXT, umpire2 TEXT
);

CREATE TABLE stg_deliveries (
    match_id INT, inning SMALLINT, batting_team TEXT, bowling_team TEXT,
    over SMALLINT, ball SMALLINT, batter TEXT, bowler TEXT, non_striker TEXT,
    batsman_runs SMALLINT, extra_runs SMALLINT, total_runs SMALLINT,
    extras_type TEXT, is_wicket SMALLINT, player_dismissed TEXT,
    dismissal_kind TEXT, fielder TEXT
);

CREATE TABLE stg_auction (
    season INT, player_name TEXT, team TEXT,
    base_price_cr NUMERIC, final_price_cr NUMERIC, acquisition TEXT
);

CREATE TABLE stg_player_attr (
    player_name TEXT, batting_hand TEXT, bowling_style TEXT,
    primary_role TEXT, country TEXT
);

/* Load the CSVs. Adjust paths to your machine.
   \copy is a psql client command, so it works without superuser rights —
   unlike server-side COPY.

   \copy stg_matches      FROM 'data/raw/matches.csv'           CSV HEADER;
   \copy stg_deliveries   FROM 'data/raw/deliveries.csv'        CSV HEADER;
   \copy stg_auction      FROM 'data/raw/ipl_auction.csv'       CSV HEADER;
   \copy stg_player_attr  FROM 'data/raw/player_attributes.csv' CSV HEADER;
*/


-- -----------------------------------------------------------------------------
-- STEP 2: player name resolution
--
-- The single biggest data quality problem in IPL datasets. The same person
-- appears as "MS Dhoni", "M.S. Dhoni" and "MS Dhoni " across seasons and across
-- the delivery vs auction files. Left unresolved, one player's career splits
-- into three and every per-player metric is wrong.
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS player_name_map;
CREATE TABLE player_name_map (
    raw_name        TEXT PRIMARY KEY,
    canonical_name  TEXT NOT NULL
);

-- Normalisation function: strip punctuation, collapse whitespace, trim, title-case.
-- This catches most cases automatically; the remainder go in player_name_map by hand.
CREATE OR REPLACE FUNCTION normalise_name(p_name TEXT)
RETURNS TEXT AS $$
    SELECT INITCAP(
        TRIM(REGEXP_REPLACE(REGEXP_REPLACE(p_name, '[.\-'']', '', 'g'),
                            '\s+', ' ', 'g'))
    );
$$ LANGUAGE SQL IMMUTABLE;

-- Seed the map with every distinct raw name from all sources
INSERT INTO player_name_map (raw_name, canonical_name)
SELECT DISTINCT raw, normalise_name(raw)
FROM (
    SELECT batter          AS raw FROM stg_deliveries
    UNION SELECT bowler           FROM stg_deliveries
    UNION SELECT non_striker      FROM stg_deliveries
    UNION SELECT player_dismissed FROM stg_deliveries
    UNION SELECT fielder          FROM stg_deliveries
    UNION SELECT player_name      FROM stg_auction
    UNION SELECT player_name      FROM stg_player_attr
) all_names
WHERE raw IS NOT NULL AND TRIM(raw) <> ''
ON CONFLICT (raw_name) DO NOTHING;

/* Manual overrides for cases normalisation cannot catch — different
   abbreviations of the same person. Add rows here as you find them.

   UPDATE player_name_map SET canonical_name = 'Ms Dhoni'
   WHERE raw_name IN ('MSD', 'M Dhoni');
*/


-- -----------------------------------------------------------------------------
-- STEP 3: populate dim_player
-- -----------------------------------------------------------------------------
INSERT INTO dim_player (player_name)
SELECT DISTINCT canonical_name FROM player_name_map
ON CONFLICT (player_name) DO NOTHING;

UPDATE dim_player p
SET batting_hand  = a.batting_hand,
    bowling_style = a.bowling_style,
    primary_role  = a.primary_role,
    country       = a.country,
    is_overseas   = (a.country IS DISTINCT FROM 'India')
FROM stg_player_attr a
JOIN player_name_map m ON m.raw_name = a.player_name
WHERE p.player_name = m.canonical_name;

-- Roll individual bowling styles up into families.
-- Rationale: 8 individual styles fragment the matchup sample so badly that most
-- batter x style cells fall below the 50-ball threshold. 5 families keep it usable.
UPDATE dim_player
SET bowling_family = CASE
        WHEN bowling_style IN ('RF','RFM','RM','RMF') THEN 'Right Pace'
        WHEN bowling_style IN ('LF','LFM','LM','LMF') THEN 'Left Pace'
        WHEN bowling_style = 'OB'                     THEN 'Off Spin'
        WHEN bowling_style IN ('LB','LBG','LC')       THEN 'Leg Spin'
        WHEN bowling_style = 'SLA'                    THEN 'Left Arm Spin'
        ELSE NULL
    END;


-- -----------------------------------------------------------------------------
-- STEP 4: populate dim_venue, then derive venue_type from actual scores
-- -----------------------------------------------------------------------------
INSERT INTO dim_venue (venue_name, city)
SELECT DISTINCT TRIM(venue), TRIM(city)
FROM stg_matches
WHERE venue IS NOT NULL;

WITH first_innings AS (
    SELECT d.match_id, SUM(d.total_runs) AS score
    FROM stg_deliveries d
    WHERE d.inning = 1
    GROUP BY d.match_id
),
venue_avg AS (
    SELECT TRIM(m.venue) AS venue_name,
           AVG(f.score)  AS avg_score,
           COUNT(*)      AS n_matches
    FROM first_innings f
    JOIN stg_matches m ON m.id = f.match_id
    GROUP BY TRIM(m.venue)
)
UPDATE dim_venue v
SET avg_first_inn_score = ROUND(va.avg_score, 1),
    venue_type = CASE
        WHEN va.n_matches < 10     THEN 'Insufficient Data'
        WHEN va.avg_score >= 175   THEN 'High Scoring'
        WHEN va.avg_score <  155   THEN 'Bowler Friendly'
        ELSE 'Balanced'
    END
FROM venue_avg va
WHERE v.venue_name = va.venue_name;


-- -----------------------------------------------------------------------------
-- STEP 5: populate dim_match
-- -----------------------------------------------------------------------------
INSERT INTO dim_match (
    match_id, season, match_date, venue_id,
    team_bat_first, team_bat_second, toss_winner, toss_decision,
    winner, result_margin, target_runs, match_stage
)
SELECT
    m.id,
    -- season arrives as '2007/08' in some rows and '2020' in others
    CAST(LEFT(REGEXP_REPLACE(m.season, '[^0-9]', '', 'g'), 4) AS INT),
    m.date,
    v.venue_id,
    CASE WHEN m.toss_decision = 'bat'  THEN m.toss_winner
         ELSE CASE WHEN m.toss_winner = m.team1 THEN m.team2 ELSE m.team1 END END,
    CASE WHEN m.toss_decision = 'field' THEN m.toss_winner
         ELSE CASE WHEN m.toss_winner = m.team1 THEN m.team2 ELSE m.team1 END END,
    m.toss_winner,
    m.toss_decision,
    m.winner,
    m.result_margin,
    m.target_runs,
    CASE WHEN m.match_type ILIKE '%final%'  THEN 'Final'
         WHEN m.match_type ILIKE '%qualif%'
           OR m.match_type ILIKE '%elimin%' THEN 'Playoff'
         ELSE 'League' END
FROM stg_matches m
LEFT JOIN dim_venue v ON v.venue_name = TRIM(m.venue);


-- -----------------------------------------------------------------------------
-- STEP 6: populate fact_ball
-- -----------------------------------------------------------------------------
INSERT INTO fact_ball (
    match_id, inning, over_number, ball_number,
    batting_team, bowling_team,
    batter_id, bowler_id, non_striker_id,
    batsman_runs, extra_runs, total_runs, extra_type,
    is_wicket, dismissal_kind, player_out_id, fielder_id
)
SELECT
    d.match_id, d.inning,
    d.over + 1,          -- source is 0-indexed; the whole project uses 1..20
    d.ball,
    d.batting_team, d.bowling_team,
    pb.player_id, pw.player_id, pn.player_id,
    d.batsman_runs, d.extra_runs, d.total_runs,
    NULLIF(TRIM(d.extras_type), ''),
    d.is_wicket, NULLIF(TRIM(d.dismissal_kind), ''),
    pd.player_id, pf.player_id
FROM stg_deliveries d
LEFT JOIN player_name_map mb ON mb.raw_name = d.batter
LEFT JOIN dim_player      pb ON pb.player_name = mb.canonical_name
LEFT JOIN player_name_map mw ON mw.raw_name = d.bowler
LEFT JOIN dim_player      pw ON pw.player_name = mw.canonical_name
LEFT JOIN player_name_map mn ON mn.raw_name = d.non_striker
LEFT JOIN dim_player      pn ON pn.player_name = mn.canonical_name
LEFT JOIN player_name_map md ON md.raw_name = d.player_dismissed
LEFT JOIN dim_player      pd ON pd.player_name = md.canonical_name
LEFT JOIN player_name_map mf ON mf.raw_name = d.fielder
LEFT JOIN dim_player      pf ON pf.player_name = mf.canonical_name;


-- -----------------------------------------------------------------------------
-- STEP 7: populate fact_auction
-- -----------------------------------------------------------------------------
INSERT INTO fact_auction (season, player_id, team, base_price_cr,
                          final_price_cr, acquisition)
SELECT a.season, p.player_id, a.team, a.base_price_cr,
       a.final_price_cr, COALESCE(a.acquisition, 'Auction')
FROM stg_auction a
JOIN player_name_map m ON m.raw_name = a.player_name
JOIN dim_player      p ON p.player_name = m.canonical_name
ON CONFLICT (season, player_id) DO NOTHING;


-- -----------------------------------------------------------------------------
-- STEP 8: flag rain-affected matches
-- A full innings is 120 legal deliveries. Materially fewer means the match was
-- shortened. These are FLAGGED, not deleted: deleting them would bias the
-- dataset against players at high-rainfall venues.
-- -----------------------------------------------------------------------------
WITH innings_length AS (
    SELECT match_id, inning, COUNT(*) AS legal_balls
    FROM fact_ball
    WHERE extra_type IS NULL OR extra_type IN ('legbyes','byes')
    GROUP BY match_id, inning
)
UPDATE dim_match m
SET is_rain_affected = TRUE
WHERE EXISTS (
    SELECT 1 FROM innings_length il
    WHERE il.match_id = m.match_id AND il.legal_balls < 108   -- < 18 overs
);
