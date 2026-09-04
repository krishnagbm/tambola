-- =====================================================================
-- Migration: 20260901000003_mpt_claims_and_rewards_rpc.sql
-- Description: Prize Claim and Reward Verification RPCs for Multiplayer Tambola
-- =====================================================================

-- 1. MPT_submit_claim: Server-authoritative claim validation
CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_reg public."MPT_game_registrations";
    v_ticket public."MPT_player_tickets";
    v_claim_ref TEXT;
    v_claim public."MPT_claims";
    v_reward public."MPT_rewards";
    v_already_won BOOLEAN;
    v_is_valid BOOLEAN := TRUE;
    v_num INT;
    v_called_count INT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Must be authenticated';
    END IF;

    -- Verify game is IN_PROGRESS
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND OR v_game.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'GAME_NOT_IN_PROGRESS: Cannot claim prize when game status is %', COALESCE(v_game.status, 'NOT_FOUND');
    END IF;

    -- Verify player is ELIGIBLE
    SELECT * INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status <> 'ELIGIBLE' THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: Player seat status is %', COALESCE(v_reg.seat_status, 'NOT_REGISTERED');
    END IF;

    -- Check if prize already claimed/approved
    SELECT EXISTS (
        SELECT 1 FROM public."MPT_claims"
        WHERE game_id = p_game_id AND prize_type = p_prize_type AND status = 'APPROVED'
    ) INTO v_already_won;

    IF v_already_won THEN
        -- Prize was already won by someone else
        INSERT INTO public."MPT_claims" (
            game_id,
            user_id,
            prize_type,
            status,
            marked_numbers,
            rejection_reason,
            idempotency_key,
            processed_at
        )
        VALUES (
            p_game_id,
            v_uid,
            p_prize_type,
            'REJECTED',
            p_marked_numbers,
            'Prize has already been claimed by another player',
            p_idempotency_key,
            NOW()
        )
        RETURNING * INTO v_claim;

        RETURN jsonb_build_object(
            'status', 'REJECTED',
            'reason', 'Prize already won by another player'
        );
    END IF;

    -- Load player ticket
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid
    LIMIT 1;

    -- Validate marked numbers against authoritative called_numbers
    IF jsonb_array_length(p_marked_numbers) > 0 THEN
        FOR v_num IN SELECT jsonb_array_elements_text(p_marked_numbers)::INT LOOP
            SELECT COUNT(*) INTO v_called_count
            FROM public."MPT_called_numbers"
            WHERE game_id = p_game_id AND number = v_num;

            IF v_called_count = 0 THEN
                v_is_valid := FALSE;
                EXIT;
            END IF;
        END LOOP;
    END IF;

    IF NOT v_is_valid THEN
        -- Bogey claim
        INSERT INTO public."MPT_claims" (
            game_id,
            user_id,
            prize_type,
            status,
            marked_numbers,
            rejection_reason,
            idempotency_key,
            processed_at
        )
        VALUES (
            p_game_id,
            v_uid,
            p_prize_type,
            'BOGEY',
            p_marked_numbers,
            'Claim includes numbers that have not been called yet (Bogey)',
            p_idempotency_key,
            NOW()
        )
        RETURNING * INTO v_claim;

        RETURN jsonb_build_object(
            'status', 'BOGEY',
            'reason', 'Invalid claim: Contains uncalled numbers (Bogey)'
        );
    END IF;

    -- Approve claim
    INSERT INTO public."MPT_claims" (
        game_id,
        user_id,
        prize_type,
        status,
        marked_numbers,
        idempotency_key,
        processed_at
    )
    VALUES (
        p_game_id,
        v_uid,
        p_prize_type,
        'APPROVED',
        p_marked_numbers,
        p_idempotency_key,
        NOW()
    )
    RETURNING * INTO v_claim;

    -- Generate unique server verifiable reference code (e.g. MPT-REW-8F3K-2B9D)
    v_claim_ref := 'MPT-REW-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT) FROM 1 FOR 4))
                  || '-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT || v_claim.id::TEXT) FROM 1 FOR 4));

    -- Insert into MPT_rewards
    INSERT INTO public."MPT_rewards" (
        game_id,
        user_id,
        prize_type,
        claim_id,
        claim_reference,
        status
    )
    VALUES (
        p_game_id,
        v_uid,
        p_prize_type,
        v_claim.id,
        v_claim_ref,
        'AVAILABLE_TO_CLAIM'
    )
    RETURNING * INTO v_reward;

    -- Create in-app winner notification
    INSERT INTO public."MPT_notifications" (
        user_id,
        game_id,
        type,
        title,
        message,
        payload
    )
    VALUES (
        v_uid,
        p_game_id,
        'REWARD_ISSUED',
        'Congratulations! You Won! 🏆',
        'Your claim for ' || REPLACE(p_prize_type, '_', ' ') || ' was approved! Show reference ' || v_claim_ref || ' to claim your prize.',
        jsonb_build_object('reward_id', v_reward.id, 'claim_reference', v_claim_ref, 'prize_type', p_prize_type)
    );

    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'status', 'APPROVED',
        'prize_type', p_prize_type,
        'claim_reference', v_claim_ref,
        'reward_id', v_reward.id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. MPT_verify_reward: Admin verifies and marks a reward voucher claimed
CREATE OR REPLACE FUNCTION public."MPT_verify_reward"(
    p_claim_reference TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_reward public."MPT_rewards";
    v_game public."MPT_games";
    v_player public."MPT_users";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT * INTO v_reward
    FROM public."MPT_rewards"
    WHERE claim_reference = UPPER(TRIM(p_claim_reference));

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
