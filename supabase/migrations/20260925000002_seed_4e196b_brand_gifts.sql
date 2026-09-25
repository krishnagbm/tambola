-- 1. Ensure fulfilled_brand and fulfilled_code exist on MPT_rewards
ALTER TABLE public."MPT_rewards"
    ADD COLUMN IF NOT EXISTS fulfilled_brand TEXT,
    ADD COLUMN IF NOT EXISTS fulfilled_code TEXT,
    ADD COLUMN IF NOT EXISTS prize_value NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS brand_offer_id UUID REFERENCES public."MPT_brand_offers"(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS fulfilled_product_url TEXT,
    ADD COLUMN IF NOT EXISTS fulfilled_product_image_url TEXT;

-- 2. Enhance MPT_get_active_brand_offers to include convenient alias fields
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
                    'retail_value', o.retail_price
                )
                ORDER BY o.retail_price ASC, o.clicks_count DESC
            )
            FROM public."MPT_brand_offers" o
            WHERE o.status = 'ACTIVE'
        ),
        '[]'::jsonb
    );
END;
$$;

-- 3. Backfill sample Brand Gifts & Prize Values on concluded game 4E196B
DO $$
DECLARE
    v_game_id UUID;
    v_starbucks_id UUID;
    v_amazon_id UUID;
    v_ferrero_id UUID;
    v_uber_id UUID;
BEGIN
    SELECT id INTO v_game_id FROM public."MPT_games" WHERE invite_code = '4E196B' LIMIT 1;
    SELECT id INTO v_starbucks_id FROM public."MPT_brand_offers" WHERE brand_name = 'Starbucks' LIMIT 1;
    SELECT id INTO v_amazon_id FROM public."MPT_brand_offers" WHERE brand_name = 'Amazon' LIMIT 1;
    SELECT id INTO v_ferrero_id FROM public."MPT_brand_offers" WHERE brand_name = 'Ferrero Rocher' LIMIT 1;
    SELECT id INTO v_uber_id FROM public."MPT_brand_offers" WHERE brand_name = 'Uber Eats' LIMIT 1;

    IF v_game_id IS NOT NULL THEN
        UPDATE public."MPT_games"
        SET total_prize_budget = 92.00,
            minor_prize_policy = 'ONE_MINOR_PER_PLAYER',
            prize_gifts_config = jsonb_build_object(
                'EARLY_FIVE', jsonb_build_object(
                    'prize_value', 10,
                    'offer_id', v_starbucks_id,
                    'brand_name', 'Starbucks',
                    'gift_title', '$10 Coffee & Bakery E-Gift Voucher',
                    'product_title', '$10 Coffee & Bakery E-Gift Voucher',
                    'product_url', 'https://www.starbucks.com/gift',
                    'organizer_price', 7.50
                ),
                'FOUR_CORNERS', jsonb_build_object(
                    'prize_value', 12,
                    'offer_id', v_ferrero_id,
                    'brand_name', 'Ferrero Rocher',
                    'gift_title', 'Golden Hazelnut Celebration Box (16-pc)',
                    'product_title', 'Golden Hazelnut Celebration Box (16-pc)',
                    'product_url', 'https://www.ferrerorocher.com/us/en/',
                    'organizer_price', 8.00
                ),
                'TOP_LINE', jsonb_build_object(
                    'prize_value', 15,
                    'offer_id', v_uber_id,
                    'brand_name', 'Uber Eats',
                    'gift_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_url', 'https://www.ubereats.com/gift-cards',
                    'organizer_price', 11.00
                ),
                'MIDDLE_LINE', jsonb_build_object(
                    'prize_value', 15,
                    'offer_id', v_uber_id,
                    'brand_name', 'Uber Eats',
                    'gift_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_url', 'https://www.ubereats.com/gift-cards',
                    'organizer_price', 11.00
                ),
                'BOTTOM_LINE', jsonb_build_object(
                    'prize_value', 15,
                    'offer_id', v_uber_id,
                    'brand_name', 'Uber Eats',
                    'gift_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_title', '$15 Party Treat & Dining Delivery Pass',
                    'product_url', 'https://www.ubereats.com/gift-cards',
                    'organizer_price', 11.00
                ),
                'FULL_HOUSE', jsonb_build_object(
                    'prize_value', 25,
                    'offer_id', v_amazon_id,
                    'brand_name', 'Amazon',
                    'gift_title', '$25 Everything Store Digital Gift Card',
                    'product_title', '$25 Everything Store Digital Gift Card',
                    'product_url', 'https://www.amazon.com/gift-cards',
                    'organizer_price', 21.50
                )
            )
        WHERE id = v_game_id;

        UPDATE public."MPT_rewards"
        SET prize_value = 10.00,
            brand_offer_id = v_starbucks_id,
            fulfilled_brand = 'Starbucks — $10 Coffee & Bakery E-Gift Voucher',
            fulfilled_brand_name = 'Starbucks',
            fulfilled_gift_title = '$10 Coffee & Bakery E-Gift Voucher',
            fulfilled_product_url = 'https://www.starbucks.com/gift'
        WHERE game_id = v_game_id AND prize_type = 'EARLY_FIVE';

        UPDATE public."MPT_rewards"
        SET prize_value = 12.00,
            brand_offer_id = v_ferrero_id,
            fulfilled_brand = 'Ferrero Rocher — Golden Hazelnut Celebration Box (16-pc)',
            fulfilled_brand_name = 'Ferrero Rocher',
            fulfilled_gift_title = 'Golden Hazelnut Celebration Box (16-pc)',
            fulfilled_product_url = 'https://www.ferrerorocher.com/us/en/'
        WHERE game_id = v_game_id AND prize_type = 'FOUR_CORNERS';

        UPDATE public."MPT_rewards"
        SET prize_value = 15.00,
            brand_offer_id = v_uber_id,
            fulfilled_brand = 'Uber Eats — $15 Party Treat & Dining Delivery Pass',
            fulfilled_brand_name = 'Uber Eats',
            fulfilled_gift_title = '$15 Party Treat & Dining Delivery Pass',
            fulfilled_product_url = 'https://www.ubereats.com/gift-cards'
        WHERE game_id = v_game_id AND prize_type IN ('TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE');

        UPDATE public."MPT_rewards"
        SET prize_value = 25.00,
            brand_offer_id = v_amazon_id,
            fulfilled_brand = 'Amazon — $25 Everything Store Digital Gift Card',
            fulfilled_brand_name = 'Amazon',
            fulfilled_gift_title = '$25 Everything Store Digital Gift Card',
            fulfilled_product_url = 'https://www.amazon.com/gift-cards'
        WHERE game_id = v_game_id AND prize_type = 'FULL_HOUSE';

        PERFORM public."MPT_archive_concluded_game"(v_game_id);
    END IF;
END;
$$;
