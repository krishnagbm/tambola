-- =====================================================================
-- Migration: 20260921000001_fix_claims_registration_names.sql
-- Description:
--   1. Updates MPT_get_game_claims RPC function to join MPT_game_registrations
--      so that player display names and avatars from room registrations
--      are returned accurately instead of generic 'Player'.
-- =====================================================================

CREATE OR REPLACE FUNCTION public."MPT_get_game_claims"(p_game_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', c.id,
                'game_id', c.game_id,
                'user_id', c.user_id,
                'prize_type', c.prize_type,
                'status', c.status,
                'marked_numbers', c.marked_numbers,
                'claim_seq', c.claim_seq,
                'submitted_at', c.submitted_at,
                'rejection_reason', c.rejection_reason,
                'user_name', COALESCE(NULLIF(r.display_name, ''), NULLIF(u.display_name, ''), 'Player'),
                'user_avatar', COALESCE(r.avatar, u.avatar, 'avatar_1')
            ) ORDER BY c.submitted_at DESC
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public."MPT_claims" c
    LEFT JOIN public."MPT_game_registrations" r ON (r.game_id = c.game_id AND r.user_id = c.user_id)
    LEFT JOIN public."MPT_users" u ON u.id = c.user_id
    WHERE c.game_id = p_game_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_game_claims"(UUID) TO authenticated, anon;
