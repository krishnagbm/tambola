-- =====================================================================
-- Migration: 20260918000002_fix_claim_rls_and_rpc.sql
-- Description:
--   1. Fixes RLS policies for MPT_claims and MPT_rewards to allow players to submit claims.
--   2. Updates MPT_submit_claim RPC to accept JSONB marked_numbers, support CONFIRMED seats,
--      and properly validate all prize types (Early Five, Lines, Four Corners, Full House).
-- =====================================================================

-- 1. Add SELECT, INSERT, and UPDATE RLS Policies for MPT_claims (public read for room claims)
DROP POLICY IF EXISTS "MPT_claims_read" ON public."MPT_claims";
CREATE POLICY "MPT_claims_read"
ON public."MPT_claims"
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "MPT_claims_insert_self" ON public."MPT_claims";
CREATE POLICY "MPT_claims_insert_self"
ON public."MPT_claims"
FOR INSERT
WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "MPT_claims_update_self" ON public."MPT_claims";
CREATE POLICY "MPT_claims_update_self"
ON public."MPT_claims"
FOR UPDATE
USING (auth.uid() = user_id);

-- 2. Add SELECT and INSERT RLS Policies for MPT_rewards
DROP POLICY IF EXISTS "MPT_rewards_read" ON public."MPT_rewards";
CREATE POLICY "MPT_rewards_read"
ON public."MPT_rewards"
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "MPT_rewards_insert_self" ON public."MPT_rewards";
CREATE POLICY "MPT_rewards_insert_self"
ON public."MPT_rewards"
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 3. Recreate MPT_submit_claim with robust signature and validation
DROP FUNCTION IF EXISTS public."MPT_submit_claim"(UUID, TEXT, INT[], TEXT);
DROP FUNCTION IF EXISTS public."MPT_submit_claim"(UUID, TEXT, JSONB, TEXT);

CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_reg RECORD;
    v_ticket public."MPT_player_tickets";
    v_already_won BOOLEAN;
    v_is_valid BOOLEAN := FALSE;
    v_claim_id UUID;
    v_row1 INT[];
    v_row2 INT[];
    v_row3 INT[];
    v_called_numbers INT[];
    v_marked_list INT[] := ARRAY[]::INT[];
    v_early5_count INT := 0;
    v_row_count INT := 0;
    v_fh_count INT := 0;
    v_num INT;
    v_c1 INT;
    v_c2 INT;
    v_c3 INT;
    v_c4 INT;
    v_row1_non_zero INT[];
    v_row3_non_zero INT[];
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    -- Verify player is registered with an active seat (CONFIRMED or ELIGIBLE)
    SELECT * INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status NOT IN ('ELIGIBLE', 'CONFIRMED') THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: Player seat status is %', COALESCE(v_reg.seat_status, 'NOT_REGISTERED');
    END IF;

    -- Safely convert JSONB array to integer array
    IF p_marked_numbers IS NOT NULL AND jsonb_typeof(p_marked_numbers) = 'array' THEN
        SELECT ARRAY(
            SELECT jsonb_array_elements_text(p_marked_numbers)::INT
        ) INTO v_marked_list;
    END IF;

    -- Check if prize already claimed/approved
    SELECT EXISTS (
        SELECT 1 FROM public."MPT_claims"
        WHERE game_id = p_game_id AND prize_type = p_prize_type AND status = 'APPROVED'
    ) INTO v_already_won;

    IF v_already_won THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, rejection_reason, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'REJECTED',
            'Prize already won by another player', p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'REJECTED',
            'reason', 'Prize already won by another player'
        );
    END IF;

    -- Fetch player ticket
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NO_TICKET_FOUND: No ticket issued for player';
    END IF;

    -- Fetch all called numbers so far
    SELECT COALESCE(array_agg(number ORDER BY call_seq), ARRAY[]::INT[])
    INTO v_called_numbers
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- Extract ticket rows
    v_row1 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->0)::INT);
    v_row2 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->1)::INT);
    v_row3 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->2)::INT);

    -- 1. Strict Bogey Check: Make sure NO marked number is uncalled or not on ticket
    FOREACH v_num IN ARRAY v_marked_list LOOP
        IF NOT (v_num = ANY(v_called_numbers)) THEN
            INSERT INTO public."MPT_claims" (
                game_id, user_id, prize_type, marked_numbers, status, rejection_reason, idempotency_key
            )
            VALUES (
                p_game_id, v_uid, p_prize_type, p_marked_numbers, 'BOGEY',
                'Marked number ' || v_num || ' has not been called yet', p_idempotency_key
            )
            RETURNING id INTO v_claim_id;

            RETURN jsonb_build_object(
                'claim_id', v_claim_id,
                'status', 'BOGEY',
                'reason', 'Marked number ' || v_num || ' has not been called yet'
            );
        END IF;

        IF NOT (v_num = ANY(v_row1) OR v_num = ANY(v_row2) OR v_num = ANY(v_row3)) THEN
            INSERT INTO public."MPT_claims" (
                game_id, user_id, prize_type, marked_numbers, status, rejection_reason, idempotency_key
            )
            VALUES (
                p_game_id, v_uid, p_prize_type, p_marked_numbers, 'BOGEY',
                'Number ' || v_num || ' is not on your ticket', p_idempotency_key
            )
            RETURNING id INTO v_claim_id;

            RETURN jsonb_build_object(
                'claim_id', v_claim_id,
                'status', 'BOGEY',
                'reason', 'Number ' || v_num || ' is not on your ticket'
            );
        END IF;
    END LOOP;

    -- 2. Validate claim pattern
    IF p_prize_type = 'EARLY_FIVE' THEN
        v_early5_count := 0;
        FOREACH v_num IN ARRAY v_marked_list LOOP
            IF (v_num = ANY(v_row1) OR v_num = ANY(v_row2) OR v_num = ANY(v_row3))
               AND v_num = ANY(v_called_numbers) THEN
                v_early5_count := v_early5_count + 1;
            END IF;
        END LOOP;
        IF v_early5_count >= 5 AND array_length(v_marked_list, 1) = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'TOP_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row1 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(v_marked_list) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'MIDDLE_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row2 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(v_marked_list) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'BOTTOM_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row3 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(v_marked_list) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'FOUR_CORNERS' THEN
        SELECT array_agg(x) INTO v_row1_non_zero FROM unnest(v_row1) AS x WHERE x > 0;
        SELECT array_agg(x) INTO v_row3_non_zero FROM unnest(v_row3) AS x WHERE x > 0;
        
        IF array_length(v_row1_non_zero, 1) >= 2 AND array_length(v_row3_non_zero, 1) >= 2 THEN
            v_c1 := v_row1_non_zero[1];
            v_c2 := v_row1_non_zero[array_length(v_row1_non_zero, 1)];
            v_c3 := v_row3_non_zero[1];
            v_c4 := v_row3_non_zero[array_length(v_row3_non_zero, 1)];

            IF v_c1 = ANY(v_marked_list) AND v_c1 = ANY(v_called_numbers) AND
               v_c2 = ANY(v_marked_list) AND v_c2 = ANY(v_called_numbers) AND
               v_c3 = ANY(v_marked_list) AND v_c3 = ANY(v_called_numbers) AND
               v_c4 = ANY(v_marked_list) AND v_c4 = ANY(v_called_numbers) THEN
                v_is_valid := TRUE;
            END IF;
        END IF;

    ELSIF p_prize_type = 'FULL_HOUSE' THEN
        v_fh_count := 0;
        FOREACH v_num IN ARRAY (v_row1 || v_row2 || v_row3) LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(v_marked_list) AND v_num = ANY(v_called_numbers) THEN
                    v_fh_count := v_fh_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_fh_count = 15 THEN
            v_is_valid := TRUE;
        END IF;
    END IF;

    -- Record claim result
    IF v_is_valid THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'APPROVED', p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        -- Issue reward
        INSERT INTO public."MPT_rewards" (
            claim_id, user_id, game_id, prize_type, reward_title, reward_code, expires_at
        )
        VALUES (
            v_claim_id, v_uid, p_game_id, p_prize_type, p_prize_type || ' Winner',
            'DAB-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 8)),
            NOW() + INTERVAL '30 days'
        )
        ON CONFLICT (claim_id) DO NOTHING;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'APPROVED',
            'prize_type', p_prize_type,
            'claim_reference', 'DAB-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 8))
        );
    ELSE
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, rejection_reason, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'REJECTED',
            'Claim numbers pattern is incomplete or incorrect', p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'REJECTED',
            'reason', 'Claim numbers pattern is incomplete or incorrect'
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
