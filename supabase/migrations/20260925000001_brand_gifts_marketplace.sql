-- ============================================================================
-- Migration: 20260925000001_brand_gifts_marketplace.sql
-- Purpose:
-- 1. Create MPT_brand_offers table for Brand Marketing self-registration from
--    Hall of Fame and Organizer Gift Catalog search/filtering.
-- 2. Add total_prize_budget, prize_gifts_config, and minor_prize_policy to MPT_games.
-- 3. Add prize_value, brand_offer_id, fulfilled_product_url, and
--    fulfilled_product_image_url to MPT_rewards.
-- 4. Update MPT_submit_claim to enforce:
--    - 1st Full House ALWAYS open to all players
--    - 2nd Full House open to all EXCEPT 1st Full House winner
--    - Host-configurable minor prize combination policy
--    - Automatic binding of configured prize value & Brand Gift to MPT_rewards
-- 5. Update MPT_archive_concluded_game and MPT_get_game_rewards_for_host to
--    include Brand Gift & clickable product_url in Hall of Fame & Rewards.
-- ============================================================================

-- 1. Create MPT_brand_offers table
CREATE TABLE IF NOT EXISTS public."MPT_brand_offers" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    brand_name TEXT NOT NULL,
    brand_domain TEXT NOT NULL,
    brand_logo_url TEXT,
    contact_name TEXT,
    contact_email TEXT NOT NULL,
    product_title TEXT NOT NULL,
    product_description TEXT,
    category TEXT NOT NULL DEFAULT 'General',
    product_image_url TEXT,
    product_url TEXT NOT NULL,
    retail_price NUMERIC(10,2) NOT NULL DEFAULT 0,
    organizer_price NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount_percent INT NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'USD',
    promo_code TEXT,
    emoji TEXT NOT NULL DEFAULT '🎁',
    badge_text TEXT,
    status TEXT NOT NULL DEFAULT 'ACTIVE'
        CHECK (status IN ('PENDING_VERIFICATION', 'ACTIVE', 'PAUSED', 'EXPIRED')),
    verification_token TEXT UNIQUE,
    verified_at TIMESTAMPTZ,
    games_assigned_count INT NOT NULL DEFAULT 0,
    clicks_count INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public."MPT_brand_offers" ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can read active brand offers" ON public."MPT_brand_offers";
CREATE POLICY "Public can read active brand offers"
ON public."MPT_brand_offers"
FOR SELECT
USING (status = 'ACTIVE');

GRANT SELECT ON public."MPT_brand_offers" TO anon, authenticated;

-- Seed curated Brand Publisher offers if table is empty
INSERT INTO public."MPT_brand_offers" (
    brand_name, brand_domain, brand_logo_url, contact_name, contact_email,
    product_title, product_description, category, product_url,
    retail_price, organizer_price, discount_percent, promo_code, emoji, badge_text,
    status, verified_at, games_assigned_count, clicks_count
)
SELECT * FROM (VALUES
    (
        'Starbucks', 'starbucks.com', 'https://img.logo.dev/starbucks.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Starbucks Brand Partnerships', 'partnerships@starbucks.com',
        '$10 Coffee & Bakery E-Gift Voucher',
        'Instant digital café voucher redeemable for handcrafted beverages and bakery treats.',
        'Coffee & Dining', 'https://www.starbucks.com/gift',
        10.00, 7.50, 25, 'DAB-SBUX10', '☕', 'POPULAR FOR EARLY 5',
        'ACTIVE', NOW(), 18, 142
    ),
    (
        'Ferrero Rocher', 'ferrerorocher.com', 'https://img.logo.dev/ferrerorocher.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Ferrero Gifting Team', 'gifting@ferrerorocher.com',
        'Golden Hazelnut Celebration Box (16-pc)',
        'Festive gourmet chocolate gift box ideal for Four Corners andEarly Five winners.',
        'Gourmet Hampers', 'https://www.ferrerorocher.com/us/en/',
        12.00, 8.00, 33, 'DAB-FERRERO', '🍫', '33% BRAND DISCOUNT',
        'ACTIVE', NOW(), 14, 98
    ),
    (
        'Uber Eats', 'ubereats.com', 'https://img.logo.dev/ubereats.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Uber Eats Promotions', 'promos@ubereats.com',
        '$15 Party Treat & Dining Pass',
        'Let row line winners order their favorite celebratory meal, pizza, or dessert.',
        'Coffee & Dining', 'https://www.ubereats.com',
        15.00, 11.00, 27, 'DAB-UBER15', '🍕', 'GREAT FOR ROW LINES',
        'ACTIVE', NOW(), 22, 189
    ),
    (
        'Sephora', 'sephora.com', 'https://img.logo.dev/sephora.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Sephora Digital Campaigns', 'campaigns@sephora.com',
        '$20 Beauty & Wellness Discovery Set',
        'Curated skincare & fragrance mini gift voucher with free shipping.',
        'Beauty & Lifestyle', 'https://www.sephora.com/beauty/gift-cards',
        20.00, 14.00, 30, 'DAB-GLOW20', '✨', 'KITTY PARTY FAVORITE',
        'ACTIVE', NOW(), 11, 87
    ),
    (
        'Amazon', 'amazon.com', 'https://img.logo.dev/amazon.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Amazon Corporate Gift Cards', 'incentives@amazon.com',
        '$25 Everything Store Digital Gift Card',
        'Universal shopping voucher delivered straight to the winner reward wallet.',
        'Shopping Vouchers', 'https://www.amazon.com/gift-cards',
        25.00, 21.50, 14, 'DAB-AMZ25', '🛍️', 'UNIVERSAL CHOICE',
        'ACTIVE', NOW(), 31, 264
    ),
    (
        'Anker Soundcore', 'soundcore.com', 'https://img.logo.dev/soundcore.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Soundcore Audio Marketing', 'events@soundcore.com',
        'Mini Bluetooth Party Speaker (Waterproof)',
        'Punchy 360° bass portable speaker — an unforgettable Full House Grand Prize.',
        'Tech & Gadgets', 'https://us.soundcore.com',
        35.00, 22.00, 37, 'DAB-SOUND35', '🔊', 'FULL HOUSE FAVORITE',
        'ACTIVE', NOW(), 16, 215
    ),
    (
        'Nike', 'nike.com', 'https://img.logo.dev/nike.com?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png',
        'Nike Promotional Rewards', 'rewards@nike.com',
        '$50 Gear & Sportswear Digital Voucher',
        'Premium Grand Prize voucher redeemable online or in Nike retail stores.',
        'Shopping Vouchers', 'https://www.nike.com/gift-cards',
        50.00, 38.00, 24, 'DAB-NIKE50', '👟', 'MEGA FULL HOUSE PRIZE',
        'ACTIVE', NOW(), 9, 134
    )
) AS v(
    brand_name, brand_domain, brand_logo_url, contact_name, contact_email,
    product_title, product_description, category, product_url,
    retail_price, organizer_price, discount_percent, promo_code, emoji, badge_text,
    status, verified_at, games_assigned_count, clicks_count
)
WHERE NOT EXISTS (SELECT 1 FROM public."MPT_brand_offers");

-- 2. Extend MPT_games with Prize Budget, Per-Prize Gift Mapping & Minor Prize Policy
ALTER TABLE public."MPT_games"
    ADD COLUMN IF NOT EXISTS total_prize_budget NUMERIC(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS prize_gifts_config JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS minor_prize_policy TEXT NOT NULL DEFAULT 'ONE_MINOR_PER_PLAYER';

-- 3. Extend MPT_rewards with Prize Value & Brand Offer Link Metadata
ALTER TABLE public."MPT_rewards"
    ADD COLUMN IF NOT EXISTS prize_value NUMERIC(10,2),
    ADD COLUMN IF NOT EXISTS brand_offer_id UUID REFERENCES public."MPT_brand_offers"(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS fulfilled_product_url TEXT,
    ADD COLUMN IF NOT EXISTS fulfilled_product_image_url TEXT;

-- 4. RPCs for Brand Offers Marketplace (Get, Self-Register, Verify, Track Click)
CREATE OR REPLACE FUNCTION public."MPT_get_active_brand_offers"()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN COALESCE(
        (
            SELECT jsonb_agg(row_to_json(o)::jsonb ORDER BY o.retail_price ASC, o.clicks_count DESC)
            FROM public."MPT_brand_offers" o
            WHERE o.status = 'ACTIVE'
        ),
        '[]'::jsonb
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_active_brand_offers"() TO anon, authenticated;

CREATE OR REPLACE FUNCTION public."MPT_register_brand_offer"(
    p_brand_name TEXT,
    p_brand_domain TEXT,
    p_brand_logo_url TEXT,
    p_contact_name TEXT,
    p_contact_email TEXT,
    p_product_title TEXT,
    p_product_description TEXT,
    p_category TEXT,
    p_product_url TEXT,
    p_product_image_url TEXT DEFAULT NULL,
    p_retail_price NUMERIC DEFAULT 15,
    p_organizer_price NUMERIC DEFAULT 10,
    p_promo_code TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🎁'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_token TEXT;
    v_discount INT := 0;
    v_offer public."MPT_brand_offers";
BEGIN
    v_token := encode(gen_random_bytes(24), 'hex');

    IF COALESCE(p_retail_price, 0) > 0 AND COALESCE(p_organizer_price, 0) < p_retail_price THEN
        v_discount := ROUND(((p_retail_price - p_organizer_price) / p_retail_price) * 100)::INT;
    END IF;

    INSERT INTO public."MPT_brand_offers" (
        brand_name,
        brand_domain,
        brand_logo_url,
        contact_name,
        contact_email,
        product_title,
        product_description,
        category,
        product_image_url,
        product_url,
        retail_price,
        organizer_price,
        discount_percent,
        promo_code,
        emoji,
        badge_text,
        status,
        verification_token,
        verified_at
    )
    VALUES (
        TRIM(p_brand_name),
        LOWER(TRIM(p_brand_domain)),
        NULLIF(TRIM(COALESCE(p_brand_logo_url, '')), ''),
        NULLIF(TRIM(COALESCE(p_contact_name, '')), ''),
        LOWER(TRIM(p_contact_email)),
        TRIM(p_product_title),
        NULLIF(TRIM(COALESCE(p_product_description, '')), ''),
        COALESCE(NULLIF(TRIM(p_category), ''), 'General'),
        TRIM(p_product_url),
        NULLIF(TRIM(COALESCE(p_product_image_url, '')), ''),
        GREATEST(0, COALESCE(p_retail_price, 0)),
        GREATEST(0, COALESCE(p_organizer_price, 0)),
        GREATEST(0, v_discount),
        NULLIF(TRIM(COALESCE(p_promo_code, '')), ''),
        COALESCE(NULLIF(TRIM(p_emoji), ''), '🎁'),
        CASE WHEN v_discount > 0 THEN v_discount || '% BRAND PARTNER OFFER' ELSE 'SPONSORED BRAND GIFT' END,
        'ACTIVE',
        v_token,
        NOW()
    )
    RETURNING * INTO v_offer;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer.id,
        'verification_token', v_token,
        'offer', row_to_json(v_offer)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_register_brand_offer"(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, NUMERIC, TEXT, TEXT
) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public."MPT_track_brand_offer_click"(
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
    SET clicks_count = clicks_count + 1
    WHERE id = p_offer_id
    RETURNING * INTO v_offer;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer.id,
        'clicks_count', v_offer.clicks_count,
        'product_url', v_offer.product_url
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_track_brand_offer_click"(UUID) TO anon, authenticated;

-- 5. Update MPT_create_game to store total_prize_budget, prize_gifts_config, minor_prize_policy
DROP FUNCTION IF EXISTS public."MPT_create_game"(TEXT, INT, TIMESTAMPTZ, JSONB, BOOLEAN);
DROP FUNCTION IF EXISTS public."MPT_create_game"(TEXT, INT, TIMESTAMPTZ, JSONB, UUID);
DROP FUNCTION IF EXISTS public."MPT_create_game"(TEXT, INT, UUID, TIMESTAMPTZ, JSONB);

CREATE OR REPLACE FUNCTION public."MPT_create_game"(
    p_name TEXT,
    p_planned_capacity INT DEFAULT 25,
    p_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    p_prizes_config JSONB DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    p_is_private BOOLEAN DEFAULT FALSE,
    p_total_prize_budget NUMERIC DEFAULT 0,
    p_prize_gifts_config JSONB DEFAULT '{}'::jsonb,
    p_minor_prize_policy TEXT DEFAULT 'ONE_MINOR_PER_PLAYER'
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
        COALESCE(p_minor_prize_policy, 'ONE_MINOR_PER_PLAYER')
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

    IF COALESCE(p_is_private, FALSE) = TRUE THEN
        PERFORM public."MPT_generate_game_seat_otps"(
            v_game.id,
            COALESCE(p_planned_capacity, 25),
            1
        );
    END IF;

    RETURN v_game;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_create_game"(
    TEXT, INT, TIMESTAMPTZ, JSONB, BOOLEAN, NUMERIC, JSONB, TEXT
) TO authenticated;

-- 6. Update MPT_submit_claim to enforce Full House / 2nd Full House / Minor Prize Rules
--    and automatically attach configured Brand Gift & Prize Value to MPT_rewards!
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

    -- 3. Enforce Winner Eligibility Rules:
    --    - FULL_HOUSE is ALWAYS open to ALL players!
    --    - SECOND_FULL_HOUSE is open to ALL players EXCEPT the 1st FULL_HOUSE winner!
    --    - Minor prizes follow v_game.minor_prize_policy ('ONE_MINOR_PER_PLAYER', 'ONE_LINE_PLUS_BONUS', 'UNLIMITED')
    v_policy := COALESCE(v_game.minor_prize_policy, 'ONE_MINOR_PER_PLAYER');

    IF p_prize_type = 'SECOND_FULL_HOUSE' THEN
        IF EXISTS (
            SELECT 1 FROM public."MPT_claims"
            WHERE game_id = p_game_id
              AND user_id = v_uid
              AND prize_type = 'FULL_HOUSE'
              AND status = 'APPROVED'
        ) THEN
            RETURN jsonb_build_object(
                'status', 'REJECTED',
                'reason', 'First Full House winner cannot claim Second Full House — open to all other players!'
            );
        END IF;
    ELSIF p_prize_type <> 'FULL_HOUSE' THEN
        IF v_policy = 'ONE_MINOR_PER_PLAYER' THEN
            IF EXISTS (
                SELECT 1 FROM public."MPT_claims"
                WHERE game_id = p_game_id
                  AND user_id = v_uid
                  AND prize_type NOT IN ('FULL_HOUSE', 'SECOND_FULL_HOUSE')
                  AND status = 'APPROVED'
            ) THEN
                RETURN jsonb_build_object(
                    'status', 'REJECTED',
                    'reason', 'Host Rule: Max 1 minor/line prize per player! Keep playing — you are still eligible for Full House 🏆'
                );
            END IF;
        ELSIF v_policy = 'ONE_LINE_PLUS_BONUS' THEN
            IF p_prize_type IN ('TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE') AND EXISTS (
                SELECT 1 FROM public."MPT_claims"
                WHERE game_id = p_game_id
                  AND user_id = v_uid
                  AND prize_type IN ('TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE')
                  AND status = 'APPROVED'
            ) THEN
                RETURN jsonb_build_object(
                    'status', 'REJECTED',
                    'reason', 'Host Rule: Max 1 Row Line prize per player! You are still eligible for Bonus & Full House prizes 🏆'
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
                    'reason', 'Host Rule: Max 1 Bonus prize (Early 5 / Corners) per player! You are still eligible for Row Lines & Full House 🏆'
                );
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

-- 7. Update MPT_archive_concluded_game so Hall of Fame winners_roster includes Brand Gift & product_url
CREATE OR REPLACE FUNCTION public."MPT_archive_concluded_game"(p_game_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_game public."MPT_games";
    v_player_count INT := 0;
    v_numbers_called_count INT := 0;
    v_duration_seconds INT := 0;
    v_effective_completed_at TIMESTAMPTZ;
    v_winners JSONB := '[]'::jsonb;
    v_archive public."MPT_game_archives";
BEGIN
    SELECT * INTO v_game
    FROM public."MPT_games"
    WHERE id = p_game_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Game not found');
    END IF;

    v_effective_completed_at := GREATEST(
        COALESCE(v_game.completed_at, v_game.updated_at, NOW()),
        COALESCE(
            (SELECT MAX(submitted_at) FROM public."MPT_claims" WHERE game_id = p_game_id),
            v_game.started_at,
            v_game.created_at,
            NOW()
        )
    );

    UPDATE public."MPT_games"
    SET
        status = 'COMPLETED',
        completed_at = v_effective_completed_at,
        updated_at = NOW()
    WHERE id = p_game_id;

    SELECT COUNT(*) INTO v_player_count
    FROM public."MPT_game_registrations"
    WHERE game_id = p_game_id AND seat_status IN ('CONFIRMED', 'ELIGIBLE');

    v_player_count := GREATEST(v_player_count, COALESCE(v_game.final_capacity, 0), COALESCE(v_game.funded_capacity, 5));

    SELECT COUNT(*) INTO v_numbers_called_count
    FROM public."MPT_called_numbers"
    WHERE game_id = p_game_id;

    v_duration_seconds := GREATEST(
        10,
        EXTRACT(EPOCH FROM (v_effective_completed_at - COALESCE(v_game.started_at, v_game.created_at, v_effective_completed_at)))::INT
    );

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'prize_type', c.prize_type,
                'winner_name', COALESCE(NULLIF(r.display_name, ''), NULLIF(u.display_name, ''), 'Player'),
                'winner_avatar', COALESCE(r.avatar, u.avatar, 'avatar_lion'),
                'ticket_seq', COALESCE(t.ticket_number, r.registration_seq, 1),
                'claim_reference', COALESCE(rw.claim_reference, ''),
                'prize_value', COALESCE(
                    rw.prize_value,
                    CASE
                        WHEN (v_game.prize_gifts_config -> c.prize_type ->> 'prize_value') ~ '^[0-9]+(\.[0-9]+)?$'
                        THEN (v_game.prize_gifts_config -> c.prize_type ->> 'prize_value')::NUMERIC(10,2)
                        ELSE NULL
                    END
                ),
                'brand_name', COALESCE(
                    rw.fulfilled_brand_name,
                    v_game.prize_gifts_config -> c.prize_type ->> 'brand_name'
                ),
                'gift_title', COALESCE(
                    rw.fulfilled_gift_title,
                    v_game.prize_gifts_config -> c.prize_type ->> 'product_title'
                ),
                'product_url', COALESCE(
                    rw.fulfilled_product_url,
                    v_game.prize_gifts_config -> c.prize_type ->> 'product_url'
                ),
                'offer_id', COALESCE(
                    rw.brand_offer_id::TEXT,
                    v_game.prize_gifts_config -> c.prize_type ->> 'offer_id'
                ),
                'verified_at', COALESCE(c.processed_at, c.submitted_at, NOW())
            )
            ORDER BY
                CASE
                    WHEN c.prize_type = 'FULL_HOUSE' THEN 0
                    WHEN c.prize_type = 'SECOND_FULL_HOUSE' THEN 1
                    WHEN c.prize_type = 'TOP_LINE' THEN 2
                    WHEN c.prize_type = 'MIDDLE_LINE' THEN 3
                    WHEN c.prize_type = 'BOTTOM_LINE' THEN 4
                    WHEN c.prize_type IN ('EARLY_FIVE', 'EARLY_5') THEN 5
                    WHEN c.prize_type = 'FOUR_CORNERS' THEN 6
                    ELSE 7
                END ASC,
                c.submitted_at ASC
        ),
        '[]'::jsonb
    ) INTO v_winners
    FROM public."MPT_claims" c
    LEFT JOIN public."MPT_game_registrations" r ON (r.game_id = c.game_id AND r.user_id = c.user_id)
    LEFT JOIN public."MPT_users" u ON u.id = c.user_id
    LEFT JOIN public."MPT_player_tickets" t ON (t.game_id = c.game_id AND t.user_id = c.user_id)
    LEFT JOIN LATERAL (
        SELECT *
        FROM public."MPT_rewards" rw_sub
        WHERE rw_sub.claim_id = c.id
           OR (rw_sub.game_id = c.game_id AND rw_sub.user_id = c.user_id AND rw_sub.prize_type = c.prize_type)
        LIMIT 1
    ) rw ON TRUE
    WHERE c.game_id = p_game_id AND c.status = 'APPROVED';

    INSERT INTO public."MPT_game_archives" (
        game_id,
        name,
        invite_code,
        admin_user_id,
        game_type,
        is_private,
        funded_capacity,
        player_count,
        numbers_called_count,
        duration_seconds,
        winners_roster,
        organization_name,
        organization_logo_url,
        organization_logo_alt,
        organization_logo_approved,
        summary,
        started_at,
        completed_at,
        created_at,
        archived_at
    )
    VALUES (
        v_game.id,
        v_game.name,
        v_game.invite_code,
        v_game.admin_user_id,
        'STANDARD_TAMBOLA',
        COALESCE(v_game.is_private, FALSE),
        COALESCE(v_game.funded_capacity, 5),
        v_player_count,
        v_numbers_called_count,
        v_duration_seconds,
        v_winners,
        v_game.organization_name,
        v_game.organization_logo_url,
        v_game.organization_logo_alt,
        COALESCE(v_game.organization_logo_approved, FALSE),
        jsonb_build_object(
            'total_claims_count', (SELECT COUNT(*) FROM public."MPT_claims" WHERE game_id = p_game_id),
            'approved_prizes_count', jsonb_array_length(v_winners),
            'total_prize_budget', COALESCE(v_game.total_prize_budget, 0)
        ),
        COALESCE(v_game.started_at, v_game.created_at),
        v_effective_completed_at,
        v_game.created_at,
        NOW()
    )
    ON CONFLICT (game_id) DO UPDATE SET
        name = EXCLUDED.name,
        invite_code = EXCLUDED.invite_code,
        is_private = EXCLUDED.is_private,
        funded_capacity = EXCLUDED.funded_capacity,
        player_count = EXCLUDED.player_count,
        numbers_called_count = EXCLUDED.numbers_called_count,
        duration_seconds = EXCLUDED.duration_seconds,
        winners_roster = EXCLUDED.winners_roster,
        organization_name = EXCLUDED.organization_name,
        organization_logo_url = EXCLUDED.organization_logo_url,
        organization_logo_alt = EXCLUDED.organization_logo_alt,
        organization_logo_approved = EXCLUDED.organization_logo_approved,
        summary = EXCLUDED.summary,
        started_at = EXCLUDED.started_at,
        completed_at = EXCLUDED.completed_at,
        archived_at = NOW()
    RETURNING * INTO v_archive;

    RETURN jsonb_build_object(
        'success', true,
        'archived_game_id', v_archive.id,
        'game_id', v_archive.game_id,
        'invite_code', v_archive.invite_code,
        'player_count', v_archive.player_count,
        'winners_count', jsonb_array_length(v_archive.winners_roster)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_archive_concluded_game"(UUID) TO anon, authenticated;

-- 8. Update MPT_get_game_rewards_for_host and MPT_close_game_claim to include product_url and prize_value
CREATE OR REPLACE FUNCTION public."MPT_get_game_rewards_for_host"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_is_host BOOLEAN := FALSE;
    v_result JSONB := '[]'::jsonb;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public."MPT_games" WHERE id = p_game_id AND admin_user_id = v_uid
        UNION ALL
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND admin_user_id = v_uid
    ) INTO v_is_host;

    IF NOT v_is_host THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the organizer of this game can manage its prize claims';
    END IF;

    -- Self-heal any APPROVED claims in this game that do not yet have an MPT_rewards row
    INSERT INTO public."MPT_rewards" (
        claim_id, user_id, game_id, prize_type, claim_reference, reward_code, reward_title, status, expires_at
    )
    SELECT
        c.id,
        c.user_id,
        c.game_id,
        c.prize_type,
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        'Dab-Housie-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 1 FOR 4)) || '-' || UPPER(SUBSTRING(MD5(c.id::TEXT) FROM 5 FOR 4)),
        c.prize_type || ' Winner',
        'AVAILABLE_TO_CLAIM',
        NOW() + INTERVAL '30 days'
    FROM public."MPT_claims" c
    WHERE c.game_id = p_game_id
      AND c.status = 'APPROVED'
      AND NOT EXISTS (
          SELECT 1 FROM public."MPT_rewards" r
          WHERE r.claim_id = c.id
             OR (r.game_id = c.game_id AND r.prize_type = c.prize_type AND r.user_id = c.user_id)
      )
    ON CONFLICT (claim_reference) DO NOTHING;

    SELECT COALESCE(
        jsonb_agg(
            jsonb_build_object(
                'id', r.id,
                'claim_id', r.claim_id,
                'game_id', r.game_id,
                'user_id', r.user_id,
                'prize_type', r.prize_type,
                'claim_reference', r.claim_reference,
                'status', r.status,
                'claimed_at', r.claimed_at,
                'created_at', r.created_at,
                'game_name', COALESCE(g.name, arch.name),
                'invite_code', COALESCE(g.invite_code, arch.invite_code),
                'game_date', COALESCE(g.completed_at, arch.completed_at, g.started_at, g.created_at, arch.created_at),
                'winner_name', COALESCE(
                    NULLIF(TRIM(reg.display_name), ''),
                    NULLIF(TRIM(u.display_name), ''),
                    (
                        SELECT w->>'winner_name'
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                        LIMIT 1
                    ),
                    'Player'
                ),
                'winner_avatar', COALESCE(
                    NULLIF(TRIM(reg.avatar), ''),
                    NULLIF(TRIM(u.avatar), ''),
                    (
                        SELECT w->>'winner_avatar'
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                        LIMIT 1
                    ),
                    'avatar_lion'
                ),
                'winner_email', ap.email,
                'is_guest', COALESCE(u.is_anonymous, TRUE),
                'ticket_number', COALESCE(
                    t.ticket_number,
                    reg.registration_seq::INT,
                    (
                        SELECT (w->>'ticket_seq')::INT
                        FROM jsonb_array_elements(COALESCE(arch.winners_roster, '[]'::jsonb)) w
                        WHERE (w->>'claim_reference' = r.claim_reference OR w->>'prize_type' = r.prize_type)
                          AND (w->>'ticket_seq') ~ '^[0-9]+$'
                        LIMIT 1
                    ),
                    1
                ),
                'prize_value', r.prize_value,
                'brand_offer_id', r.brand_offer_id,
                'fulfilled_gift_title', r.fulfilled_gift_title,
                'fulfilled_brand_name', r.fulfilled_brand_name,
                'fulfilled_gift_code', r.fulfilled_gift_code,
                'fulfilled_product_url', r.fulfilled_product_url,
                'fulfilled_product_image_url', r.fulfilled_product_image_url,
                'fulfillment_note', r.fulfillment_note
            )
            ORDER BY
                CASE
                    WHEN r.prize_type = 'FULL_HOUSE' THEN 0
                    WHEN r.prize_type = 'SECOND_FULL_HOUSE' THEN 1
                    WHEN r.prize_type = 'TOP_LINE' THEN 2
                    WHEN r.prize_type = 'MIDDLE_LINE' THEN 3
                    WHEN r.prize_type = 'BOTTOM_LINE' THEN 4
                    WHEN r.prize_type IN ('EARLY_FIVE', 'EARLY_5') THEN 5
                    WHEN r.prize_type = 'FOUR_CORNERS' THEN 6
                    ELSE 7
                END ASC,
                r.created_at ASC
        ),
        '[]'::jsonb
    )
    INTO v_result
    FROM public."MPT_rewards" r
    LEFT JOIN public."MPT_games" g ON g.id = r.game_id
    LEFT JOIN public."MPT_game_archives" arch ON arch.game_id = r.game_id
    LEFT JOIN public."MPT_users" u ON u.id = r.user_id
    LEFT JOIN public."MPT_admin_profiles" ap ON ap.user_id = r.user_id
    LEFT JOIN public."MPT_game_registrations" reg
        ON reg.game_id = r.game_id AND reg.user_id = r.user_id
    LEFT JOIN public."MPT_player_tickets" t
        ON t.game_id = r.game_id AND t.user_id = r.user_id
    WHERE r.game_id = p_game_id;

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_get_game_rewards_for_host"(UUID) TO authenticated;

DROP FUNCTION IF EXISTS public."MPT_close_game_claim"(UUID, UUID, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public."MPT_close_game_claim"(
    p_game_id UUID,
    p_reward_id UUID DEFAULT NULL,
    p_claim_id UUID DEFAULT NULL,
    p_close_all BOOLEAN DEFAULT FALSE,
    p_gift_title TEXT DEFAULT NULL,
    p_brand_name TEXT DEFAULT NULL,
    p_gift_code TEXT DEFAULT NULL,
    p_fulfillment_note TEXT DEFAULT NULL,
    p_product_url TEXT DEFAULT NULL,
    p_prize_value NUMERIC DEFAULT NULL,
    p_brand_offer_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_is_host BOOLEAN := FALSE;
    v_updated_count INT := 0;
BEGIN
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM public."MPT_games" WHERE id = p_game_id AND admin_user_id = v_uid
        UNION ALL
        SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id AND admin_user_id = v_uid
    ) INTO v_is_host;

    IF NOT v_is_host THEN
        RAISE EXCEPTION 'NOT_AUTHORIZED: Only the organizer of this game can close prize claims';
    END IF;

    IF p_close_all THEN
        UPDATE public."MPT_rewards"
        SET status = 'CLAIMED',
            verified_by_admin_id = v_uid,
            claimed_at = COALESCE(claimed_at, NOW()),
            fulfilled_gift_title = COALESCE(p_gift_title, fulfilled_gift_title),
            fulfilled_brand_name = COALESCE(p_brand_name, fulfilled_brand_name),
            fulfilled_gift_code = COALESCE(p_gift_code, fulfilled_gift_code),
            fulfillment_note = COALESCE(p_fulfillment_note, fulfillment_note),
            fulfilled_product_url = COALESCE(p_product_url, fulfilled_product_url),
            prize_value = COALESCE(p_prize_value, prize_value),
            brand_offer_id = COALESCE(p_brand_offer_id, brand_offer_id)
        WHERE game_id = p_game_id
          AND status <> 'CLAIMED';
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    ELSE
        UPDATE public."MPT_rewards"
        SET status = 'CLAIMED',
            verified_by_admin_id = v_uid,
            claimed_at = COALESCE(claimed_at, NOW()),
            fulfilled_gift_title = COALESCE(p_gift_title, fulfilled_gift_title),
            fulfilled_brand_name = COALESCE(p_brand_name, fulfilled_brand_name),
            fulfilled_gift_code = COALESCE(p_gift_code, fulfilled_gift_code),
            fulfillment_note = COALESCE(p_fulfillment_note, fulfillment_note),
            fulfilled_product_url = COALESCE(p_product_url, fulfilled_product_url),
            prize_value = COALESCE(p_prize_value, prize_value),
            brand_offer_id = COALESCE(p_brand_offer_id, brand_offer_id)
        WHERE game_id = p_game_id
          AND (
              (p_reward_id IS NOT NULL AND id = p_reward_id)
              OR (p_claim_id IS NOT NULL AND claim_id = p_claim_id)
          );
        GET DIAGNOSTICS v_updated_count = ROW_COUNT;
    END IF;

    -- Refresh Hall of Fame archive if this game is already archived so any newly attached Brand Gift link shows on Hall of Fame!
    IF EXISTS (SELECT 1 FROM public."MPT_game_archives" WHERE game_id = p_game_id) THEN
        PERFORM public."MPT_archive_concluded_game"(p_game_id);
    END IF;

    RETURN jsonb_build_object(
        'status', 'SUCCESS',
        'updated_count', v_updated_count,
        'rewards', public."MPT_get_game_rewards_for_host"(p_game_id)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public."MPT_close_game_claim"(
    UUID, UUID, UUID, BOOLEAN, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, UUID
) TO authenticated;
