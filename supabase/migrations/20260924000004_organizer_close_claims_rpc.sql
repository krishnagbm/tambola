-- ============================================================================
-- Migration: 20260924000004_organizer_close_claims_rpc.sql
-- Purpose:
-- 1. Allow Game Organizers (hosts) to view all prize rewards/claims for their
--    hosted games with full player details (nickname, avatar, ticket/seat #,
--    guest/registered status, email) and close/settle claims (individually or
--    all at once), optionally attaching a Brand Partner gift/voucher.
-- 2. Auto-heal any missing MPT_rewards rows for APPROVED claims in a game.
-- 3. Provide MPT_get_organizer_all_games_claims() for the Organizer Wallet
--    Claims & Brand Gift Fulfillment Hub.
-- 4. Add RLS policies on MPT_rewards for game organizers as a fallback.
-- ============================================================================

-- 0. Add optional Brand Gift Fulfillment columns to MPT_rewards
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS reward_code TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS reward_title TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS fulfilled_gift_title TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS fulfilled_brand_name TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS fulfilled_gift_code TEXT;
ALTER TABLE public."MPT_rewards" ADD COLUMN IF NOT EXISTS fulfillment_note TEXT;

-- 1. RLS Policies on MPT_rewards for Game Organizers
DROP POLICY IF EXISTS "Organizers can view rewards for their games" ON public."MPT_rewards";
CREATE POLICY "Organizers can view rewards for their games"
ON public."MPT_rewards"
FOR SELECT
USING (
    auth.uid() = user_id
    OR EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_rewards".game_id
          AND g.admin_user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM public."MPT_game_archives" a
        WHERE a.game_id = "MPT_rewards".game_id
          AND a.admin_user_id = auth.uid()
    )
);

DROP POLICY IF EXISTS "Organizers can update rewards for their games" ON public."MPT_rewards";
CREATE POLICY "Organizers can update rewards for their games"
ON public."MPT_rewards"
FOR UPDATE
USING (
    EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_rewards".game_id
          AND g.admin_user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM public."MPT_game_archives" a
        WHERE a.game_id = "MPT_rewards".game_id
          AND a.admin_user_id = auth.uid()
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_rewards".game_id
          AND g.admin_user_id = auth.uid()
    )
    OR EXISTS (
        SELECT 1 FROM public."MPT_game_archives" a
        WHERE a.game_id = "MPT_rewards".game_id
          AND a.admin_user_id = auth.uid()
    )
);

-- 2. RPC: MPT_get_game_rewards_for_host
CREATE OR REPLACE FUNCTION public."MPT_get_game_rewards_for_host"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_is_host BOOLEAN := FALSE;
    v_result JSONB := '[]'::jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public."MPT_games" WHERE id = p_game_id AND admin_user_id = v_uid
        UNION ALL
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND admin_user_id = v_uid
    ) INTO v_is_host;

    IF NOT v_is_host THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the organizer of this game can manage its prize claims';
    END IF;

    -- Self-heal any APPROVED claims in this game that do not yet have an MPT_rewards row
    INSERT INTO public."MPT_rewards" (
        claim_id, user_id, game_id, prize_type, claim_reference, reward_code, reward_title, status, expires_at
    )
    SELECT
        c.id,
        c.user_id,
        c.game_id,
        c.prize_type,
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        c.prize_type || ' Winner',
        'AVAILABLE_TO_CLAIM',
        NOW() + INTERVAL '30 days'
    FROM public."MPT_claims" c
    WHERE c.game_id = p_game_id
      AND c.status = 'APPROVED'
      AND NOT EXISTS (
          SELECT 1 FROM public."MPT_rewards" r
          WHERE r.claim_id = c.id
             OR (r.game_id = c.game_id AND r.prize_type = c.prize_type AND r.user_id = c.user_id)
      )
    ON CONFLICT (claim_reference) DO NOTHING;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'claim_id', r.claim_id,
                'game_id', r.game_id,
                'user_id', r.user_id,
                'prize_type', r.prize_type,
                'claim_reference', r.claim_reference,
                'status', r.status,
                'claimed_at', r.claimed_at,
                'created_at', r.created_at,
                'game_name', COALESCE(g.name, arch.name),
                'invite_code', COALESCE(g.invite_code, arch.invite_code),
                'game_date', COALESCE(g.completed_at, arch.completed_at, g.started_at, g.created_at, arch.created_at),
                'winner_name', COALESCE(
                    NULLIF(TRIM(reg.display_name), ''),
                    NULLIF(TRIM(u.display_name), ''),
                    (
                        SELECT w->>'winner_name'
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                        LIMIT 1
                    ),
                    'Player'
                ),
                'winner_avatar', COALESCE(
                    NULLIF(TRIM(reg.avatar), ''),
                    NULLIF(TRIM(u.avatar), ''),
                    (
                        SELECT w->>'winner_avatar'
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                        LIMIT 1
                    ),
                    'avatar_lion'
                ),
                'winner_email', ap.email,
                'is_guest', COALESCE(u.is_anonymous, TRUE),
                'ticket_number', COALESCE(
                    t.ticket_number,
                    reg.registration_seq::INT,
                    (
                        SELECT (w->>'ticket_seq')::INT
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                          AND (w->>'ticket_seq') ~ '^[0-9]+$'
                        LIMIT 1
                    ),
                    1
                ),
                'fulfilled_gift_title', r.fulfilled_gift_title,
                'fulfilled_brand_name', r.fulfilled_brand_name,
                'fulfilled_gift_code', r.fulfilled_gift_code,
                'fulfillment_note', r.fulfillment_note
            )
            ORDER BY
                CASE
                    WHEN r.prize_type = 'FULL_HOUSE' THEN 0
                    WHEN r.prize_type = 'SECOND_FULL_HOUSE' THEN 1
                    WHEN r.prize_type = 'TOP_LINE' THEN 2
                    WHEN r.prize_type = 'MIDDLE_LINE' THEN 3
                    WHEN r.prize_type = 'BOTTOM_LINE' THEN 4
                    WHEN r.prize_type IN ('EARLY_FIVE', 'EARLY_5') THEN 5
                    WHEN r.prize_type = 'FOUR_CORNERS' THEN 6
                    ELSE 7
                END ASC,
                r.created_at ASC
        ),
        '[]'::jsonb
    )
    INTO v_result
    FROM public."MPT_rewards" r
    LEFT JOIN public."MPT_games" g ON g.id = r.game_id
    LEFT JOIN public."MPT_game_archives" arch ON arch.game_id = r.game_id
    LEFT JOIN public."MPT_users" u ON u.id = r.user_id
    LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = r.user_id
    LEFT JOIN public."MPT_game_registrations" reg
        ON reg.game_id = r.game_id AND reg.user_id = r.user_id
    LEFT JOIN public."MPT_player_tickets" t
        ON t.game_id = r.game_id AND t.user_id = r.user_id
    WHERE r.game_id = p_game_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_game_rewards_for_host"(UUID) TO authenticated;

-- 3. RPC: MPT_close_game_claim (with optional Brand Partner Gift fulfillment metadata)
DROP FUNCTION IF EXISTS public."MPT_close_game_claim"(UUID, UUID, UUID, BOOLEAN);

CREATE OR REPLACE FUNCTION public."MPT_close_game_claim"(
    p_game_id UUID,
    p_reward_id UUID DEFAULT NULL,
    p_claim_id UUID DEFAULT NULL,
    p_close_all BOOLEAN DEFAULT FALSE,
    p_gift_title TEXT DEFAULT NULL,
    p_brand_name TEXT DEFAULT NULL,
    p_gift_code TEXT DEFAULT NULL,
    p_fulfillment_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_is_host BOOLEAN := FALSE;
    v_updated_count INT := 0;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public."MPT_games" WHERE id = p_game_id AND admin_user_id = v_uid
        UNION ALL
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND admin_user_id = v_uid
    ) INTO v_is_host;

    IF NOT v_is_host THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the organizer of this game can close prize claims';
    END IF;

    -- Self-heal any APPROVED claims in this game that do not yet have an MPT_rewards row
    INSERT INTO public."MPT_rewards" (
        claim_id, user_id, game_id, prize_type, claim_reference, reward_code, reward_title, status, expires_at
    )
    SELECT
        c.id,
        c.user_id,
        c.game_id,
        c.prize_type,
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        c.prize_type || ' Winner',
        'AVAILABLE_TO_CLAIM',
        NOW() + INTERVAL '30 days'
    FROM public."MPT_claims" c
    WHERE c.game_id = p_game_id
      AND c.status = 'APPROVED'
      AND NOT EXISTS (
          SELECT 1 FROM public."MPT_rewards" r
          WHERE r.claim_id = c.id
             OR (r.game_id = c.game_id AND r.prize_type = c.prize_type AND r.user_id = c.user_id)
      )
    ON CONFLICT (claim_reference) DO NOTHING;

    IF p_close_all THEN
        UPDATE public."MPT_rewards"
        SET status = 'CLAIMED',
            verified_by_admin_id = v_uid,
            claimed_at = COALESCE(claimed_at, NOW()),
            fulfilled_gift_title = COALESCE(p_gift_title, fulfilled_gift_title),
            fulfilled_brand_name = COALESCE(p_brand_name, fulfilled_brand_name),
            fulfilled_gift_code = COALESCE(p_gift_code, fulfilled_gift_code),
            fulfillment_note = COALESCE(p_fulfillment_note, fulfillment_note)
        WHERE game_id = p_game_id
          AND status <> 'CLAIMED';
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSE
        UPDATE public."MPT_rewards"
        SET status = 'CLAIMED',
            verified_by_admin_id = v_uid,
            claimed_at = COALESCE(claimed_at, NOW()),
            fulfilled_gift_title = COALESCE(p_gift_title, fulfilled_gift_title),
            fulfilled_brand_name = COALESCE(p_brand_name, fulfilled_brand_name),
            fulfilled_gift_code = COALESCE(p_gift_code, fulfilled_gift_code),
            fulfillment_note = COALESCE(p_fulfillment_note, fulfillment_note)
        WHERE game_id = p_game_id
          AND (
              (p_reward_id IS NOT NULL AND id = p_reward_id)
              OR (p_claim_id IS NOT NULL AND claim_id = p_claim_id)
          );
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    END IF;

    RETURN jsonb_build_object(
        'status', 'SUCCESS',
        'updated_count', v_updated_count,
        'rewards', public."MPT_get_game_rewards_for_host"(p_game_id)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_close_game_claim"(UUID, UUID, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- 4. RPC: MPT_get_organizer_all_games_claims
-- Returns all games conducted by the authenticated organizer along with their
-- unsettled/settled claim counts and full player-enriched rewards list.
CREATE OR REPLACE FUNCTION public."MPT_get_organizer_all_games_claims"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_game RECORD;
    v_games_array JSONB := '[]'::jsonb;
    v_game_rewards JSONB;
    v_unsettled INT;
    v_settled INT;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    FOR v_game IN
        WITH combined_games AS (
            SELECT
                g.id AS game_id,
                g.name AS game_name,
                g.invite_code,
                g.status,
                COALESCE(
                    a.player_count,
                    (SELECT COUNT(*)::INT FROM public."MPT_game_registrations" reg WHERE reg.game_id = g.id AND reg.seat_status IN ('CONFIRMED', 'ELIGIBLE')),
                    g.final_capacity,
                    0
                ) AS player_count,
                g.funded_capacity,
                COALESCE(g.organization_name, a.organization_name) AS organization_name,
                COALESCE(g.organization_logo_url, a.organization_logo_url) AS organization_logo_url,
                COALESCE(g.completed_at, a.completed_at, g.started_at, g.created_at) AS game_date,
                g.created_at
            FROM public."MPT_games" g
            LEFT JOIN public."MPT_game_archives" a ON a.game_id = g.id
            WHERE g.admin_user_id = v_uid

            UNION ALL

            SELECT
                a.game_id,
                a.name AS game_name,
                a.invite_code,
                'COMPLETED' AS status,
                COALESCE(a.player_count, 0) AS player_count,
                COALESCE(a.funded_capacity, 25) AS funded_capacity,
                a.organization_name,
                a.organization_logo_url,
                COALESCE(a.completed_at, a.created_at) AS game_date,
                a.created_at
            FROM public."MPT_game_archives" a
            WHERE a.admin_user_id = v_uid
              AND NOT EXISTS (
                  SELECT 1 FROM public."MPT_games" g2 WHERE g2.id = a.game_id
              )
        )
        SELECT * FROM combined_games
        ORDER BY game_date DESC NULLS LAST, created_at DESC
    LOOP
        v_game_rewards := public."MPT_get_game_rewards_for_host"(v_game.game_id);

        SELECT
            COUNT(*) FILTER (WHERE (elem->>'status') = 'AVAILABLE_TO_CLAIM'),
            COUNT(*) FILTER (WHERE (elem->>'status') = 'CLAIMED')
        INTO v_unsettled, v_settled
        FROM jsonb_array_elements(v_game_rewards) AS elem;

        v_games_array := v_games_array || jsonb_build_array(
            jsonb_build_object(
                'game_id', v_game.game_id,
                'name', v_game.game_name,
                'invite_code', v_game.invite_code,
                'status', v_game.status,
                'player_count', v_game.player_count,
                'funded_capacity', v_game.funded_capacity,
                'organization_name', v_game.organization_name,
                'organization_logo_url', v_game.organization_logo_url,
                'game_date', v_game.game_date,
                'unsettled_count', COALESCE(v_unsettled, 0),
                'settled_count', COALESCE(v_settled, 0),
                'total_claims_count', COALESCE(v_unsettled, 0) + COALESCE(v_settled, 0),
                'rewards', v_game_rewards
            )
        );
    END LOOP;

    RETURN v_games_array;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_organizer_all_games_claims"() TO authenticated;
