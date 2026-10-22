-- ==============================================================================
-- Migration: 20261022000001_dynamic_prize_eligibility_by_player_count.sql
-- Description: Implement active player count aware dynamic prize eligibility:
--   1. If active players < 5: All prizes open to all players (prevents stranded prizes in small/micro parties).
--   2. If active players >= 5: Enforce balanced distribution:
--      - Max 1 Bonus (Early 5 or Four Corners) per player
--      - Max 1 Row Line (Top, Middle, Bottom) per player
--      - Max 1 Housie (Full House 1 or 2) per player
--   3. Update default minor_prize_policy to 'ONE_LINE_PLUS_BONUS'.
-- ==============================================================================

-- 1. Update default minor_prize_policy on MPT_games table
ALTER TABLE public."MPT_games"
    ALTER COLUMN minor_prize_policy SET DEFAULT 'ONE_LINE_PLUS_BONUS';

-- 2. Update MPT_create_game function signature & default
CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    p_is_private BOOLEAN DEFAULT FALSE,
    p_total_prize_budget NUMERIC DEFAULT 0,
    p_prize_gifts_config JSONB DEFAULT '{}'::jsonb,
    p_minor_prize_policy TEXT DEFAULT 'ONE_LINE_PLUS_BONUS'
)
RETURNS public."MPT_games"
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID;
    v_game public."MPT_games";
    v_invite_code TEXT;
    v_tier_id UUID;
    v_attempts INT := 0;
    v_key TEXT;
    v_offer_id_str TEXT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: Must be logged in to create a game';
    END IF;

    LOOP
        v_invite_code := UPPER(SUBSTRING(MD5(RANDOM()::TEXT || CLOCK_TIMESTAMP()::TEXT) FROM 1 FOR 6));
        EXIT WHEN NOT EXISTS (SELECT 1 FROM public."MPT_games" WHERE invite_code = v_invite_code);
        v_attempts := v_attempts + 1;
        IF v_attempts > 10 THEN
            v_invite_code := 'TAMB' || (FLOOR(RANDOM() * 9000 + 1000)::TEXT);
            EXIT;
        END IF;
    END LOOP;

    SELECT id INTO v_tier_id
    FROM public."MPT_capacity_tiers"
    WHERE p_planned_capacity BETWEEN min_players AND max_players
    LIMIT 1;

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
        is_private,
        total_prize_budget,
        prize_gifts_config,
        minor_prize_policy
    )
    VALUES (
        v_uid,
        p_name,
        v_invite_code,
        'OPEN',
        v_tier_id,
        COALESCE(p_planned_capacity, 25),
        COALESCE(p_planned_capacity, 25),
        p_scheduled_at,
        COALESCE(p_prizes_config, '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb),
        COALESCE(p_is_private, FALSE),
        COALESCE(p_total_prize_budget, 0),
        COALESCE(p_prize_gifts_config, '{}'::jsonb),
        COALESCE(p_minor_prize_policy, 'ONE_LINE_PLUS_BONUS')
    )
    RETURNING * INTO v_game;

    -- Increment games_assigned_count for any Brand Offer assigned to this game's prizes
    IF p_prize_gifts_config IS NOT NULL AND jsonb_typeof(p_prize_gifts_config) = 'object' THEN
        FOR v_key IN SELECT jsonb_object_keys(p_prize_gifts_config) LOOP
            v_offer_id_str := p_prize_gifts_config -> v_key ->> 'offer_id';
            IF v_offer_id_str IS NOT NULL AND v_offer_id_str ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
                UPDATE public."MPT_brand_offers"
                SET games_assigned_count = games_assigned_count + 1
                WHERE id = v_offer_id_str::UUID;
            END IF;
        END LOOP;
    END IF;

    RETURN v_game;
END;
$$;

-- 3. Update MPT_submit_claim with dynamic active player quorum & balanced prize rules
CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers INT[],
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_game public."MPT_games";
    v_called_numbers INT[];
    v_uncalled INT[];
    v_existing_claim UUID;
    v_existing_reward public."MPT_rewards";
    v_claim_id UUID;
    v_claim_ref TEXT;
    v_policy TEXT;
    v_player_count INT := 0;
    v_gift_cfg JSONB := '{}'::jsonb;
    v_prize_val NUMERIC(10,2) := NULL;
    v_offer_id UUID := NULL;
    v_brand_name TEXT := NULL;
    v_gift_title TEXT := NULL;
    v_product_url TEXT := NULL;
    v_product_img TEXT := NULL;
    v_promo_code TEXT := NULL;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Game not found';
    END IF;

    -- 1. Check idempotency if provided
    IF p_idempotency_key IS NOT NULL THEN
        SELECT id INTO v_claim_id
        FROM public."MPT_claims"
        WHERE game_id = p_game_id
          AND user_id = v_uid
          AND prize_type = p_prize_type
          AND idempotency_key = p_idempotency_key
        LIMIT 1;

        IF v_claim_id IS NOT NULL THEN
            SELECT * INTO v_existing_reward
            FROM public."MPT_rewards"
            WHERE claim_id = v_claim_id
            LIMIT 1;

            RETURN jsonb_build_object(
                'status', 'APPROVED',
                'prize_type', p_prize_type,
                'claim_id', v_claim_id,
                'claim_reference', COALESCE(v_existing_reward.claim_reference, ''),
                'prize_value', v_existing_reward.prize_value,
                'brand_name', v_existing_reward.fulfilled_brand_name,
                'gift_title', v_existing_reward.fulfilled_gift_title,
                'product_url', v_existing_reward.fulfilled_product_url
            );
        END IF;
    END IF;

    -- 2. Check if this prize was already won in this game
    SELECT id INTO v_existing_claim
    FROM public."MPT_claims"
    WHERE game_id = p_game_id
      AND prize_type = p_prize_type
      AND status = 'APPROVED'
    LIMIT 1;

    IF v_existing_claim IS NOT NULL THEN
        RETURN jsonb_build_object(
            'status', 'REJECTED',
            'reason', 'Prize already won by another player'
        );
    END IF;

    -- Count active players who have tickets in this game
    SELECT COUNT(DISTINCT user_id) INTO v_player_count
    FROM public."MPT_player_tickets"
    WHERE game_id = p_game_id;

    IF v_player_count IS NULL OR v_player_count = 0 THEN
        SELECT COUNT(DISTINCT user_id) INTO v_player_count
        FROM public."MPT_game_registrations"
        WHERE game_id = p_game_id;
    END IF;
    v_player_count := COALESCE(v_player_count, 1);

    -- 3. Enforce Winner Eligibility Rules:
    --    - FULL_HOUSE is ALWAYS open to ALL players!
    --    - SECOND_FULL_HOUSE is open to ALL players EXCEPT the 1st FULL_HOUSE winner (if multiple players)!
    --    - Dynamic Rule based on active player count:
    --      * If active players < 5: ALL prizes open to ALL players (prevents stranded prizes in small parties)!
    --      * If active players >= 5:
    --        - Policy 'ONE_LINE_PLUS_BONUS' or 'DYNAMIC_BALANCED' (Default):
    --          Max 1 Bonus (Early 5 or Corners) + Max 1 Row Line (Top, Mid, Bottom) + Full House
    --        - Policy 'ONE_MINOR_PER_PLAYER': Max 1 minor prize per player + Full House
    --        - Policy 'UNLIMITED': Open to all players regardless of count
    v_policy := COALESCE(v_game.minor_prize_policy, 'ONE_LINE_PLUS_BONUS');

    IF p_prize_type = 'SECOND_FULL_HOUSE' THEN
        IF v_player_count > 1 AND EXISTS (
            SELECT 1 FROM public."MPT_claims"
            WHERE game_id = p_game_id
              AND user_id = v_uid
              AND prize_type = 'FULL_HOUSE'
              AND status = 'APPROVED'
        ) THEN
            RETURN jsonb_build_object(
                'status', 'REJECTED',
                'reason', 'First Full House winner cannot claim Second Full House — open to other players!'
            );
        END IF;
    ELSIF p_prize_type <> 'FULL_HOUSE' THEN
        -- If active players are 5 or more and policy is not UNLIMITED, enforce fair distribution:
        IF v_player_count >= 5 AND v_policy <> 'UNLIMITED' THEN
            IF v_policy IN ('ONE_LINE_PLUS_BONUS', 'DYNAMIC_BALANCED') THEN
                IF p_prize_type IN ('TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE') AND EXISTS (
                    SELECT 1 FROM public."MPT_claims"
                    WHERE game_id = p_game_id
                      AND user_id = v_uid
                      AND prize_type IN ('TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE')
                      AND status = 'APPROVED'
                ) THEN
                    RETURN jsonb_build_object(
                        'status', 'REJECTED',
                        'reason', 'Host Rule (5+ players): Max 1 Row Line prize per player! You are still eligible for Bonus & Full House prizes 🏆'
                    );
                ELSIF p_prize_type IN ('EARLY_FIVE', 'EARLY_5', 'FOUR_CORNERS') AND EXISTS (
                    SELECT 1 FROM public."MPT_claims"
                    WHERE game_id = p_game_id
                      AND user_id = v_uid
                      AND prize_type IN ('EARLY_FIVE', 'EARLY_5', 'FOUR_CORNERS')
                      AND status = 'APPROVED'
                ) THEN
                    RETURN jsonb_build_object(
                        'status', 'REJECTED',
                        'reason', 'Host Rule (5+ players): Max 1 Bonus prize (Early 5 or Corners) per player! You are still eligible for Row Lines & Full House 🏆'
                    );
                END IF;
            ELSIF v_policy = 'ONE_MINOR_PER_PLAYER' THEN
                IF EXISTS (
                    SELECT 1 FROM public."MPT_claims"
                    WHERE game_id = p_game_id
                      AND user_id = v_uid
                      AND prize_type NOT IN ('FULL_HOUSE', 'SECOND_FULL_HOUSE')
                      AND status = 'APPROVED'
                ) THEN
                    RETURN jsonb_build_object(
                        'status', 'REJECTED',
                        'reason', 'Host Rule (5+ players): Max 1 minor/line prize per player! Keep playing — you are still eligible for Full House 🏆'
                    );
                END IF;
            END IF;
        END IF;
    END IF;

    -- 4. Fetch all called numbers for this game
    SELECT COALESCE(array_agg(number), ARRAY[]::INT[])
    INTO v_called_numbers
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    -- 5. Verify all marked numbers have been called
    SELECT COALESCE(array_agg(m), ARRAY[]::INT[])
    INTO v_uncalled
    FROM unnest(p_marked_numbers) AS m
    WHERE NOT (m = ANY(v_called_numbers));

    IF array_length(v_uncalled, 1) IS NOT NULL AND array_length(v_uncalled, 1) > 0 THEN
        INSERT INTO public."MPT_claims" (
            game_id, user_id, prize_type, status, marked_numbers, rejection_reason, idempotency_key, processed_at
        ) VALUES (
            p_game_id, v_uid, p_prize_type, 'BOGEY', to_jsonb(p_marked_numbers),
            'Contains uncalled numbers: ' || array_to_string(v_uncalled, ', '),
            p_idempotency_key, NOW()
        );

        RETURN jsonb_build_object(
            'status', 'BOGEY',
            'reason', 'Contains uncalled numbers: ' || array_to_string(v_uncalled, ', ')
        );
    END IF;

    -- 6. Insert APPROVED claim
    INSERT INTO public."MPT_claims" (
        game_id, user_id, prize_type, status, marked_numbers, idempotency_key, processed_at
    ) VALUES (
        p_game_id, v_uid, p_prize_type, 'APPROVED', to_jsonb(p_marked_numbers), p_idempotency_key, NOW()
    )
    RETURNING id INTO v_claim_id;

    -- 7. Extract configured Brand Gift & Prize Value for this prize_type from MPT_games.prize_gifts_config
    IF v_game.prize_gifts_config IS NOT NULL AND jsonb_typeof(v_game.prize_gifts_config) = 'object' THEN
        v_gift_cfg := COALESCE(v_game.prize_gifts_config -> p_prize_type, '{}'::jsonb);
        IF (v_gift_cfg->>'prize_value') IS NOT NULL AND (v_gift_cfg->>'prize_value') ~ '^[0-9]+(\.[0-9]+)?$' THEN
            v_prize_val := (v_gift_cfg->>'prize_value')::NUMERIC(10,2);
        END IF;
        IF (v_gift_cfg->>'offer_id') IS NOT NULL AND (v_gift_cfg->>'offer_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
            v_offer_id := (v_gift_cfg->>'offer_id')::UUID;
        END IF;
        v_brand_name := NULLIF(TRIM(COALESCE(v_gift_cfg->>'brand_name', '')), '');
        v_gift_title := NULLIF(TRIM(COALESCE(v_gift_cfg->>'product_title', '')), '');
        v_product_url := NULLIF(TRIM(COALESCE(v_gift_cfg->>'product_url', '')), '');
        v_product_img := NULLIF(TRIM(COALESCE(v_gift_cfg->>'product_image_url', '')), '');
        v_promo_code := NULLIF(TRIM(COALESCE(v_gift_cfg->>'promo_code', '')), '');
    END IF;

    -- 8. Generate canonical Dab-Housie-XXXX-XXXX voucher reference and insert into MPT_rewards
    v_claim_ref := 'Dab-Housie-'
        || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4))
        || '-'
        || upper(substr(replace(gen_random_uuid()::text, '-', ''), 5, 4));

    INSERT INTO public."MPT_rewards" (
        game_id,
        user_id,
        prize_type,
        claim_id,
        claim_reference,
        reward_code,
        reward_title,
        status,
        prize_value,
        brand_offer_id,
        fulfilled_brand_name,
        fulfilled_gift_title,
        fulfilled_product_url,
        fulfilled_product_image_url,
        fulfilled_gift_code,
        expires_at
    ) VALUES (
        p_game_id,
        v_uid,
        p_prize_type,
        v_claim_id,
        v_claim_ref,
        v_claim_ref,
        COALESCE(v_gift_title, p_prize_type || ' Winner'),
        'AVAILABLE_TO_CLAIM',
        v_prize_val,
        v_offer_id,
        v_brand_name,
        v_gift_title,
        v_product_url,
        v_product_img,
        v_promo_code,
        NOW() + INTERVAL '30 days'
    );

    -- 9. If FULL_HOUSE was won (and SECOND_FULL_HOUSE is not enabled or also won), archive to Hall of Fame
    IF p_prize_type = 'FULL_HOUSE' AND NOT (v_game.prizes_config @> '["SECOND_FULL_HOUSE"]'::jsonb) THEN
        PERFORM public."MPT_archive_concluded_game"(p_game_id);
    ELSIF p_prize_type = 'SECOND_FULL_HOUSE' THEN
        PERFORM public."MPT_archive_concluded_game"(p_game_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'APPROVED',
        'prize_type', p_prize_type,
        'claim_id', v_claim_id,
        'claim_reference', v_claim_ref,
        'prize_value', v_prize_val,
        'brand_name', v_brand_name,
        'gift_title', v_gift_title,
        'product_url', v_product_url,
        'gift_code', v_promo_code
    );
END;
$$;

-- Delegate JSONB overload to INT[] overload
CREATE OR REPLACE FUNCTION public."MPT_submit_claim"(
    p_game_id UUID,
    p_prize_type TEXT,
    p_marked_numbers JSONB DEFAULT '[]'::jsonb,
    p_idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_arr INT[] := ARRAY[]::INT[];
BEGIN
    IF p_marked_numbers IS NOT NULL AND jsonb_typeof(p_marked_numbers) = 'array' THEN
        SELECT COALESCE(ARRAY_AGG(elem::INT), ARRAY[]::INT[])
        INTO v_arr
        FROM jsonb_array_elements_text(p_marked_numbers) AS elem;
    END IF;
    RETURN public."MPT_submit_claim"(p_game_id, p_prize_type, v_arr, p_idempotency_key);
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_submit_claim"(UUID, TEXT, INT[], TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public."MPT_submit_claim"(UUID, TEXT, JSONB, TEXT) TO anon, authenticated;
