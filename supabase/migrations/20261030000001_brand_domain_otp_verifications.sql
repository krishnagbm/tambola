-- ============================================================================
-- Migration: 20261030000001_brand_domain_otp_verifications.sql
-- Purpose:
--   1. Create MPT_brand_domain_verifications table to store secure, short-lived
--      6-digit email OTPs for Brand Partner registration on Step 1.
--   2. Enforces corporate email domain validation before partner offers are created.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public."MPT_brand_domain_verifications" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    domain TEXT NOT NULL,
    otp_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'VERIFIED', 'EXPIRED')),
    expires_at TIMESTAMPTZ NOT NULL,
    verified_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for speedy lookup by email, domain and status
CREATE INDEX IF NOT EXISTS idx_mpt_brand_verifications_lookup
    ON public."MPT_brand_domain_verifications" (email, domain, status, expires_at);

-- Enable RLS
ALTER TABLE public."MPT_brand_domain_verifications" ENABLE ROW LEVEL SECURITY;

-- Allow service_role to manage verifications
DROP POLICY IF EXISTS "mpt_brand_verifications_service_role" ON public."MPT_brand_domain_verifications";
CREATE POLICY "mpt_brand_verifications_service_role"
    ON public."MPT_brand_domain_verifications"
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

