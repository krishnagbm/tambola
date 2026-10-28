-- ==============================================================================
-- Migration: Corporate Post-Game Recall Trivia & Winners Consolidation Engine
-- Purpose:
--   1. Extensible tables for Trivia categories and dynamic question templates
--   2. Live trivia round storage with 1 random question per category
--   3. Kahoot-style player response capture with accuracy + speed scoring
--   4. Autonomous / scheduled trivia generator and prize finalization
-- ==============================================================================

-- 1. Trivia Question Templates (Categories & Dynamic Formulas)
CREATE TABLE IF NOT EXISTS public."MPT_trivia_question_templates" (
    id TEXT PRIMARY KEY,
    category TEXT NOT NULL,
    category_display_name TEXT NOT NULL,
    title TEXT NOT NULL,
    question_template TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Seed Initial Categories & Question Templates
INSERT INTO public."MPT_trivia_question_templates" (id, category, category_display_name, title, question_template, is_active)
VALUES
    -- Category 1: Social & Winner Observation
    ('WHO_WON_FIRST_PRIZE', 'WINNERS_OBSERVATION', 'Social & Winner Recall', 'First Prize Winner', 'Which player claimed the very first prize in today''s game?', true),
    ('WHO_WON_TOP_LINE', 'WINNERS_OBSERVATION', 'Social & Winner Recall', 'Top Line Winner', 'Who successfully claimed the Top Line prize?', true),
    ('WHO_WON_FULL_HOUSE', 'WINNERS_OBSERVATION', 'Social & Winner Recall', 'Full House Champion', 'Which player hit the winning Full House?', true),
    ('DISTINCT_WINNERS_COUNT', 'WINNERS_OBSERVATION', 'Social & Winner Recall', 'Distinct Winners', 'How many distinct players won prizes in this game?', true),

    -- Category 2: Numbers & Draw Milestones
    ('CALL_NUMBER_EARLY_FIVE', 'NUMBERS_RECALL', 'Numbers & Milestones', 'Early-5 Draw Number', 'On which drawn number was Early-5 (Jaldi 5) claimed?', true),
    ('FIRST_NUMBER_CALLED', 'NUMBERS_RECALL', 'Numbers & Milestones', 'First Drawn Number', 'What was the very first number called by Dabby today?', true),
    ('LAST_NUMBER_CALLED', 'NUMBERS_RECALL', 'Numbers & Milestones', 'Winning Full House Number', 'What was the final number drawn that completed Full House?', true),

    -- Category 3: Room & Participation Stats
    ('TOTAL_PLAYERS_JOINED', 'GAME_STATS', 'Game Room Stats', 'Total Attendance', 'How many total players checked into the game room today?', true),
    ('TOTAL_CALLS_DRAWN', 'GAME_STATS', 'Game Room Stats', 'Total Calls', 'How many total numbers were called before the game concluded?', true),

    -- Category 4: Pacing & Pattern Sequence
    ('FIRST_PRIZE_PATTERN', 'TIME_PACING', 'Pacing & Sequence', 'First Pattern Won', 'Which prize pattern was claimed first in the room?', true),
    ('APPROX_GAME_DURATION', 'TIME_PACING', 'Pacing & Sequence', 'Game Duration', 'Approximately how many minutes did today''s Tambola game take?', true)
ON CONFLICT (id) DO UPDATE SET
    category = EXCLUDED.category,
    category_display_name = EXCLUDED.category_display_name,
    title = EXCLUDED.title,
    question_template = EXCLUDED.question_template,
    is_active = EXCLUDED.is_active;

-- 2. Live Game Trivia Round
CREATE TABLE IF NOT EXISTS public."MPT_game_trivia_rounds" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    questions JSONB NOT NULL DEFAULT '[]'::jsonb,
    status TEXT NOT NULL DEFAULT 'PENDING', -- PENDING, COUNTDOWN, ACTIVE, COMPLETED
    time_gap_seconds INT NOT NULL DEFAULT 15,
    seconds_per_question INT NOT NULL DEFAULT 15,
    current_question_index INT NOT NULL DEFAULT 0,
    starts_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_game_trivia_round UNIQUE (game_id)
);

-- 3. Player Trivia Responses & Scoring
CREATE TABLE IF NOT EXISTS public."MPT_trivia_responses" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    user_name TEXT,
    user_avatar TEXT,
    question_index INT NOT NULL,
    selected_option_index INT NOT NULL,
    is_correct BOOLEAN NOT NULL,
    response_time_ms INT NOT NULL,
    score_points INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_question_response UNIQUE (game_id, user_id, question_index)
);

-- 4. Trivia Winners & Podium
CREATE TABLE IF NOT EXISTS public."MPT_trivia_winners" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    user_name TEXT NOT NULL,
    user_avatar TEXT,
    rank INT NOT NULL, -- 1, 2, 3
    total_score INT NOT NULL,
    correct_count INT NOT NULL,
    avg_response_time_ms INT NOT NULL,
    title TEXT NOT NULL, -- 'Observation Champion 🥇', 'Recall Runner-Up 🥈', 'Focus Master 🥉'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_game_trivia_rank UNIQUE (game_id, rank)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_mpt_trivia_rounds_game_id ON public."MPT_game_trivia_rounds"(game_id);
CREATE INDEX IF NOT EXISTS idx_mpt_trivia_responses_game_user ON public."MPT_trivia_responses"(game_id, user_id);
CREATE INDEX IF NOT EXISTS idx_mpt_trivia_winners_game_id ON public."MPT_trivia_winners"(game_id);

-- Enable RLS
ALTER TABLE public."MPT_trivia_question_templates" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_game_trivia_rounds" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_trivia_responses" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_trivia_winners" ENABLE ROW LEVEL SECURITY;

-- Read policies
DROP POLICY IF EXISTS "Public read trivia templates" ON public."MPT_trivia_question_templates";
CREATE POLICY "Public read trivia templates" ON public."MPT_trivia_question_templates" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read trivia rounds" ON public."MPT_game_trivia_rounds";
CREATE POLICY "Public read trivia rounds" ON public."MPT_game_trivia_rounds" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public read trivia responses" ON public."MPT_trivia_responses";
CREATE POLICY "Public read trivia responses" ON public."MPT_trivia_responses" FOR SELECT USING (true);

DROP POLICY IF EXISTS "Public insert trivia responses" ON public."MPT_trivia_responses";
CREATE POLICY "Public insert trivia responses" ON public."MPT_trivia_responses" FOR INSERT WITH CHECK (true);

DROP POLICY IF EXISTS "Public read trivia winners" ON public."MPT_trivia_winners";
CREATE POLICY "Public read trivia winners" ON public."MPT_trivia_winners" FOR SELECT USING (true);


-- ==============================================================================
-- 5. RPC Function: MPT_generate_game_trivia
-- Dynamically constructs 1 question per category with ground-truth answer + smart distractors
-- ==============================================================================
CREATE OR REPLACE FUNCTION public."MPT_generate_game_trivia"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_game RECORD;
    v_total_players INT := 0;
    v_total_calls INT := 0;
    v_first_call INT := 0;
    v_last_call INT := 0;
    v_duration_min INT := 5;
    v_first_claim RECORD;
    v_fh_claim RECORD;
    v_top_claim RECORD;
    v_early5_claim RECORD;
    v_distinct_winners INT := 0;
    v_player_names TEXT[];
    v_categories TEXT[];
    v_category TEXT;
    v_template RECORD;
    v_questions JSONB := '[]'::jsonb;
    v_q_obj JSONB;
    v_options TEXT[];
    v_correct_answer TEXT;
    v_correct_idx INT;
    v_time_gap INT := 15;
    v_trivia_cfg JSONB;
BEGIN
    -- 1. Fetch Game Record
    SELECT * INTO v_game FROM public."MPT_games" WHERE id = p_game_id;
    IF v_game IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Game not found');
    END IF;

    -- Extract config
    v_trivia_cfg := COALESCE(v_game.prize_gifts_config->'_post_game_trivia', '{}'::jsonb);
    IF (v_trivia_cfg->>'time_gap_seconds') IS NOT NULL THEN
        v_time_gap := (v_trivia_cfg->>'time_gap_seconds')::INT;
    END IF;

    -- 2. Gather Ground Truth Data
    -- A. Total Players & Names
    SELECT COUNT(*), array_agg(COALESCE(NULLIF(display_name, ''), 'Player ' || registration_seq))
    INTO v_total_players, v_player_names
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');
    
    IF v_total_players < 1 THEN
        v_total_players := COALESCE(v_game.funded_capacity, 5);
        v_player_names := ARRAY['Aarav', 'Priya', 'Rohan', 'Sneha', 'Neon Falcon'];
    END IF;

    -- B. Calls Data
    SELECT COUNT(*), 
           COALESCE((SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id ORDER BY call_seq ASC LIMIT 1), 17),
           COALESCE((SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id ORDER BY call_seq DESC LIMIT 1), 90)
    INTO v_total_calls, v_first_call, v_last_call
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;
    
    IF v_total_calls < 1 THEN
        v_total_calls := 52;
    END IF;

    -- C. Game Duration
    IF v_game.started_at IS NOT NULL AND v_game.completed_at IS NOT NULL THEN
        v_duration_min := GREATEST(1, ROUND(EXTRACT(EPOCH FROM (v_game.completed_at - v_game.started_at)) / 60.0)::INT);
    ELSE
        v_duration_min := 8;
    END IF;

    -- D. Claims Ground Truth
    -- First Claim
    SELECT prize_type, 
           CASE 
               WHEN marked_numbers IS NOT NULL AND jsonb_typeof(marked_numbers) = 'array' AND jsonb_array_length(marked_numbers) > 0 
               THEN (marked_numbers->>-1)::INT 
               ELSE 24 
           END as call_number,
           user_id, 
           COALESCE((SELECT display_name FROM public."MPT_game_registrations" p WHERE p.game_id = p_game_id AND p.user_id = c.user_id LIMIT 1), 'Player') as winner_name
    INTO v_first_claim
    FROM public."MPT_claims" c
    WHERE game_id = p_game_id AND status = 'APPROVED'
    ORDER BY submitted_at ASC LIMIT 1;

    -- Full House Claim
    SELECT prize_type, 
           CASE 
               WHEN marked_numbers IS NOT NULL AND jsonb_typeof(marked_numbers) = 'array' AND jsonb_array_length(marked_numbers) > 0 
               THEN (marked_numbers->>-1)::INT 
               ELSE 90 
           END as call_number,
           user_id,
           COALESCE((SELECT display_name FROM public."MPT_game_registrations" p WHERE p.game_id = p_game_id AND p.user_id = c.user_id LIMIT 1), 'Champion') as winner_name
    INTO v_fh_claim
    FROM public."MPT_claims" c
    WHERE game_id = p_game_id AND status = 'APPROVED' AND prize_type IN ('FULL_HOUSE', 'SECOND_FULL_HOUSE')
    ORDER BY submitted_at ASC LIMIT 1;

    -- Top Line Claim
    SELECT prize_type, 
           CASE 
               WHEN marked_numbers IS NOT NULL AND jsonb_typeof(marked_numbers) = 'array' AND jsonb_array_length(marked_numbers) > 0 
               THEN (marked_numbers->>-1)::INT 
               ELSE 56 
           END as call_number,
           user_id,
           COALESCE((SELECT display_name FROM public."MPT_game_registrations" p WHERE p.game_id = p_game_id AND p.user_id = c.user_id LIMIT 1), 'Player') as winner_name
    INTO v_top_claim
    FROM public."MPT_claims" c
    WHERE game_id = p_game_id AND status = 'APPROVED' AND prize_type = 'TOP_LINE'
    LIMIT 1;

    -- Early 5 Claim
    SELECT prize_type, 
           CASE 
               WHEN marked_numbers IS NOT NULL AND jsonb_typeof(marked_numbers) = 'array' AND jsonb_array_length(marked_numbers) > 0 
               THEN (marked_numbers->>-1)::INT 
               ELSE 18 
           END as call_number,
           user_id,
           COALESCE((SELECT display_name FROM public."MPT_game_registrations" p WHERE p.game_id = p_game_id AND p.user_id = c.user_id LIMIT 1), 'Player') as winner_name
    INTO v_early5_claim
    FROM public."MPT_claims" c
    WHERE game_id = p_game_id AND status = 'APPROVED' AND prize_type = 'EARLY_FIVE'
    LIMIT 1;

    -- Distinct Winners Count
    SELECT COUNT(DISTINCT user_id) INTO v_distinct_winners
    FROM public."MPT_claims"
    WHERE game_id = p_game_id AND status = 'APPROVED';
    IF v_distinct_winners < 1 THEN v_distinct_winners := 3; END IF;

    -- 3. Loop over distinct active categories
    SELECT array_agg(DISTINCT category) INTO v_categories
    FROM public."MPT_trivia_question_templates"
    WHERE is_active = true;

    FOREACH v_category IN ARRAY v_categories
    LOOP
        -- Pick 1 random question template from this category
        SELECT * INTO v_template
        FROM public."MPT_trivia_question_templates"
        WHERE category = v_category AND is_active = true
        ORDER BY random() LIMIT 1;

        IF v_template IS NOT NULL THEN
            v_options := ARRAY[]::TEXT[];
            v_correct_answer := '';

            -- Synthesize Question Ground Truth + Distractors
            CASE v_template.id
                WHEN 'WHO_WON_FIRST_PRIZE' THEN
                    v_correct_answer := COALESCE(v_first_claim.winner_name, 'Aarav');
                    v_options := ARRAY[
                        v_correct_answer,
                        COALESCE(v_player_names[1], 'Game Tiger'),
                        COALESCE(v_player_names[2], 'Priya'),
                        COALESCE(v_player_names[3], 'Groovy Dancer')
                    ];

                WHEN 'WHO_WON_TOP_LINE' THEN
                    v_correct_answer := COALESCE(v_top_claim.winner_name, v_player_names[1], 'Priya');
                    v_options := ARRAY[
                        v_correct_answer,
                        COALESCE(v_player_names[2], 'Liam'),
                        COALESCE(v_player_names[3], 'Aarav'),
                        COALESCE(v_player_names[4], 'Game Tiger')
                    ];

                WHEN 'WHO_WON_FULL_HOUSE' THEN
                    v_correct_answer := COALESCE(v_fh_claim.winner_name, v_player_names[1], 'Champion Player');
                    v_options := ARRAY[
                        v_correct_answer,
                        COALESCE(v_player_names[2], 'Rohan'),
                        COALESCE(v_player_names[3], 'Priya'),
                        COALESCE(v_player_names[4], 'Aarav')
                    ];

                WHEN 'DISTINCT_WINNERS_COUNT' THEN
                    v_correct_answer := v_distinct_winners::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        GREATEST(1, v_distinct_winners - 1)::TEXT,
                        (v_distinct_winners + 1)::TEXT,
                        (v_distinct_winners + 2)::TEXT
                    ];

                WHEN 'CALL_NUMBER_EARLY_FIVE' THEN
                    v_correct_answer := COALESCE(v_early5_claim.call_number, 24)::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        (COALESCE(v_early5_claim.call_number, 24) - 6)::TEXT,
                        (COALESCE(v_early5_claim.call_number, 24) + 7)::TEXT,
                        (COALESCE(v_early5_claim.call_number, 24) + 14)::TEXT
                    ];

                WHEN 'FIRST_NUMBER_CALLED' THEN
                    v_correct_answer := v_first_call::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        ((v_first_call + 11) % 90 + 1)::TEXT,
                        ((v_first_call + 27) % 90 + 1)::TEXT,
                        ((v_first_call + 45) % 90 + 1)::TEXT
                    ];

                WHEN 'LAST_NUMBER_CALLED' THEN
                    v_correct_answer := v_last_call::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        ((v_last_call + 5) % 90 + 1)::TEXT,
                        ((v_last_call + 19) % 90 + 1)::TEXT,
                        ((v_last_call + 33) % 90 + 1)::TEXT
                    ];

                WHEN 'TOTAL_PLAYERS_JOINED' THEN
                    v_correct_answer := v_total_players::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        GREATEST(1, v_total_players - 2)::TEXT,
                        (v_total_players + 3)::TEXT,
                        (v_total_players + 5)::TEXT
                    ];

                WHEN 'TOTAL_CALLS_DRAWN' THEN
                    v_correct_answer := v_total_calls::TEXT;
                    v_options := ARRAY[
                        v_correct_answer,
                        (v_total_calls - 8)::TEXT,
                        (v_total_calls + 7)::TEXT,
                        (v_total_calls + 15)::TEXT
                    ];

                WHEN 'FIRST_PRIZE_PATTERN' THEN
                    v_correct_answer := REPLACE(COALESCE(v_first_claim.prize_type, 'EARLY_FIVE'), '_', ' ');
                    v_options := ARRAY[
                        v_correct_answer,
                        'TOP LINE',
                        'FOUR CORNERS',
                        'MIDDLE LINE'
                    ];

                WHEN 'APPROX_GAME_DURATION' THEN
                    v_correct_answer := v_duration_min::TEXT || ' minutes';
                    v_options := ARRAY[
                        v_correct_answer,
                        GREATEST(2, v_duration_min - 4)::TEXT || ' minutes',
                        (v_duration_min + 5)::TEXT || ' minutes',
                        (v_duration_min + 10)::TEXT || ' minutes'
                    ];

                ELSE
                    v_correct_answer := v_total_players::TEXT;
                    v_options := ARRAY[v_correct_answer, '4', '8', '12'];
            END CASE;

            -- Deduplicate and Shuffle options
            SELECT array_agg(opt ORDER BY random())
            INTO v_options
            FROM (SELECT DISTINCT unnest(v_options) as opt) sub;

            -- Find correct index (0-based)
            FOR i IN 1..array_length(v_options, 1) LOOP
                IF v_options[i] = v_correct_answer THEN
                    v_correct_idx := i - 1;
                    EXIT;
                END IF;
            END LOOP;

            -- Build Question Object
            v_q_obj := jsonb_build_object(
                'id', v_template.id,
                'category', v_template.category,
                'category_name', v_template.category_display_name,
                'question', v_template.question_template,
                'options', to_jsonb(v_options),
                'correct_index', v_correct_idx,
                'correct_answer', v_correct_answer
            );

            v_questions := v_questions || v_q_obj;
        END IF;
    END LOOP;

    -- 4. Upsert into MPT_game_trivia_rounds
    INSERT INTO public."MPT_game_trivia_rounds" (
        game_id,
        questions,
        status,
        time_gap_seconds,
        seconds_per_question,
        starts_at
    )
    VALUES (
        p_game_id,
        v_questions,
        'COUNTDOWN',
        v_time_gap,
        15,
        NOW() + (v_time_gap || ' seconds')::INTERVAL
    )
    ON CONFLICT (game_id) DO UPDATE SET
        questions = EXCLUDED.questions,
        status = 'COUNTDOWN',
        time_gap_seconds = EXCLUDED.time_gap_seconds,
        starts_at = NOW() + (EXCLUDED.time_gap_seconds || ' seconds')::INTERVAL;

    RETURN jsonb_build_object(
        'success', true,
        'game_id', p_game_id,
        'question_count', jsonb_array_length(v_questions),
        'starts_at', NOW() + (v_time_gap || ' seconds')::INTERVAL
    );
END;
$$;


-- ==============================================================================
-- 6. RPC Function: MPT_submit_trivia_answer (Kahoot-Style Scoring)
-- Formula: 500 base + 500 * ((max_ms - response_ms) / max_ms) if correct, else 0
-- ==============================================================================
CREATE OR REPLACE FUNCTION public."MPT_submit_trivia_answer"(
    p_game_id UUID,
    p_user_id TEXT,
    p_user_name TEXT,
    p_user_avatar TEXT,
    p_question_index INT,
    p_selected_option INT,
    p_response_time_ms INT,
    p_max_time_ms INT DEFAULT 15000
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_round RECORD;
    v_target_q JSONB;
    v_correct_idx INT;
    v_is_correct BOOLEAN := false;
    v_score INT := 0;
    v_speed_ratio NUMERIC;
BEGIN
    -- Fetch Trivia Round
    SELECT * INTO v_round FROM public."MPT_game_trivia_rounds" WHERE game_id = p_game_id;
    IF v_round IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No active trivia round for this game');
    END IF;

    -- Get Question
    v_target_q := v_round.questions->p_question_index;
    IF v_target_q IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid question index');
    END IF;

    v_correct_idx := (v_target_q->>'correct_index')::INT;
    IF p_selected_option = v_correct_idx THEN
        v_is_correct := true;
        -- Speed decay: full 500 bonus at 0ms, linearly decreasing to 0 at max_time
        v_speed_ratio := GREATEST(0.0, LEAST(1.0, (p_max_time_ms - p_response_time_ms)::NUMERIC / p_max_time_ms::NUMERIC));
        v_score := 500 + ROUND(500 * v_speed_ratio)::INT;
    ELSE
        v_is_correct := false;
        v_score := 0;
    END IF;

    -- Upsert Response
    INSERT INTO public."MPT_trivia_responses" (
        game_id,
        user_id,
        user_name,
        user_avatar,
        question_index,
        selected_option_index,
        is_correct,
        response_time_ms,
        score_points
    )
    VALUES (
        p_game_id,
        p_user_id,
        COALESCE(p_user_name, 'Player'),
        p_user_avatar,
        p_question_index,
        p_selected_option,
        v_is_correct,
        p_response_time_ms,
        v_score
    )
    ON CONFLICT (game_id, user_id, question_index) DO UPDATE SET
        selected_option_index = EXCLUDED.selected_option_index,
        is_correct = EXCLUDED.is_correct,
        response_time_ms = EXCLUDED.response_time_ms,
        score_points = EXCLUDED.score_points;

    RETURN jsonb_build_object(
        'success', true,
        'is_correct', v_is_correct,
        'points_awarded', v_score,
        'correct_index', v_correct_idx
    );
END;
$$;


-- ==============================================================================
-- 7. RPC Function: MPT_finalize_game_trivia (Crowns Top 3 Podium)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public."MPT_finalize_game_trivia"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_titles TEXT[] := ARRAY['Observation Champion 🥇', 'Recall Runner-Up 🥈', 'Focus Master 🥉'];
    v_rank INT := 1;
    v_row RECORD;
    v_winners JSONB := '[]'::jsonb;
BEGIN
    -- Clear previous winners if re-finalizing
    DELETE FROM public."MPT_trivia_winners" WHERE game_id = p_game_id;

    -- Aggregate Leaderboard
    FOR v_row IN
        SELECT 
            user_id,
            COALESCE(MAX(user_name), 'Player') as user_name,
            MAX(user_avatar) as user_avatar,
            SUM(score_points) as total_score,
            COUNT(*) FILTER (WHERE is_correct = true) as correct_count,
            ROUND(AVG(response_time_ms))::INT as avg_time_ms
        FROM public."MPT_trivia_responses"
        WHERE game_id = p_game_id
        GROUP BY user_id
        ORDER BY total_score DESC, avg_time_ms ASC
        LIMIT 3
    LOOP
        INSERT INTO public."MPT_trivia_winners" (
            game_id,
            user_id,
            user_name,
            user_avatar,
            rank,
            total_score,
            correct_count,
            avg_response_time_ms,
            title
        )
        VALUES (
            p_game_id,
            v_row.user_id,
            v_row.user_name,
            v_row.user_avatar,
            v_rank,
            v_row.total_score,
            v_row.correct_count,
            v_row.avg_time_ms,
            v_titles[v_rank]
        );

        v_winners := v_winners || jsonb_build_object(
            'rank', v_rank,
            'title', v_titles[v_rank],
            'user_name', v_row.user_name,
            'total_score', v_row.total_score,
            'correct_count', v_row.correct_count
        );

        v_rank := v_rank + 1;
    END LOOP;

    -- Mark trivia round as COMPLETED
    UPDATE public."MPT_game_trivia_rounds"
    SET status = 'COMPLETED', completed_at = NOW()
    WHERE game_id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'winners', v_winners
    );
END;
$$;


-- ==============================================================================
-- 8. Trigger: Auto-generate trivia upon game completion if enabled
-- ==============================================================================
CREATE OR REPLACE FUNCTION public."MPT_on_game_completed_trigger"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF NEW.status = 'COMPLETED' AND (OLD.status IS NULL OR OLD.status <> 'COMPLETED') THEN
        IF COALESCE((NEW.prize_gifts_config->'_post_game_trivia'->>'enabled')::BOOLEAN, false) IS TRUE THEN
            PERFORM public."MPT_generate_game_trivia"(NEW.id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mpt_game_completed_trivia ON public."MPT_games";
CREATE TRIGGER trg_mpt_game_completed_trivia
AFTER UPDATE OF status ON public."MPT_games"
FOR EACH ROW
EXECUTE FUNCTION public."MPT_on_game_completed_trigger"();

