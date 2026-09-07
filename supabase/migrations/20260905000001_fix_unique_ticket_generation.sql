-- =====================================================================
-- Migration: 20260905000001_fix_unique_ticket_generation.sql
-- Description: Fix unique randomized ticket generation in PostgreSQL,
--              prevent PostgREST overload ambiguity on MPT_create_game,
--              and ensure atomic server-side ticket issuance on game start.
-- =====================================================================

-- 1. Drop obsolete 4-parameter MPT_create_game overload to prevent PostgREST HTTP 300
DROP FUNCTION IF EXISTS public."MPT_create_game"(TEXT, INT, TIMESTAMPTZ, JSONB);

-- 2. Generate a valid randomized 3x9 Tambola ticket matrix per eligible player.
--    Fix: Uses `FROM generate_series(...)` in the FROM clause with high-entropy ordering
--    so PostgreSQL evaluates the random sort across all generated numbers rather than
--    evaluating ORDER BY on a single row before SRF expansion.
CREATE OR REPLACE FUNCTION public."MPT_generate_ticket_matrix"()
RETURNS JSONB AS $$
DECLARE
    v_matrix INT[][];
    v_col INT;
    v_min INT;
    v_max INT;
    v_count INT;
    v_values INT[];
BEGIN
    -- Standard 3x9 grid: 5 numbers in each row, 1-3 numbers per column (15 numbers total)
    v_matrix := ARRAY[
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0]
    ];

    FOR v_col IN 1..9 LOOP
        v_min := CASE WHEN v_col = 1 THEN 1 ELSE (v_col - 1) * 10 END;
        v_max := CASE WHEN v_col = 9 THEN 90 ELSE (v_col * 10) - 1 END;
        v_count := CASE v_col
            WHEN 1 THEN 2
            WHEN 2 THEN 1
            WHEN 3 THEN 2
            WHEN 4 THEN 1
            WHEN 5 THEN 2
            WHEN 6 THEN 2
            WHEN 7 THEN 1
            WHEN 8 THEN 2
            ELSE 2
        END;

        -- Select distinct values in the column, then sort them vertically.
        SELECT array_agg(number ORDER BY number)
        INTO v_values
        FROM (
            SELECT number
            FROM generate_series(v_min, v_max) AS numbers(number)
            ORDER BY md5(clock_timestamp()::TEXT || random()::TEXT || number::TEXT)
            LIMIT v_count
        ) selected;

        CASE v_col
            WHEN 1 THEN
                v_matrix[1][v_col] := v_values[1];
                v_matrix[3][v_col] := v_values[2];
            WHEN 2 THEN
                v_matrix[2][v_col] := v_values[1];
            WHEN 3 THEN
                v_matrix[1][v_col] := v_values[1];
                v_matrix[3][v_col] := v_values[2];
            WHEN 4 THEN
                v_matrix[2][v_col] := v_values[1];
            WHEN 5 THEN
                v_matrix[1][v_col] := v_values[1];
                v_matrix[3][v_col] := v_values[2];
            WHEN 6 THEN
                v_matrix[2][v_col] := v_values[1];
                v_matrix[3][v_col] := v_values[2];
            WHEN 7 THEN
                v_matrix[1][v_col] := v_values[1];
            WHEN 8 THEN
                v_matrix[2][v_col] := v_values[1];
                v_matrix[3][v_col] := v_values[2];
            ELSE
                v_matrix[1][v_col] := v_values[1];
                v_matrix[2][v_col] := v_values[2];
        END CASE;
    END LOOP;

    RETURN to_jsonb(v_matrix);
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

-- 3. MPT_start_game_and_charge: Authoritative game start with credit deduction and unique ticket generation
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
    v_ticket_attempts INT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

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

    SELECT COUNT(*) INTO v_confirmed_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    SELECT * INTO v_tier
    FROM public."MPT_capacity_tiers"
    WHERE v_confirmed_count BETWEEN min_players AND max_players
      AND is_active = TRUE
    ORDER BY credits_required ASC
    LIMIT 1;

    IF FOUND THEN
        v_credits_needed := v_tier.credits_required;
    ELSE
        SELECT * INTO v_tier
        FROM public."MPT_capacity_tiers"
        WHERE max_players >= v_confirmed_count AND is_active = TRUE
        ORDER BY credits_required ASC
        LIMIT 1;

        IF FOUND THEN
            v_credits_needed := v_tier.credits_required;
        ELSE
            SELECT COALESCE(MIN(credits_required), 10) INTO v_credits_needed
            FROM public."MPT_capacity_tiers"
            WHERE is_active = TRUE;
        END IF;
    END IF;

    SELECT * INTO v_wallet
    FROM public."MPT_admin_wallets"
    WHERE user_id = v_uid
    FOR UPDATE;

    IF NOT FOUND OR v_wallet.available_credits < v_credits_needed THEN
        RAISE EXCEPTION 'INSUFFICIENT_CREDITS: Required %, available %',
            v_credits_needed, COALESCE(v_wallet.available_credits, 0);
    END IF;

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
        'Game start charge for ' || v_confirmed_count || ' players', p_idempotency_key
    );

    INSERT INTO public."MPT_game_charges" (game_id, tier_id, player_count, credits_charged)
    VALUES (p_game_id, v_tier.id, v_confirmed_count, v_credits_needed);

    UPDATE public."MPT_game_registrations"
    SET seat_status = 'ELIGIBLE', updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'CONFIRMED';

    UPDATE public."MPT_game_registrations"
    SET seat_status = 'NOT_ELIGIBLE', updated_at = NOW()
    WHERE game_id = p_game_id AND seat_status = 'WAITING';

    UPDATE public."MPT_games"
    SET status = 'IN_PROGRESS',
        final_capacity = v_confirmed_count,
        started_at = NOW(),
        state_version = state_version + 1,
        updated_at = NOW()
    WHERE id = p_game_id;

    FOR v_reg IN
        SELECT user_id FROM public."MPT_game_registrations"
        WHERE game_id = p_game_id AND seat_status = 'ELIGIBLE'
          AND NOT EXISTS (
              SELECT 1 FROM public."MPT_player_tickets" t
              WHERE t.game_id = p_game_id AND t.user_id = public."MPT_game_registrations".user_id
          )
    LOOP
        v_ticket_attempts := 0;
        LOOP
            v_ticket_matrix := public."MPT_generate_ticket_matrix"();
            EXIT WHEN NOT EXISTS (
                SELECT 1
                FROM public."MPT_player_tickets"
                WHERE game_id = p_game_id
                  AND ticket_matrix = v_ticket_matrix
            );

            v_ticket_attempts := v_ticket_attempts + 1;
            IF v_ticket_attempts >= 100 THEN
                RAISE EXCEPTION 'TICKET_GENERATION_FAILED: Could not create a unique ticket after 100 attempts';
            END IF;
        END LOOP;

        INSERT INTO public."MPT_player_tickets" (
            game_id, user_id, ticket_matrix, ticket_number
        )
        VALUES (p_game_id, v_reg.user_id, v_ticket_matrix, 1)
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

-- 4. Allow the client fallback to create only its own ticket after eligibility
--    has been established. The normal game-start RPC inserts tickets server-side.
DROP POLICY IF EXISTS "MPT_player_tickets_insert_self" ON public."MPT_player_tickets";
CREATE POLICY "MPT_player_tickets_insert_self"
ON public."MPT_player_tickets"
FOR INSERT
WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
        SELECT 1
        FROM public."MPT_game_registrations" r
        WHERE r.game_id = public."MPT_player_tickets".game_id
          AND r.user_id = auth.uid()
          AND r.seat_status = 'ELIGIBLE'
    )
);
