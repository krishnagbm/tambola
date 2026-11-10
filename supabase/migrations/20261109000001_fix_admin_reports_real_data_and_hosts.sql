-- ============================================================================
-- Migration: 20261109000001_fix_admin_reports_real_data_and_hosts.sql
-- Description:
--   1. Replaces MPT_get_admin_reports_overview with accurate, unfiltered data.
--   2. Restricts 'recent_hosts' strictly to organizers who created games in MPT_games
--      or hold an explicit organizer profile (eliminating anonymous player wallet spam).
--   3. Restricts 'recent_users' strictly to genuine non-anonymous accounts from auth.users.
--   4. Increases game list limit from 50 to 500, enriching games with host_email,
--      host_name, host_id, and exact quorum configuration.
--   5. Fixes platform metrics to report true active hosts, true registered users,
--      and true total games.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.MPT_get_admin_reports_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_result JSONB;
    v_uid UUID;
    v_role TEXT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in';
    END IF;

    -- Security check: Super Admin only
    SELECT role INTO v_role
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_uid;

    IF v_role IS DISTINCT FROM 'ADMIN' THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Administrator privileges required';
    END IF;

    SELECT jsonb_build_object(
        'overview', jsonb_build_object(
            'total_games', (SELECT COUNT(*) FROM public."MPT_games"),
            'active_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')),
            'completed_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status = 'COMPLETED'),
            'total_hosts', (
                SELECT COUNT(DISTINCT user_id) FROM (
                    SELECT admin_user_id AS user_id FROM public."MPT_games" WHERE admin_user_id IS NOT NULL
                    UNION
                    SELECT user_id FROM public."MPT_admin_profiles"
                ) h_all
            ),
            'total_registered_users', (
                SELECT COUNT(*) FROM auth.users 
                WHERE email IS NOT NULL AND email <> '' 
                  AND (is_anonymous IS FALSE OR is_anonymous IS NULL)
            ),
            'total_users', (SELECT COUNT(*) FROM public."MPT_users"),
            'total_tickets', (SELECT COUNT(*) FROM public."MPT_player_tickets"),
            'total_claims', (SELECT COUNT(*) FROM public."MPT_claims"),
            'total_brand_offers', (SELECT COUNT(*) FROM public."MPT_brand_offers"),
            'active_brand_offers', (SELECT COUNT(*) FROM public."MPT_brand_offers" WHERE status = 'ACTIVE'),
            'total_brand_approvals', (SELECT COUNT(*) FROM public."MPT_brand_approvals"),
            'pending_brand_approvals', (SELECT COUNT(*) FROM public."MPT_brand_approvals" WHERE status = 'PENDING'),
            'total_payments_count', (SELECT COUNT(*) FROM public."MPT_payments" WHERE LOWER(status) IN ('succeeded', 'completed')),
            'total_revenue_amount', (SELECT COALESCE(SUM(amount_usd), 0) FROM public."MPT_payments" WHERE LOWER(status) IN ('succeeded', 'completed'))
        ),
        'recent_games', COALESCE((
            SELECT jsonb_agg(g_row)
            FROM (
                SELECT 
                    g.id,
                    g.name,
                    g.invite_code,
                    g.status,
                    g.initial_funded_capacity,
                    g.funded_capacity,
                    g.prize_gifts_config,
                    g.scheduled_at,
                    g.started_at,
                    g.completed_at,
                    g.created_at,
                    COALESCE(g.is_publicly_visible, true) AS is_publicly_visible,
                    COALESCE(g.is_private, false) AS is_private,
                    g.admin_user_id AS host_id,
                    COALESCE(au.email, ap.email) AS host_email,
                    COALESCE(u.display_name, au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', 'Organizer') AS host_name,
                    COALESCE(au.email, ap.email, u.display_name, 'Unknown Host') AS host_identifier,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id) AS player_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id AND seat_status IN ('CONFIRMED', 'ELIGIBLE')) AS confirmed_players_count,
                    (SELECT COUNT(*) FROM public."MPT_claims" WHERE game_id = g.id) AS claims_count,
                    (SELECT COUNT(*) FROM public."MPT_called_numbers" WHERE game_id = g.id) AS called_count,
                    CASE 
                        WHEN g.initial_funded_capacity <= 5 THEN 'Family Pack (1–5)'
                        WHEN g.initial_funded_capacity <= 25 THEN 'Small Party (6–25)'
                        WHEN g.initial_funded_capacity <= 50 THEN 'Standard Event (26–50)'
                        WHEN g.initial_funded_capacity <= 100 THEN 'Large Gala (51–100)'
                        ELSE 'Mega Event (101–250+)'
                    END AS capacity_tier_name
                FROM public."MPT_games" g
                LEFT JOIN auth.users au ON au.id = g.admin_user_id
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = g.admin_user_id
                LEFT JOIN public."MPT_users" u ON u.id = g.admin_user_id
                ORDER BY g.created_at DESC
                LIMIT 500
            ) g_row
        ), '[]'::jsonb),
        'recent_hosts', COALESCE((
            SELECT jsonb_agg(h_row)
            FROM (
                SELECT 
                    h.user_id,
                    COALESCE(au.email, ap.email, 'No Email') AS email,
                    COALESCE(u.display_name, au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', 'Organizer') AS display_name,
                    COALESCE(u.avatar, 'avatar_lion') AS avatar,
                    COALESCE(ap.role, 'HOST') AS role,
                    COALESCE(h.first_game_at, au.created_at, NOW()) AS created_at,
                    COALESCE(h.games_created_count, 0) AS games_created_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status = 'COMPLETED') AS games_completed_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status = 'CANCELLED') AS games_cancelled_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')) AS games_active_count,
                    COALESCE(w.available_credits, 0) AS available_credits,
                    w.credits_expire_at
                FROM (
                    SELECT 
                        admin_user_id AS user_id, 
                        COUNT(*) AS games_created_count,
                        MIN(created_at) AS first_game_at
                    FROM public."MPT_games"
                    WHERE admin_user_id IS NOT NULL
                    GROUP BY admin_user_id
                    UNION
                    SELECT 
                        user_id,
                        0 AS games_created_count,
                        created_at AS first_game_at
                    FROM public."MPT_admin_profiles"
                    WHERE user_id NOT IN (SELECT admin_user_id FROM public."MPT_games" WHERE admin_user_id IS NOT NULL)
                ) h
                LEFT JOIN auth.users au ON au.id = h.user_id
                LEFT JOIN public."MPT_users" u ON u.id = h.user_id
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = h.user_id
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = h.user_id
                WHERE (au.is_anonymous IS NOT TRUE OR au.is_anonymous IS NULL)
                ORDER BY games_created_count DESC, created_at DESC
                LIMIT 100
            ) h_row
        ), '[]'::jsonb),
        'recent_payments', COALESCE((
            SELECT jsonb_agg(p_row)
            FROM (
                SELECT 
                    p.id,
                    p.user_id,
                    p.email,
                    p.pack,
                    p.credits,
                    p.amount_usd,
                    p.currency,
                    p.provider,
                    p.provider_ref,
                    p.status,
                    p.customer_id,
                    p.created_at,
                    CASE 
                        WHEN p.provider_ref ILIKE '%_test_%' OR p.provider_ref ILIKE 'cs_test_%' OR p.provider_ref ILIKE 'pi_test_%' THEN TRUE
                        ELSE FALSE
                    END AS is_test_mode
                FROM public."MPT_payments" p
                ORDER BY p.created_at DESC
                LIMIT 100
            ) p_row
        ), '[]'::jsonb),
        'recent_users', COALESCE((
            SELECT jsonb_agg(u_row)
            FROM (
                SELECT 
                    au.id AS user_id,
                    au.email,
                    COALESCE(
                        au.raw_app_meta_data ->> 'provider',
                        CASE WHEN au.email LIKE '%gmail.com' THEN 'google' ELSE 'email' END
                    ) AS provider,
                    COALESCE(
                        u.display_name,
                        au.raw_user_meta_data ->> 'full_name',
                        au.raw_user_meta_data ->> 'name',
                        'Organizer'
                    ) AS display_name,
                    COALESCE(u.avatar, 'avatar_lion') AS avatar,
                    au.created_at AS registered_at,
                    au.last_sign_in_at,
                    COALESCE(ap.role, 'PLAYER') AS role,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = au.id) AS games_hosted_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE user_id = au.id) AS games_joined_count,
                    COALESCE(w.available_credits, 0) AS credits_balance
                FROM auth.users au
                LEFT JOIN public."MPT_users" u ON u.id = au.id
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = au.id
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = au.id
                WHERE au.email IS NOT NULL 
                  AND au.email <> ''
                  AND (au.is_anonymous IS FALSE OR au.is_anonymous IS NULL)
                ORDER BY au.created_at DESC
                LIMIT 250
            ) u_row
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.MPT_get_admin_reports_overview() TO authenticated;
