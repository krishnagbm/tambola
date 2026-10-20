-- =====================================================================
-- Migration: 20261020000001_mpt_create_promotional_game_batch.sql
-- Description:
--   RPC MPT_create_promotional_game_batch to allow Super Admins to batch-create
--   promotional / marketing / festival games with standardized prize pools and autonomous Dabby orchestration.
-- =====================================================================

CREATE OR REPLACE FUNCTION public."MPT_create_promotional_game_batch"(
    p_games JSONB,
    p_increment_brand_offers BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_role TEXT := 'HOST';
    v_game JSONB;
    v_created_games JSONB := '[]'::JSONB;
    v_game_id UUID;
    v_invite_code TEXT;
    v_name TEXT;
    v_scheduled_at TIMESTAMPTZ;
    v_capacity INT;
    v_tier_id UUID;
    v_admin_id UUID;
    v_prizes_config JSONB;
    v_prize_gifts_config JSONB;
    v_budget NUMERIC;
    v_is_public BOOLEAN;
    v_policy TEXT;
    v_inserted_record RECORD;
    v_dabby_time TEXT;
    v_chars TEXT := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    i INT;
    v_char_len INT := length(v_chars);
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    -- Verify Super Admin role
    SELECT role INTO v_role
    FROM public."MPT_admin_profiles"
    WHERE user_id = v_uid;

    IF v_role IS NULL OR UPPER(v_role) != 'ADMIN' THEN
        RAISE EXCEPTION 'Unauthorized: Only Super Administrators can create promotional game batches.';
    END IF;

    -- Loop through each game object
    FOR v_game IN SELECT * FROM jsonb_array_elements(p_games)
    LOOP
        v_name := COALESCE(v_game->>'name', 'DabHousie Promotional Event 🏆');
        v_scheduled_at := (v_game->>'scheduled_at')::TIMESTAMPTZ;
        v_capacity := COALESCE((v_game->>'capacity')::INT, 250);

        -- Resolve capacity tier dynamically if not explicitly specified
        IF (v_game->>'planned_capacity_tier_id') IS NOT NULL THEN
            v_tier_id := (v_game->>'planned_capacity_tier_id')::UUID;
        ELSE
            SELECT id INTO v_tier_id
            FROM public."MPT_capacity_tiers"
            WHERE v_capacity BETWEEN min_players AND max_players
            ORDER BY display_order ASC
            LIMIT 1;

            IF v_tier_id IS NULL THEN
                SELECT id INTO v_tier_id
                FROM public."MPT_capacity_tiers"
                ORDER BY max_players DESC
                LIMIT 1;
            END IF;
        END IF;
        v_admin_id := COALESCE((v_game->>'admin_user_id')::UUID, v_uid);
        v_budget := COALESCE((v_game->>'total_prize_budget')::NUMERIC, 35.00);
        v_is_public := COALESCE((v_game->>'is_publicly_visible')::BOOLEAN, TRUE);
        v_policy := COALESCE(v_game->>'minor_prize_policy', 'ONE_MINOR_PER_PLAYER');

        -- Invite Code generation if not provided
        v_invite_code := UPPER(TRIM(COALESCE(v_game->>'invite_code', '')));
        IF length(v_invite_code) < 6 THEN
            LOOP
                v_invite_code := '';
                FOR i IN 1..6 LOOP
                    v_invite_code := v_invite_code || substr(v_chars, floor(random() * v_char_len + 1)::INT, 1);
                END LOOP;
                -- Ensure uniqueness
                EXIT WHEN NOT EXISTS (SELECT 1 FROM public."MPT_games" WHERE invite_code = v_invite_code);
            END LOOP;
        END IF;

        -- Prizes Config default
        v_prizes_config := COALESCE(
            v_game->'prizes_config',
            '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::JSONB
        );

        -- Prize Gifts Config with Dabby Orchestration
        v_prize_gifts_config := v_game->'prize_gifts_config';
        IF v_prize_gifts_config IS NULL OR v_prize_gifts_config = 'null'::JSONB THEN
            -- Build standard $35 pool with DABFREE5 & DABFREE10
            v_prize_gifts_config := jsonb_build_object(
                'EARLY_FIVE', jsonb_build_object(
                    'emoji', '🎟️', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', 'c2d53003-6f75-4191-b7dd-413cf02e038a',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE5',
                    'prize_value', 5, 'retail_price', 5, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                'TOP_LINE', jsonb_build_object(
                    'emoji', '🎟️', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', 'c2d53003-6f75-4191-b7dd-413cf02e038a',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE5',
                    'prize_value', 5, 'retail_price', 5, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                'MIDDLE_LINE', jsonb_build_object(
                    'emoji', '🎟️', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', 'c2d53003-6f75-4191-b7dd-413cf02e038a',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE5',
                    'prize_value', 5, 'retail_price', 5, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                'BOTTOM_LINE', jsonb_build_object(
                    'emoji', '🎟️', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', 'c2d53003-6f75-4191-b7dd-413cf02e038a',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE5',
                    'prize_value', 5, 'retail_price', 5, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                'FOUR_CORNERS', jsonb_build_object(
                    'emoji', '🎟️', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', 'c2d53003-6f75-4191-b7dd-413cf02e038a',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'product_title', '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE5',
                    'prize_value', 5, 'retail_price', 5, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                'FULL_HOUSE', jsonb_build_object(
                    'emoji', '🎁', 'currency', 'USD', 'currency_symbol', '$',
                    'offer_id', '5a5b8d5b-c6fa-4507-a6fa-32174db5d28b',
                    'brand_name', 'DabHousie', 'brand_domain', 'dabhousie.com',
                    'gift_title', '$10 Free Party Pack Credit Voucher (Row Line Prize)',
                    'product_title', '$10 Free Party Pack Credit Voucher (Row Line Prize)',
                    'offer_type', 'PROMO_CODE', 'promo_code', 'DABFREE10',
                    'prize_value', 10, 'retail_price', 10, 'organizer_price', 0,
                    'product_url', 'https://www.dabhousie.com/pricing.html',
                    'target_region', 'Global', 'is_custom_host_offer', false
                ),
                '_currency_code', 'USD',
                '_currency_symbol', '$'
            );
        END IF;

        -- Ensure Dabby orchestration is set
        IF v_scheduled_at IS NOT NULL THEN
            v_dabby_time := to_char(v_scheduled_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
            v_prize_gifts_config := v_prize_gifts_config || jsonb_build_object(
                '_dabby_orchestration', jsonb_build_object(
                    'autonomous_host_enabled', true,
                    'scheduled_at', v_dabby_time,
                    'low_quorum_action', 'AUTO_CANCEL',
                    'quorum_count', 1,
                    'quorum_percentage', 0,
                    'grace_period_minutes', 3,
                    'auto_upgrade_on_waitlist', true
                )
            );
        END IF;

        -- Insert game
        INSERT INTO public."MPT_games" (
            admin_user_id,
            name,
            invite_code,
            status,
            planned_capacity_tier_id,
            initial_funded_capacity,
            funded_capacity,
            scheduled_at,
            prizes_config,
            prize_gifts_config,
            total_prize_budget,
            is_private,
            is_publicly_visible,
            minor_prize_policy
        ) VALUES (
            v_admin_id,
            v_name,
            v_invite_code,
            'OPEN',
            v_tier_id,
            v_capacity,
            v_capacity,
            v_scheduled_at,
            v_prizes_config,
            v_prize_gifts_config,
            v_budget,
            FALSE,
            v_is_public,
            v_policy
        )
        RETURNING * INTO v_inserted_record;

        v_created_games := v_created_games || jsonb_build_array(to_jsonb(v_inserted_record));

        -- Increment brand offer assigned count if applicable
        IF p_increment_brand_offers THEN
            UPDATE public."MPT_brand_offers"
            SET games_assigned_count = COALESCE(games_assigned_count, 0) + 5
            WHERE promo_code = 'DABFREE5';

            UPDATE public."MPT_brand_offers"
            SET games_assigned_count = COALESCE(games_assigned_count, 0) + 1
            WHERE promo_code = 'DABFREE10';
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'success', TRUE,
        'count', jsonb_array_length(v_created_games),
        'created_games', v_created_games
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_create_promotional_game_batch" TO authenticated, service_role;
