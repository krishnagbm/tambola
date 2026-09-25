-- ============================================================================
-- Migration: 20260925000007_brand_offer_pending_approval.sql
-- Purpose:
--   1. Require backend approval before newly submitted Brand Partner offers
--      appear in the public Partner Catalog or Host Gift Catalog.
--   2. Update MPT_register_brand_offer to insert new offers with
--      status = 'PENDING' (waiting for approval) and verified_at = NULL.
--   3. Add MPT_approve_brand_offer(p_offer_id UUID) helper for backend admin
--      approval.
--   4. Move recently submitted non-seeded test offers into 'PENDING' status
--      until approved in the backend.
-- ============================================================================

-- 1. Move any recently submitted inbound pilot offers (excluding official DabHousie & global templates) to PENDING
UPDATE public."MPT_brand_offers"
SET
    status = 'PENDING',
    outreach_status = 'PENDING_APPROVAL',
    verified_at = NULL
WHERE outreach_status = 'INBOUND_PILOT'
  AND brand_domain <> 'dabhousie.com';

-- 2. Update MPT_register_brand_offer to insert with status = 'PENDING' (Waiting for Approval)
CREATE OR REPLACE FUNCTION public."MPT_register_brand_offer"(
    p_brand_name TEXT,
    p_brand_domain TEXT,
    p_contact_name TEXT,
    p_contact_email TEXT,
    p_product_title TEXT,
    p_product_description TEXT DEFAULT NULL,
    p_category TEXT DEFAULT 'Shopping Vouchers',
    p_product_url TEXT DEFAULT '',
    p_retail_price NUMERIC DEFAULT 10,
    p_organizer_price NUMERIC DEFAULT 0,
    p_promo_code TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🎁',
    p_product_image_url TEXT DEFAULT NULL,
    p_vouchers_total_count INTEGER DEFAULT 10,
    p_offer_type TEXT DEFAULT 'GIFT_VOUCHER',
    p_target_region TEXT DEFAULT 'Global',
    p_target_countries TEXT[] DEFAULT ARRAY['Global']::TEXT[],
    p_currency TEXT DEFAULT 'USD',
    p_voucher_code_type TEXT DEFAULT 'SHARED_PROMO_CODE',
    p_expiration_date TIMESTAMPTZ DEFAULT NULL,
    p_redemption_restrictions TEXT DEFAULT NULL,
    p_minimum_purchase TEXT DEFAULT NULL,
    p_new_customers_only BOOLEAN DEFAULT FALSE,
    p_redemption_channel TEXT DEFAULT 'ONLINE',
    p_contact_role TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_domain TEXT;
    v_discount INT := 0;
    v_offer public."MPT_brand_offers";
    v_vouchers INT := GREATEST(COALESCE(NULLIF(p_vouchers_total_count, 0), 10), 1);
    v_countries TEXT[];
    v_badge TEXT;
BEGIN
    IF COALESCE(TRIM(p_brand_name), '') = '' OR COALESCE(TRIM(p_product_title), '') = '' THEN
        RAISE EXCEPTION 'Brand name and offer title are required';
    END IF;

    v_clean_domain := LOWER(TRIM(COALESCE(p_brand_domain, '')));
    v_clean_domain := REGEXP_REPLACE(v_clean_domain, '^https?://', '');
    v_clean_domain := REGEXP_REPLACE(v_clean_domain, '^www\.', '');
    v_clean_domain := SPLIT_PART(v_clean_domain, '/', 1);

    IF COALESCE(p_retail_price, 0) > 0 AND COALESCE(p_organizer_price, 0) < COALESCE(p_retail_price, 0) THEN
        v_discount := ROUND(((p_retail_price - p_organizer_price) / p_retail_price) * 100)::INT;
    END IF;

    IF p_target_countries IS NULL OR array_length(p_target_countries, 1) IS NULL THEN
        v_countries := ARRAY[COALESCE(NULLIF(TRIM(p_target_region), ''), 'Global')]::TEXT[];
    ELSE
        v_countries := p_target_countries;
    END IF;

    v_badge := CASE
        WHEN COALESCE(p_organizer_price, 0) = 0 THEN 'SPONSORED PARTNER REWARD'
        WHEN v_discount >= 20 THEN v_discount || '% PARTNER OFFER'
        ELSE 'BRAND PARTNER REWARD'
    END;

    INSERT INTO public."MPT_brand_offers" (
        brand_name,
        brand_domain,
        contact_name,
        contact_email,
        contact_role,
        product_title,
        product_description,
        category,
        product_image_url,
        product_url,
        retail_price,
        organizer_price,
        discount_percent,
        currency,
        promo_code,
        emoji,
        badge_text,
        status,
        vouchers_total_count,
        vouchers_consumed_count,
        platform_fee_per_voucher,
        offer_type,
        target_region,
        target_countries,
        voucher_code_type,
        expiration_date,
        redemption_restrictions,
        minimum_purchase,
        new_customers_only,
        redemption_channel,
        outreach_status,
        partnership_status,
        verified_at
    ) VALUES (
        TRIM(p_brand_name),
        v_clean_domain,
        NULLIF(TRIM(COALESCE(p_contact_name, '')), ''),
        LOWER(TRIM(p_contact_email)),
        NULLIF(TRIM(COALESCE(p_contact_role, '')), ''),
        TRIM(p_product_title),
        NULLIF(TRIM(COALESCE(p_product_description, '')), ''),
        COALESCE(NULLIF(TRIM(p_category), ''), 'Shopping Vouchers'),
        NULLIF(TRIM(COALESCE(p_product_image_url, '')), ''),
        TRIM(p_product_url),
        GREATEST(COALESCE(p_retail_price, 0), 0),
        GREATEST(COALESCE(p_organizer_price, 0), 0),
        GREATEST(v_discount, 0),
        UPPER(COALESCE(NULLIF(TRIM(p_currency), ''), 'USD')),
        NULLIF(TRIM(COALESCE(p_promo_code, '')), ''),
        COALESCE(NULLIF(TRIM(p_emoji), ''), '🎁'),
        v_badge,
        'PENDING',
        v_vouchers,
        0,
        2.00,
        UPPER(COALESCE(NULLIF(TRIM(p_offer_type), ''), 'GIFT_VOUCHER')),
        COALESCE(NULLIF(TRIM(p_target_region), ''), 'Global'),
        v_countries,
        UPPER(COALESCE(NULLIF(TRIM(p_voucher_code_type), ''), 'SHARED_PROMO_CODE')),
        p_expiration_date,
        NULLIF(TRIM(COALESCE(p_redemption_restrictions, '')), ''),
        NULLIF(TRIM(COALESCE(p_minimum_purchase, '')), ''),
        COALESCE(p_new_customers_only, FALSE),
        UPPER(COALESCE(NULLIF(TRIM(p_redemption_channel), ''), 'ONLINE')),
        'PENDING_APPROVAL',
        'PILOT',
        NULL
    )
    RETURNING * INTO v_offer;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer.id,
        'status', v_offer.status,
        'message', 'Thank you for sponsoring a DabHousie Brand Offer! Your ' || v_vouchers || '-reward pilot has been submitted and is waiting for approval.'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_register_brand_offer"(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, INTEGER,
    TEXT, TEXT, TEXT[], TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, BOOLEAN, TEXT, TEXT
) TO anon, authenticated;

-- 3. Backend Admin Helper RPC to approve a pending Brand Offer
CREATE OR REPLACE FUNCTION public."MPT_approve_brand_offer"(
    p_offer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_offer public."MPT_brand_offers";
BEGIN
    UPDATE public."MPT_brand_offers"
    SET
        status = 'ACTIVE',
        outreach_status = 'PARTNER_ACTIVE',
        verified_at = NOW(),
        updated_at = NOW()
    WHERE id = p_offer_id
    RETURNING * INTO v_offer;

    IF v_offer.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Brand offer not found.');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer.id,
        'status', v_offer.status,
        'message', 'Brand offer approved and published to the active Partner Catalog.'
    );
END;
$$;

REVOKE ALL ON FUNCTION public."MPT_approve_brand_offer"(UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public."MPT_approve_brand_offer"(UUID) TO service_role;
