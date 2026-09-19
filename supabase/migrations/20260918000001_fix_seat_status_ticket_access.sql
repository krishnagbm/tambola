-- =====================================================================
-- Migration: 20260918000001_fix_seat_status_ticket_access.sql
-- Description: 
--   1. Ensures MPT_generate_ticket_matrix() strictly adheres to standard
--      3x9 Tambola rules (exactly 5 numbers in Row 1, 5 in Row 2, 5 in Row 3).
--   2. Allows players with seat_status IN ('ELIGIBLE', 'CONFIRMED')
--      to fetch/create unique player tickets and submit prize claims.
-- =====================================================================

-- 1. Strictly Validated 3x9 Tambola Ticket Matrix Generator (5, 5, 5 per row)
CREATE OR REPLACE FUNCTION public."MPT_generate_ticket_matrix"()
RETURNS JSONB AS $$
DECLARE
    v_matrix INT[][] := ARRAY[
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0]
    ];
    v_pattern INT;
    v_col INT;
    v_min INT;
    v_max INT;
    v_count INT;
    v_values INT[];
BEGIN
    -- Randomly select 1 of 8 verified structural templates (strictly 5 per row, 1-2 per column)
    v_pattern := FLOOR(RANDOM() * 8 + 1)::INT;

    FOR v_col IN 1..9 LOOP
        v_min := CASE WHEN v_col = 1 THEN 1 ELSE (v_col - 1) * 10 END;
        v_max := CASE WHEN v_col = 9 THEN 90 ELSE (v_col * 10) - 1 END;

        CASE v_pattern
            WHEN 1 THEN v_count := CASE WHEN v_col IN (1, 3, 5, 6, 8, 9) THEN 2 ELSE 1 END;
            WHEN 2 THEN v_count := CASE WHEN v_col IN (1, 2, 4, 5, 6, 8) THEN 2 ELSE 1 END;
            WHEN 3 THEN v_count := CASE WHEN v_col IN (1, 2, 3, 6, 7, 9) THEN 2 ELSE 1 END;
            WHEN 4 THEN v_count := CASE WHEN v_col IN (1, 2, 4, 5, 7, 8) THEN 2 ELSE 1 END;
            WHEN 5 THEN v_count := CASE WHEN v_col IN (2, 3, 4, 6, 8, 9) THEN 2 ELSE 1 END;
            WHEN 6 THEN v_count := CASE WHEN v_col IN (1, 2, 4, 5, 7, 8) THEN 2 ELSE 1 END;
            WHEN 7 THEN v_count := CASE WHEN v_col IN (1, 3, 4, 6, 7, 9) THEN 2 ELSE 1 END;
            WHEN 8 THEN v_count := CASE WHEN v_col IN (1, 2, 4, 5, 6, 8) THEN 2 ELSE 1 END;
        END CASE;

        -- High-entropy cryptographic number draw sorted vertically
        SELECT array_agg(number ORDER BY number)
        INTO v_values
        FROM (
            SELECT number
            FROM generate_series(v_min, v_max) AS numbers(number)
            ORDER BY md5(clock_timestamp()::TEXT || random()::TEXT || number::TEXT)
            LIMIT v_count
        ) selected;

        -- Place values into row coordinates
        CASE v_pattern
            WHEN 1 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[2][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[2][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 2 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[2][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[2][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[2][8] := v_values[2];
                    WHEN 9 THEN v_matrix[3][9] := v_values[1];
                END CASE;
            WHEN 3 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[2][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1];
                    WHEN 5 THEN v_matrix[3][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[2][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1]; v_matrix[3][9] := v_values[2];
                END CASE;
            WHEN 4 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[2][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[2][8] := v_values[2];
                    WHEN 9 THEN v_matrix[3][9] := v_values[1];
                END CASE;
            WHEN 5 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[2][1] := v_values[1];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[2][4] := v_values[2];
                    WHEN 5 THEN v_matrix[3][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[2][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 6 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[2][4] := v_values[2];
                    WHEN 5 THEN v_matrix[2][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[3][6] := v_values[1];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1]; v_matrix[2][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1];
                END CASE;
            WHEN 7 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[2][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[3][8] := v_values[1];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 8 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[2][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[2][2] := v_values[2];
                    WHEN 3 THEN v_matrix[3][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[2][5] := v_values[2];
                    WHEN 6 THEN v_matrix[2][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1];
                END CASE;
        END CASE;
    END LOOP;

    RETURN to_jsonb(v_matrix);
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

-- 2. Update MPT_get_or_create_player_ticket to accept both 'ELIGIBLE' and 'CONFIRMED'
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

    -- Verify player is registered with a confirmed/eligible seat in this game
    SELECT registration_seq, seat_status INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status NOT IN ('ELIGIBLE', 'CONFIRMED') THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: Player does not have an active confirmed seat for this game (status: %)', COALESCE(v_reg.seat_status, 'NONE');
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
    ON CONFLICT (game_id, user_id, ticket_number) DO NOTHING;

    -- Re-select in case of concurrent insert race condition
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid;

    RETURN v_ticket;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Update RLS policy for MPT_player_tickets to allow insert for 'CONFIRMED' or 'ELIGIBLE' seats
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
          AND r.seat_status IN ('ELIGIBLE', 'CONFIRMED')
    )
);

-- 4. Update MPT_submit_claim to accept both 'ELIGIBLE' and 'CONFIRMED' seats
CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers INT[],
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_reg RECORD;
    v_ticket public."MPT_player_tickets";
    v_already_won BOOLEAN;
    v_is_valid BOOLEAN := FALSE;
    v_claim_id UUID;
    v_row1 INT[];
    v_row2 INT[];
    v_row3 INT[];
    v_called_numbers INT[];
    v_early5_count INT := 0;
    v_row_count INT := 0;
    v_fh_count INT := 0;
    v_num INT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    -- Verify player is registered with an active seat
    SELECT * INTO v_reg
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND OR v_reg.seat_status NOT IN ('ELIGIBLE', 'CONFIRMED') THEN
        RAISE EXCEPTION 'NOT_ELIGIBLE: Player seat status is %', COALESCE(v_reg.seat_status, 'NOT_REGISTERED');
    END IF;

    -- Check if prize already claimed/approved
    SELECT EXISTS (
        SELECT 1 FROM public."MPT_claims"
        WHERE game_id = p_game_id AND prize_type = p_prize_type AND status = 'APPROVED'
    ) INTO v_already_won;

    IF v_already_won THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, validation_details, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'REJECTED',
            jsonb_build_object('reason', 'Prize already won by another player'), p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'REJECTED',
            'reason', 'Prize already won by another player'
        );
    END IF;

    -- Fetch player ticket
    SELECT * INTO v_ticket
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id AND user_id = v_uid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NO_TICKET_FOUND: No ticket issued for player';
    END IF;

    -- Fetch all called numbers so far
    SELECT array_agg(number ORDER BY call_seq)
    INTO v_called_numbers
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- Extract ticket rows
    v_row1 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->0)::INT);
    v_row2 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->1)::INT);
    v_row3 := ARRAY(SELECT jsonb_array_elements_text(v_ticket.ticket_matrix->2)::INT);

    -- Validate claim pattern
    IF p_prize_type = 'EARLY_FIVE' THEN
        v_early5_count := 0;
        FOREACH v_num IN ARRAY p_marked_numbers LOOP
            IF (v_num = ANY(v_row1) OR v_num = ANY(v_row2) OR v_num = ANY(v_row3))
               AND v_num = ANY(v_called_numbers) THEN
                v_early5_count := v_early5_count + 1;
            END IF;
        END LOOP;
        IF v_early5_count >= 5 AND array_length(p_marked_numbers, 1) = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'TOP_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row1 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(p_marked_numbers) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'MIDDLE_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row2 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(p_marked_numbers) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'BOTTOM_LINE' THEN
        v_row_count := 0;
        FOREACH v_num IN ARRAY v_row3 LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(p_marked_numbers) AND v_num = ANY(v_called_numbers) THEN
                    v_row_count := v_row_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_row_count = 5 THEN
            v_is_valid := TRUE;
        END IF;

    ELSIF p_prize_type = 'FULL_HOUSE' THEN
        v_fh_count := 0;
        FOREACH v_num IN ARRAY (v_row1 || v_row2 || v_row3) LOOP
            IF v_num > 0 THEN
                IF v_num = ANY(p_marked_numbers) AND v_num = ANY(v_called_numbers) THEN
                    v_fh_count := v_fh_count + 1;
                END IF;
            END IF;
        END LOOP;
        IF v_fh_count = 15 THEN
            v_is_valid := TRUE;
        END IF;
    END IF;

    -- Record claim result
    IF v_is_valid THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, validation_details, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'APPROVED',
            jsonb_build_object('validated_at', NOW()), p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        -- Issue reward
        INSERT INTO public."MPT_rewards" (
            claim_id, user_id, game_id, prize_type, reward_title, reward_code, expires_at
        )
        VALUES (
            v_claim_id, v_uid, p_game_id, p_prize_type, p_prize_type || ' Winner',
            'DAB-' || UPPER(SUBSTRING(MD5(RANDOM()::TEXT) FROM 1 FOR 8)),
            NOW() + INTERVAL '30 days'
        )
        ON CONFLICT (claim_id) DO NOTHING;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'APPROVED',
            'prize_type', p_prize_type
        );
    ELSE
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, marked_numbers, status, validation_details, idempotency_key
        )
        VALUES (
            p_game_id, v_uid, p_prize_type, p_marked_numbers, 'REJECTED',
            jsonb_build_object('reason', 'Numbers claimed do not match ticket or called numbers sequence'),
            p_idempotency_key
        )
        RETURNING id INTO v_claim_id;

        RETURN jsonb_build_object(
            'claim_id', v_claim_id,
            'status', 'REJECTED',
            'reason', 'Claim verification failed'
        );
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
