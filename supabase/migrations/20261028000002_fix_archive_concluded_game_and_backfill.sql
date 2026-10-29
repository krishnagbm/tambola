-- ==============================================================================
-- Migration: 20261028000002_fix_archive_concluded_game_and_backfill.sql
-- Fix: MPT_archive_concluded_game column typo (t.registration_seq -> t.ticket_number)
-- and v_game.game_type (MPT_games does not have game_type column)
-- and backfill all completed October games into MPT_game_archives
-- ==============================================================================

CREATE OR REPLACE FUNCTION public."MPT_archive_concluded_game"(p_game_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game RECORD;
    v_player_count INT := 0;
    v_numbers_called_count INT := 0;
    v_duration_seconds INT := 0;
    v_effective_completed_at TIMESTAMPTZ;
    v_winners JSONB := '[]'::jsonb;
    v_archive public."MPT_game_archives";
    v_status TEXT;
    v_public_visible BOOLEAN;
    v_calling_mode TEXT;
BEGIN
    -- 1. Fetch live game
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF v_game IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Game not found');
    END IF;

    -- 2. Determine status and visibility
    v_status := COALESCE(v_game.status, 'COMPLETED');
    v_public_visible := COALESCE(v_game.is_publicly_visible, true)
        AND NOT COALESCE(v_game.is_private, false)
        AND v_status <> 'CANCELLED';

    v_calling_mode := COALESCE(
        v_game.prize_gifts_config ->> '_calling_mode',
        'CLASSIC'
    );

    -- 3. Calculate effective completion time
    v_effective_completed_at := GREATEST(
        COALESCE(v_game.completed_at, v_game.updated_at, NOW()),
        COALESCE(
            (SELECT MAX(submitted_at) FROM public."MPT_claims" WHERE game_id = p_game_id),
            v_game.started_at,
            v_game.created_at,
            NOW()
        )
    );

    -- 4. Count players
    SELECT COUNT(*) INTO v_player_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');

    v_player_count := GREATEST(v_player_count, COALESCE(v_game.final_capacity, 0), COALESCE(v_game.funded_capacity, 5));

    -- 5. Count numbers called
    SELECT COUNT(*) INTO v_numbers_called_count
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- 6. Calculate duration
    v_duration_seconds := GREATEST(
        10,
        EXTRACT(EPOCH FROM (v_effective_completed_at - COALESCE(v_game.started_at, v_game.created_at, v_effective_completed_at)))::INT
    );

    -- 7. Aggregate approved winners (ticket_seq mapped to t.ticket_number or r.registration_seq)
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'prize_type', c.prize_type,
                'winner_name', COALESCE(NULLIF(r.display_name, ''), NULLIF(u.display_name, ''), 'Player'),
                'winner_avatar', COALESCE(r.avatar, u.avatar, 'avatar_lion'),
                'ticket_seq', COALESCE(t.ticket_number, r.registration_seq, 1),
                'claim_reference', COALESCE(rw.claim_reference, ''),
                'prize_value', COALESCE(
                    rw.prize_value,
                    CASE
                        WHEN (v_game.prize_gifts_config -> c.prize_type ->> 'prize_value') ~ '^[0-9]+(\.[0-9]+)?$'
                        THEN (v_game.prize_gifts_config -> c.prize_type ->> 'prize_value')::NUMERIC(10,2)
                        ELSE NULL
                    END
                ),
                'brand_name', COALESCE(
                    rw.fulfilled_brand_name,
                    v_game.prize_gifts_config -> c.prize_type ->> 'brand_name'
                ),
                'brand_domain', COALESCE(
                    v_game.prize_gifts_config -> c.prize_type ->> 'brand_domain',
                    bo.brand_domain
                ),
                'gift_title', COALESCE(
                    rw.fulfilled_gift_title,
                    v_game.prize_gifts_config -> c.prize_type ->> 'product_title'
                ),
                'product_url', COALESCE(
                    rw.fulfilled_product_url,
                    v_game.prize_gifts_config -> c.prize_type ->> 'product_url'
                ),
                'offer_id', COALESCE(
                    rw.brand_offer_id::TEXT,
                    v_game.prize_gifts_config -> c.prize_type ->> 'offer_id'
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
    LEFT JOIN LATERAL (
        SELECT *
        FROM public."MPT_rewards" rw_sub
        WHERE rw_sub.claim_id = c.id
           OR (rw_sub.game_id = c.game_id AND rw_sub.user_id = c.user_id AND rw_sub.prize_type = c.prize_type)
        LIMIT 1
    ) rw ON TRUE
    LEFT JOIN public."MPT_brand_offers" bo ON bo.id = rw.brand_offer_id
    WHERE c.game_id = p_game_id AND c.status = 'APPROVED';

    -- 8. Upsert into MPT_game_archives
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
        archived_at,
        status,
        is_publicly_visible
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
            'approved_prizes_count', jsonb_array_length(v_winners),
            'total_prize_budget', COALESCE(v_game.total_prize_budget, 0),
            'calling_mode', v_calling_mode
        ),
        COALESCE(v_game.started_at, v_game.created_at),
        v_effective_completed_at,
        v_game.created_at,
        NOW(),
        v_status,
        v_public_visible
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
        archived_at = NOW(),
        status = EXCLUDED.status,
        is_publicly_visible = EXCLUDED.is_publicly_visible
    RETURNING * INTO v_archive;

    RETURN jsonb_build_object(
        'success', true,
        'archive_id', v_archive.id,
        'game_id', v_archive.game_id,
        'invite_code', v_archive.invite_code,
        'player_count', v_archive.player_count,
        'winners_count', jsonb_array_length(v_winners),
        'is_publicly_visible', v_archive.is_publicly_visible
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_archive_concluded_game"(UUID) TO anon, authenticated;

-- Backfill all completed games in MPT_games that missed archiving due to the column typo
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT id, invite_code
        FROM public."MPT_games"
        WHERE status = 'COMPLETED'
        ORDER BY completed_at DESC NULLS LAST
    ) LOOP
        BEGIN
            PERFORM public."MPT_archive_concluded_game"(r.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Failed to archive game % (%): %', r.id, r.invite_code, SQLERRM;
        END;
    END LOOP;
END $$;
