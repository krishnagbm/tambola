-- Migration: 20261017000002_filter_anonymous_from_admin_reports.sql
-- Description: Filter out anonymous users without email from the Super Admin Hosts drilldown report in MPT_get_admin_reports_overview.

CREATE OR REPLACE FUNCTION public.MPT_get_admin_reports_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_result JSONB;
BEGIN
    SELECT jsonb_build_object(
        'overview', jsonb_build_object(
            'total_games', (SELECT COUNT(*) FROM public."MPT_games"),
            'active_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')),
            'completed_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status = 'COMPLETED'),
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
                    g.scheduled_at,
                    g.created_at,
                    COALESCE(g.is_publicly_visible, true) AS is_publicly_visible,
                    COALESCE(g.is_private, false) AS is_private,
                    COALESCE(ap.email, u.display_name, 'Unknown Host') AS host_identifier,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id) AS player_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id AND seat_status IN ('CONFIRMED', 'ELIGIBLE')) AS confirmed_players_count,
                    ((SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id AND seat_status IN ('CONFIRMED', 'ELIGIBLE')) >= 2) AS quorum_met,
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
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = g.admin_user_id
                LEFT JOIN public."MPT_users" u ON u.id = g.admin_user_id
                ORDER BY g.created_at DESC
                LIMIT 50
            ) g_row
        ), '[]'::jsonb),
        'recent_hosts', COALESCE((
            SELECT jsonb_agg(h_row)
            FROM (
                SELECT 
                    h.user_id,
                    COALESCE(h.email, au.email, u.display_name, 'Unknown Host') AS email,
                    COALESCE(h.role, 'HOST') AS role,
                    COALESCE(h.created_at, au.created_at, NOW()) AS created_at,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id) AS games_created_count,
                    COALESCE(w.available_credits, 0) AS available_credits,
                    w.credits_expire_at
                FROM (
                    SELECT ap.user_id, ap.email, ap.role, ap.created_at FROM public."MPT_admin_profiles" ap
                    UNION
                    SELECT g.admin_user_id AS user_id, NULL::TEXT as email, 'HOST'::TEXT as role, MIN(g.created_at) as created_at 
                    FROM public."MPT_games" g 
                    WHERE g.admin_user_id IS NOT NULL 
                    GROUP BY g.admin_user_id
                    UNION
                    SELECT w2.user_id, NULL::TEXT as email, 'HOST'::TEXT as role, w2.updated_at AS created_at
                    FROM public."MPT_admin_wallets" w2
                    WHERE w2.user_id IS NOT NULL AND w2.available_credits > 0
                ) h
                LEFT JOIN auth.users au ON au.id = h.user_id
                LEFT JOIN public."MPT_users" u ON u.id = h.user_id
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = h.user_id
                WHERE (COALESCE(h.email, au.email) IS NOT NULL AND COALESCE(h.email, au.email) NOT LIKE '%anon%')
                  AND (au.is_anonymous IS NOT TRUE OR au.is_anonymous IS NULL)
                ORDER BY created_at DESC
                LIMIT 50
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
                LIMIT 50
            ) p_row
        ), '[]'::jsonb),
        'recent_users', COALESCE((
            SELECT jsonb_agg(u_row)
            FROM (
                SELECT 
                    u.id AS user_id,
                    COALESCE(au.email, ap.email, 'No Email / Anonymous') AS email,
                    COALESCE(u.display_name, 'Player') AS display_name,
                    COALESCE(u.avatar, 'avatar_1') AS avatar,
                    COALESCE(u.created_at, au.created_at, NOW()) AS registered_at,
                    COALESCE(u.is_anonymous, (au.email IS NULL), FALSE) AS is_anonymous,
                    COALESCE(ap.role, 'PLAYER') AS role,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = u.id) AS games_hosted_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE user_id = u.id) AS games_joined_count,
                    COALESCE(w.available_credits, 0) AS credits_balance
                FROM public."MPT_users" u
                LEFT JOIN auth.users au ON au.id = u.id
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = u.id
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = u.id
                ORDER BY u.created_at DESC
                LIMIT 50
            ) u_row
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;
