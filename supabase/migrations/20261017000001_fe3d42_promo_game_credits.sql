-- ============================================================================
-- Migration: 20261017000001_fe3d42_promo_game_credits.sql
-- Purpose:
--   Assign $5 DabHousie Credit Vouchers (DABFREE5) to all minor patterns
--   (EARLY_FIVE, FOUR_CORNERS, TOP_LINE, MIDDLE_LINE, BOTTOM_LINE) alongside
--   the existing $10 Full House DabHousie voucher (DABFREE10) for Facebook
--   promotional game FE3D42 (Dashara DabHousie League 🏆, 250 capacity).
-- ============================================================================

DO $$
DECLARE
    v_dab5_id UUID;
    v_dab10_id UUID;
    v_game_id UUID;
BEGIN
    -- 1. Locate brand offers for DabHousie vouchers
    SELECT id INTO v_dab5_id FROM public."MPT_brand_offers" WHERE promo_code = 'DABFREE5' LIMIT 1;
    SELECT id INTO v_dab10_id FROM public."MPT_brand_offers" WHERE promo_code = 'DABFREE10' LIMIT 1;
    SELECT id INTO v_game_id FROM public."MPT_games" WHERE invite_code = 'FE3D42' LIMIT 1;

    IF v_game_id IS NOT NULL AND v_dab5_id IS NOT NULL THEN
        UPDATE public."MPT_games"
        SET 
            total_prize_budget = 35.00,
            prize_gifts_config = COALESCE(prize_gifts_config, '{}'::jsonb) || jsonb_build_object(
                'EARLY_FIVE', jsonb_build_object(
                    'emoji', '🎟️',
                    'currency', 'USD',
                    'offer_id', v_dab5_id,
                    'brand_name', 'DabHousie',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE5',
                    'prize_value', 5,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 5,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                ),
                'FOUR_CORNERS', jsonb_build_object(
                    'emoji', '🎟️',
                    'currency', 'USD',
                    'offer_id', v_dab5_id,
                    'brand_name', 'DabHousie',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE5',
                    'prize_value', 5,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 5,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                ),
                'TOP_LINE', jsonb_build_object(
                    'emoji', '🎟️',
                    'currency', 'USD',
                    'offer_id', v_dab5_id,
                    'brand_name', 'DabHousie',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE5',
                    'prize_value', 5,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 5,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                ),
                'MIDDLE_LINE', jsonb_build_object(
                    'emoji', '🎟️',
                    'currency', 'USD',
                    'offer_id', v_dab5_id,
                    'brand_name', 'DabHousie',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE5',
                    'prize_value', 5,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 5,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                ),
                'BOTTOM_LINE', jsonb_build_object(
                    'emoji', '🎟️',
                    'currency', 'USD',
                    'offer_id', v_dab5_id,
                    'brand_name', 'DabHousie',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE5',
                    'prize_value', 5,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 5,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                ),
                'FULL_HOUSE', jsonb_build_object(
                    'emoji', '🎁',
                    'currency', 'USD',
                    'offer_id', COALESCE(v_dab10_id, (prize_gifts_config -> 'FULL_HOUSE' ->> 'offer_id')::UUID),
                    'brand_name', 'DabHousie',
                    'gift_title', '$10 Free Party Pack Credit Voucher (Row Line Prize)',
                    'product_title', '$10 Free Party Pack Credit Voucher (Row Line Prize)',
                    'offer_type', 'PROMO_CODE',
                    'promo_code', 'DABFREE10',
                    'prize_value', 10,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'brand_domain', 'dabhousie.com',
                    'retail_price', 10,
                    'target_region', 'Global',
                    'brand_logo_url', null,
                    'currency_symbol', '$',
                    'organizer_price', 0,
                    'product_image_url', null,
                    'is_custom_host_offer', false
                )
            )
        WHERE id = v_game_id;

        -- Update stats counter on DABFREE5 offer
        UPDATE public."MPT_brand_offers"
        SET games_assigned_count = games_assigned_count + 5
        WHERE id = v_dab5_id;
    END IF;
END $$;
