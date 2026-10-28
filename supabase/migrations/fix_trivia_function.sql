-- ==============================================================================
-- Fix: MPT_generate_game_trivia Table & Column Mappings
-- Run this in Supabase SQL Editor: https://supabase.com/dashboard/project/itfcnurjrnyalauwwdkj/sql/new
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
    -- A. Total Players & Names (from MPT_game_registrations)
    SELECT COUNT(*), array_agg(COALESCE(NULLIF(display_name, ''), 'Player ' || registration_seq))
    INTO v_total_players, v_player_names
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');
    
    IF v_total_players < 1 THEN
        v_total_players := COALESCE(v_game.funded_capacity, 5);
        v_player_names := ARRAY['Aarav', 'Priya', 'Rohan', 'Sneha', 'Neon Falcon'];
    END IF;

    -- B. Calls Data (from MPT_called_numbers)
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

    -- D. Claims Ground Truth (from MPT_claims & MPT_game_registrations)
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
        questions = CASE 
            WHEN "MPT_game_trivia_rounds".status = 'COMPLETED' OR "MPT_game_trivia_rounds".completed_at IS NOT NULL 
            THEN "MPT_game_trivia_rounds".questions 
            ELSE EXCLUDED.questions 
        END,
        status = CASE 
            WHEN "MPT_game_trivia_rounds".status = 'COMPLETED' OR "MPT_game_trivia_rounds".completed_at IS NOT NULL 
            THEN 'COMPLETED' 
            ELSE 'COUNTDOWN' 
        END,
        time_gap_seconds = EXCLUDED.time_gap_seconds,
        starts_at = CASE 
            WHEN "MPT_game_trivia_rounds".status = 'COMPLETED' OR "MPT_game_trivia_rounds".completed_at IS NOT NULL 
            THEN "MPT_game_trivia_rounds".starts_at 
            ELSE NOW() + (EXCLUDED.time_gap_seconds || ' seconds')::INTERVAL 
        END;

    RETURN jsonb_build_object(
        'success', true,
        'game_id', p_game_id,
        'question_count', jsonb_array_length(v_questions),
        'starts_at', NOW() + (v_time_gap || ' seconds')::INTERVAL
    );
END;
$$;

-- Enable Supabase Realtime for trivia tables
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_game_trivia_rounds";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_trivia_winners";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END $$;

-- Allow update on trivia rounds (for status, current_question_index)
DROP POLICY IF EXISTS "Public update trivia rounds" ON public."MPT_game_trivia_rounds";
CREATE POLICY "Public update trivia rounds" ON public."MPT_game_trivia_rounds" FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public delete trivia responses" ON public."MPT_trivia_responses";
CREATE POLICY "Public delete trivia responses" ON public."MPT_trivia_responses" FOR DELETE USING (true);

DROP POLICY IF EXISTS "Public delete trivia winners" ON public."MPT_trivia_winners";
CREATE POLICY "Public delete trivia winners" ON public."MPT_trivia_winners" FOR DELETE USING (true);

-- RPC Function to safely advance question index
CREATE OR REPLACE FUNCTION public."MPT_advance_trivia_question"(
    p_game_id UUID,
    p_next_index INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public."MPT_game_trivia_rounds"
    SET current_question_index = p_next_index,
        status = 'ACTIVE'
    WHERE game_id = p_game_id;

    RETURN jsonb_build_object('success', true, 'current_question_index', p_next_index);
END;
$$;

-- RPC Function to cleanly reset trivia round
CREATE OR REPLACE FUNCTION public."MPT_reset_game_trivia"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    DELETE FROM public."MPT_trivia_responses" WHERE game_id = p_game_id;
    DELETE FROM public."MPT_trivia_winners" WHERE game_id = p_game_id;
    UPDATE public."MPT_game_trivia_rounds"
    SET status = 'ACTIVE',
        current_question_index = 0,
        completed_at = null
    WHERE game_id = p_game_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

