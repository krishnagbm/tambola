-- ============================================================================
-- Migration: 20260925000005_zero_template_discounts.sql
-- Purpose: Set discount_percent = 0 on all Option B Global Gift Templates
--          so Hall of Fame and Host Catalog never show old "SAVE X%" badges
--          on self-fulfilled global gift templates.
-- ============================================================================

UPDATE public."MPT_brand_offers"
SET discount_percent = 0
WHERE organizer_price > 0
  AND (promo_code IS NULL OR btrim(promo_code) = '');
