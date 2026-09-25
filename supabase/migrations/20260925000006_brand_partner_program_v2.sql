-- ============================================================================
-- Migration: 20260925000006_brand_partner_program_v2.sql
-- Purpose:
--   1. Strengthen & professionalize the DabHousie Brand Marketing Partner
--      Program data model (MPT_brand_offers).
--   2. Add Offer Type, Target Country/Region, Voucher Code Type, and
--      Redemption Rules fields (Expiration Date, Restrictions, Minimum
--      Purchase, New Customers Only, Online/In-Store/Both).
--   3. Add lightweight Partner Outreach CRM columns (outreach_status,
--      contact_role, first_outreach_date, last_followup_date,
--      next_followup_date, outreach_response, partnership_status,
--      campaign_results, crm_notes) so future CRM functionality requires
--      zero schema restructuring.
--   4. Add Analytics Preparation counters (game_views_count,
--      offer_views_count, winner_count, reward_claims_count,
--      redemptions_count) alongside existing games_assigned_count &
--      clicks_count.
--   5. Expand status constraint to support ACTIVE, PENDING,
--      PENDING_VERIFICATION, PAUSED, EXPIRED, DRAFT, ARCHIVED.
--   6. Update MPT_register_brand_offer and MPT_get_active_brand_offers
--      while preserving 100% backward compatibility with existing game and
--      reward flows.
-- ============================================================================

-- 1. Expand status constraint on MPT_brand_offers to include PENDING, DRAFT, ARCHIVED
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
    CHECK (status IN ('ACTIVE', 'PENDING', 'PENDING_VERIFICATION', 'PAUSED', 'EXPIRED', 'DRAFT', 'ARCHIVED'));

-- 2. Add Offer Type, Target Market, Redemption Rules, CRM, and Analytics columns
ALTER TABLE public."MPT_brand_offers"
    -- Offer & Targeting
    ADD COLUMN IF NOT EXISTS offer_type TEXT NOT NULL DEFAULT 'GIFT_VOUCHER',
    ADD COLUMN IF NOT EXISTS target_region TEXT NOT NULL DEFAULT 'Global',
    ADD COLUMN IF NOT EXISTS target_countries TEXT[] NOT NULL DEFAULT ARRAY['Global']::TEXT[],
    ADD COLUMN IF NOT EXISTS voucher_code_type TEXT NOT NULL DEFAULT 'SHARED_PROMO_CODE',
    -- Redemption Rules
    ADD COLUMN IF NOT EXISTS expiration_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS redemption_restrictions TEXT,
    ADD COLUMN IF NOT EXISTS minimum_purchase TEXT,
    ADD COLUMN IF NOT EXISTS new_customers_only BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS redemption_channel TEXT NOT NULL DEFAULT 'ONLINE',
    -- Audit Timestamps
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Future Partner Outreach CRM Fields
    ADD COLUMN IF NOT EXISTS outreach_status TEXT NOT NULL DEFAULT 'INBOUND_PILOT',
    ADD COLUMN IF NOT EXISTS contact_role TEXT,
    ADD COLUMN IF NOT EXISTS first_outreach_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_followup_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS next_followup_date TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS outreach_response TEXT,
    ADD COLUMN IF NOT EXISTS partnership_status TEXT NOT NULL DEFAULT 'PILOT',
    ADD COLUMN IF NOT EXISTS campaign_results JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS crm_notes TEXT,
    -- Analytics Preparation Counters
    ADD COLUMN IF NOT EXISTS game_views_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS offer_views_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS winner_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS reward_claims_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS redemptions_count INTEGER NOT NULL DEFAULT 0;

-- 3. Trigger to maintain updated_at automatically on MPT_brand_offers
CREATE OR REPLACE FUNCTION public."MPT_touch_brand_offers_updated_at"()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mpt_brand_offers_updated_at ON public."MPT_brand_offers";
CREATE TRIGGER trg_mpt_brand_offers_updated_at
BEFORE UPDATE ON public."MPT_brand_offers"
FOR EACH ROW
EXECUTE FUNCTION public."MPT_touch_brand_offers_updated_at"();

-- 4. Enrich existing seeded records with structured offer_type, target_region, and B2B positioning
UPDATE public."MPT_brand_offers"
SET
    offer_type = 'PROMO_CODE',
    target_region = 'Global',
    target_countries = ARRAY['Global', 'United States', 'Canada', 'United Kingdom', 'India', 'Australia', 'Europe']::TEXT[],
    voucher_code_type = 'SHARED_PROMO_CODE',
    redemption_channel = 'ONLINE',
    partnership_status = 'ACTIVE_PARTNER',
    outreach_status = 'PARTNER_ACTIVE',
    badge_text = 'SPONSORED PROMOTIONAL REWARD'
WHERE brand_domain = 'dabhousie.com';

UPDATE public."MPT_brand_offers"
SET
    offer_type = CASE
        WHEN brand_domain IN ('jbl.com', 'ferrerorocher.com') THEN 'FREE_PRODUCT'
        ELSE 'GIFT_VOUCHER'
    END,
    target_region = 'Global',
    target_countries = ARRAY['Global', 'United States', 'Canada', 'United Kingdom', 'India', 'Australia', 'Europe']::TEXT[],
    voucher_code_type = 'UNIQUE_PER_WINNER',
    redemption_channel = CASE
        WHEN brand_domain IN ('starbucks.com', 'nike.com') THEN 'BOTH'
        ELSE 'ONLINE'
    END,
    partnership_status = 'ACTIVE_PARTNER'
WHERE brand_domain <> 'dabhousie.com'
  AND organizer_price > 0
  AND (promo_code IS NULL OR btrim(promo_code) = '');

-- 5. Update MPT_get_active_brand_offers to return all enriched partner fields
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
            WHERE o.status = 'ACTIVE'
              AND (o.vouchers_total_count IS NULL OR o.vouchers_consumed_count < o.vouchers_total_count)
              AND (o.expiration_date IS NULL OR o.expiration_date > NOW())
        ),
        '[]'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_active_brand_offers"() TO anon, authenticated;

-- 6. Admin / Filtered Catalog RPC supporting Status (ACTIVE, PENDING, EXPIRED, DRAFT, ALL) and Country/Region
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
                OR (v_norm_status = 'ACTIVE' AND o.status = 'ACTIVE' AND (o.expiration_date IS NULL OR o.expiration_date > NOW()))
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

-- 7. Update MPT_register_brand_offer to support all new Partner Program & Pilot fields
-- Drop older 14-arg overload so PostgREST resolves cleanly to the comprehensive signature with defaults
DROP FUNCTION IF EXISTS public."MPT_register_brand_offer"(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, INTEGER
);
DROP FUNCTION IF EXISTS public."MPT_register_brand_offer"(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT
);

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
        'ACTIVE',
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
        'INBOUND_PILOT',
        'PILOT',
        NOW()
    )
    RETURNING * INTO v_offer;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer.id,
        'offer', row_to_json(v_offer),
        'message', 'Your ' || v_vouchers || '-reward promotional pilot is now active in the DabHousie Partner Catalog!'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_register_brand_offer"(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT, TEXT, INTEGER,
    TEXT, TEXT, TEXT[], TEXT, TEXT, TIMESTAMPTZ, TEXT, TEXT, BOOLEAN, TEXT, TEXT
) TO anon, authenticated;

-- 8. Analytics Tracking RPCs (Offer Views & Landing Page Clicks)
CREATE OR REPLACE FUNCTION public."MPT_track_brand_offer_view"(
    p_offer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public."MPT_brand_offers"
    SET offer_views_count = COALESCE(offer_views_count, 0) + 1
    WHERE id = p_offer_id;

    RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_track_brand_offer_view"(UUID) TO anon, authenticated;

-- 9. Trigger on MPT_rewards to increment winner_count (on insert) and reward_claims_count / redemptions_count (on settlement)
CREATE OR REPLACE FUNCTION public."MPT_sync_brand_offer_reward_metrics"()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.brand_offer_id IS NOT NULL THEN
            UPDATE public."MPT_brand_offers"
            SET winner_count = COALESCE(winner_count, 0) + 1
            WHERE id = NEW.brand_offer_id;
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.status = 'CLAIMED' AND COALESCE(OLD.status, '') <> 'CLAIMED' THEN
            IF COALESCE(NEW.brand_offer_id, OLD.brand_offer_id) IS NOT NULL THEN
                UPDATE public."MPT_brand_offers"
                SET
                    reward_claims_count = COALESCE(reward_claims_count, 0) + 1,
                    vouchers_consumed_count = COALESCE(vouchers_consumed_count, 0) + 1,
                    redemptions_count = CASE
                        WHEN NEW.fulfilled_gift_code IS NOT NULL AND btrim(NEW.fulfilled_gift_code) <> ''
                        THEN COALESCE(redemptions_count, 0) + 1
                        ELSE COALESCE(redemptions_count, 0)
                    END
                WHERE id = COALESCE(NEW.brand_offer_id, OLD.brand_offer_id);
            END IF;
        END IF;
        RETURN NEW;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_mpt_sync_brand_offer_metrics ON public."MPT_rewards";
CREATE TRIGGER trg_mpt_sync_brand_offer_metrics
AFTER INSERT OR UPDATE ON public."MPT_rewards"
FOR EACH ROW
EXECUTE FUNCTION public."MPT_sync_brand_offer_reward_metrics"();
