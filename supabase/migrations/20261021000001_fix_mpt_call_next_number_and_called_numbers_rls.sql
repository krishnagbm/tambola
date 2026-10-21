-- Migration: 20261021000001_fix_mpt_call_next_number_and_called_numbers_rls.sql
-- Fixes:
-- 1. Corrects column name in MPT_call_next_number from "claim_type" to "prize_type" (MPT_claims schema).
-- 2. Ensures MPT_call_next_number runs with SECURITY DEFINER and search_path = public.
-- 3. Adds explicit INSERT RLS policy on MPT_called_numbers so organizers and service_role can record called numbers.

-- 1. Grant explicit INSERT policy on MPT_called_numbers for organizers & service role
DROP POLICY IF EXISTS "MPT_called_numbers_insert" ON public."MPT_called_numbers";
CREATE POLICY "MPT_called_numbers_insert" ON public."MPT_called_numbers"
FOR INSERT
WITH CHECK (
    auth.role() = 'service_role' OR
    current_user = 'postgres' OR
    EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_called_numbers".game_id
          AND g.admin_user_id = auth.uid()
    )
);

-- 2. Replace MPT_call_next_number with correct prize_type column check
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

    -- Check if Full House has already been claimed and approved (column is prize_type in MPT_claims)
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

    -- Select a random uncalled number between 1 and 90
    SELECT num INTO v_next_num
    FROM generate_series(1, 90) AS s(num)
    WHERE num NOT IN (
        SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id
    )
    ORDER BY RANDOM()
    LIMIT 1;

    -- If all 90 numbers called, automatically conclude game
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
            'message', 'All 90 numbers have been called'
        );
    END IF;

    -- Fetch next sequence number for the board
    SELECT COALESCE(MAX(call_seq), 0) + 1 INTO v_next_seq
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- Insert authoritative called number
    INSERT INTO public."MPT_called_numbers" (
        game_id,
        number,
        call_seq
    )
    VALUES (
        p_game_id,
        v_next_num,
        v_next_seq
    )
    RETURNING * INTO v_called_rec;

    -- Bump game state version so realtime/pollers immediately receive update
    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'number', v_next_num,
        'call_seq', v_next_seq,
        'called_at', v_called_rec.called_at,
        'game_completed', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
