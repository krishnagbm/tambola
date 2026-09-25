-- ============================================================================
-- Migration: 20260925000009_fix_uber_gift_card_url.sql
-- Purpose:
--   Update Uber / Uber Eats gift card URL from https://www.ubereats.com/gift-cards
--   (and https://www.uber.com/gift-cards/) to https://gifts.uber.com/ across:
--     1. public."MPT_brand_offers"
--     2. public."MPT_rewards"
--     3. public."MPT_games" (prize_gifts_config)
--     4. public."MPT_game_archives" (winners_json)
-- ============================================================================

-- 1. Update MPT_brand_offers
UPDATE public."MPT_brand_offers"
SET product_url = 'https://gifts.uber.com/'
WHERE brand_domain IN ('uber.com', 'ubereats.com')
   OR product_url ILIKE '%ubereats.com/gift-cards%'
   OR product_url ILIKE '%uber.com/gift-cards%';

-- 2. Update MPT_rewards
UPDATE public."MPT_rewards"
SET fulfilled_product_url = 'https://gifts.uber.com/'
WHERE fulfilled_product_url ILIKE '%ubereats.com/gift-cards%'
   OR fulfilled_product_url ILIKE '%uber.com/gift-cards%';

-- 3. Update MPT_games prize_gifts_config JSONB
UPDATE public."MPT_games"
SET prize_gifts_config = REPLACE(
        REPLACE(prize_gifts_config::TEXT, 'https://www.ubereats.com/gift-cards', 'https://gifts.uber.com/'),
        'https://www.uber.com/gift-cards/',
        'https://gifts.uber.com/'
    )::JSONB
WHERE prize_gifts_config::TEXT ILIKE '%ubereats.com/gift-cards%'
   OR prize_gifts_config::TEXT ILIKE '%uber.com/gift-cards%';

-- 4. Update MPT_game_archives winners_json JSONB
UPDATE public."MPT_game_archives"
SET winners_json = REPLACE(
        REPLACE(winners_json::TEXT, 'https://www.ubereats.com/gift-cards', 'https://gifts.uber.com/'),
        'https://www.uber.com/gift-cards/',
        'https://gifts.uber.com/'
    )::JSONB
WHERE winners_json::TEXT ILIKE '%ubereats.com/gift-cards%'
   OR winners_json::TEXT ILIKE '%uber.com/gift-cards%';
