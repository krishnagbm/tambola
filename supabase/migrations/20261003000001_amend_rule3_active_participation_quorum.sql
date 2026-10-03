-- Migration: 20261003000001_amend_rule3_active_participation_quorum.sql
-- Description: Amends Rule 3 from raw attendance to 75% Active Participation Quorum.
-- Computes active_player_count based on distinct players who actively marked their tickets (MPT_claims with marked_numbers or MPT_claims submissions)
-- and updates MPT_get_organizer_all_games_claims RPC to return active_player_count.

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
                -- Compute active player count: distinct players who actively filled/marked numbers on tickets
                COALESCE(
                    (
                        SELECT COUNT(DISTINCT c.user_id)::INT
                        FROM public."MPT_claims" c
                        WHERE c.game_id = g.id
                          AND (
                              (c.marked_numbers IS NOT NULL AND jsonb_array_length(c.marked_numbers) > 0)
                              OR c.status IN ('APPROVED', 'SUBMITTED', 'BOGEY')
                          )
                    ),
                    a.player_count,
                    (SELECT COUNT(*)::INT FROM public."MPT_game_registrations" reg WHERE reg.game_id = g.id AND reg.seat_status IN ('CONFIRMED', 'ELIGIBLE')),
                    g.final_capacity,
                    0
                ) AS active_player_count,
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
                COALESCE(
                    (
                        SELECT COUNT(DISTINCT c.user_id)::INT
                        FROM public."MPT_claims" c
                        WHERE c.game_id = a.game_id
                          AND (
                              (c.marked_numbers IS NOT NULL AND jsonb_array_length(c.marked_numbers) > 0)
                              OR c.status IN ('APPROVED', 'SUBMITTED', 'BOGEY')
                          )
                    ),
                    a.player_count,
                    0
                ) AS active_player_count,
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
                'active_player_count', v_game.active_player_count,
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
