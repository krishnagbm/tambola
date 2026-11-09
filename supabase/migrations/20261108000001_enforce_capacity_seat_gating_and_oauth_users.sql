-- supabase/migrations/20261108000001_enforce_capacity_seat_gating_and_oauth_users.sql
-- 1. Security & Financial Hardening: Gated Seat Capacity, Waitlist Enforcement, and Dabby System Caller Support
-- 2. Super Admin Executive Visibility: Registered OAuth Users List from auth.users

-- ============================================================================
-- A. Update MPT_create_game: Lock funded_capacity to available credits / Family Pack
-- ============================================================================
CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    p_is_private BOOLEAN DEFAULT FALSE,
    p_total_prize_budget NUMERIC DEFAULT 0,
    p_prize_gifts_config JSONB DEFAULT '{}'::jsonb,
    p_minor_prize_policy TEXT DEFAULT 'ONE_LINE_PLUS_BONUS'
)
RETURNS public."MPT_games"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_invite_code TEXT;
    v_tier_id UUID;
    v_attempts INT := 0;
    v_key TEXT;
    v_offer_id_str TEXT;
    v_wallet_credits INT := 0;
    v_planned_tier public."MPT_capacity_tiers";
    v_effective_funded_capacity INT := 5; -- Default free Family Pack limit
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

    -- Find matching planned capacity tier
    SELECT * INTO v_planned_tier
    FROM public."MPT_capacity_tiers"
    WHERE p_planned_capacity BETWEEN min_players AND max_players
    LIMIT 1;

    IF FOUND THEN
        v_tier_id := v_planned_tier.id;
    END IF;

    -- Check host wallet balance
    SELECT COALESCE(available_credits, 0) INTO v_wallet_credits
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid;

    -- FINANCIAL GATE:
    -- If planned capacity is within free Family Pack (<= 5), it is fully funded for free (5 players).
    -- If planned capacity is > 5:
    --    - If host has sufficient credits to cover the planned tier, grant full planned capacity.
    --    - Otherwise, lock initial funded capacity to 5 (free Family Pack).
    --      Any player joining past seat #5 will automatically be placed in WAITING status (Lobby Waitlist)
    --      until the host tops up / upgrades.
    IF p_planned_capacity <= 5 THEN
        v_effective_funded_capacity := COALESCE(p_planned_capacity, 5);
    ELSIF v_planned_tier.credits_required IS NOT NULL AND v_wallet_credits >= v_planned_tier.credits_required THEN
        v_effective_funded_capacity := p_planned_capacity;
    ELSE
        -- Host has 0 or insufficient credits for the requested tier; lock funded capacity to 5
        v_effective_funded_capacity := 5;
    END IF;

    INSERT INTO public."MPT_games" (
        admin_user_id,
        name,
        invite_code,
        status,
        planned_capacity_tier_id,
        initial_funded_capacity,
        funded_capacity,
        scheduled_at,
        prizes_config,
        is_private,
        total_prize_budget,
        prize_gifts_config,
        minor_prize_policy
    )
    VALUES (
        v_uid,
        p_name,
        v_invite_code,
        'OPEN',
        v_tier_id,
        COALESCE(p_planned_capacity, 25), -- Planned capacity record
        v_effective_funded_capacity,       -- Strict funded capacity (max confirmed seats)
        p_scheduled_at,
        COALESCE(p_prizes_config, '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb),
        COALESCE(p_is_private, FALSE),
        COALESCE(p_total_prize_budget, 0),
        COALESCE(p_prize_gifts_config, '{}'::jsonb),
        COALESCE(p_minor_prize_policy, 'ONE_LINE_PLUS_BONUS')
    )
    RETURNING * INTO v_game;

    -- Increment games_assigned_count for any Brand Offer assigned to this game's prizes
    IF p_prize_gifts_config IS NOT NULL AND jsonb_typeof(p_prize_gifts_config) = 'object' THEN
        FOR v_key IN SELECT jsonb_object_keys(p_prize_gifts_config) LOOP
            v_offer_id_str := p_prize_gifts_config -> v_key ->> 'offer_id';
            IF v_offer_id_str IS NOT NULL AND v_offer_id_str ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
                UPDATE public."MPT_brand_offers"
                SET games_assigned_count = games_assigned_count + 1
                WHERE id = v_offer_id_str::UUID;
            END IF;
        END LOOP;
    END IF;

    RETURN v_game;
END;
$$;


-- ============================================================================
-- B. Update MPT_start_game_and_charge: Support Service-Role Caller & Enforce Wallet
-- ============================================================================
CREATE OR REPLACE FUNCTION public."MPT_start_game_and_charge"(
    p_game_id UUID,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_is_service_role BOOLEAN := FALSE;
    v_game public."MPT_games";
    v_confirmed_count INT;
    v_tier public."MPT_capacity_tiers";
    v_credits_needed INT := 10;
    v_wallet public."MPT_admin_wallets";
    v_new_balance INT;
    v_reg RECORD;
    v_ticket_matrix JSONB;
    v_ticket_attempts INT;
    v_bulk_ticket_threshold CONSTANT INT := 300;
BEGIN
    v_uid := auth.uid();
    -- Allow trusted autonomous backend scheduler (service_role) to execute kickoff on behalf of organizer
    IF current_setting('request.jwt.claim.role', true) = 'service_role' OR auth.role() = 'service_role' THEN
        v_is_service_role := TRUE;
    END IF;

    IF v_uid IS NULL AND NOT v_is_service_role THEN
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

    -- If system service role, resolve v_uid to the game's admin user
    IF v_is_service_role THEN
        v_uid := v_game.admin_user_id;
    END IF;

    IF v_game.admin_user_id <> v_uid AND NOT v_is_service_role THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the Game Admin can start the game';
    END IF;

    IF v_game.status NOT IN ('OPEN', 'READY_TO_START') THEN
        RAISE EXCEPTION 'INVALID_GAME_STATE: Game cannot be started from status %', v_game.status;
    END IF;

    -- Count confirmed players
    SELECT COUNT(*) INTO v_confirmed_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    -- Minimum 1 participant required to start
    IF v_confirmed_count < 1 THEN
        RAISE EXCEPTION 'NO_CONFIRMED_PLAYERS: Cannot start game with 0 confirmed players';
    END IF;

    -- Find matching capacity tier
    SELECT * INTO v_tier
    FROM public."MPT_capacity_tiers"
    WHERE (v_confirmed_count = 0 AND min_players = 1)
       OR (v_confirmed_count > 0 AND v_confirmed_count BETWEEN min_players AND max_players)
       OR (v_confirmed_count > 0 AND max_players >= v_confirmed_count)
    ORDER BY credits_required ASC
    LIMIT 1;

    IF FOUND THEN
        v_credits_needed := v_tier.credits_required;
    ELSE
        SELECT COALESCE(MIN(credits_required), 10) INTO v_credits_needed
        FROM public."MPT_capacity_tiers"
        WHERE is_active = TRUE;
    END IF;

    -- Lock organizer wallet row
    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid
    FOR UPDATE;

    -- FINANCIAL GATE:
    -- If credits are needed (more than free Family Pack), host MUST have sufficient credits.
    -- Zero exceptions — system caller and host caller are strictly checked.
    IF v_credits_needed > 0 THEN
        IF v_wallet.user_id IS NULL OR v_wallet.available_credits < v_credits_needed THEN
            RAISE EXCEPTION 'INSUFFICIENT_CREDITS: Required % credits to start game for % confirmed players, but organizer only has % credits available.',
                v_credits_needed, v_confirmed_count, COALESCE(v_wallet.available_credits, 0);
        END IF;

        -- Deduct credits
        v_new_balance := v_wallet.available_credits - v_credits_needed;
        UPDATE public."MPT_admin_wallets"
        SET available_credits = v_new_balance,
            last_paid_game_at = NOW(),
            updated_at = NOW()
        WHERE user_id = v_uid;

        -- Record transaction
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
            'Game start charge for ' || v_confirmed_count || ' players (' || v_tier.name || ')',
            p_idempotency_key
        );
    ELSE
        -- 0 credits required (Family Pack 1-5 players)
        v_new_balance := COALESCE(v_wallet.available_credits, 0);
        IF v_wallet.user_id IS NOT NULL THEN
            UPDATE public."MPT_admin_wallets"
            SET last_paid_game_at = NOW(),
                updated_at = NOW()
            WHERE user_id = v_uid;
        END IF;

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
            0,
            v_new_balance,
            p_game_id::TEXT,
            'Free Family Pack game start charge for ' || v_confirmed_count || ' players',
            p_idempotency_key
        );
    END IF;

    -- Update game status to IN_PROGRESS
    UPDATE public."MPT_games"
    SET status = 'IN_PROGRESS',
        started_at = NOW(),
        updated_at = NOW()
    WHERE id = p_game_id;

    -- Generate player tickets for all CONFIRMED players
    FOR v_reg IN
        SELECT r.id, r.user_id, r.registration_seq
        FROM public."MPT_game_registrations" r
        WHERE r.game_id = p_game_id AND r.seat_status = 'CONFIRMED'
        ORDER BY r.registration_seq ASC
    LOOP
        -- Check if player already has a ticket
        IF NOT EXISTS (
            SELECT 1 FROM public."MPT_player_tickets"
            WHERE game_id = p_game_id AND user_id = v_reg.user_id
        ) THEN
            v_ticket_attempts := 0;
            LOOP
                v_ticket_matrix := public."MPT_generate_ticket_matrix"();
                EXIT WHEN v_confirmed_count > v_bulk_ticket_threshold
                   OR NOT EXISTS (
                       SELECT 1 FROM public."MPT_player_tickets"
                       WHERE game_id = p_game_id AND ticket_matrix = v_ticket_matrix
                   );
                v_ticket_attempts := v_ticket_attempts + 1;
                IF v_ticket_attempts >= 15 THEN
                    EXIT;
                END IF;
            END LOOP;

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
            );
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'game_id', p_game_id,
        'status', 'IN_PROGRESS',
        'confirmed_players', v_confirmed_count,
        'credits_deducted', v_credits_needed,
        'new_balance', v_new_balance,
        'tier_applied', v_tier.name
    );
END;
$$;


-- ============================================================================
-- C. Super Admin Executive Visibility: MPT_get_registered_oauth_users
-- ============================================================================
CREATE OR REPLACE FUNCTION public."MPT_get_registered_oauth_users"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT;
    v_users JSONB;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in';
    END IF;

    SELECT role INTO v_role
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_uid;

    IF v_role IS DISTINCT FROM 'ADMIN' THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Administrator privileges required';
    END IF;

    SELECT COALESCE(jsonb_agg(u_row), '[]'::jsonb)
    INTO v_users
    FROM (
        SELECT 
            au.id AS user_id,
            au.email,
            COALESCE(
                au.raw_app_meta_data ->> 'provider',
                CASE WHEN au.email LIKE '%gmail.com' THEN 'google' ELSE 'email' END
            ) AS provider,
            COALESCE(
                au.raw_user_meta_data ->> 'full_name',
                au.raw_user_meta_data ->> 'name',
                u.display_name,
                'Organizer'
            ) AS display_name,
            COALESCE(u.avatar, 'avatar_1') AS avatar,
            au.created_at AS registered_at,
            au.last_sign_in_at,
            COALESCE(ap.role, 'PLAYER') AS role,
            (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = au.id) AS games_hosted_count,
            (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE user_id = au.id) AS games_joined_count,
            COALESCE(w.available_credits, 0) AS credits_balance
        FROM auth.users au
        LEFT JOIN public."MPT_users" u ON u.id = au.id
        LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = au.id
        LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = au.id
        WHERE au.email IS NOT NULL 
          AND au.email <> ''
          AND (au.is_anonymous IS FALSE OR au.is_anonymous IS NULL)
        ORDER BY au.created_at DESC
        LIMIT 250
    ) u_row;

    RETURN v_users;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_registered_oauth_users"() TO authenticated;

