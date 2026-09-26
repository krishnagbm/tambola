-- =============================================================================
-- DabHousie Option-B Additive Migration: Memory Bingo Live TV Board Telemetry
-- Branch: memory-bingo (100% Isolated from 'main' 90-Ball Tambola tables)
-- =============================================================================

-- 1. Standalone Table for Per-Cycle Memory Recall & Live TV Leaderboard
CREATE TABLE IF NOT EXISTS public."MPT_memory_round_scores" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id UUID NOT NULL,
    display_name TEXT NOT NULL DEFAULT 'Player',
    avatar TEXT NOT NULL DEFAULT '🎉',
    cycle_index INT NOT NULL DEFAULT 1,          -- Round number (1..N)
    quadrant_label TEXT NOT NULL DEFAULT 'R1-Q1', -- e.g. 'R1-Q2', 'R2-Q1'
    correct_numbers INT[] NOT NULL DEFAULT '{}', -- Numbers recalled in this round
    correct_count INT NOT NULL DEFAULT 0,        -- Primary Round Winner metric
    wrong_tap_count INT NOT NULL DEFAULT 0,      -- 1st Tie-Breaker (fewest wrong/decoy taps)
    total_reaction_ms INT NOT NULL DEFAULT 0,    -- 2nd Tie-Breaker (fastest cumulative tap speed)
    last_recalled_number INT,                    -- For Live TV Board "Fastest Tap" ticker
    last_reaction_ms INT,                        -- Reaction speed on last recalled ball
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_memory_game_user_cycle UNIQUE (game_id, user_id, cycle_index)
);

-- 2. Performance Indexes for 1.5s Live TV Board Polling & Full House Aggregation
CREATE INDEX IF NOT EXISTS idx_mpt_memory_scores_game_cycle
    ON public."MPT_memory_round_scores" (game_id, cycle_index, correct_count DESC, wrong_tap_count ASC, total_reaction_ms ASC);

CREATE INDEX IF NOT EXISTS idx_mpt_memory_scores_game_user
    ON public."MPT_memory_round_scores" (game_id, user_id);

-- 3. Row Level Security (Public Read for Live TV Display, Authenticated Player Upsert)
ALTER TABLE public."MPT_memory_round_scores" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public read for Live TV Board" ON public."MPT_memory_round_scores";
CREATE POLICY "Allow public read for Live TV Board"
    ON public."MPT_memory_round_scores"
    FOR SELECT
    USING (true);

DROP POLICY IF EXISTS "Allow players to insert own cycle score" ON public."MPT_memory_round_scores";
CREATE POLICY "Allow players to insert own cycle score"
    ON public."MPT_memory_round_scores"
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Allow players to update own cycle score" ON public."MPT_memory_round_scores";
CREATE POLICY "Allow players to update own cycle score"
    ON public."MPT_memory_round_scores"
    FOR UPDATE
    USING (auth.uid() = user_id);
