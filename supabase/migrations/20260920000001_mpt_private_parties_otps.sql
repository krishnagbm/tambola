-- =====================================================================
-- Migration: 20260920000001_mpt_private_parties_otps.sql
-- Description: Adds Private Parties feature with Single-Use Seat OTPs,
--              Host Management RPCs (reissue, add seats, revoke),
--              and Option A Credit pricing for private events.
-- =====================================================================

-- 1. Add is_private column to MPT_games
ALTER TABLE public."MPT_games"
ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Create MPT_game_seat_otps table
CREATE TABLE IF NOT EXISTS public."MPT_game_seat_otps" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    seat_number INT NOT NULL,
    otp_code TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'UNCLAIMED' CHECK (status IN ('UNCLAIMED', 'CLAIMED', 'REVOKED')),
    claimed_by_user_id UUID REFERENCES public."MPT_users"(id) ON DELETE SET NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(game_id, seat_number),
    UNIQUE(game_id, otp_code)
);

-- Index for rapid lookups
CREATE INDEX IF NOT EXISTS idx_mpt_game_seat_otps_game_id ON public."MPT_game_seat_otps"(game_id);
CREATE INDEX IF NOT EXISTS idx_mpt_game_seat_otps_otp ON public."MPT_game_seat_otps"(game_id, otp_code);
CREATE INDEX IF NOT EXISTS idx_mpt_game_seat_otps_user ON public."MPT_game_seat_otps"(game_id, claimed_by_user_id);

-- Enable RLS
ALTER TABLE public."MPT_game_seat_otps" ENABLE ROW LEVEL SECURITY;

-- Host has full access to seat OTPs for their games
CREATE POLICY "mpt_game_seat_otps_admin_all" ON public."MPT_game_seat_otps"
FOR ALL USING (
    EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_game_seat_otps".game_id
          AND g.admin_user_id = auth.uid()
    )
);

-- Players can view the seat OTP they claimed
CREATE POLICY "mpt_game_seat_otps_player_select" ON public."MPT_game_seat_otps"
FOR SELECT USING (
    claimed_by_user_id = auth.uid()
);

-- Enable Supabase Realtime for live updates in Admin Lobby
ALTER PUBLICATION supabase_realtime ADD TABLE public."MPT_game_seat_otps";

-- 3. Helper function to generate single-use Seat OTPs
CREATE OR REPLACE FUNCTION public."MPT_generate_game_seat_otps"(
    p_game_id UUID,
    p_count INT,
    p_start_seat INT DEFAULT 1
)
RETURNS VOID AS $$
DECLARE
    v_seat INT;
    v_otp TEXT;
    v_exists BOOLEAN;
BEGIN
    FOR v_seat IN p_start_seat..(p_start_seat + p_count - 1) LOOP
        LOOP
            -- Generate a 6-digit numeric OTP (e.g. 581924)
            v_otp := (FLOOR(RANDOM() * 900000 + 100000))::TEXT;
            
            -- Ensure uniqueness within this game
            SELECT EXISTS (
                SELECT 1 FROM public."MPT_game_seat_otps"
                WHERE game_id = p_game_id AND otp_code = v_otp
            ) INTO v_exists;
            
            EXIT WHEN NOT v_exists;
        END LOOP;

        INSERT INTO public."MPT_game_seat_otps" (
            game_id, seat_number, otp_code, status
        )
        VALUES (
            p_game_id, v_seat, v_otp, 'UNCLAIMED'
        )
        ON CONFLICT (game_id, seat_number) DO UPDATE
        SET otp_code = EXCLUDED.otp_code,
            status = 'UNCLAIMED',
            claimed_by_user_id = NULL,
            claimed_at = NULL,
            updated_at = NOW();
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Update MPT_create_game to support is_private and OTP generation
CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    p_is_private BOOLEAN DEFAULT FALSE
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

    -- Generate a unique 6-character uppercase alphanumeric invite code
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
        prizes_config,
        is_private
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
        COALESCE(p_prizes_config, '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb),
        COALESCE(p_is_private, FALSE)
    )
    RETURNING * INTO v_game;

    -- If private party, automatically generate initial single-use Seat OTPs
    IF COALESCE(p_is_private, FALSE) = TRUE THEN
        PERFORM public."MPT_generate_game_seat_otps"(
            v_game.id,
            COALESCE(p_planned_capacity, 25),
            1
        );
    END IF;

    RETURN v_game;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. MPT_claim_seat_otp: Atomic seat OTP verification and binding
CREATE OR REPLACE FUNCTION public."MPT_claim_seat_otp"(
    p_game_id UUID,
    p_otp_code TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_clean_otp TEXT;
    v_seat RECORD;
    v_game RECORD;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Player must be authenticated';
    END IF;

    v_clean_otp := UPPER(TRIM(p_otp_code));
    IF v_clean_otp IS NULL OR v_clean_otp = '' THEN
        RAISE EXCEPTION 'INVALID_OTP: Please enter a valid seat passcode';
    END IF;

    -- Check game
    SELECT * INTO v_game FROM public."MPT_games" WHERE id = p_game_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game does not exist';
    END IF;

    IF NOT v_game.is_private THEN
        RETURN jsonb_build_object('success', true, 'is_private', false);
    END IF;

    -- Look up seat OTP
    SELECT * INTO v_seat
    FROM public."MPT_game_seat_otps"
    WHERE game_id = p_game_id AND otp_code = v_clean_otp
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'INVALID_OTP: Invalid seat passcode for this event';
    END IF;

    IF v_seat.status = 'REVOKED' THEN
        RAISE EXCEPTION 'OTP_REVOKED: This seat passcode has been revoked by the organizer';
    END IF;

    -- If already claimed by this same user, allow reconnect
    IF v_seat.status = 'CLAIMED' AND v_seat.claimed_by_user_id = v_uid THEN
        RETURN jsonb_build_object(
            'success', true,
            'seat_number', v_seat.seat_number,
            'is_existing', true
        );
    END IF;

    -- If already claimed by another user, reject
    IF v_seat.status = 'CLAIMED' AND v_seat.claimed_by_user_id <> v_uid THEN
        RAISE EXCEPTION 'OTP_ALREADY_CLAIMED: This seat passcode has already been claimed by another player';
    END IF;

    -- Claim seat for this user
    UPDATE public."MPT_game_seat_otps"
    SET status = 'CLAIMED',
        claimed_by_user_id = v_uid,
        claimed_at = NOW(),
        updated_at = NOW()
    WHERE id = v_seat.id;

    RETURN jsonb_build_object(
        'success', true,
        'seat_number', v_seat.seat_number,
        'is_existing', false
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Update MPT_register_player to enforce claimed seat for Private Parties
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
    v_seat RECORD;
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

    -- Lock the game row to prevent concurrent race conditions
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

    -- If private party, verify user has a claimed seat
    IF v_game.is_private THEN
        SELECT * INTO v_seat
        FROM public."MPT_game_seat_otps"
        WHERE game_id = p_game_id AND claimed_by_user_id = v_uid AND status = 'CLAIMED';

        IF NOT FOUND THEN
            RAISE EXCEPTION 'PRIVATE_GAME_OTP_REQUIRED: A valid claimed seat passcode is required to join this private party';
        END IF;
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

-- 7. Host Management RPCs: Reissue, Add Seats, Revoke

-- 7a. Reissue Seat OTP
CREATE OR REPLACE FUNCTION public."MPT_reissue_seat_otp"(
    p_game_id UUID,
    p_seat_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_game RECORD;
    v_seat RECORD;
    v_new_otp TEXT;
    v_exists BOOLEAN;
BEGIN
    SELECT * INTO v_game FROM public."MPT_games" WHERE id = p_game_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game not found';
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the game host can manage seat OTPs';
    END IF;

    SELECT * INTO v_seat
    FROM public."MPT_game_seat_otps"
    WHERE id = p_seat_id AND game_id = p_game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SEAT_NOT_FOUND: Seat not found';
    END IF;

    -- If seat was previously claimed by a user, delete their registration & tickets
    IF v_seat.claimed_by_user_id IS NOT NULL THEN
        DELETE FROM public."MPT_game_registrations"
        WHERE game_id = p_game_id AND user_id = v_seat.claimed_by_user_id;

        DELETE FROM public."MPT_player_tickets"
        WHERE game_id = p_game_id AND user_id = v_seat.claimed_by_user_id;
    END IF;

    -- Generate a fresh unique 6-digit OTP
    LOOP
        v_new_otp := (FLOOR(RANDOM() * 900000 + 100000))::TEXT;
        SELECT EXISTS (
            SELECT 1 FROM public."MPT_game_seat_otps"
            WHERE game_id = p_game_id AND otp_code = v_new_otp
        ) INTO v_exists;
        EXIT WHEN NOT v_exists;
    END LOOP;

    -- Update seat record
    UPDATE public."MPT_game_seat_otps"
    SET otp_code = v_new_otp,
        status = 'UNCLAIMED',
        claimed_by_user_id = NULL,
        claimed_at = NULL,
        updated_at = NOW()
    WHERE id = p_seat_id
    RETURNING * INTO v_seat;

    -- Update state version on game to notify listeners
    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'seat', row_to_json(v_seat)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7b. Add Seats to Private Party
CREATE OR REPLACE FUNCTION public."MPT_add_seat_otps"(
    p_game_id UUID,
    p_additional_seats INT
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_game RECORD;
    v_max_seat INT;
    v_new_capacity INT;
    v_new_tier_id UUID;
BEGIN
    IF p_additional_seats <= 0 OR p_additional_seats > 100 THEN
        RAISE EXCEPTION 'INVALID_COUNT: Additional seats must be between 1 and 100';
    END IF;

    SELECT * INTO v_game FROM public."MPT_games" WHERE id = p_game_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game not found';
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the game host can add seats';
    END IF;

    SELECT COALESCE(MAX(seat_number), 0) INTO v_max_seat
    FROM public."MPT_game_seat_otps"
    WHERE game_id = p_game_id;

    -- Generate new OTPs starting from v_max_seat + 1
    PERFORM public."MPT_generate_game_seat_otps"(
        p_game_id,
        p_additional_seats,
        v_max_seat + 1
    );

    v_new_capacity := v_game.funded_capacity + p_additional_seats;

    -- Find matching capacity tier for updated capacity
    SELECT id INTO v_new_tier_id
    FROM public."MPT_capacity_tiers"
    WHERE v_new_capacity BETWEEN min_players AND max_players
    LIMIT 1;

    -- Update game capacities and tier
    UPDATE public."MPT_games"
    SET funded_capacity = v_new_capacity,
        initial_funded_capacity = v_new_capacity,
        planned_capacity_tier_id = COALESCE(v_new_tier_id, planned_capacity_tier_id),
        state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'new_capacity', v_new_capacity,
        'added_seats', p_additional_seats
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7c. Revoke Seat OTP
CREATE OR REPLACE FUNCTION public."MPT_revoke_seat_otp"(
    p_game_id UUID,
    p_seat_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_game RECORD;
    v_seat RECORD;
BEGIN
    SELECT * INTO v_game FROM public."MPT_games" WHERE id = p_game_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game not found';
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the game host can revoke seats';
    END IF;

    SELECT * INTO v_seat
    FROM public."MPT_game_seat_otps"
    WHERE id = p_seat_id AND game_id = p_game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SEAT_NOT_FOUND: Seat not found';
    END IF;

    -- Remove claimant registration & tickets if any
    IF v_seat.claimed_by_user_id IS NOT NULL THEN
        DELETE FROM public."MPT_game_registrations"
        WHERE game_id = p_game_id AND user_id = v_seat.claimed_by_user_id;

        DELETE FROM public."MPT_player_tickets"
        WHERE game_id = p_game_id AND user_id = v_seat.claimed_by_user_id;
    END IF;

    UPDATE public."MPT_game_seat_otps"
    SET status = 'REVOKED',
        claimed_by_user_id = NULL,
        claimed_at = NULL,
        updated_at = NOW()
    WHERE id = p_seat_id
    RETURNING * INTO v_seat;

    UPDATE public."MPT_games"
    SET state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'seat', row_to_json(v_seat)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Update MPT_start_game to calculate credits based on Option A Private Party Rates
CREATE OR REPLACE FUNCTION public."MPT_start_game"(
    p_game_id UUID,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_confirmed_count INT;
    v_tier public."MPT_capacity_tiers";
    v_credits_needed INT := 0;
    v_wallet public."MPT_admin_wallets";
    v_new_balance INT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated to start game';
    END IF;

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND: Game % does not exist', p_game_id;
    END IF;

    IF v_game.admin_user_id <> v_uid THEN
        RAISE EXCEPTION 'UNAUTHORIZED: Only the game admin can start the game';
    END IF;

    IF v_game.status = 'IN_PROGRESS' THEN
        RETURN jsonb_build_object('success', true, 'message', 'Game already in progress', 'game', row_to_json(v_game));
    END IF;

    IF v_game.status NOT IN ('OPEN', 'READY_TO_START') THEN
        RAISE EXCEPTION 'INVALID_GAME_STATE: Cannot start game in status %', v_game.status;
    END IF;

    -- Count confirmed registered players
    SELECT COUNT(*) INTO v_confirmed_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    -- Credit calculation:
    -- If Private Party -> Option A rate schedule:
    --   1-5: 5 credits, 6-15: 20 credits, 16-25: 35 credits,
    --   26-50: 70 credits, 51-100: 135 credits, 101-250: 325 credits
    IF v_game.is_private THEN
        IF v_confirmed_count <= 5 THEN
            v_credits_needed := 5;
        ELSIF v_confirmed_count <= 15 THEN
            v_credits_needed := 20;
        ELSIF v_confirmed_count <= 25 THEN
            v_credits_needed := 35;
        ELSIF v_confirmed_count <= 50 THEN
            v_credits_needed := 70;
        ELSIF v_confirmed_count <= 100 THEN
            v_credits_needed := 135;
        ELSE
            v_credits_needed := 325;
        END IF;
    ELSE
        -- Standard Public Game Rate
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
            SELECT COALESCE(MIN(credits_required), 0) INTO v_credits_needed
            FROM public."MPT_capacity_tiers"
            WHERE is_active = TRUE;
        END IF;
    END IF;

    -- Fetch Admin Wallet
    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid
    FOR UPDATE;

    IF NOT FOUND OR v_wallet.available_credits < v_credits_needed THEN
        RAISE EXCEPTION 'INSUFFICIENT_CREDITS: Required %, available %',
            v_credits_needed, COALESCE(v_wallet.available_credits, 0);
    END IF;

    -- Deduct credits if > 0
    IF v_credits_needed > 0 THEN
        v_new_balance := v_wallet.available_credits - v_credits_needed;
        UPDATE public."MPT_admin_wallets"
        SET available_credits = v_new_balance,
            last_paid_game_at = NOW(),
            credits_expire_at = NOW() + INTERVAL '1 year',
            updated_at = NOW()
        WHERE user_id = v_uid;

        INSERT INTO public."MPT_credit_transactions" (
            user_id, type, amount, balance_after, reference_id, description, idempotency_key
        )
        VALUES (
            v_uid, 'GAME_CHARGE', -v_credits_needed, v_new_balance, p_game_id::TEXT,
            (CASE WHEN v_game.is_private THEN 'Private Party' ELSE 'Game' END) || ' start charge for ' || v_confirmed_count || ' players',
            p_idempotency_key
        );

        INSERT INTO public."MPT_game_charges" (game_id, tier_id, player_count, credits_charged)
        VALUES (p_game_id, v_tier.id, v_confirmed_count, v_credits_needed);
    ELSE
        v_new_balance := v_wallet.available_credits;
    END IF;

    -- Promote confirmed players to ELIGIBLE
    UPDATE public."MPT_game_registrations"
    SET seat_status = 'ELIGIBLE', updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    -- Freeze waiting players to NOT_ELIGIBLE
    UPDATE public."MPT_game_registrations"
    SET seat_status = 'NOT_ELIGIBLE', updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'WAITING';

    -- Update Game state to IN_PROGRESS
    UPDATE public."MPT_games"
    SET status = 'IN_PROGRESS',
        final_capacity = v_confirmed_count,
        started_at = NOW(),
        state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id
    RETURNING * INTO v_game;

    RETURN jsonb_build_object(
        'success', true,
        'game', row_to_json(v_game),
        'confirmed_players', v_confirmed_count,
        'credits_charged', v_credits_needed,
        'new_balance', v_new_balance
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
