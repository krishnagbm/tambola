-- Migration: 20261110000001_add_host_profile_and_drilldown.sql
-- Description: Adds MPT_get_admin_host_details RPC and enriches recent_hosts in MPT_get_admin_reports_overview
-- Enables clicking on any HOST in the Super Admin Dashboard to inspect their full profile, copy email,
-- view join date, last active sign-in date, hosted games breakdown, joined games, and Stripe payment transactions.

-- 1. DROP EXISTING OVERLOADS IF ANY TO PREVENT SIGNATURE CONFLICTS
DROP FUNCTION IF EXISTS public.MPT_get_admin_host_details(UUID, TEXT);
DROP FUNCTION IF EXISTS public.mpt_get_admin_host_details(UUID, TEXT);

-- 2. CREATE FUNCTION: MPT_get_admin_host_details
CREATE OR REPLACE FUNCTION public.MPT_get_admin_host_details(
    p_user_id UUID DEFAULT NULL,
    p_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_user_id UUID;
    v_email TEXT;
    v_result JSONB;
BEGIN
    -- 1. Resolve Target User ID & Email
    IF p_user_id IS NOT NULL THEN
        v_user_id := p_user_id;
        SELECT email INTO v_email FROM auth.users WHERE id = v_user_id;
        IF v_email IS NULL THEN
            SELECT email INTO v_email FROM public."MPT_admin_profiles" WHERE user_id = v_user_id;
        END IF;
    ELSIF p_email IS NOT NULL AND p_email <> '' THEN
        v_email := LOWER(TRIM(p_email));
        SELECT id INTO v_user_id FROM auth.users WHERE LOWER(email) = v_email LIMIT 1;
        IF v_user_id IS NULL THEN
            SELECT user_id INTO v_user_id FROM public."MPT_admin_profiles" WHERE LOWER(email) = v_email LIMIT 1;
        END IF;
    ELSE
        RETURN jsonb_build_object('error', 'Either p_user_id or p_email must be provided');
    END IF;

    -- 2. Construct Complete Host Profile Response
    SELECT jsonb_build_object(
        'profile', (
            SELECT jsonb_build_object(
                'user_id', COALESCE(v_user_id, au.id, ap.user_id),
                'email', COALESCE(au.email, ap.email, v_email, 'No Email'),
                'display_name', COALESCE(u.display_name, au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', 'Organizer'),
                'avatar', COALESCE(u.avatar, 'avatar_lion'),
                'role', COALESCE(ap.role, 'HOST'),
                'registered_at', au.created_at,
                'last_sign_in_at', au.last_sign_in_at,
                'email_confirmed_at', au.email_confirmed_at,
                'provider', COALESCE(
                    au.raw_app_meta_data->>'provider',
                    CASE WHEN COALESCE(au.email, ap.email, '') LIKE '%gmail.com' THEN 'google' ELSE 'email' END
                ),
                'available_credits', COALESCE(w.available_credits, 0),
                'credits_expire_at', w.credits_expire_at,
                'games_created_count', (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = v_user_id),
                'games_completed_count', (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = v_user_id AND status = 'COMPLETED'),
                'games_active_count', (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = v_user_id AND status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')),
                'games_cancelled_count', (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = v_user_id AND status = 'CANCELLED'),
                'games_joined_count', (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE user_id = v_user_id),
                'total_paid_usd', (
                    SELECT COALESCE(SUM(amount_usd), 0) 
                    FROM public."MPT_payments" 
                    WHERE (user_id = v_user_id OR (v_email IS NOT NULL AND LOWER(email) = v_email))
                      AND status IN ('succeeded', 'completed')
                ),
                'payments_count', (
                    SELECT COUNT(*) 
                    FROM public."MPT_payments" 
                    WHERE (user_id = v_user_id OR (v_email IS NOT NULL AND LOWER(email) = v_email))
                )
            )
            FROM (SELECT 1) _dummy
            LEFT JOIN auth.users au ON au.id = v_user_id
            LEFT JOIN public."MPT_users" u ON u.id = v_user_id
            LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = v_user_id
            LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = v_user_id
        ),
        'games', COALESCE((
            SELECT jsonb_agg(g_row)
            FROM (
                SELECT 
                    id,
                    name,
                    invite_code,
                    status,
                    created_at,
                    scheduled_at,
                    initial_funded_capacity,
                    is_publicly_visible,
                    called_count,
                    claims_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id AND seat_status IN ('CONFIRMED', 'ELIGIBLE')) AS confirmed_players_count
                FROM public."MPT_games" g
                WHERE g.admin_user_id = v_user_id
                ORDER BY g.created_at DESC
                LIMIT 100
            ) g_row
        ), '[]'::jsonb),
        'payments', COALESCE((
            SELECT jsonb_agg(p_row)
            FROM (
                SELECT 
                    id,
                    pack,
                    credits,
                    amount_usd,
                    currency,
                    provider,
                    provider_ref,
                    status,
                    customer_id,
                    created_at,
                    CASE 
                        WHEN provider_ref ILIKE '%_test_%' OR provider_ref ILIKE 'cs_test_%' OR provider_ref ILIKE 'pi_test_%' THEN TRUE
                        ELSE FALSE
                    END AS is_test_mode
                FROM public."MPT_payments"
                WHERE (user_id = v_user_id OR (v_email IS NOT NULL AND LOWER(email) = v_email))
                ORDER BY created_at DESC
                LIMIT 50
            ) p_row
        ), '[]'::jsonb)
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- Lowercase alias for MPT_get_admin_host_details
CREATE OR REPLACE FUNCTION public.mpt_get_admin_host_details(
    p_user_id UUID DEFAULT NULL,
    p_email TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    RETURN public.MPT_get_admin_host_details(p_user_id, p_email);
END;
$$;

-- 3. UPDATE MPT_get_admin_reports_overview TO RETURN ENRICHED HOST PROFILE FIELDS
CREATE OR REPLACE FUNCTION public.MPT_get_admin_reports_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_overview JSONB;
    v_metrics JSONB;
BEGIN
    -- Compute top-level metrics
    SELECT jsonb_build_object(
        'total_games', (SELECT COUNT(*) FROM public."MPT_games"),
        'active_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')),
        'completed_games', (SELECT COUNT(*) FROM public."MPT_games" WHERE status = 'COMPLETED'),
        'total_registered_users', (
            SELECT COUNT(DISTINCT id) FROM (
                SELECT id FROM auth.users WHERE (is_anonymous IS FALSE OR is_anonymous IS NULL) AND email IS NOT NULL AND email <> ''
                UNION
                SELECT id FROM public."MPT_users" WHERE (is_anonymous IS FALSE OR is_anonymous IS NULL)
                UNION
                SELECT user_id AS id FROM public."MPT_admin_profiles" WHERE email IS NOT NULL AND email <> ''
            ) all_users
        ),
        'total_active_hosts', (
            SELECT COUNT(DISTINCT user_id) FROM (
                SELECT admin_user_id AS user_id FROM public."MPT_games" WHERE admin_user_id IS NOT NULL
                UNION
                SELECT user_id FROM public."MPT_admin_profiles" WHERE role IN ('HOST', 'ADMIN')
            ) active_hosts
        ),
        'total_tickets_created', (SELECT COUNT(*) FROM public."MPT_tickets"),
        'total_claims_submitted', (SELECT COUNT(*) FROM public."MPT_claims"),
        'total_claims_approved', (SELECT COUNT(*) FROM public."MPT_claims" WHERE status = 'APPROVED'),
        'total_revenue_usd', COALESCE((SELECT SUM(amount_usd) FROM public."MPT_payments" WHERE status IN ('succeeded', 'completed')), 0),
        'total_payments_count', (SELECT COUNT(*) FROM public."MPT_payments"),
        'active_brand_offers', (SELECT COUNT(*) FROM public."MPT_brand_offers" WHERE is_active = TRUE),
        'pending_brand_approvals', (SELECT COUNT(*) FROM public."MPT_brand_partner_approvals" WHERE status = 'PENDING_REVIEW')
    ) INTO v_metrics;

    -- Build full report payload
    SELECT jsonb_build_object(
        'overview', v_metrics,
        'metrics', v_metrics,
        'recent_games', COALESCE((
            SELECT jsonb_agg(g_row)
            FROM (
                SELECT 
                    g.id,
                    g.name,
                    g.invite_code,
                    g.status,
                    g.created_at,
                    g.scheduled_at,
                    g.initial_funded_capacity,
                    g.is_publicly_visible,
                    g.called_count,
                    g.claims_count,
                    g.admin_user_id,
                    COALESCE(ap.email, au.email, u.display_name, 'Unknown Host') AS host_identifier,
                    COALESCE(ap.email, au.email) AS host_email,
                    COALESCE(u.display_name, au.raw_user_meta_data->>'full_name', au.raw_user_meta_data->>'name', 'Organizer') AS host_name,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id AND seat_status IN ('CONFIRMED', 'ELIGIBLE')) AS confirmed_players_count,
                    CASE 
                        WHEN g.initial_funded_capacity <= 5 THEN 'Family Pack (1–5)'
                        WHEN g.initial_funded_capacity <= 25 THEN 'Small Party (6–25)'
                        WHEN g.initial_funded_capacity <= 50 THEN 'Standard Event (26–50)'
                        WHEN g.initial_funded_capacity <= 100 THEN 'Large Gala (51–100)'
                        ELSE 'Mega Event (101–250+)'
                    END AS capacity_tier_name
                FROM public."MPT_games" g
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = g.admin_user_id
                LEFT JOIN auth.users au ON au.id = g.admin_user_id
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
                    au.created_at AS registered_at,
                    au.last_sign_in_at,
                    COALESCE(
                        au.raw_app_meta_data->>'provider',
                        CASE WHEN COALESCE(au.email, ap.email, '') LIKE '%gmail.com' THEN 'google' ELSE 'email' END
                    ) AS provider,
                    COALESCE(h.games_created_count, 0) AS games_created_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status = 'COMPLETED') AS games_completed_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status = 'CANCELLED') AS games_cancelled_count,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = h.user_id AND status IN ('OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS')) AS games_active_count,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE user_id = h.user_id) AS games_joined_count,
                    (SELECT COALESCE(SUM(amount_usd), 0) FROM public."MPT_payments" WHERE (user_id = h.user_id OR email = COALESCE(au.email, ap.email)) AND status IN ('succeeded', 'completed')) AS total_paid_usd,
                    (SELECT COUNT(*) FROM public."MPT_payments" WHERE user_id = h.user_id OR email = COALESCE(au.email, ap.email)) AS payments_count,
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
        ), '[]'::jsonb),
        'brand_offers', COALESCE((
            SELECT jsonb_agg(b_row)
            FROM (
                SELECT 
                    id,
                    brand_name,
                    brand_domain,
                    product_title,
                    retail_price,
                    discounted_price,
                    currency,
                    promo_code,
                    expires_at,
                    is_active,
                    category,
                    created_at
                FROM public."MPT_brand_offers"
                ORDER BY created_at DESC
                LIMIT 50
            ) b_row
        ), '[]'::jsonb),
        'brand_approvals', COALESCE((
            SELECT jsonb_agg(ba_row)
            FROM (
                SELECT 
                    id,
                    brand_name,
                    contact_email,
                    brand_domain,
                    status,
                    submitted_by,
                    reviewed_by,
                    notes,
                    created_at
                FROM public."MPT_brand_partner_approvals"
                ORDER BY created_at DESC
                LIMIT 50
            ) ba_row
        ), '[]'::jsonb)
    ) INTO v_overview;

    RETURN v_overview;
END;
$$;

-- Lowercase alias for MPT_get_admin_reports_overview
CREATE OR REPLACE FUNCTION public.mpt_get_admin_reports_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
    RETURN public.MPT_get_admin_reports_overview();
END;
$$;

-- 4. GRANT PERMISSIONS TO AUTHENTICATED AND ANON (Function uses SECURITY DEFINER)
GRANT EXECUTE ON FUNCTION public.MPT_get_admin_host_details(UUID, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.mpt_get_admin_host_details(UUID, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.MPT_get_admin_reports_overview() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.mpt_get_admin_reports_overview() TO authenticated, anon;
