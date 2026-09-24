-- =====================================================================
-- Migration: 20260924000001_update_reward_token_prefix.sql
-- Description: Update reward voucher reference generation to Dab-Housie-XXXX-XXXX
--              and enable case-insensitive reward verification.
-- =====================================================================

-- Ensure MPT_rewards has required columns
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS reward_code TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS reward_title TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Recreate MPT_submit_claim with Dab-Housie- branding and robust reward creation
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
    v_claim_ref TEXT;
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
    v_row1_non_zero INT[] := ARRAY[]::INT[];
    v_row3_non_zero INT[] := ARRAY[]::INT[];
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: You must be logged in to claim a prize';
    END IF;

    -- Verify player is registered and has an active seat in this game
    SELECT * INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status NOT IN ('CONFIRMED', 'ELIGIBLE') THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: You do not have an active confirmed seat in this game';
    END IF;

    -- Check if prize was already won by someone else
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
            'Prize has already been claimed and approved for another player', p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'REJECTED',
            'reason', 'Prize has already been claimed by another player'
        );
    END IF;

    -- Fetch called numbers so far
    SELECT COALESCE(ARRAY_AGG(number ORDER BY call_seq ASC), ARRAY[]::INT[])
    INTO v_called_numbers
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- Fetch player ticket
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TICKET_NOT_FOUND: No ticket found for this player';
    END IF;

    -- Extract ticket rows from 3x9 JSONB ticket_matrix
    v_row1 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->0)::INT);
    v_row2 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->1)::INT);
    v_row3 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->2)::INT);

    -- Convert JSONB marked numbers array to INT[]
    IF p_marked_numbers IS NOT NULL AND jsonb_typeof(p_marked_numbers) = 'array' THEN
        SELECT ARRAY(
            SELECT jsonb_array_elements_text(p_marked_numbers)::INT
        ) INTO v_marked_list;
    END IF;

    -- Validate that all marked numbers have actually been called and are on ticket
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

    -- Validate claim pattern
    IF p_prize_type = 'EARLY_FIVE' THEN
        v_early5_count := 0;
        FOREACH v_num IN ARRAY v_marked_list LOOP
            IF (v_num = ANY(v_row1) OR v_num = ANY(v_row2) OR v_num = ANY(v_row3))
               AND v_num = ANY(v_called_numbers) THEN
                v_early5_count := v_early5_count + 1;
            END IF;
        END LOOP;
        IF v_early5_count >= 5 THEN
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
        v_row1_non_zero := ARRAY[]::INT[];
        v_row3_non_zero := ARRAY[]::INT[];
        FOREACH v_num IN ARRAY v_row1 LOOP
            IF v_num > 0 THEN v_row1_non_zero := array_append(v_row1_non_zero, v_num); END IF;
        END LOOP;
        FOREACH v_num IN ARRAY v_row3 LOOP
            IF v_num > 0 THEN v_row3_non_zero := array_append(v_row3_non_zero, v_num); END IF;
        END LOOP;
        
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

    ELSIF p_prize_type IN ('FULL_HOUSE', 'SECOND_FULL_HOUSE') THEN
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
            game_id, user_id, prize_type, marked_numbers, status, idempotency_key, processed_at
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'APPROVED', p_idempotency_key, NOW()
        )
        RETURNING id INTO v_claim_id;

        -- Generate unique branded reference code (e.g. Dab-Housie-8F3K-2B9D)
        v_claim_ref := 'Dab-Housie-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT) FROM 1 FOR 4))
                      || '-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || v_claim_id::TEXT) FROM 1 FOR 4));

        -- Issue reward voucher
        INSERT INTO public."MPT_rewards" (
            claim_id, user_id, game_id, prize_type, claim_reference, reward_code, reward_title, status, expires_at
        )
        VALUES (
            v_claim_id, v_uid, p_game_id, p_prize_type, v_claim_ref, v_claim_ref, p_prize_type || ' Winner',
            'AVAILABLE_TO_CLAIM', NOW() + INTERVAL '30 days'
        )
        ON CONFLICT (claim_reference) DO NOTHING;

        -- Winner in-app notification
        INSERT INTO public."MPT_notifications" (
            user_id, game_id, type, title, message, payload
        )
        VALUES (
            v_uid, p_game_id, 'REWARD_ISSUED',
            'Congratulations! You Won! 🏆',
            'Your claim for ' || REPLACE(p_prize_type, '_', ' ') || ' was approved! Show voucher ' || v_claim_ref || ' to claim your prize.',
            jsonb_build_object('claim_reference', v_claim_ref, 'prize_type', p_prize_type)
        );

        UPDATE public."MPT_games"
        SET state_version = state_version + 1,
            updated_at = NOW()
        WHERE id = p_game_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'APPROVED',
            'prize_type', p_prize_type,
            'claim_reference', v_claim_ref
        );
    ELSE
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, rejection_reason, idempotency_key, processed_at
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'REJECTED',
            'Claim numbers pattern is incomplete or incorrect', p_idempotency_key, NOW()
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


-- Backfill any APPROVED claims in MPT_claims that are missing a row in MPT_rewards
INSERT INTO public."MPT_rewards" (
    claim_id, user_id, game_id, prize_type, claim_reference, reward_code, reward_title, status, expires_at
)
SELECT
    c.id,
    c.user_id,
    c.game_id,
    c.prize_type,
    'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
    'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
    c.prize_type || ' Winner',
    'AVAILABLE_TO_CLAIM',
    NOW() + INTERVAL '30 days'
FROM public."MPT_claims" c
WHERE c.status = 'APPROVED'
  AND NOT EXISTS (
      SELECT 1 FROM public."MPT_rewards" r WHERE r.claim_id = c.id
  )
ON CONFLICT (claim_reference) DO NOTHING;


-- Rename any existing MPT-REW-xxxx or MPT-xxxx codes to Dab-Housie-xxxx across database tables
UPDATE public."MPT_rewards"
SET claim_reference = REGEXP_REPLACE(claim_reference, '^MPT-(REW-)?', 'Dab-Housie-', 'i'),
    reward_code = CASE
        WHEN reward_code IS NOT NULL THEN REGEXP_REPLACE(reward_code, '^MPT-(REW-)?', 'Dab-Housie-', 'i')
        ELSE NULL
    END
WHERE claim_reference ~* '^MPT-(REW-)?'
   OR COALESCE(reward_code, '') ~* '^MPT-(REW-)?';

UPDATE public."MPT_game_archives"
SET winners_roster = REGEXP_REPLACE(winners_roster::TEXT, '"MPT-(REW-)?', '"Dab-Housie-', 'gi')::JSONB
WHERE winners_roster::TEXT ~* '"MPT-(REW-)?';

UPDATE public."MPT_notifications"
SET message = REGEXP_REPLACE(message, 'MPT-(REW-)?', 'Dab-Housie-', 'gi'),
    payload = CASE
        WHEN payload IS NOT NULL THEN REGEXP_REPLACE(payload::TEXT, 'MPT-(REW-)?', 'Dab-Housie-', 'gi')::JSONB
        ELSE NULL
    END
WHERE message ~* 'MPT-(REW-)?'
   OR COALESCE(payload::TEXT, '') ~* 'MPT-(REW-)?';


-- Update MPT_verify_reward for case-insensitive verification of Dab-Housie- codes
CREATE OR REPLACE FUNCTION public."MPT_verify_reward"(
    p_claim_reference TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_normalized_ref TEXT;
    v_reward public."MPT_rewards";
    v_game public."MPT_games";
    v_player public."MPT_users";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    v_normalized_ref := REGEXP_REPLACE(UPPER(TRIM(p_claim_reference)), '^MPT-(REW-)?', 'DAB-HOUSIE-');

    SELECT * INTO v_reward
    FROM public."MPT_rewards"
    WHERE UPPER(TRIM(claim_reference)) = v_normalized_ref
       OR UPPER(TRIM(COALESCE(reward_code, ''))) = v_normalized_ref
       OR UPPER(TRIM(claim_reference)) = UPPER(TRIM(p_claim_reference));

    IF NOT FOUND THEN
        RAISE EXCEPTION 'REWARD_NOT_FOUND: Invalid verification reference code';
    END IF;

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = v_reward.game_id;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the Game Admin for this event can verify this reward';
    END IF;

    IF v_reward.status = 'CLAIMED' THEN
        RETURN jsonb_build_object(
            'status', 'ALREADY_CLAIMED',
            'reward', row_to_json(v_reward),
            'message', 'This reward has already been claimed on ' || v_reward.claimed_at
        );
    END IF;

    UPDATE public."MPT_rewards"
    SET status = 'CLAIMED',
        verified_by_admin_id = v_uid,
        claimed_at = NOW()
    WHERE id = v_reward.id
    RETURNING * INTO v_reward;

    SELECT * INTO v_player
    FROM public."MPT_users"
    WHERE id = v_reward.user_id;

    RETURN jsonb_build_object(
        'status', 'CLAIMED_SUCCESSFULLY',
        'claim_reference', v_reward.claim_reference,
        'prize_type', v_reward.prize_type,
        'player_display_name', COALESCE(v_player.display_name, 'Player'),
        'claimed_at', v_reward.claimed_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
