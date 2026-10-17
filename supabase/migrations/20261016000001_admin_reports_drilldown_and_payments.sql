-- =====================================================================
-- Migration: 20261016000001_admin_reports_drilldown_and_payments.sql
-- Description:
--   1. Updates MPT_get_admin_reports_overview() RPC to include:
--      - recent_payments (full Stripe transactions with is_test_mode detection)
--      - recent_users (all registered player & host profiles)
--      - tickets_claims_summary (platform-wide ticket and claim analytics)
--      - comprehensive recent_hosts (union of admin_profiles, wallets, and game creators)
--   2. Grants Admin SELECT access on MPT_payments and MPT_users for direct query fallback
-- =====================================================================

-- 1. Admin RLS policy on MPT_payments for Super Admin access
DROP POLICY IF EXISTS "mpt_payments_select_admin" ON public."MPT_payments";
CREATE POLICY "mpt_payments_select_admin" ON public."MPT_payments"
    FOR SELECT
    USING (
        auth.uid() = user_id 
        OR EXISTS (
            SELECT 1 FROM public."MPT_admin_profiles" 
            WHERE user_id = auth.uid() AND role = 'ADMIN'
        )
    );

GRANT SELECT ON public."MPT_payments" TO authenticated;
GRANT SELECT ON public."MPT_users" TO authenticated;

-- 2. Enhanced RPC: MPT_get_admin_reports_overview
CREATE OR REPLACE FUNCTION public."MPT_get_admin_reports_overview"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT;
    v_res JSONB;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in';
    END IF;

    SELECT role INTO v_role
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_uid;

    IF v_role IS DISTINCT FROM 'ADMIN' THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Administrator privileges required';
    END IF;

    SELECT jsonb_build_object(
        'metrics', jsonb_build_object(
            'total_registered_users', COALESCE(
                (SELECT COUNT(*) FROM auth.users WHERE email IS NOT NULL AND email <> ''),
                (SELECT COUNT(*) FROM public."MPT_users" WHERE is_anonymous = FALSE),
                0
            ),
            'total_users', (SELECT COUNT(*) FROM public."MPT_users"),
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
                    WHERE w2.user_id IS NOT NULL
                ) h
                LEFT JOIN auth.users au ON au.id = h.user_id
                LEFT JOIN public."MPT_users" u ON u.id = h.user_id
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = h.user_id
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
        ), '[]'::jsonb),
        'tickets_claims_summary', jsonb_build_object(
            'total_tickets', (SELECT COUNT(*) FROM public."MPT_player_tickets"),
            'total_claims', (SELECT COUNT(*) FROM public."MPT_claims"),
            'approved_claims', (SELECT COUNT(*) FROM public."MPT_claims" WHERE status = 'APPROVED'),
            'rejected_claims', (SELECT COUNT(*) FROM public."MPT_claims" WHERE status = 'REJECTED'),
            'pending_claims', (SELECT COUNT(*) FROM public."MPT_claims" WHERE status IN ('SUBMITTED', 'PENDING')),
            'claims_by_prize', COALESCE((
                SELECT jsonb_agg(pz_row)
                FROM (
                    SELECT prize_type, COUNT(*) as count, COUNT(*) FILTER (WHERE status = 'APPROVED') as approved_count
                    FROM public."MPT_claims"
                    GROUP BY prize_type
                    ORDER BY count DESC
                ) pz_row
            ), '[]'::jsonb),
            'top_games_by_tickets', COALESCE((
                SELECT jsonb_agg(tg_row)
                FROM (
                    SELECT g.id, g.name, g.invite_code, COUNT(pt.id) as tickets_count
                    FROM public."MPT_games" g
                    JOIN public."MPT_player_tickets" pt ON pt.game_id = g.id
                    GROUP BY g.id, g.name, g.invite_code
                    ORDER BY tickets_count DESC
                    LIMIT 10
                ) tg_row
            ), '[]'::jsonb)
        ),
        'brand_offers', COALESCE((
            SELECT jsonb_agg(b_row)
            FROM (
                SELECT 
                    id,
                    brand_name,
                    brand_domain,
                    product_title,
                    retail_price,
                    organizer_price,
                    discount_percent,
                    status,
                    clicks_count,
                    games_assigned_count,
                    created_at
                FROM public."MPT_brand_offers"
                ORDER BY created_at DESC
                LIMIT 40
            ) b_row
        ), '[]'::jsonb),
        'brand_approvals', COALESCE((
            SELECT jsonb_agg(a_row)
            FROM (
                SELECT 
                    id,
                    game_id,
                    organization_name,
                    approver_email,
                    status,
                    created_at,
                    expires_at,
                    approved_at
                FROM public."MPT_brand_approvals"
                ORDER BY created_at DESC
                LIMIT 40
            ) a_row
        ), '[]'::jsonb)
    ) INTO v_res;

    RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_admin_reports_overview"() TO authenticated;
