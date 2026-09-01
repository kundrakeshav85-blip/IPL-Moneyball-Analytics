/* =============================================================================
   01_schema.sql
   Purpose : Create the star schema for the IPL Moneyball analytics project.
   Engine  : PostgreSQL 14+
   Author  : Keshav Kundra

   Design note
   -----------
   The raw Kaggle data arrives as two wide, denormalised CSVs. Analysing them
   directly is slow and unmaintainable: team, venue and date are repeated on all
   ~260,000 delivery rows. This script normalises them into a star schema —
   one central fact table (fact_ball) surrounded by conformed dimensions.

   Benefits:
     * join keys become narrow integers that index well
     * player attributes change in one row, not thousands
     * the model maps directly onto Power BI, which is built for star schemas
   ============================================================================= */

DROP TABLE IF EXISTS fact_auction CASCADE;
DROP TABLE IF EXISTS fact_ball    CASCADE;
DROP TABLE IF EXISTS dim_match    CASCADE;
DROP TABLE IF EXISTS dim_venue    CASCADE;
DROP TABLE IF EXISTS dim_player   CASCADE;


-- -----------------------------------------------------------------------------
-- DIMENSION: player
-- Role-playing dimension: joined three times to fact_ball (batter, bowler,
-- fielder). In Power BI, only the batter relationship is active; the others are
-- activated per-measure with USERELATIONSHIP.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_player (
    player_id       SERIAL PRIMARY KEY,
    player_name     TEXT NOT NULL UNIQUE,
    batting_hand    TEXT,        -- 'RHB' | 'LHB'
    bowling_style   TEXT,        -- 'RF','RFM','RM','OB','LB','LF','SLA','LC'
    bowling_family  TEXT,        -- 'Right Pace','Left Pace','Off Spin','Leg Spin','Left Arm Spin'
    primary_role    TEXT,        -- 'Batter','Bowler','All-rounder','Wicketkeeper'
    country         TEXT,
    is_overseas     BOOLEAN DEFAULT FALSE
);

COMMENT ON COLUMN dim_player.bowling_family IS
    'Coarser grouping of bowling_style. Used by the matchup engine: individual '
    'styles fragment the sample too much to be reliable.';


-- -----------------------------------------------------------------------------
-- DIMENSION: venue
-- avg_first_inn_score and venue_type are DERIVED from the data in
-- 02_load_and_transform.sql, not hand-entered. Hand-entering them would bake in
-- my own assumptions about which grounds are high-scoring.
-- -----------------------------------------------------------------------------
CREATE TABLE dim_venue (
    venue_id             SERIAL PRIMARY KEY,
    venue_name           TEXT NOT NULL,
    city                 TEXT,
    avg_first_inn_score  NUMERIC(5,1),
    venue_type           TEXT      -- 'High Scoring' | 'Balanced' | 'Bowler Friendly'
);


-- -----------------------------------------------------------------------------
-- DIMENSION: match
-- -----------------------------------------------------------------------------
CREATE TABLE dim_match (
    match_id         INT PRIMARY KEY,
    season           INT  NOT NULL,
    match_date       DATE NOT NULL,
    venue_id         INT REFERENCES dim_venue(venue_id),
    team_bat_first   TEXT,
    team_bat_second  TEXT,
    toss_winner      TEXT,
    toss_decision    TEXT,
    winner           TEXT,
    result_margin    INT,
    target_runs      INT,
    match_stage      TEXT DEFAULT 'League',  -- 'League' | 'Playoff' | 'Final'
    is_rain_affected BOOLEAN DEFAULT FALSE   -- see 03_data_quality_checks.sql
);


-- -----------------------------------------------------------------------------
-- FACT: ball
-- Grain: one row per delivery bowled. ~260,000 rows for 2008-2024.
-- -----------------------------------------------------------------------------
CREATE TABLE fact_ball (
    ball_id         BIGSERIAL PRIMARY KEY,
    match_id        INT      NOT NULL REFERENCES dim_match(match_id),
    inning          SMALLINT NOT NULL,
    over_number     SMALLINT NOT NULL,   -- 1..20 (1-indexed, see data/README.md)
    ball_number     SMALLINT NOT NULL,
    batting_team    TEXT,
    bowling_team    TEXT,
    batter_id       INT REFERENCES dim_player(player_id),
    bowler_id       INT REFERENCES dim_player(player_id),
    non_striker_id  INT REFERENCES dim_player(player_id),
    batsman_runs    SMALLINT NOT NULL DEFAULT 0,
    extra_runs      SMALLINT NOT NULL DEFAULT 0,
    total_runs      SMALLINT NOT NULL DEFAULT 0,
    extra_type      TEXT,                -- 'wides','noballs','legbyes','byes', NULL
    is_wicket       SMALLINT NOT NULL DEFAULT 0,
    dismissal_kind  TEXT,
    player_out_id   INT REFERENCES dim_player(player_id),
    fielder_id      INT REFERENCES dim_player(player_id)
);

COMMENT ON COLUMN fact_ball.extra_type IS
    'NULL for a normal delivery. Wides and no-balls do not count as balls faced '
    'by the batter, which is why every strike-rate calculation filters on this.';


-- -----------------------------------------------------------------------------
-- FACT: auction
-- Grain: one row per player per season signing.
-- -----------------------------------------------------------------------------
CREATE TABLE fact_auction (
    auction_id      SERIAL PRIMARY KEY,
    season          INT NOT NULL,
    player_id       INT REFERENCES dim_player(player_id),
    team            TEXT,
    base_price_cr   NUMERIC(6,2),
    final_price_cr  NUMERIC(6,2),
    acquisition     TEXT,      -- 'Auction' | 'Retained' | 'RTM' | 'Replacement'
    UNIQUE (season, player_id)
);
