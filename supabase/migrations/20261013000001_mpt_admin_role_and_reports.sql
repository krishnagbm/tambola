-- =====================================================================
-- Migration: 20261013000001_mpt_admin_role_and_reports.sql
-- Description:
--   1. Adds 'role' column to MPT_admin_profiles (default 'HOST', 'ADMIN' for Super Admin).
--   2. Adds RPC MPT_check_my_admin_role to verify current user's role.
--   3. Adds RPC MPT_get_admin_reports_overview for the executive dashboard.
-- =====================================================================

-- 1. Add role column to MPT_admin_profiles
ALTER TABLE public."MPT_admin_profiles"
ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'HOST';

CREATE INDEX IF NOT EXISTS idx_mpt_admin_profiles_role 
ON public."MPT_admin_profiles"(role);

-- 2. Update RLS policy to allow Admins to read all profiles
DROP POLICY IF EXISTS "MPT_admin_profiles_self" ON public."MPT_admin_profiles";
CREATE POLICY "MPT_admin_profiles_self" ON public."MPT_admin_profiles"
FOR ALL USING (
    auth.uid() = user_id 
    OR (SELECT role FROM public."MPT_admin_profiles" WHERE user_id = auth.uid()) = 'ADMIN'
);

-- 3. RPC: Check current caller's admin role
CREATE OR REPLACE FUNCTION public."MPT_check_my_admin_role"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT := 'HOST';
    v_email TEXT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RETURN jsonb_build_object(
            'is_admin', FALSE, 
            'role', 'ANONYMOUS',
            'email', NULL
        );
    END IF;

    -- Look up role and email from MPT_admin_profiles
    SELECT role, email INTO v_role, v_email
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_uid;

    -- If no email in MPT_admin_profiles yet, check auth.users
    IF v_email IS NULL THEN
        SELECT email INTO v_email
        FROM auth.users
        WHERE id = v_uid;
    END IF;

    RETURN jsonb_build_object(
        'is_admin', COALESCE(v_role = 'ADMIN', FALSE),
        'role', COALESCE(v_role, 'HOST'),
        'email', v_email,
        'user_id', v_uid
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_check_my_admin_role"() TO anon, authenticated;

-- 4. RPC: Get comprehensive administrative KPI & reporting overview
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
            'total_registered_users', (SELECT COUNT(*) FROM auth.users WHERE email IS NOT NULL AND is_anonymous = FALSE),
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
            'total_payments_count', (SELECT COUNT(*) FROM public."MPT_payments" WHERE status = 'SUCCEEDED'),
            'total_revenue_amount', (SELECT COALESCE(SUM(amount), 0) FROM public."MPT_payments" WHERE status = 'SUCCEEDED')
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
                    COALESCE(ap.email, u.display_name, 'Unknown Host') AS host_identifier,
                    (SELECT COUNT(*) FROM public."MPT_game_registrations" WHERE game_id = g.id) AS player_count,
                    (SELECT COUNT(*) FROM public."MPT_claims" WHERE game_id = g.id) AS claims_count
                FROM public."MPT_games" g
                LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = g.admin_user_id
                LEFT JOIN public."MPT_users" u ON u.id = g.admin_user_id
                ORDER BY g.created_at DESC
                LIMIT 40
            ) g_row
        ), '[]'::jsonb),
        'recent_hosts', COALESCE((
            SELECT jsonb_agg(h_row)
            FROM (
                SELECT 
                    ap.user_id,
                    ap.email,
                    ap.role,
                    ap.created_at,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = ap.user_id) AS games_created_count,
                    COALESCE(w.available_credits, 0) AS available_credits
                FROM public."MPT_admin_profiles" ap
                LEFT JOIN public."MPT_admin_wallets" w ON w.user_id = ap.user_id
                ORDER BY ap.created_at DESC
                LIMIT 40
            ) h_row
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
