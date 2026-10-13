-- =====================================================================
-- Migration: 20261013000001_mpt_admin_role_and_reports.sql
-- Description:
--   1. Adds 'role' column to MPT_admin_profiles (default 'HOST', 'ADMIN' for Super Admin).
--   2. Adds RPC MPT_check_my_admin_role to verify current user's role.
--   3. Adds RPC MPT_get_admin_reports_overview for the executive dashboard.
--   4. Adds RPC MPT_set_game_public_visibility to show/hide games in Recent Games.
--   5. Adds RPC MPT_auto_hide_below_quorum_games for 1-click batch cleanup.
--   6. Adds RPC MPT_get_admin_game_details to inspect game stats & participants.
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
                    ap.user_id,
                    ap.email,
                    ap.role,
                    ap.created_at,
                    (SELECT COUNT(*) FROM public."MPT_games" WHERE admin_user_id = ap.user_id) AS games_created_count,
                    COALESCE(w.available_credits, 0) AS available_credits,
                    w.credits_expire_at
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

-- 5. RPC: Toggle game visibility in public Recent Games
CREATE OR REPLACE FUNCTION public."MPT_set_game_public_visibility"(
    p_game_id UUID,
    p_is_visible BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT;
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

    UPDATE public."MPT_games"
    SET is_publicly_visible = p_is_visible,
        updated_at = NOW()
    WHERE id = p_game_id;

    UPDATE public."MPT_game_archives"
    SET is_publicly_visible = p_is_visible
    WHERE game_id = p_game_id;

    RETURN jsonb_build_object(
        'success', TRUE,
        'game_id', p_game_id,
        'is_publicly_visible', p_is_visible
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_set_game_public_visibility"(UUID, BOOLEAN) TO authenticated;

-- 6. RPC: Auto-hide all games that did not meet quorum from Recent Games
CREATE OR REPLACE FUNCTION public."MPT_auto_hide_below_quorum_games"(
    p_min_quorum INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT;
    v_updated_count INT := 0;
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

    WITH below_quorum_ids AS (
        SELECT g.id
        FROM public."MPT_games" g
        WHERE (
            SELECT COUNT(*) 
            FROM public."MPT_game_registrations" reg 
            WHERE reg.game_id = g.id AND reg.seat_status IN ('CONFIRMED', 'ELIGIBLE')
        ) < p_min_quorum
    )
    UPDATE public."MPT_games"
    SET is_publicly_visible = FALSE,
        updated_at = NOW()
    WHERE id IN (SELECT id FROM below_quorum_ids);

    GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    -- Also sync to archives
    UPDATE public."MPT_game_archives"
    SET is_publicly_visible = FALSE
    WHERE COALESCE(player_count, 0) < p_min_quorum;

    RETURN jsonb_build_object(
        'success', TRUE,
        'hidden_games_count', v_updated_count,
        'min_quorum', p_min_quorum
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_auto_hide_below_quorum_games"(INT) TO authenticated;

-- 7. RPC: Fetch detailed game stats, participants, claims, and draws for Admin Inspection
CREATE OR REPLACE FUNCTION public."MPT_get_admin_game_details"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT;
    v_game RECORD;
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

    SELECT 
        g.*,
        COALESCE(ap.email, u.display_name, 'Unknown Host') AS host_identifier,
        COALESCE(ap.email, '') AS host_email
    INTO v_game
    FROM public."MPT_games" g
    LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = g.admin_user_id
    LEFT JOIN public."MPT_users" u ON u.id = g.admin_user_id
    WHERE g.id = p_game_id;

    IF v_game IS NULL THEN
        RAISE EXCEPTION 'GAME_NOT_FOUND';
    END IF;

    SELECT jsonb_build_object(
        'game', jsonb_build_object(
            'id', v_game.id,
            'name', v_game.name,
            'invite_code', v_game.invite_code,
            'status', v_game.status,
            'initial_funded_capacity', v_game.initial_funded_capacity,
            'funded_capacity', v_game.funded_capacity,
            'final_capacity', v_game.final_capacity,
            'is_private', v_game.is_private,
            'is_publicly_visible', COALESCE(v_game.is_publicly_visible, true),
            'scheduled_at', v_game.scheduled_at,
            'started_at', v_game.started_at,
            'completed_at', v_game.completed_at,
            'created_at', v_game.created_at,
            'prizes_config', v_game.prizes_config,
            'host_identifier', v_game.host_identifier,
            'host_email', v_game.host_email,
            'capacity_tier_name', CASE 
                WHEN v_game.initial_funded_capacity <= 5 THEN 'Family Pack (1–5)'
                WHEN v_game.initial_funded_capacity <= 25 THEN 'Small Party (6–25)'
                WHEN v_game.initial_funded_capacity <= 50 THEN 'Standard Event (26–50)'
                WHEN v_game.initial_funded_capacity <= 100 THEN 'Large Gala (51–100)'
                ELSE 'Mega Event (101–250+)'
            END
        ),
        'players', COALESCE((
            SELECT jsonb_agg(p_row)
            FROM (
                SELECT 
                    r.user_id,
                    r.display_name,
                    r.avatar,
                    r.registration_seq,
                    r.seat_status,
                    r.joined_at,
                    (SELECT COUNT(*) FROM public."MPT_player_tickets" t WHERE t.game_id = p_game_id AND t.user_id = r.user_id) AS tickets_count
                FROM public."MPT_game_registrations" r
                WHERE r.game_id = p_game_id
                ORDER BY r.registration_seq ASC
            ) p_row
        ), '[]'::jsonb),
        'claims', COALESCE((
            SELECT jsonb_agg(c_row)
            FROM (
                SELECT 
                    c.id,
                    c.prize_type,
                    c.status,
                    c.rejection_reason,
                    c.submitted_at,
                    c.processed_at,
                    c.marked_numbers,
                    u.display_name AS player_name
                FROM public."MPT_claims" c
                LEFT JOIN public."MPT_users" u ON u.id = c.user_id
                WHERE c.game_id = p_game_id
                ORDER BY c.submitted_at DESC
            ) c_row
        ), '[]'::jsonb),
        'called_numbers', COALESCE((
            SELECT jsonb_agg(n_row)
            FROM (
                SELECT 
                    number,
                    number AS called_number,
                    call_seq,
                    called_at
                FROM public."MPT_called_numbers"
                WHERE game_id = p_game_id
                ORDER BY call_seq ASC
            ) n_row
        ), '[]'::jsonb)
    ) INTO v_res;

    RETURN v_res;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_admin_game_details"(UUID) TO authenticated;

-- Lowercase aliases to guarantee compatibility across PostgREST schema cache configurations:
CREATE OR REPLACE FUNCTION public.mpt_get_admin_game_details(p_game_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public."MPT_get_admin_game_details"(p_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.mpt_get_admin_game_details(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.mpt_set_game_public_visibility(p_game_id UUID, p_is_visible BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public."MPT_set_game_public_visibility"(p_game_id, p_is_visible);
END;
$$;
GRANT EXECUTE ON FUNCTION public.mpt_set_game_public_visibility(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.mpt_auto_hide_below_quorum_games(p_min_quorum INT DEFAULT 2)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public."MPT_auto_hide_below_quorum_games"(p_min_quorum);
END;
$$;
GRANT EXECUTE ON FUNCTION public.mpt_auto_hide_below_quorum_games(INT) TO authenticated;

-- 8. RPC: Admin Grant Free/Promotional Credits to Selected Host
CREATE OR REPLACE FUNCTION public."MPT_admin_grant_credits"(
    p_target_user_id UUID DEFAULT NULL,
    p_target_email TEXT DEFAULT NULL,
    p_credits INT DEFAULT 300,
    p_validity_days INT DEFAULT 30,
    p_reason TEXT DEFAULT 'Marketing Promo'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_admin_uid UUID;
    v_admin_role TEXT;
    v_target_user_id UUID := p_target_user_id;
    v_target_email TEXT := TRIM(p_target_email);
    v_target_name TEXT;
    v_new_balance INT := 0;
    v_expires_at TIMESTAMPTZ;
    v_final_expiry TIMESTAMPTZ;
BEGIN
    v_admin_uid := auth.uid();
    IF v_admin_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Please sign in';
    END IF;

    SELECT role INTO v_admin_role
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_admin_uid;

    IF v_admin_role IS DISTINCT FROM 'ADMIN' THEN
        RAISE EXCEPTION 'ACCESS_DENIED: Administrator privileges required';
    END IF;

    IF p_credits <= 0 THEN
        RAISE EXCEPTION 'INVALID_AMOUNT: Credits must be greater than zero';
    END IF;

    -- Resolve target user ID if only email is provided
    IF v_target_user_id IS NULL AND v_target_email IS NOT NULL THEN
        SELECT user_id INTO v_target_user_id
        FROM public."MPT_admin_profiles"
        WHERE LOWER(email) = LOWER(v_target_email)
        LIMIT 1;

        IF v_target_user_id IS NULL THEN
            SELECT id INTO v_target_user_id
            FROM auth.users
            WHERE LOWER(email) = LOWER(v_target_email)
            LIMIT 1;
        END IF;

        IF v_target_user_id IS NULL THEN
            SELECT id INTO v_target_user_id
            FROM public."MPT_users"
            WHERE LOWER(email) = LOWER(v_target_email)
            LIMIT 1;
        END IF;
    END IF;

    IF v_target_user_id IS NULL THEN
        RAISE EXCEPTION 'USER_NOT_FOUND: Could not find user with email %', v_target_email;
    END IF;

    -- Fetch or fallback email
    IF v_target_email IS NULL OR v_target_email = '' THEN
        SELECT email INTO v_target_email
        FROM public."MPT_admin_profiles"
        WHERE user_id = v_target_user_id;

        IF v_target_email IS NULL THEN
            SELECT email INTO v_target_email
            FROM auth.users
            WHERE id = v_target_user_id;
        END IF;
    END IF;

    v_target_name := COALESCE(split_part(v_target_email, '@', 1), 'Host');

    -- Ensure MPT_users profile exists
    INSERT INTO public."MPT_users" (id, display_name, is_anonymous)
    VALUES (v_target_user_id, v_target_name, FALSE)
    ON CONFLICT (id) DO NOTHING;

    -- Ensure MPT_admin_profiles exists
    INSERT INTO public."MPT_admin_profiles" (user_id, email, role)
    VALUES (v_target_user_id, COALESCE(v_target_email, 'unknown@dabhousie.com'), 'HOST')
    ON CONFLICT (user_id) DO UPDATE
    SET email = COALESCE(EXCLUDED.email, public."MPT_admin_profiles".email);

    -- Calculate expiry timestamp based on validity days
    v_expires_at := NOW() + (GREATEST(p_validity_days, 1) || ' days')::INTERVAL;

    -- Upsert credits in MPT_admin_wallets
    INSERT INTO public."MPT_admin_wallets" (
        user_id,
        available_credits,
        credits_expire_at,
        updated_at
    )
    VALUES (
        v_target_user_id,
        p_credits,
        v_expires_at,
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET available_credits = public."MPT_admin_wallets".available_credits + EXCLUDED.available_credits,
        credits_expire_at = GREATEST(COALESCE(public."MPT_admin_wallets".credits_expire_at, NOW()), v_expires_at),
        updated_at = NOW()
    RETURNING available_credits, credits_expire_at INTO v_new_balance, v_final_expiry;

    -- Ledger record in MPT_credit_transactions
    INSERT INTO public."MPT_credit_transactions" (
        user_id,
        type,
        amount,
        balance_after,
        reference_id,
        description
    )
    VALUES (
        v_target_user_id,
        'ADJUSTMENT',
        p_credits,
        v_new_balance,
        'ADMIN_GRANT_' || v_admin_uid,
        COALESCE(p_reason, 'Marketing Promo (' || p_validity_days || ' days validity)')
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'user_id', v_target_user_id,
        'email', v_target_email,
        'granted_credits', p_credits,
        'new_balance', v_new_balance,
        'expires_at', v_final_expiry,
        'validity_days', p_validity_days
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_admin_grant_credits"(UUID, TEXT, INT, INT, TEXT) TO authenticated;

-- Lowercase alias for PostgREST:
CREATE OR REPLACE FUNCTION public.mpt_admin_grant_credits(
    p_target_user_id UUID DEFAULT NULL,
    p_target_email TEXT DEFAULT NULL,
    p_credits INT DEFAULT 300,
    p_validity_days INT DEFAULT 30,
    p_reason TEXT DEFAULT 'Marketing Promo'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN public."MPT_admin_grant_credits"(p_target_user_id, p_target_email, p_credits, p_validity_days, p_reason);
END;
$$;

GRANT EXECUTE ON FUNCTION public.mpt_admin_grant_credits(UUID, TEXT, INT, INT, TEXT) TO authenticated;


