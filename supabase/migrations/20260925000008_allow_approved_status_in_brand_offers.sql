-- ============================================================================
-- Migration: 20260925000008_allow_approved_status_in_brand_offers.sql
-- Purpose:
--   1. Allow 'APPROVED' and 'REJECTED' (in addition to 'ACTIVE', 'PENDING', etc.)
--      in the MPT_brand_offers status check constraint so admins editing rows
--      directly in Supabase Table Editor can type either 'APPROVED' or 'ACTIVE'.
--   2. Automatically uppercase/trim status on INSERT/UPDATE and set verified_at
--      when an offer is moved to 'APPROVED' or 'ACTIVE'.
--   3. Treat both 'ACTIVE' and 'APPROVED' as active offers in
--      MPT_get_active_brand_offers, MPT_get_brand_offers_filtered, and RLS.
-- ============================================================================

-- 1. Drop existing status check constraint(s) on MPT_brand_offers and allow APPROVED & REJECTED
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE nsp.nspname = 'public'
          AND rel.relname = 'MPT_brand_offers'
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) ILIKE '%status%'
    LOOP
        EXECUTE format('ALTER TABLE public."MPT_brand_offers" DROP CONSTRAINT IF EXISTS %I', r.conname);
    END LOOP;
END $$;

ALTER TABLE public."MPT_brand_offers"
    ADD CONSTRAINT mpt_brand_offers_status_check
    CHECK (UPPER(TRIM(status)) IN (
        'ACTIVE',
        'APPROVED',
        'PENDING',
        'PENDING_VERIFICATION',
        'REJECTED',
        'PAUSED',
        'EXPIRED',
        'DRAFT',
        'ARCHIVED'
    ));

-- 2. Enhance BEFORE INSERT OR UPDATE trigger so manual edits in Supabase Table Editor
--    automatically normalize case and stamp verified_at when approved/activated
CREATE OR REPLACE FUNCTION public."MPT_touch_brand_offers_updated_at"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status IS NOT NULL THEN
        NEW.status := UPPER(TRIM(NEW.status));
    END IF;

    IF NEW.status IN ('ACTIVE', 'APPROVED') THEN
        IF NEW.verified_at IS NULL THEN
            NEW.verified_at := NOW();
        END IF;
        IF COALESCE(NEW.outreach_status, '') IN ('', 'PENDING_APPROVAL', 'INBOUND_PILOT') THEN
            NEW.outreach_status := 'PARTNER_ACTIVE';
        END IF;
    END IF;

    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mpt_brand_offers_updated_at ON public."MPT_brand_offers";
CREATE TRIGGER trg_mpt_brand_offers_updated_at
BEFORE INSERT OR UPDATE ON public."MPT_brand_offers"
FOR EACH ROW
EXECUTE FUNCTION public."MPT_touch_brand_offers_updated_at"();

-- 3. Update RLS select policy to include both ACTIVE and APPROVED
DROP POLICY IF EXISTS "Public can read active brand offers" ON public."MPT_brand_offers";
CREATE POLICY "Public can read active brand offers"
ON public."MPT_brand_offers"
FOR SELECT
USING (status IN ('ACTIVE', 'APPROVED'));

-- 4. Update MPT_get_active_brand_offers to include both ACTIVE and APPROVED
CREATE OR REPLACE FUNCTION public."MPT_get_active_brand_offers"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN COALESCE(
        (
            SELECT jsonb_agg(
                (row_to_json(o)::jsonb) || jsonb_build_object(
                    'gift_title', o.product_title,
                    'gift_description', o.product_description,
                    'retail_value', o.retail_price,
                    'description', o.product_description,
                    'vouchers_remaining', GREATEST(COALESCE(o.vouchers_total_count, 10) - COALESCE(o.vouchers_consumed_count, 0), 0)
                )
                ORDER BY
                    CASE WHEN o.organizer_price = 0 THEN 0 ELSE 1 END ASC,
                    o.retail_price ASC,
                    o.clicks_count DESC
            )
            FROM public."MPT_brand_offers" o
            WHERE o.status IN ('ACTIVE', 'APPROVED')
              AND (o.vouchers_total_count IS NULL OR o.vouchers_consumed_count < o.vouchers_total_count)
              AND (o.expiration_date IS NULL OR o.expiration_date > NOW())
        ),
        '[]'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_active_brand_offers"() TO anon, authenticated;

-- 5. Update MPT_get_brand_offers_filtered to treat both ACTIVE and APPROVED as Active
CREATE OR REPLACE FUNCTION public."MPT_get_brand_offers_filtered"(
    p_status TEXT DEFAULT 'ACTIVE',
    p_country TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_norm_status TEXT := UPPER(TRIM(COALESCE(p_status, 'ACTIVE')));
    v_norm_country TEXT := NULLIF(TRIM(COALESCE(p_country, '')), '');
BEGIN
    RETURN COALESCE(
        (
            SELECT jsonb_agg(
                (row_to_json(o)::jsonb) || jsonb_build_object(
                    'gift_title', o.product_title,
                    'gift_description', o.product_description,
                    'retail_value', o.retail_price,
                    'description', o.product_description,
                    'vouchers_remaining', GREATEST(COALESCE(o.vouchers_total_count, 10) - COALESCE(o.vouchers_consumed_count, 0), 0)
                )
                ORDER BY
                    CASE WHEN o.organizer_price = 0 THEN 0 ELSE 1 END ASC,
                    o.created_at DESC
            )
            FROM public."MPT_brand_offers" o
            WHERE (
                v_norm_status = 'ALL'
                OR (v_norm_status IN ('ACTIVE', 'APPROVED') AND o.status IN ('ACTIVE', 'APPROVED') AND (o.expiration_date IS NULL OR o.expiration_date > NOW()))
                OR (v_norm_status = 'PENDING' AND o.status IN ('PENDING', 'PENDING_VERIFICATION'))
                OR (v_norm_status = 'EXPIRED' AND (o.status = 'EXPIRED' OR (o.expiration_date IS NOT NULL AND o.expiration_date <= NOW())))
                OR (v_norm_status = 'DRAFT' AND o.status = 'DRAFT')
                OR o.status = v_norm_status
            )
            AND (
                v_norm_country IS NULL
                OR UPPER(v_norm_country) = 'ALL'
                OR LOWER(o.target_region) ILIKE '%' || LOWER(v_norm_country) || '%'
                OR EXISTS (
                    SELECT 1
                    FROM unnest(COALESCE(o.target_countries, ARRAY['Global']::TEXT[])) AS tc
                    WHERE LOWER(tc) = LOWER(v_norm_country)
                       OR (LOWER(v_norm_country) = 'global' AND LOWER(tc) = 'global')
                )
            )
        ),
        '[]'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_brand_offers_filtered"(TEXT, TEXT) TO anon, authenticated;
