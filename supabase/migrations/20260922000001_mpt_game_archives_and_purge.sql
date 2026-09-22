-- =====================================================================
-- Migration: 20260922000001_mpt_game_archives_and_purge.sql
-- Description:
--   1. Creates MPT_game_archives table to store lightweight (1-2 KB) summaries
--      of completed games with full winners roster, duration, and metrics.
--   2. Adds MPT_archive_concluded_game RPC to snapshot games automatically.
--   3. Adds MPT_backfill_all_archives RPC to archive all existing finished games.
--   4. Adds MPT_purge_old_games RPC for 30-day cleanup of raw ticket/draw tables
--      while preserving 100% of winner records and organizer claim references.
--   5. Enables public read RLS for public Hall of Fame page (recent-games.html).
-- =====================================================================

CREATE TABLE IF NOT EXISTS public."MPT_game_archives" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID UNIQUE NOT NULL,
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL,
    admin_user_id UUID REFERENCES public."MPT_users"(id) ON DELETE SET NULL,
    game_type TEXT DEFAULT 'STANDARD_TAMBOLA',
    is_private BOOLEAN DEFAULT FALSE,
    funded_capacity INT DEFAULT 5,
    player_count INT DEFAULT 0,
    numbers_called_count INT DEFAULT 0,
    duration_seconds INT DEFAULT 0,
    winners_roster JSONB DEFAULT '[]'::jsonb,
    summary JSONB DEFAULT '{}'::jsonb,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    archived_at TIMESTAMPTZ DEFAULT NOW()
);

-- Ensure foreign key cascade is dropped if previously added so archives survive game purge
ALTER TABLE public."MPT_game_archives" DROP CONSTRAINT IF EXISTS "MPT_game_archives_game_id_fkey";

-- Enable RLS
ALTER TABLE public."MPT_game_archives" ENABLE ROW LEVEL SECURITY;

-- Allow public read of archived games for Recent Games Hall of Fame
DROP POLICY IF EXISTS "MPT_game_archives_read_all" ON public."MPT_game_archives";
CREATE POLICY "MPT_game_archives_read_all" ON public."MPT_game_archives"
    FOR SELECT USING (true);

-- Function to archive a single concluded game
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
        funded_capacity = EXCLUDED.funded_capacity,
        player_count = EXCLUDED.player_count,
        numbers_called_count = EXCLUDED.numbers_called_count,
        duration_seconds = EXCLUDED.duration_seconds,
        winners_roster = EXCLUDED.winners_roster,
        summary = EXCLUDED.summary,
        completed_at = EXCLUDED.completed_at,
        archived_at = NOW()
    RETURNING * INTO v_archive;

    RETURN jsonb_build_object(
        'success', true,
        'archive_id', v_archive.id,
        'game_id', v_archive.game_id,
        'player_count', v_archive.player_count,
        'winners_count', jsonb_array_length(v_winners)
    );
END;
$$;

-- Function to backfill all completed games into MPT_game_archives
CREATE OR REPLACE FUNCTION public."MPT_backfill_all_archives"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game_id UUID;
    v_count INT := 0;
BEGIN
    FOR v_game_id IN
        SELECT id FROM public."MPT_games"
        WHERE status = 'COMPLETED'
        ORDER BY created_at DESC
    LOOP
        PERFORM public."MPT_archive_concluded_game"(v_game_id);
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'archived_games_count', v_count
    );
END;
$$;

-- Function to safely purge raw ephemeral ticket & number call data older than retention days
CREATE OR REPLACE FUNCTION public."MPT_purge_old_games"(p_days_retention INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_purged_tickets INT := 0;
    v_purged_calls INT := 0;
    v_purged_claims INT := 0;
    v_cutoff TIMESTAMPTZ;
    v_game RECORD;
BEGIN
    v_cutoff := NOW() - (GREATEST(7, p_days_retention) || ' days')::INTERVAL;

    -- 1. Ensure all candidate games are archived before purging raw data
    FOR v_game IN
        SELECT id FROM public."MPT_games"
        WHERE status = 'COMPLETED' AND updated_at < v_cutoff
    LOOP
        PERFORM public."MPT_archive_concluded_game"(v_game.id);
    END LOOP;

    -- 2. Delete raw player tickets (biggest storage consumer)
    WITH deleted_tickets AS (
        DELETE FROM public."MPT_player_tickets"
        WHERE game_id IN (
            SELECT id FROM public."MPT_games"
            WHERE status = 'COMPLETED' AND updated_at < v_cutoff
        )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_purged_tickets FROM deleted_tickets;

    -- 3. Delete raw 1..90 called numbers logs
    WITH deleted_calls AS (
        DELETE FROM public."MPT_called_numbers"
        WHERE game_id IN (
            SELECT id FROM public."MPT_games"
            WHERE status = 'COMPLETED' AND updated_at < v_cutoff
        )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_purged_calls FROM deleted_calls;

    -- 4. Delete rejected / bogey claims (keep approved for history)
    WITH deleted_rejected_claims AS (
        DELETE FROM public."MPT_claims"
        WHERE status <> 'APPROVED'
          AND game_id IN (
              SELECT id FROM public."MPT_games"
              WHERE status = 'COMPLETED' AND updated_at < v_cutoff
          )
        RETURNING id
    )
    SELECT COUNT(*) INTO v_purged_claims FROM deleted_claims;

    RETURN jsonb_build_object(
        'success', true,
        'retention_days', p_days_retention,
        'cutoff_date', v_cutoff,
        'purged_tickets', v_purged_tickets,
        'purged_calls', v_purged_calls,
        'purged_rejected_claims', v_purged_claims
    );
END;
$$;

-- Grant permissions to authenticated and anon roles
GRANT SELECT ON public."MPT_game_archives" TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public."MPT_archive_concluded_game"(UUID) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public."MPT_backfill_all_archives"() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public."MPT_purge_old_games"(INT) TO authenticated;
