-- ============================================================================
-- Migration: 20260925000004_global_partner_templates_option_b.sql
-- Purpose:
--   1. Option B: Remove demo promo codes (DAB-AMZ25, DAB-SBUX10, etc.) and
--      unverified discount percentages from the 7 third-party sample offers so
--      hosts clearly see they are Global Gift Templates where the host buys &
--      enters the real voucher code at prize settlement.
--   2. Replace regional/US-centric samples (Sephora, Soundcore) with universally
--      recognized global brands across India, US, UK, UAE, and worldwide
--      (Amazon Global/India, Starbucks, Ferrero Rocher, Uber, Netflix, JBL, Nike).
--   3. Keep the 3 Official DabHousie 100% Free Sponsored Credit Vouchers
--      (DABFREE5, DABFREE10, DABFREE25) active with 100% Free Host pricing.
-- ============================================================================

-- 1. Update Amazon to Global Gift Template (no fake promo code)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Amazon',
  brand_domain = 'amazon.com',
  product_title = 'Amazon Digital Shopping Gift Card (Global / India / US / UK)',
  product_description = 'Universal digital gift card for winners in India (amazon.in), US (amazon.com), UK, Canada & worldwide. Host provides purchased claim code at settlement.',
  category = 'Shopping Vouchers',
  retail_price = 25.00,
  organizer_price = 25.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '🛍️'
WHERE brand_domain = 'amazon.com';

-- 2. Update Starbucks to Global Gift Template (no fake promo code)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Starbucks',
  brand_domain = 'starbucks.com',
  product_title = 'Starbucks Coffee & Treats eGift Voucher (Global)',
  product_description = 'Instant digital coffee & bakery treat voucher loved by Early 5 and Corner winners worldwide. Host provides purchased eGift code at settlement.',
  category = 'Coffee & Dining',
  retail_price = 10.00,
  organizer_price = 10.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '☕'
WHERE brand_domain = 'starbucks.com';

-- 3. Update Ferrero Rocher to Global Gift Template (no fake promo code)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Ferrero Rocher',
  brand_domain = 'ferrerorocher.com',
  product_title = 'Golden Hazelnut Celebration Box (16-pc Gift Pack)',
  product_description = 'Festive gourmet chocolate gift box recognized across India, US, Europe & Asia — ideal for Four Corners and Early 5 winners.',
  category = 'Gourmet Hampers',
  retail_price = 12.00,
  organizer_price = 12.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '🍫'
WHERE brand_domain = 'ferrerorocher.com';

-- 4. Update Uber Eats / Uber to Global Gift Template (no fake promo code)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Uber & Uber Eats',
  brand_domain = 'uber.com',
  product_title = 'Party Dining & Ride Pass Gift Voucher (Global)',
  product_description = 'Universal dining delivery or ride voucher for row-line winners. Host provides purchased voucher code at settlement.',
  category = 'Coffee & Dining',
  product_url = 'https://www.uber.com/gift-cards/',
  brand_logo_url = 'https://img.logo.dev/uber.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
  retail_price = 15.00,
  organizer_price = 15.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '🍕'
WHERE brand_domain IN ('ubereats.com', 'uber.com');

-- 5. Replace Sephora with Netflix (Universal Global Entertainment Brand in India, US & Worldwide)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Netflix',
  brand_domain = 'netflix.com',
  contact_name = 'Netflix Gift Cards',
  contact_email = 'gifts@netflix.com',
  product_title = 'Netflix Entertainment & Movie Night Gift Pass (Global)',
  product_description = 'Universally loved streaming & entertainment gift pass across India, US, UK & worldwide. Host provides gift code at settlement.',
  category = 'Shopping Vouchers',
  product_url = 'https://www.netflix.com/gift-cards',
  brand_logo_url = 'https://img.logo.dev/netflix.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
  retail_price = 20.00,
  organizer_price = 20.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '🎬'
WHERE brand_domain IN ('sephora.com', 'netflix.com');

-- 6. Replace Anker Soundcore with JBL (Universally Recognized Audio Brand in India & Worldwide)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'JBL Audio',
  brand_domain = 'jbl.com',
  contact_name = 'JBL Global Gifting',
  contact_email = 'gifts@jbl.com',
  product_title = 'JBL Portable Waterproof Bluetooth Party Speaker',
  product_description = 'Iconic punchy-bass Bluetooth speaker loved in India, US & worldwide — an unforgettable Full House Grand Prize.',
  category = 'Tech & Gadgets',
  product_url = 'https://www.jbl.com/bluetooth-speakers/',
  brand_logo_url = 'https://img.logo.dev/jbl.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
  retail_price = 35.00,
  organizer_price = 35.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '🔊'
WHERE brand_domain IN ('soundcore.com', 'jbl.com');

-- 7. Update Nike to Global Gift Template (no fake promo code)
UPDATE public."MPT_brand_offers"
SET
  brand_name = 'Nike',
  brand_domain = 'nike.com',
  product_title = 'Nike Global Sportswear & Gear Digital Gift Voucher',
  product_description = 'Premium Grand Prize voucher recognized worldwide across India, US, UK & Europe. Host provides purchased gift code at settlement.',
  category = 'Shopping Vouchers',
  retail_price = 50.00,
  organizer_price = 50.00,
  promo_code = NULL,
  badge_text = 'GLOBAL GIFT TEMPLATE • HOST PROVIDES CODE',
  emoji = '👟'
WHERE brand_domain = 'nike.com';
