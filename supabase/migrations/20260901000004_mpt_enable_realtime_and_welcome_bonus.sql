-- =====================================================================
-- Migration: 20260901000004_mpt_enable_realtime_and_welcome_bonus.sql
-- Description: 
--   1. Enable Supabase Realtime publication on MPT_ tables
--   2. Default 10 free credits welcome bonus for all admin wallets
--   3. Dynamic capacity tier linking for create_game and start_game
-- =====================================================================

-- 1. Enable Supabase Realtime on MPT_ tables
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_games";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_game_registrations";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_called_numbers";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_claims";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_rewards";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_notifications";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_admin_wallets";
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
END $$;

-- 2. Alter MPT_admin_wallets default to 10 available credits
ALTER TABLE public."MPT_admin_wallets" 
    ALTER COLUMN available_credits SET DEFAULT 10;

-- 3. Update MPT_upsert_user to grant 10 free credits to new users on creation
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
        -- Create wallet with 10 free welcome credits
        INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
        VALUES (v_uid, 10, NOW() + INTERVAL '1 year');

        -- Log welcome bonus in ledger
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

    RETURN v_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Update MPT_create_game to dynamically link planned_capacity_tier_id
CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    p_planned_capacity_tier_id UUID DEFAULT NULL
)
RETURNS public."MPT_games" AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_invite_code TEXT;
    v_tier_id UUID;
    v_final_cap INT;
    v_attempts INT := 0;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Must be logged in to create a game';
    END IF;

    -- Generate a unique 6-character uppercase alphanumeric code
    LOOP
        v_invite_code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT) FROM 1 FOR 6));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM public."MPT_games" WHERE invite_code = v_invite_code);
        v_attempts := v_attempts + 1;
        IF v_attempts > 10 THEN
            v_invite_code := 'TAMB' || (FLOOR(RANDOM() * 9000 + 1000)::TEXT);
            EXIT;
        END IF;
    END LOOP;

    -- Find matching capacity tier if not provided directly
    IF p_planned_capacity_tier_id IS NOT NULL THEN
        v_tier_id := p_planned_capacity_tier_id;
        SELECT max_players INTO v_final_cap
        FROM public."MPT_capacity_tiers"
        WHERE id = v_tier_id;
    ELSE
        SELECT id, max_players INTO v_tier_id, v_final_cap
        FROM public."MPT_capacity_tiers"
        WHERE p_planned_capacity BETWEEN min_players AND max_players
        ORDER BY display_order ASC
        LIMIT 1;
    END IF;

    v_final_cap := COALESCE(v_final_cap, p_planned_capacity, 25);

    INSERT INTO public."MPT_games" (
        admin_user_id,
        name,
        invite_code,
        status,
        planned_capacity_tier_id,
        initial_funded_capacity,
        funded_capacity,
        scheduled_at,
        prizes_config
    )
    VALUES (
        v_uid,
        p_name,
        v_invite_code,
        'OPEN',
        v_tier_id,
        v_final_cap,
        v_final_cap,
        p_scheduled_at,
        COALESCE(p_prizes_config, '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb)
    )
    RETURNING * INTO v_game;

    RETURN v_game;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Update MPT_start_game_and_charge to dynamically calculate charge from MPT_capacity_tiers
CREATE OR REPLACE FUNCTION public."MPT_start_game_and_charge"(
    p_game_id UUID,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_confirmed_count INT;
    v_tier public."MPT_capacity_tiers";
    v_credits_needed INT := 10;
    v_wallet public."MPT_admin_wallets";
    v_new_balance INT;
    v_reg RECORD;
    v_ticket_matrix JSONB;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    -- Lock game row
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND';
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the Game Admin can start the game';
    END IF;

    IF v_game.status NOT IN ('OPEN', 'READY_TO_START') THEN
        RAISE EXCEPTION 'INVALID_GAME_STATE: Game cannot be started from status %', v_game.status;
    END IF;

    -- Count confirmed players
    SELECT COUNT(*) INTO v_confirmed_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    -- Find matching capacity tier from active database tiers
    SELECT * INTO v_tier
    FROM public."MPT_capacity_tiers"
    WHERE v_confirmed_count BETWEEN min_players AND max_players AND is_active = TRUE
    ORDER BY credits_required ASC
    LIMIT 1;

    IF FOUND THEN
        v_credits_needed := v_tier.credits_required;
    ELSE
        -- Fallback: smallest tier with max_players >= confirmed_count or lowest active tier
        SELECT * INTO v_tier
        FROM public."MPT_capacity_tiers"
        WHERE max_players >= v_confirmed_count AND is_active = TRUE
        ORDER BY credits_required ASC
        LIMIT 1;

        IF FOUND THEN
            v_credits_needed := v_tier.credits_required;
        ELSE
            SELECT COALESCE(MIN(credits_required), 10) INTO v_credits_needed
            FROM public."MPT_capacity_tiers" WHERE is_active = TRUE;
        END IF;
    END IF;

    -- Lock and check wallet
    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid
    FOR UPDATE;

    IF NOT FOUND OR v_wallet.available_credits < v_credits_needed THEN
        RAISE EXCEPTION 'INSUFFICIENT_CREDITS: Required % credits, but wallet has %', 
            v_credits_needed, COALESCE(v_wallet.available_credits, 0);
    END IF;

    -- Deduct credits atomically
    v_new_balance := v_wallet.available_credits - v_credits_needed;
    UPDATE public."MPT_admin_wallets"
    SET available_credits = v_new_balance,
        last_paid_game_at = NOW(),
        credits_expire_at = NOW() + INTERVAL '1 year',
        updated_at = NOW()
    WHERE user_id = v_uid;

    -- Record immutable ledger entries
    INSERT INTO public."MPT_credit_transactions" (
        user_id,
        type,
        amount,
        balance_after,
        reference_id,
        description,
        idempotency_key
    )
    VALUES (
        v_uid,
        'GAME_CHARGE',
        -v_credits_needed,
        v_new_balance,
        p_game_id::TEXT,
        'Game start charge for ' || v_confirmed_count || ' players',
        p_idempotency_key
    );

    INSERT INTO public."MPT_game_charges" (
        game_id,
        tier_id,
        player_count,
        credits_charged
    )
    VALUES (
        p_game_id,
        v_tier.id,
        v_confirmed_count,
        v_credits_needed
    );

    -- Finalize seats: CONFIRMED -> ELIGIBLE, WAITING -> NOT_ELIGIBLE
    UPDATE public."MPT_game_registrations"
    SET seat_status = 'ELIGIBLE',
        updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    UPDATE public."MPT_game_registrations"
    SET seat_status = 'NOT_ELIGIBLE',
        updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'WAITING';

    -- Update game status to IN_PROGRESS
    UPDATE public."MPT_games"
    SET status = 'IN_PROGRESS',
        final_capacity = v_confirmed_count,
        started_at = NOW(),
        state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    -- Generate tickets for all ELIGIBLE players
    FOR v_reg IN
        SELECT user_id FROM public."MPT_game_registrations"
        WHERE game_id = p_game_id AND seat_status = 'ELIGIBLE'
    LOOP
        v_ticket_matrix := public."MPT_generate_ticket_matrix"();
        INSERT INTO public."MPT_player_tickets" (
            game_id,
            user_id,
            ticket_matrix,
            ticket_number
        )
        VALUES (
            p_game_id,
            v_reg.user_id,
            v_ticket_matrix,
            1
        )
        ON CONFLICT (game_id, user_id, ticket_number) DO NOTHING;
    END LOOP;

    RETURN jsonb_build_object(
        'game_id', p_game_id,
        'status', 'IN_PROGRESS',
        'eligible_players', v_confirmed_count,
        'credits_charged', v_credits_needed,
        'balance_remaining', v_new_balance
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
