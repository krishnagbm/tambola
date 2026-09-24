-- ============================================================================
-- Migration: 20260924000004_organizer_close_claims_rpc.sql
-- Purpose:
-- 1. Allow Game Organizers (hosts) to view all prize rewards/claims for their
--    hosted games and close/mark claims as CLAIMED (individually or all at once).
-- 2. Auto-heal any missing MPT_rewards rows for APPROVED claims in a game.
-- 3. Add RLS policies on MPT_rewards for game organizers as a fallback.
-- ============================================================================

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
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public."MPT_games" g
        WHERE g.id = "MPT_rewards".game_id
          AND g.admin_user_id = auth.uid()
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
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND host_id = v_uid
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
                'winner_name', COALESCE(
                    NULLIF(TRIM(reg.display_name), ''),
                    NULLIF(TRIM(u.display_name), ''),
                    'Player'
                ),
                'winner_avatar', COALESCE(
                    NULLIF(TRIM(reg.avatar), ''),
                    NULLIF(TRIM(u.avatar), ''),
                    'avatar_lion'
                )
            )
            ORDER BY r.created_at ASC
        ),
        '[]'::jsonb
    )
    INTO v_result
    FROM public."MPT_rewards" r
    LEFT JOIN public."MPT_users" u ON u.id = r.user_id
    LEFT JOIN public."MPT_game_registrations" reg
        ON reg.game_id = r.game_id AND reg.user_id = r.user_id
    WHERE r.game_id = p_game_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_game_rewards_for_host"(UUID) TO authenticated;

-- 3. RPC: MPT_close_game_claim
CREATE OR REPLACE FUNCTION public."MPT_close_game_claim"(
    p_game_id UUID,
    p_reward_id UUID DEFAULT NULL,
    p_claim_id UUID DEFAULT NULL,
    p_close_all BOOLEAN DEFAULT FALSE
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
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND host_id = v_uid
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
            claimed_at = COALESCE(claimed_at, NOW())
        WHERE game_id = p_game_id
          AND status <> 'CLAIMED';
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSE
        UPDATE public."MPT_rewards"
        SET status = 'CLAIMED',
            verified_by_admin_id = v_uid,
            claimed_at = COALESCE(claimed_at, NOW())
        WHERE game_id = p_game_id
          AND status <> 'CLAIMED'
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

GRANT EXECUTE ON FUNCTION public."MPT_close_game_claim"(UUID, UUID, UUID, BOOLEAN) TO authenticated;
