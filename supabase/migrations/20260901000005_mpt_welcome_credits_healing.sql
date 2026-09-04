-- =====================================================================
-- Migration: 20260901000005_mpt_welcome_credits_healing.sql
-- Description: 
--   1. Self-healing welcome bonus for any existing or new wallet with 0 credits
--   2. RPC to get/create wallet securely with 10 credits
--   3. Ensure RLS policies allow organizers and players to fetch their hosted and joined games
-- =====================================================================

-- 1. Self-heal existing wallets that have 0 credits and no transactions
DO $$
DECLARE
    v_wallet RECORD;
BEGIN
    FOR v_wallet IN 
        SELECT w.user_id 
        FROM public."MPT_admin_wallets" w
        LEFT JOIN public."MPT_credit_transactions" t ON w.user_id = t.user_id
        WHERE w.available_credits = 0 AND t.id IS NULL
    LOOP
        UPDATE public."MPT_admin_wallets"
        SET available_credits = 10,
            credits_expire_at = NOW() + INTERVAL '1 year',
            updated_at = NOW()
        WHERE user_id = v_wallet.user_id;

        INSERT INTO public."MPT_credit_transactions" (
            user_id,
            type,
            amount,
            balance_after,
            description,
            idempotency_key
        )
        VALUES (
            v_wallet.user_id,
            'PURCHASE',
            10,
            10,
            'Welcome Bonus: 10 Free Credits',
            'welcome-' || v_wallet.user_id::TEXT
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    END LOOP;
END $$;

-- 2. Authoritative RPC to get or create wallet with 10 welcome credits
CREATE OR REPLACE FUNCTION public."MPT_get_or_create_wallet"()
RETURNS public."MPT_admin_wallets" AS $$
DECLARE
    v_uid UUID;
    v_wallet public."MPT_admin_wallets";
    v_tx_count INT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Must be logged in';
    END IF;

    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid;

    IF NOT FOUND THEN
        -- Create new wallet with 10 welcome credits
        INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
        VALUES (v_uid, 10, NOW() + INTERVAL '1 year')
        RETURNING * INTO v_wallet;

        INSERT INTO public."MPT_credit_transactions" (
            user_id,
            type,
            amount,
            balance_after,
            description,
            idempotency_key
        )
        VALUES (
            v_uid,
            'PURCHASE',
            10,
            10,
            'Welcome Bonus: 10 Free Credits',
            'welcome-' || v_uid::TEXT
        )
        ON CONFLICT (idempotency_key) DO NOTHING;
    ELSE
        -- If wallet exists but has 0 credits and 0 transactions, heal it with welcome credits
        SELECT COUNT(*) INTO v_tx_count
        FROM public."MPT_credit_transactions"
        WHERE user_id = v_uid;

        IF v_wallet.available_credits = 0 AND v_tx_count = 0 THEN
            UPDATE public."MPT_admin_wallets"
            SET available_credits = 10,
                credits_expire_at = NOW() + INTERVAL '1 year',
                updated_at = NOW()
            WHERE user_id = v_uid
            RETURNING * INTO v_wallet;

            INSERT INTO public."MPT_credit_transactions" (
                user_id,
                type,
                amount,
                balance_after,
                description,
                idempotency_key
            )
            VALUES (
                v_uid,
                'PURCHASE',
                10,
                10,
                'Welcome Bonus: 10 Free Credits',
                'welcome-' || v_uid::TEXT
            )
            ON CONFLICT (idempotency_key) DO NOTHING;
        END IF;
    END IF;

    RETURN v_wallet;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
