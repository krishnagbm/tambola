-- =====================================================================
-- Migration: 20260919000001_fix_public_claims_visibility.sql
-- Description:
--   1. Ensures all players in a game room can see approved prize claims.
--   2. Provides MPT_get_game_claims RPC function with SECURITY DEFINER.
--   3. Sets MPT_claims SELECT policy to true for room-wide claim transparency.
-- =====================================================================

-- 1. Ensure RLS on MPT_claims allows all room participants to read claims
DROP POLICY IF EXISTS "MPT_claims_read" ON public."MPT_claims";
CREATE POLICY "MPT_claims_read"
ON public."MPT_claims"
FOR SELECT
USING (true);

-- 2. Create MPT_get_game_claims RPC for high-performance claim aggregation
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
                'user_name', COALESCE(u.display_name, 'Player'),
                'user_avatar', u.avatar
            ) ORDER BY c.submitted_at DESC
        ),
        '[]'::JSONB
    )
    INTO v_result
    FROM public."MPT_claims" c
    LEFT JOIN public."MPT_users" u ON u.id = c.user_id
    WHERE c.game_id = p_game_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_game_claims"(UUID) TO authenticated, anon;
