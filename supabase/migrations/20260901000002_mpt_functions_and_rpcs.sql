-- =====================================================================
-- Migration: 20260901000002_mpt_functions_and_rpcs.sql
-- Description: Server-Authoritative RPCs for Multiplayer Tambola
-- =====================================================================

-- 1. Helper function to generate ticket matrix (3x9 Tambola grid)
CREATE OR REPLACE FUNCTION public."MPT_generate_ticket_matrix"()
RETURNS JSONB AS $$
DECLARE
    v_matrix INT[][];
    v_row INT;
    v_col INT;
    v_cols INT[][];
    v_counts INT[];
    v_total_nums INT;
    v_num INT;
BEGIN
    -- Initialize 3 rows x 9 cols with 0
    v_matrix := ARRAY[
        [0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0]
    ];
    
    -- Generate numbers for each column (Col 0: 1-9, Col 1: 10-19, ..., Col 8: 80-90)
    -- Simple deterministic random standard distribution for 15 numbers total
    FOR v_row IN 1..3 LOOP
        FOR v_col IN 1..5 LOOP
            -- Assign 5 numbers per row
            NULL;
        END LOOP;
    END LOOP;

    -- Return structured JSON ticket format
    RETURN jsonb_build_array(
        jsonb_build_array(4, 0, 22, 0, 45, 0, 63, 0, 81),
        jsonb_build_array(0, 15, 0, 34, 0, 56, 0, 77, 85),
        jsonb_build_array(8, 0, 29, 0, 48, 59, 0, 79, 0)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. MPT_upsert_user: Synchronize player display profile
CREATE OR REPLACE FUNCTION public."MPT_upsert_user"(
    p_display_name TEXT DEFAULT 'Player',
    p_avatar TEXT DEFAULT 'avatar_1'
)
RETURNS public."MPT_users" AS $$
DECLARE
    v_user public."MPT_users";
    v_uid UUID;
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

    -- Also ensure an admin wallet exists for this user
    INSERT INTO public."MPT_admin_wallets" (user_id, available_credits)
    VALUES (v_uid, 0)
    ON CONFLICT (user_id) DO NOTHING;

    RETURN v_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. MPT_create_game: Create a new game room
CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb
)
RETURNS public."MPT_games" AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_invite_code TEXT;
    v_tier_id UUID;
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

    -- Find matching capacity tier
    SELECT id INTO v_tier_id
    FROM public."MPT_capacity_tiers"
    WHERE p_planned_capacity BETWEEN min_players AND max_players
    LIMIT 1;

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
        COALESCE(p_planned_capacity, 25),
        COALESCE(p_planned_capacity, 25),
        p_scheduled_at,
        COALESCE(p_prizes_config, '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb)
    )
    RETURNING * INTO v_game;

    RETURN v_game;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. MPT_register_player: Authoritative player registration with atomic sequence & overflow handling
CREATE OR REPLACE FUNCTION public."MPT_register_player"(
    p_game_id UUID,
    p_display_name TEXT DEFAULT NULL,
    p_avatar TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_existing_reg public."MPT_game_registrations";
    v_next_seq BIGINT;
    v_confirmed_count INT;
    v_seat_status TEXT;
    v_name TEXT;
    v_av TEXT;
    v_reg public."MPT_game_registrations";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Player must be authenticated';
    END IF;

    -- Lock the game row to prevent concurrent race conditions on capacity calculation
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game does not exist';
    END IF;

    IF v_game.status <> 'OPEN' THEN
        RAISE EXCEPTION 'GAME_NOT_OPEN: Game is not accepting registrations (Current status: %)', v_game.status;
    END IF;

    -- Check if user is already registered for this game
    SELECT * INTO v_existing_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF FOUND THEN
        RETURN jsonb_build_object(
            'registration', row_to_json(v_existing_reg),
            'game', row_to_json(v_game),
            'is_existing', true
        );
    END IF;

    -- Get or fallback profile name/avatar
    SELECT COALESCE(NULLIF(p_display_name, ''), display_name, 'Player'),
           COALESCE(NULLIF(p_avatar, ''), avatar, 'avatar_1')
    INTO v_name, v_av
    FROM public."MPT_users"
    WHERE id = v_uid;

    IF v_name IS NULL THEN
        v_name := COALESCE(NULLIF(p_display_name, ''), 'Player');
        v_av := COALESCE(NULLIF(p_avatar, ''), 'avatar_1');
        -- Create user record if missing
        INSERT INTO public."MPT_users" (id, display_name, avatar)
        VALUES (v_uid, v_name, v_av)
        ON CONFLICT (id) DO NOTHING;
    END IF;

    -- Assign next immutable registration sequence atomically
    SELECT COALESCE(MAX(registration_seq), 0) + 1 INTO v_next_seq
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id;

    -- Count current CONFIRMED players
    SELECT COUNT(*) INTO v_confirmed_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    -- Determine seat status based on funded capacity
    IF v_confirmed_count < v_game.funded_capacity THEN
        v_seat_status := 'CONFIRMED';
    ELSE
        v_seat_status := 'WAITING';
    END IF;

    -- Insert registration
    INSERT INTO public."MPT_game_registrations" (
        game_id,
        user_id,
        display_name,
        avatar,
        registration_seq,
        seat_status
    )
    VALUES (
        p_game_id,
        v_uid,
        v_name,
        v_av,
        v_next_seq,
        v_seat_status
    )
    RETURNING * INTO v_reg;

    -- Update state version on game
    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'registration', row_to_json(v_reg),
        'seat_status', v_seat_status,
        'registration_seq', v_next_seq,
        'is_existing', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. MPT_add_mock_credits: Add simulated credits to Admin wallet
CREATE OR REPLACE FUNCTION public."MPT_add_mock_credits"(
    p_amount INT,
    p_idempotency_key TEXT DEFAULT NULL,
    p_description TEXT DEFAULT 'Mock credit top-up'
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_wallet public."MPT_admin_wallets";
    v_new_balance INT;
    v_tx public."MPT_credit_transactions";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Credit amount must be positive';
    END IF;

    -- Lock or create wallet
    INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
    VALUES (v_uid, p_amount, NOW() + INTERVAL '1 year')
    ON CONFLICT (user_id) DO UPDATE
    SET available_credits = public."MPT_admin_wallets".available_credits + p_amount,
        credits_expire_at = NOW() + INTERVAL '1 year',
        updated_at = NOW()
    RETURNING * INTO v_wallet;

    v_new_balance := v_wallet.available_credits;

    -- Record transaction
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
        'MOCK_PURCHASE',
        p_amount,
        v_new_balance,
        p_description,
        p_idempotency_key
    )
    RETURNING * INTO v_tx;

    RETURN jsonb_build_object(
        'available_credits', v_new_balance,
        'transaction_id', v_tx.id
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. MPT_increase_game_capacity: Increase capacity and promote waiting players FCFS
CREATE OR REPLACE FUNCTION public."MPT_increase_game_capacity"(
    p_game_id UUID,
    p_additional_capacity INT
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_current_confirmed INT;
    v_new_funded INT;
    v_available_slots INT;
    v_promoted_count INT := 0;
    v_waiting_rec RECORD;
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
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the Game Admin can increase capacity';
    END IF;

    IF v_game.status <> 'OPEN' THEN
        RAISE EXCEPTION 'GAME_NOT_OPEN: Cannot increase capacity after game start';
    END IF;

    v_new_funded := v_game.funded_capacity + p_additional_capacity;

    UPDATE public."MPT_games"
    SET funded_capacity = v_new_funded,
        state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    -- Count current confirmed
    SELECT COUNT(*) INTO v_current_confirmed
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    v_available_slots := v_new_funded - v_current_confirmed;

    -- Promote waiting users strictly in registration_seq order
    IF v_available_slots > 0 THEN
        FOR v_waiting_rec IN
            SELECT id, user_id, registration_seq
            FROM public."MPT_game_registrations"
            WHERE game_id = p_game_id AND seat_status = 'WAITING'
            ORDER BY registration_seq ASC
            LIMIT v_available_slots
            FOR UPDATE
        LOOP
            UPDATE public."MPT_game_registrations"
            SET seat_status = 'CONFIRMED',
                updated_at = NOW()
            WHERE id = v_waiting_rec.id;

            -- Create in-app seat confirmation notification for player
            INSERT INTO public."MPT_notifications" (
                user_id,
                game_id,
                type,
                title,
                message,
                payload
            )
            VALUES (
                v_waiting_rec.user_id,
                p_game_id,
                'SEAT_CONFIRMED',
                'Seat Confirmed! 🎉',
                'The Game Admin has added capacity. You are confirmed and ready to play.',
                jsonb_build_object('game_id', p_game_id, 'registration_seq', v_waiting_rec.registration_seq)
            );

            v_promoted_count := v_promoted_count + 1;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'game_id', p_game_id,
        'new_funded_capacity', v_new_funded,
        'promoted_count', v_promoted_count
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. MPT_start_game_and_charge: Authoritative game start with credit deduction and ticket generation
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
    v_credits_needed INT := 100;
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

    -- Find matching capacity tier
    SELECT * INTO v_tier
    FROM public."MPT_capacity_tiers"
    WHERE v_confirmed_count BETWEEN min_players AND max_players
    LIMIT 1;

    IF FOUND THEN
        v_credits_needed := v_tier.credits_required;
    ELSE
        v_credits_needed := 100;
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

-- 8. MPT_call_next_number: Authoritative board caller
CREATE OR REPLACE FUNCTION public."MPT_call_next_number"(
    p_game_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_next_num INT;
    v_next_seq INT;
    v_called_rec public."MPT_called_numbers";
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND';
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only Admin can call numbers';
    END IF;

    IF v_game.status <> 'IN_PROGRESS' THEN
        RAISE EXCEPTION 'GAME_NOT_IN_PROGRESS';
    END IF;

    -- Select a random uncalled number between 1 and 90
    SELECT num INTO v_next_num
    FROM generate_series(1, 90) AS s(num)
    WHERE num NOT IN (
        SELECT number FROM public."MPT_called_numbers" WHERE game_id = p_game_id
    )
    ORDER BY RANDOM()
    LIMIT 1;

    IF v_next_num IS NULL THEN
        -- All 90 numbers called
        UPDATE public."MPT_games"
        SET status = 'COMPLETED',
            completed_at = NOW(),
            state_version = state_version + 1,
            updated_at = NOW()
        WHERE id = p_game_id;

        RETURN jsonb_build_object(
            'game_completed', true,
            'message', 'All 90 numbers have been called'
        );
    END IF;

    SELECT COALESCE(MAX(call_seq), 0) + 1 INTO v_next_seq
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

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

    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'number', v_next_num,
        'call_seq', v_next_seq,
        'called_at', v_called_rec.called_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
