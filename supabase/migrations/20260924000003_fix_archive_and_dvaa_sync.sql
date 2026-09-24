-- =====================================================================
-- Migration: 20260924000003_fix_archive_and_dvaa_sync.sql
-- Description:
--   1. Fixes MPT_archive_concluded_game (replaces invalid t.registration_seq
--      and v_game.game_type references, ensures accurate duration and
--      FULL_HOUSE-first winner ordering, and marks MPT_games COMPLETED).
--   2. Updates MPT_verify_and_approve_brand so approving a brand on an
--      already-completed game immediately archives/updates it in Hall of Fame.
--   3. Updates MPT_submit_claim so winning FULL_HOUSE automatically marks
--      the game COMPLETED and archives it to MPT_game_archives.
--   4. Backfills all COMPLETED games (including 4E196B) into MPT_game_archives.
-- =====================================================================

-- 1. Fix MPT_archive_concluded_game
CREATE OR REPLACE FUNCTION public."MPT_archive_concluded_game"(p_game_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game public."MPT_games";
    v_player_count INT := 0;
    v_numbers_called_count INT := 0;
    v_duration_seconds INT := 0;
    v_effective_completed_at TIMESTAMPTZ;
    v_winners JSONB := '[]'::jsonb;
    v_archive public."MPT_game_archives";
BEGIN
    -- 1. Fetch game details
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Game not found');
    END IF;

    -- 2. Calculate effective completion timestamp (guard against client local timezone offset bugs)
    v_effective_completed_at := GREATEST(
        COALESCE(v_game.completed_at, v_game.updated_at, NOW()),
        COALESCE(
            (SELECT MAX(submitted_at) FROM public."MPT_claims" WHERE game_id = p_game_id),
            v_game.started_at,
            v_game.created_at,
            NOW()
        )
    );

    -- Ensure the game row itself is marked COMPLETED with accurate completed_at
    UPDATE public."MPT_games"
    SET
        status = 'COMPLETED',
        completed_at = v_effective_completed_at,
        updated_at = NOW()
    WHERE id = p_game_id;

    -- 3. Calculate confirmed players (fallback to final_capacity or funded_capacity)
    SELECT COUNT(*) INTO v_player_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');

    v_player_count := GREATEST(v_player_count, COALESCE(v_game.final_capacity, 0), COALESCE(v_game.funded_capacity, 5));

    -- 4. Calculate numbers called count
    SELECT COUNT(*) INTO v_numbers_called_count
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- 5. Calculate duration in seconds from started_at (or created_at) to effective completion
    v_duration_seconds := GREATEST(
        10,
        EXTRACT(EPOCH FROM (v_effective_completed_at - COALESCE(v_game.started_at, v_game.created_at, v_effective_completed_at)))::INT
    );

    -- 6. Aggregate all APPROVED winners with names, avatars, and voucher claim references
    --    Order with FULL_HOUSE (Grand Prize) first, then standard prize hierarchy
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'prize_type', c.prize_type,
                'winner_name', COALESCE(NULLIF(r.display_name, ''), NULLIF(u.display_name, ''), 'Player'),
                'winner_avatar', COALESCE(r.avatar, u.avatar, 'avatar_lion'),
                'ticket_seq', COALESCE(t.ticket_number, r.registration_seq, 1),
                'claim_reference', COALESCE(
                    (
                        SELECT rw.claim_reference
                        FROM public."MPT_rewards" rw
                        WHERE rw.claim_id = c.id
                           OR (rw.game_id = c.game_id AND rw.user_id = c.user_id AND rw.prize_type = c.prize_type)
                        LIMIT 1
                    ),
                    ''
                ),
                'verified_at', COALESCE(c.processed_at, c.submitted_at, NOW())
            )
            ORDER BY
                CASE
                    WHEN c.prize_type = 'FULL_HOUSE' THEN 0
                    WHEN c.prize_type = 'SECOND_FULL_HOUSE' THEN 1
                    WHEN c.prize_type = 'TOP_LINE' THEN 2
                    WHEN c.prize_type = 'MIDDLE_LINE' THEN 3
                    WHEN c.prize_type = 'BOTTOM_LINE' THEN 4
                    WHEN c.prize_type IN ('EARLY_FIVE', 'EARLY_5') THEN 5
                    WHEN c.prize_type = 'FOUR_CORNERS' THEN 6
                    ELSE 7
                END ASC,
                c.submitted_at ASC
        ),
        '[]'::jsonb
    ) INTO v_winners
    FROM public."MPT_claims" c
    LEFT JOIN public."MPT_game_registrations" r ON (r.game_id = c.game_id AND r.user_id = c.user_id)
    LEFT JOIN public."MPT_users" u ON u.id = c.user_id
    LEFT JOIN public."MPT_player_tickets" t ON (t.game_id = c.game_id AND t.user_id = c.user_id)
    WHERE c.game_id = p_game_id AND c.status = 'APPROVED';

    -- 7. Upsert into MPT_game_archives
    INSERT INTO public."MPT_game_archives" (
        game_id,
        name,
        invite_code,
        admin_user_id,
        game_type,
        is_private,
        funded_capacity,
        player_count,
        numbers_called_count,
        duration_seconds,
        winners_roster,
        organization_name,
        organization_logo_url,
        organization_logo_alt,
        organization_logo_approved,
        summary,
        started_at,
        completed_at,
        created_at,
        archived_at
    )
    VALUES (
        v_game.id,
        v_game.name,
        v_game.invite_code,
        v_game.admin_user_id,
        'STANDARD_TAMBOLA',
        COALESCE(v_game.is_private, FALSE),
        COALESCE(v_game.funded_capacity, 5),
        v_player_count,
        v_numbers_called_count,
        v_duration_seconds,
        v_winners,
        v_game.organization_name,
        v_game.organization_logo_url,
        v_game.organization_logo_alt,
        COALESCE(v_game.organization_logo_approved, FALSE),
        jsonb_build_object(
            'total_claims_count', (SELECT COUNT(*) FROM public."MPT_claims" WHERE game_id = p_game_id),
            'approved_prizes_count', jsonb_array_length(v_winners)
        ),
        COALESCE(v_game.started_at, v_game.created_at),
        v_effective_completed_at,
        v_game.created_at,
        NOW()
    )
    ON CONFLICT (game_id) DO UPDATE SET
        name = EXCLUDED.name,
        invite_code = EXCLUDED.invite_code,
        is_private = EXCLUDED.is_private,
        funded_capacity = EXCLUDED.funded_capacity,
        player_count = EXCLUDED.player_count,
        numbers_called_count = EXCLUDED.numbers_called_count,
        duration_seconds = EXCLUDED.duration_seconds,
        winners_roster = EXCLUDED.winners_roster,
        organization_name = EXCLUDED.organization_name,
        organization_logo_url = EXCLUDED.organization_logo_url,
        organization_logo_alt = EXCLUDED.organization_logo_alt,
        organization_logo_approved = EXCLUDED.organization_logo_approved,
        summary = EXCLUDED.summary,
        started_at = EXCLUDED.started_at,
        completed_at = EXCLUDED.completed_at,
        archived_at = NOW()
    RETURNING * INTO v_archive;

    RETURN jsonb_build_object(
        'success', true,
        'archived_game_id', v_archive.id,
        'game_id', v_archive.game_id,
        'invite_code', v_archive.invite_code,
        'player_count', v_archive.player_count,
        'winners_count', jsonb_array_length(v_archive.winners_roster),
        'organization_name', v_archive.organization_name,
        'organization_logo_approved', v_archive.organization_logo_approved
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_archive_concluded_game"(UUID) TO anon, authenticated;

-- 2. Update MPT_verify_and_approve_brand so approving a completed game archives/updates it in Hall of Fame
CREATE OR REPLACE FUNCTION public."MPT_verify_and_approve_brand"(
    p_token TEXT,
    p_ip TEXT DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_approval public."MPT_brand_approvals";
    v_game public."MPT_games";
BEGIN
    SELECT * INTO v_approval
    FROM public."MPT_brand_approvals"
    WHERE approval_token = p_token
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid or unknown approval token');
    END IF;

    IF v_approval.status = 'APPROVED' THEN
        -- Ensure completed game is also archived in Hall of Fame if already approved
        SELECT * INTO v_game FROM public."MPT_games" WHERE id = v_approval.game_id;
        IF FOUND AND v_game.status = 'COMPLETED' THEN
            PERFORM public."MPT_archive_concluded_game"(v_approval.game_id);
        END IF;
        RETURN jsonb_build_object(
            'success', true,
            'already_approved', true,
            'message', 'Organization brand was already approved',
            'organization_name', v_approval.organization_name
        );
    END IF;

    IF v_approval.expires_at < NOW() THEN
        UPDATE public."MPT_brand_approvals"
        SET status = 'EXPIRED'
        WHERE id = v_approval.id;
        RETURN jsonb_build_object('success', false, 'message', 'Approval token has expired');
    END IF;

    -- 1. Mark brand approval record as APPROVED with audit metadata
    UPDATE public."MPT_brand_approvals"
    SET
        status = 'APPROVED',
        approved_at = NOW(),
        approved_ip = p_ip,
        approved_user_agent = p_user_agent
    WHERE id = v_approval.id;

    -- 2. Activate approved flag on MPT_games
    UPDATE public."MPT_games"
    SET
        organization_name = v_approval.organization_name,
        organization_logo_url = v_approval.organization_logo_url,
        organization_logo_alt = v_approval.organization_name || ' Logo',
        organization_logo_approved = TRUE,
        updated_at = NOW()
    WHERE id = v_approval.game_id
    RETURNING * INTO v_game;

    -- 3. If game is COMPLETED, archive/upsert into MPT_game_archives so it appears immediately in Hall of Fame
    IF v_game.id IS NOT NULL AND v_game.status = 'COMPLETED' THEN
        PERFORM public."MPT_archive_concluded_game"(v_approval.game_id);
    ELSE
        UPDATE public."MPT_game_archives"
        SET
            organization_name = v_approval.organization_name,
            organization_logo_url = v_approval.organization_logo_url,
            organization_logo_alt = v_approval.organization_name || ' Logo',
            organization_logo_approved = TRUE
        WHERE game_id = v_approval.game_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'already_approved', false,
        'organization_name', v_approval.organization_name,
        'approved_at', NOW()
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_verify_and_approve_brand"(TEXT, TEXT, TEXT) TO anon, authenticated;

-- 3. Update MPT_submit_claim so winning FULL_HOUSE automatically concludes & archives the game
CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers INT[],
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_called_numbers INT[];
    v_uncalled INT[];
    v_existing_claim UUID;
    v_existing_reward public."MPT_rewards";
    v_claim_id UUID;
    v_claim_ref TEXT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- 1. Check idempotency if provided
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_claim_id
        FROM public."MPT_claims"
        WHERE game_id = p_game_id
          AND user_id = v_uid
          AND prize_type = p_prize_type
          AND idempotency_key = p_idempotency_key
        LIMIT 1;

        IF v_claim_id IS NOT NULL THEN
            SELECT * INTO v_existing_reward
            FROM public."MPT_rewards"
            WHERE claim_id = v_claim_id
            LIMIT 1;

            RETURN jsonb_build_object(
                'status', 'APPROVED',
                'prize_type', p_prize_type,
                'claim_id', v_claim_id,
                'claim_reference', COALESCE(v_existing_reward.claim_reference, '')
            );
        END IF;
    END IF;

    -- 2. Check if this prize was already won in this game
    SELECT id INTO v_existing_claim
    FROM public."MPT_claims"
    WHERE game_id = p_game_id
      AND prize_type = p_prize_type
      AND status = 'APPROVED'
    LIMIT 1;

    IF v_existing_claim IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'REJECTED',
            'reason', 'Prize already won by another player'
        );
    END IF;

    -- 3. Fetch all called numbers for this game
    SELECT COALESCE(array_agg(number), ARRAY[]::INT[])
    INTO v_called_numbers
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- 4. Verify all marked numbers have been called
    SELECT COALESCE(array_agg(m), ARRAY[]::INT[])
    INTO v_uncalled
    FROM unnest(p_marked_numbers) AS m
    WHERE NOT (m = ANY(v_called_numbers));

    IF array_length(v_uncalled, 1) IS NOT NULL AND array_length(v_uncalled, 1) > 0 THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, status, marked_numbers, rejection_reason, idempotency_key, processed_at
        ) VALUES (
            p_game_id, v_uid, p_prize_type, 'BOGEY', to_jsonb(p_marked_numbers),
            'Contains uncalled numbers: ' || array_to_string(v_uncalled, ', '),
            p_idempotency_key, NOW()
        );

        RETURN jsonb_build_object(
            'status', 'BOGEY',
            'reason', 'Contains uncalled numbers: ' || array_to_string(v_uncalled, ', ')
        );
    END IF;

    -- 5. Insert APPROVED claim
    INSERT INTO public."MPT_claims" (
        game_id, user_id, prize_type, status, marked_numbers, idempotency_key, processed_at
    ) VALUES (
        p_game_id, v_uid, p_prize_type, 'APPROVED', to_jsonb(p_marked_numbers), p_idempotency_key, NOW()
    )
    RETURNING id INTO v_claim_id;

    -- 6. Generate canonical Dab-Housie-XXXX-XXXX voucher reference and insert into MPT_rewards
    v_claim_ref := 'Dab-Housie-'
        || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
        || '-'
        || upper(substr(replace(gen_random_uuid()::text, '-', ''), 5, 4));

    INSERT INTO public."MPT_rewards" (
        game_id, user_id, prize_type, claim_id, claim_reference, status
    ) VALUES (
        p_game_id, v_uid, p_prize_type, v_claim_id, v_claim_ref, 'AVAILABLE_TO_CLAIM'
    );

    -- 7. If FULL_HOUSE was won, automatically mark game COMPLETED and archive to Hall of Fame
    IF p_prize_type = 'FULL_HOUSE' THEN
        PERFORM public."MPT_archive_concluded_game"(p_game_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'APPROVED',
        'prize_type', p_prize_type,
        'claim_id', v_claim_id,
        'claim_reference', v_claim_ref
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_submit_claim"(UUID, TEXT, INT[], TEXT) TO anon, authenticated;

-- 4. Backfill all completed games into MPT_game_archives (including 4E196B)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM public."MPT_games" WHERE status = 'COMPLETED' LOOP
        PERFORM public."MPT_archive_concluded_game"(r.id);
    END LOOP;
END;
$$;
