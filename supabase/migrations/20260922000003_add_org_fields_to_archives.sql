-- =====================================================================
-- Migration: 20260922000003_add_org_fields_to_archives.sql
-- Description:
--   Adds optional organization and corporate identity columns to
--   MPT_games and MPT_game_archives, and updates MPT_archive_concluded_game
--   to snapshot approved organization details.
-- =====================================================================

-- 1. Add optional organization columns to MPT_games
ALTER TABLE public."MPT_games" 
ADD COLUMN IF NOT EXISTS organization_name TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_url TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_alt TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_approved BOOLEAN DEFAULT FALSE;

-- 2. Add optional organization columns to MPT_game_archives
ALTER TABLE public."MPT_game_archives" 
ADD COLUMN IF NOT EXISTS organization_name TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_url TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_alt TEXT,
ADD COLUMN IF NOT EXISTS organization_logo_approved BOOLEAN DEFAULT FALSE;

-- 3. Update MPT_archive_concluded_game RPC to snapshot organization info
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

    -- 2. Calculate confirmed players
    SELECT COUNT(*) INTO v_player_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');

    -- 3. Calculate numbers called count
    SELECT COUNT(*) INTO v_numbers_called_count
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- 4. Calculate duration in seconds
    v_duration_seconds := GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(v_game.updated_at, NOW()) - COALESCE(v_game.created_at, NOW())))::INT);

    -- 5. Aggregate all APPROVED winners with names, avatars, and voucher claim references
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'prize_type', c.prize_type,
                'winner_name', COALESCE(NULLIF(r.display_name, ''), NULLIF(u.display_name, ''), 'Player'),
                'winner_avatar', COALESCE(r.avatar, u.avatar, 'avatar_lion'),
                'ticket_seq', COALESCE(t.registration_seq, r.registration_seq, 1),
                'claim_reference', COALESCE(rw.claim_reference, ''),
                'verified_at', COALESCE(c.processed_at, c.submitted_at, NOW())
            ) ORDER BY c.submitted_at ASC
        ),
        '[]'::jsonb
    ) INTO v_winners
    FROM public."MPT_claims" c
    LEFT JOIN public."MPT_game_registrations" r ON (r.game_id = c.game_id AND r.user_id = c.user_id)
    LEFT JOIN public."MPT_users" u ON u.id = c.user_id
    LEFT JOIN public."MPT_player_tickets" t ON (t.game_id = c.game_id AND t.user_id = c.user_id)
    LEFT JOIN public."MPT_rewards" rw ON (rw.claim_id = c.id)
    WHERE c.game_id = p_game_id AND c.status = 'APPROVED';

    -- 6. Upsert into MPT_game_archives
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
        v_game.game_type,
        v_game.is_private,
        v_game.funded_capacity,
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
        v_game.created_at,
        COALESCE(v_game.updated_at, NOW()),
        v_game.created_at,
        NOW()
    )
    ON CONFLICT (game_id) DO UPDATE SET
        name = EXCLUDED.name,
        invite_code = EXCLUDED.invite_code,
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
