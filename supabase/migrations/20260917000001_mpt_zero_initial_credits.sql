-- =====================================================================
-- Migration: 20260917000001_mpt_zero_initial_credits.sql
-- Description:
--   1. Sets default wallet balance to 0 credits (Pure Freemium model)
--   2. Updates MPT_upsert_user to create wallets with 0 credits
--   3. Updates MPT_get_or_create_wallet to initialize wallets with 0 credits
--      (Family Pack 1–5 players is permanent 0-credit free trial)
-- =====================================================================

-- 1. Alter default available_credits to 0
ALTER TABLE public."MPT_admin_wallets"
    ALTER COLUMN available_credits SET DEFAULT 0;

-- 2. Update MPT_upsert_user to create wallet with 0 credits
CREATE OR REPLACE FUNCTION public."MPT_upsert_user"(
    p_display_name TEXT DEFAULT 'Player',
    p_avatar TEXT DEFAULT 'avatar_1'
)
RETURNS public."MPT_users" AS $$
DECLARE
    v_user public."MPT_users";
    v_uid UUID;
    v_wallet_exists BOOLEAN;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    INSERT INTO public."MPT_users" (id, display_name, avatar, is_anonymous, updated_at)
    VALUES (v_uid, COALESCE(NULLIF(p_display_name, ''), 'Player'), COALESCE(NULLIF(p_avatar, ''), 'avatar_1'), TRUE, NOW())
    ON CONFLICT (id) DO UPDATE
    SET display_name = COALESCE(NULLIF(EXCLUDED.display_name, ''), public."MPT_users".display_name),
        avatar = COALESCE(NULLIF(EXCLUDED.avatar, ''), public."MPT_users".avatar),
        updated_at = NOW()
    RETURNING * INTO v_user;

    -- Check if admin wallet already exists
    SELECT EXISTS (SELECT 1 FROM public."MPT_admin_wallets" WHERE user_id = v_uid) INTO v_wallet_exists;

    IF NOT v_wallet_exists THEN
        -- Create wallet with 0 initial credits
        INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
        VALUES (v_uid, 0, NOW() + INTERVAL '1 year')
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN v_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Update MPT_get_or_create_wallet to return/create wallet with 0 credits without overriding
CREATE OR REPLACE FUNCTION public."MPT_get_or_create_wallet"()
RETURNS public."MPT_admin_wallets" AS $$
DECLARE
    v_uid UUID;
    v_wallet public."MPT_admin_wallets";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Must be logged in';
    END IF;

    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid;

    IF NOT FOUND THEN
        -- Create new wallet with 0 initial credits
        INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
        VALUES (v_uid, 0, NOW() + INTERVAL '1 year')
        ON CONFLICT (user_id) DO UPDATE
        SET updated_at = NOW()
        RETURNING * INTO v_wallet;
    END IF;

    RETURN v_wallet;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
