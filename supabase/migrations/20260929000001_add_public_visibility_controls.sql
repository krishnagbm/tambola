-- Migration: 20260929000001_add_public_visibility_controls.sql
-- Adds admin-controlled visibility columns and prevents cancelled/private games from appearing on the public Recent Games page.

ALTER TABLE public."MPT_games"
    ADD COLUMN IF NOT EXISTS is_publicly_visible BOOLEAN NOT NULL DEFAULT TRUE;

ALTER TABLE public."MPT_game_archives"
    ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'COMPLETED',
    ADD COLUMN IF NOT EXISTS is_publicly_visible BOOLEAN NOT NULL DEFAULT TRUE;

UPDATE public."MPT_game_archives"
SET status = 'COMPLETED', is_publicly_visible = TRUE
WHERE status IS NULL OR is_publicly_visible IS NULL;

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
    v_status TEXT;
    v_public_visible BOOLEAN;
BEGIN
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Game not found');
    END IF;

    v_status := COALESCE(v_game.status, 'COMPLETED');
    v_public_visible := COALESCE(v_game.is_publicly_visible, true)
        AND NOT COALESCE(v_game.is_private, false)
        AND v_status <> 'CANCELLED';

    SELECT COUNT(*) INTO v_player_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');

    SELECT COUNT(*) INTO v_numbers_called_count
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    v_duration_seconds := GREATEST(0, EXTRACT(EPOCH FROM (COALESCE(v_game.updated_at, NOW()) - COALESCE(v_game.created_at, NOW())))::INT);

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
        v_game.game_type,
        v_game.is_private,
        v_game.funded_capacity,
        v_player_count,
        v_numbers_called_count,
        v_duration_seconds,
        v_winners,
        jsonb_build_object(
            'total_claims_count', (SELECT COUNT(*) FROM public."MPT_claims" WHERE game_id = p_game_id),
            'approved_prizes_count', jsonb_array_length(v_winners)
        ),
        v_game.created_at,
        COALESCE(v_game.updated_at, NOW()),
        v_game.created_at,
        NOW(),
        v_status,
        v_public_visible
    )
    ON CONFLICT (game_id) DO UPDATE SET
        name = EXCLUDED.name,
        funded_capacity = EXCLUDED.funded_capacity,
        player_count = EXCLUDED.player_count,
        numbers_called_count = EXCLUDED.numbers_called_count,
        duration_seconds = EXCLUDED.duration_seconds,
        winners_roster = EXCLUDED.winners_roster,
        summary = EXCLUDED.summary,
        completed_at = EXCLUDED.completed_at,
        archived_at = NOW(),
        status = EXCLUDED.status,
        is_publicly_visible = EXCLUDED.is_publicly_visible
    RETURNING * INTO v_archive;

    RETURN jsonb_build_object(
        'success', true,
        'archive_id', v_archive.id,
        'game_id', v_archive.game_id,
        'player_count', v_archive.player_count,
        'winners_count', jsonb_array_length(v_winners),
        'is_publicly_visible', v_archive.is_publicly_visible
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_archive_concluded_game"(UUID) TO anon, authenticated;
