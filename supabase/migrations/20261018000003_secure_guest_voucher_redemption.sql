-- Migration: 20261018000003_secure_guest_voucher_redemption.sql
-- Enables secure redemption of DabHousie Event Credits from winning prize vouchers
-- with strict ownership verification to protect guest tickets against unauthorized claims.

-- 1. Add voucher redemption audit columns to MPT_rewards
ALTER TABLE public."MPT_rewards"
    ADD COLUMN IF NOT EXISTS credits_redeemed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS redeemed_by_user_id UUID REFERENCES public."MPT_users"(id),
    ADD COLUMN IF NOT EXISTS redeemed_credits_amount INT;

CREATE INDEX IF NOT EXISTS idx_mpt_rewards_claim_ref ON public."MPT_rewards"(claim_reference);
CREATE INDEX IF NOT EXISTS idx_mpt_rewards_redeemed_by ON public."MPT_rewards"(redeemed_by_user_id) WHERE redeemed_by_user_id IS NOT NULL;

-- 2. Create secure RPC MPT_redeem_prize_voucher_for_credits
CREATE OR REPLACE FUNCTION public."MPT_redeem_prize_voucher_for_credits"(
    p_voucher_code TEXT,
    p_ticket_number INT DEFAULT NULL,
    p_invite_code TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_norm_code TEXT;
    v_reward RECORD;
    v_game RECORD;
    v_credits INT;
    v_new_balance INT;
    v_is_owner BOOLEAN := FALSE;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in or register to redeem your prize voucher';
    END IF;

    -- Clean & normalize voucher code
    v_norm_code := UPPER(TRIM(p_voucher_code));
    IF v_norm_code LIKE 'MPT-REW-%' THEN
        v_norm_code := REPLACE(v_norm_code, 'MPT-REW-', 'DAB-HOUSIE-');
    ELSIF v_norm_code LIKE 'MPT-%' THEN
        v_norm_code := REPLACE(v_norm_code, 'MPT-', 'DAB-HOUSIE-');
    END IF;

    -- Look up reward
    SELECT r.*
    INTO v_reward
    FROM public."MPT_rewards" r
    WHERE UPPER(r.claim_reference) = v_norm_code;

    IF v_reward.id IS NULL THEN
        RAISE EXCEPTION 'VOUCHER_NOT_FOUND: Invalid voucher code. Please verify the code on your winning ticket screen.';
    END IF;

    -- Check if host has marked it settled
    IF v_reward.status <> 'CLAIMED' THEN
        RAISE EXCEPTION 'VOUCHER_NOT_SETTLED: This prize claim has not been marked as Settled by the game organizer yet.';
    END IF;

    -- Check if already redeemed
    IF v_reward.credits_redeemed_at IS NOT NULL THEN
        RAISE EXCEPTION 'VOUCHER_ALREADY_REDEEMED: This prize voucher was already redeemed on %.', 
            TO_CHAR(v_reward.credits_redeemed_at, 'YYYY-MM-DD HH24:MI');
    END IF;

    -- Fetch game details
    SELECT g.id, g.name, g.invite_code INTO v_game
    FROM public."MPT_games" g
    WHERE g.id = v_reward.game_id;

    IF v_game.id IS NULL THEN
        SELECT a.id, a.name, a.invite_code INTO v_game
        FROM public."MPT_game_archives" a
        WHERE a.game_id = v_reward.game_id;
    END IF;

    -- Strict Ownership Verification:
    -- Method A: Exact account match (guest converted/upgraded in the same session, or authenticated winner)
    IF v_reward.user_id = v_uid THEN
        v_is_owner := TRUE;
    -- Method B: Cross-device match using Ticket # and Game Invite Code
    ELSIF p_ticket_number IS NOT NULL AND p_invite_code IS NOT NULL THEN
        IF UPPER(TRIM(p_invite_code)) = UPPER(TRIM(COALESCE(v_game.invite_code, ''))) THEN
            -- Verify ticket registration seq or MPT_player_tickets for that original guest user
            IF EXISTS (
                SELECT 1 FROM public."MPT_player_tickets" pt
                WHERE pt.game_id = v_reward.game_id
                  AND pt.user_id = v_reward.user_id
                  AND pt.ticket_number = p_ticket_number
            ) OR EXISTS (
                SELECT 1 FROM public."MPT_game_registrations" gr
                WHERE gr.game_id = v_reward.game_id
                  AND gr.user_id = v_reward.user_id
                  AND gr.registration_seq = p_ticket_number
            ) THEN
                v_is_owner := TRUE;
            END IF;
        END IF;
    END IF;

    IF NOT v_is_owner THEN
        RAISE EXCEPTION 'VOUCHER_OWNERSHIP_MISMATCH: This voucher was issued to a different player. If redeeming from another device, please enter the Ticket # and Game Invite Code.';
    END IF;

    -- Calculate hosting credits: $1 = 5 hosting capacity credits (e.g. $10 = 50 credits)
    v_credits := GREATEST(5, ROUND(COALESCE(v_reward.prize_value, 10.0) * 5)::INT);

    -- Credit the user's hosting wallet
    INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at, updated_at)
    VALUES (v_uid, v_credits, NOW() + INTERVAL '1 year', NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET available_credits = public."MPT_admin_wallets".available_credits + v_credits,
        updated_at = NOW()
    RETURNING available_credits INTO v_new_balance;

    -- Log immutable transaction in credit ledger
    INSERT INTO public."MPT_credit_transactions" (
        user_id, type, amount, balance_after, description, reference_id, created_at
    )
    VALUES (
        v_uid,
        'PRIZE_VOUCHER_REDEMPTION',
        v_credits,
        v_new_balance,
        'Redeemed prize voucher ' || v_reward.claim_reference || ' ($' || COALESCE(v_reward.prize_value, 10.0)::TEXT || ' for ' || v_reward.prize_type || ') from ' || COALESCE(v_game.name, 'Hosted Game'),
        v_reward.id::TEXT,
        NOW()
    );

    -- Mark reward as permanently redeemed
    UPDATE public."MPT_rewards"
    SET credits_redeemed_at = NOW(),
        redeemed_by_user_id = v_uid,
        redeemed_credits_amount = v_credits
    WHERE id = v_reward.id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'credits_added', v_credits,
        'prize_value', COALESCE(v_reward.prize_value, 10.0),
        'prize_type', v_reward.prize_type,
        'game_name', COALESCE(v_game.name, 'Hosted Game'),
        'new_balance', v_new_balance,
        'claim_reference', v_reward.claim_reference
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_redeem_prize_voucher_for_credits"(TEXT, INT, TEXT) TO authenticated;
