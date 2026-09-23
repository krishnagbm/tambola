-- =====================================================================
-- Migration: 20260922000004_mpt_brand_approvals.sql
-- Description:
--   1. Creates MPT_brand_approvals table for Domain-Verified Automated Approvals (DVAA).
--   2. Adds RPC MPT_submit_brand_approval to issue secure expiring approval tokens.
--   3. Adds RPC MPT_get_brand_approval_preview to fetch preview details for corporate reviewers.
--   4. Adds RPC MPT_verify_and_approve_brand to approve brand assets with audit logging.
-- =====================================================================

CREATE TABLE IF NOT EXISTS public."MPT_brand_approvals" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    organization_name TEXT NOT NULL,
    organization_logo_url TEXT NOT NULL,
    approver_email TEXT NOT NULL,
    approval_token TEXT UNIQUE NOT NULL,
    status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'REVOKED', 'EXPIRED')),
    submitted_by UUID REFERENCES public."MPT_users"(id) ON DELETE SET NULL,
    approved_ip TEXT,
    approved_user_agent TEXT,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days'),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public."MPT_brand_approvals" ENABLE ROW LEVEL SECURITY;

-- Allow public read of brand approvals by token for the approval portal
DROP POLICY IF EXISTS "MPT_brand_approvals_select_all" ON public."MPT_brand_approvals";
CREATE POLICY "MPT_brand_approvals_select_all" ON public."MPT_brand_approvals"
    FOR SELECT USING (true);

-- 1. RPC: Submit brand approval request
CREATE OR REPLACE FUNCTION public."MPT_submit_brand_approval"(
    p_game_id UUID,
    p_organization_name TEXT,
    p_organization_logo_url TEXT,
    p_approver_email TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_approval public."MPT_brand_approvals";
    v_user_id UUID := auth.uid();
BEGIN
    -- Validate required params
    IF p_game_id IS NULL OR NULLIF(trim(p_organization_name), '') IS NULL OR NULLIF(trim(p_organization_logo_url), '') IS NULL OR NULLIF(trim(p_approver_email), '') IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Organization name, logo URL, and approver email are required.');
    END IF;

    -- Generate secure 64-char hex token using Postgres core gen_random_uuid()
    v_token := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');

    -- Update game with organization metadata (unapproved by default)
    UPDATE public."MPT_games"
    SET organization_name = trim(p_organization_name),
        organization_logo_url = trim(p_organization_logo_url),
        organization_logo_alt = trim(p_organization_name) || ' Logo',
        organization_logo_approved = FALSE
    WHERE id = p_game_id;

    -- Invalidate any previous pending tokens for this game
    UPDATE public."MPT_brand_approvals"
    SET status = 'REVOKED'
    WHERE game_id = p_game_id AND status = 'PENDING';

    -- Insert new approval request
    INSERT INTO public."MPT_brand_approvals" (
        game_id,
        organization_name,
        organization_logo_url,
        approver_email,
        approval_token,
        submitted_by,
        expires_at
    )
    VALUES (
        p_game_id,
        trim(p_organization_name),
        trim(p_organization_logo_url),
        lower(trim(p_approver_email)),
        v_token,
        v_user_id,
        NOW() + INTERVAL '7 days'
    )
    RETURNING * INTO v_approval;

    RETURN jsonb_build_object(
        'success', true,
        'approval_id', v_approval.id,
        'approval_token', v_approval.approval_token,
        'organization_name', v_approval.organization_name,
        'approver_email', v_approval.approver_email,
        'expires_at', v_approval.expires_at
    );
END;
$$;

-- 2. RPC: Fetch preview for approval portal
CREATE OR REPLACE FUNCTION public."MPT_get_brand_approval_preview"(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_approval public."MPT_brand_approvals";
    v_game public."MPT_games";
    v_organizer public."MPT_users";
BEGIN
    SELECT * INTO v_approval
    FROM public."MPT_brand_approvals"
    WHERE approval_token = trim(p_token);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Invalid or expired approval link.');
    END IF;

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = v_approval.game_id;

    IF FOUND AND v_game.admin_user_id IS NOT NULL THEN
        SELECT * INTO v_organizer
        FROM public."MPT_users"
        WHERE id = v_game.admin_user_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'status', v_approval.status,
        'is_expired', (v_approval.expires_at < NOW()),
        'organization_name', v_approval.organization_name,
        'organization_logo_url', v_approval.organization_logo_url,
        'approver_email', v_approval.approver_email,
        'expires_at', v_approval.expires_at,
        'approved_at', v_approval.approved_at,
        'game_name', COALESCE(v_game.name, 'Tambola Event'),
        'invite_code', COALESCE(v_game.invite_code, '------'),
        'capacity', COALESCE(v_game.funded_capacity, 5),
        'organizer_name', COALESCE(v_organizer.display_name, 'Event Organizer'),
        'created_at', v_approval.created_at
    );
END;
$$;

-- 3. RPC: Approve brand with audit trail
CREATE OR REPLACE FUNCTION public."MPT_verify_and_approve_brand"(
    p_token TEXT,
    p_ip TEXT DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_approval public."MPT_brand_approvals";
    v_game public."MPT_games";
BEGIN
    -- Find approval record
    SELECT * INTO v_approval
    FROM public."MPT_brand_approvals"
    WHERE approval_token = trim(p_token);

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Approval token not found.');
    END IF;

    IF v_approval.expires_at < NOW() THEN
        UPDATE public."MPT_brand_approvals" SET status = 'EXPIRED' WHERE id = v_approval.id;
        RETURN jsonb_build_object('success', false, 'message', 'This brand approval link has expired.');
    END IF;

    IF v_approval.status = 'APPROVED' THEN
        RETURN jsonb_build_object('success', true, 'message', 'Brand is already approved.', 'already_approved', true);
    END IF;

    -- Update approval record with audit info
    UPDATE public."MPT_brand_approvals"
    SET status = 'APPROVED',
        approved_at = NOW(),
        approved_ip = COALESCE(p_ip, 'Unknown IP'),
        approved_user_agent = p_user_agent
    WHERE id = v_approval.id;

    -- Update MPT_games
    UPDATE public."MPT_games"
    SET organization_name = v_approval.organization_name,
        organization_logo_url = v_approval.organization_logo_url,
        organization_logo_approved = TRUE
    WHERE id = v_approval.game_id
    RETURNING * INTO v_game;

    -- Update MPT_game_archives if already snapshotted
    UPDATE public."MPT_game_archives"
    SET organization_name = v_approval.organization_name,
        organization_logo_url = v_approval.organization_logo_url,
        organization_logo_approved = TRUE
    WHERE game_id = v_approval.game_id;

    RETURN jsonb_build_object(
        'success', true,
        'message', 'Organization brand has been successfully authorized and approved.',
        'game_name', COALESCE(v_game.name, 'Tambola Event'),
        'organization_name', v_approval.organization_name,
        'organization_logo_url', v_approval.organization_logo_url,
        'approver_email', v_approval.approver_email,
        'approved_at', NOW()
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_submit_brand_approval"(UUID, TEXT, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public."MPT_get_brand_approval_preview"(TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public."MPT_verify_and_approve_brand"(TEXT, TEXT, TEXT) TO authenticated, anon;
