-- =====================================================================
-- Migration: 20260911000001_mega_event_ticket_issuance_unification.sql
-- Description: Unify ticket generation behind canonical server-side RPC
--              (MPT_get_or_create_player_ticket) and introduce a 
--              threshold-gated lazy ticket issuance path for mega events.
-- =====================================================================

-- 1. Create canonical on-demand player ticket issuance RPC
CREATE OR REPLACE FUNCTION public."MPT_get_or_create_player_ticket"(
    p_game_id UUID
)
RETURNS public."MPT_player_tickets" AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_ticket public."MPT_player_tickets";
    v_reg RECORD;
    v_ticket_matrix JSONB;
    v_ticket_attempts INT := 0;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    -- Check if ticket already exists for this player in this game
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF FOUND THEN
        RETURN v_ticket;
    END IF;

    -- Verify player is ELIGIBLE in this game
    SELECT registration_seq, seat_status INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status <> 'ELIGIBLE' THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: Player does not have an ELIGIBLE seat for this game';
    END IF;

    -- Generate unique ticket matrix with collision retry loop (up to 100 attempts)
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

    -- Insert and return the newly generated ticket
    INSERT INTO public."MPT_player_tickets" (
        game_id, user_id, ticket_matrix, ticket_number
    )
    VALUES (
        p_game_id, v_uid, v_ticket_matrix, v_reg.registration_seq
    )
    ON CONFLICT (game_id, user_id, ticket_number) DO NOTHING
    RETURNING * INTO v_ticket;

    -- If conflict occurred (e.g. concurrent race condition), fetch the existing ticket
    IF v_ticket IS NULL THEN
        SELECT * INTO v_ticket
        FROM public."MPT_player_tickets"
        WHERE game_id = p_game_id AND user_id = v_uid;
    END IF;

    RETURN v_ticket;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Update MPT_start_game_and_charge with threshold-gated bulk ticket generation
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
    v_ticket_attempts INT;
    v_bulk_ticket_threshold CONSTANT INT := 300;
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

    -- Find tier matching confirmed player count, or minimum tier if 0 confirmed
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

    -- If confirmed player count <= threshold (<= 300, e.g. current 250 max tiers),
    -- pre-generate all tickets in bulk eagerly for instant display.
    -- If > threshold (e.g. Mega-X 1000+ players), skip bulk insertion loop;
    -- players will obtain their unique tickets on-demand via MPT_get_or_create_player_ticket.
    IF v_confirmed_count <= v_bulk_ticket_threshold THEN
        FOR v_reg IN
            SELECT user_id, registration_seq FROM public."MPT_game_registrations"
            WHERE game_id = p_game_id AND seat_status = 'ELIGIBLE'
              AND NOT EXISTS (
                  SELECT 1 FROM public."MPT_player_tickets" t
                  WHERE t.game_id = p_game_id AND t.user_id = public."MPT_game_registrations".user_id
              )
            ORDER BY registration_seq ASC
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
            VALUES (p_game_id, v_reg.user_id, v_ticket_matrix, v_reg.registration_seq)
            ON CONFLICT (game_id, user_id, ticket_number) DO NOTHING;
        END LOOP;
    END IF;

    RETURN jsonb_build_object(
        'game_id', p_game_id,
        'status', 'IN_PROGRESS',
        'eligible_players', v_confirmed_count,
        'credits_charged', v_credits_needed,
        'balance_remaining', v_new_balance,
        'lazy_ticket_issuance', (v_confirmed_count > v_bulk_ticket_threshold)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
