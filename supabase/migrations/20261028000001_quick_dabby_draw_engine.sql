-- Migration: 20261028000001_quick_dabby_draw_engine.sql
-- Description: Upgrades MPT_call_next_number to support 'QUICK_DABBY' calling mode.
-- When calling_mode is 'QUICK_DABBY', the caller draws only from numbers
-- present on registered player tickets (union pool |U|), eliminating dead numbers.
-- When calling_mode is 'CLASSIC', it draws from 1..90 as standard.

CREATE OR REPLACE FUNCTION public."MPT_call_next_number"(
    p_game_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_is_service_role BOOLEAN;
    v_uid UUID;
    v_game public."MPT_games";
    v_next_num INT;
    v_next_seq INT;
    v_called_rec public."MPT_called_numbers";
    v_calling_mode TEXT;
BEGIN
    -- Determine caller authorization: allow service_role, postgres, or game organizer
    v_is_service_role := (
        COALESCE(auth.role(), '') = 'service_role' OR 
        COALESCE(auth.jwt() ->> 'role', '') = 'service_role' OR 
        current_user = 'postgres'
    );
    v_uid := auth.uid();

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND';
    END IF;

    -- If not service role, require authenticated user who owns the game
    IF NOT v_is_service_role THEN
        IF v_uid IS NULL THEN
            RAISE EXCEPTION 'AUTH_REQUIRED';
        END IF;

        IF v_game.admin_user_id <> v_uid THEN
            RAISE EXCEPTION 'NOT_AUTHORIZED: Only Admin or Autonomous Host can call numbers';
        END IF;
    END IF;

    -- If game is already concluded, return status gracefully
    IF v_game.status <> 'IN_PROGRESS' THEN
        RETURN jsonb_build_object(
            'game_completed', true,
            'status', v_game.status,
            'message', 'Game is not in progress'
        );
    END IF;

    -- Check if Full House has already been claimed and approved
    IF EXISTS (
        SELECT 1 FROM public."MPT_claims"
        WHERE game_id = p_game_id 
          AND prize_type = 'FULL_HOUSE' 
          AND status = 'APPROVED'
    ) THEN
        UPDATE public."MPT_games"
        SET status = 'COMPLETED',
            completed_at = COALESCE(completed_at, NOW()),
            state_version = state_version + 1,
            updated_at = NOW()
        WHERE id = p_game_id;

        RETURN jsonb_build_object(
            'game_completed', true,
            'status', 'COMPLETED',
            'message', 'Full House has been claimed and awarded! Game concluded.'
        );
    END IF;

    -- Extract Calling Mode from game configuration (default: CLASSIC)
    v_calling_mode := COALESCE(v_game.prize_gifts_config->>'_calling_mode', 'CLASSIC');

    IF v_calling_mode = 'QUICK_DABBY' THEN
        -- Select a random uncalled number that exists in registered player tickets
        SELECT (num_val)::INT INTO v_next_num
        FROM (
            SELECT DISTINCT (cell_val)::INT AS num_val
            FROM public."MPT_player_tickets" t,
            LATERAL jsonb_array_elements(t.ticket_matrix) AS row_arr,
            LATERAL jsonb_array_elements_text(row_arr) AS cell_val
            WHERE t.game_id = p_game_id
              AND cell_val ~ '^[0-9]+$'
              AND (cell_val)::INT > 0
        ) active_pool
        WHERE num_val NOT IN (
            SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id
        )
        ORDER BY RANDOM()
        LIMIT 1;

        -- Fallback if no player tickets generated yet: default to 1..90
        IF v_next_num IS NULL AND NOT EXISTS (SELECT 1 FROM public."MPT_player_tickets" WHERE game_id = p_game_id) THEN
            SELECT num INTO v_next_num
            FROM generate_series(1, 90) AS s(num)
            WHERE num NOT IN (
                SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id
            )
            ORDER BY RANDOM()
            LIMIT 1;
        END IF;
    ELSE
        -- Classic 1..90 draw pool
        SELECT num INTO v_next_num
        FROM generate_series(1, 90) AS s(num)
        WHERE num NOT IN (
            SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id
        )
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;

    -- If all numbers in active pool have been called, automatically conclude game
    IF v_next_num IS NULL THEN
        UPDATE public."MPT_games"
        SET status = 'COMPLETED',
            completed_at = NOW(),
            state_version = state_version + 1,
            updated_at = NOW()
        WHERE id = p_game_id;

        RETURN jsonb_build_object(
            'game_completed', true,
            'status', 'COMPLETED',
            'message', 'All numbers in active pool have been called! Game concluded.'
        );
    END IF;

    -- Determine next call sequence atomically
    SELECT COALESCE(MAX(call_seq), 0) + 1 INTO v_next_seq
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- Record the called number
    INSERT INTO public."MPT_called_numbers" (
        game_id, number, call_seq, called_at
    )
    VALUES (
        p_game_id, v_next_num, v_next_seq, NOW()
    )
    RETURNING * INTO v_called_rec;

    -- Update game heartbeat
    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'number', v_next_num,
        'call_seq', v_next_seq,
        'game_completed', false,
        'calling_mode', v_calling_mode
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

COMMENT ON FUNCTION public."MPT_call_next_number"(UUID) IS 
'Authoritative number caller with support for Quick Dabby (draws only from player ticket numbers) and Classic Calling (draws 1..90).';
