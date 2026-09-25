-- 1. Add Voucher Batch & $2-Per-Consumed-Voucher Commission columns to MPT_brand_offers
ALTER TABLE public."MPT_brand_offers"
    ADD COLUMN IF NOT EXISTS vouchers_total_count INTEGER NOT NULL DEFAULT 10,
    ADD COLUMN IF NOT EXISTS vouchers_consumed_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS platform_fee_per_voucher NUMERIC(10,2) NOT NULL DEFAULT 2.00;

-- 2. Seed DabHousie 100% Sponsored Free Credit Vouchers (Free for Hosts!)
INSERT INTO public."MPT_brand_offers" (
    brand_name,
    brand_domain,
    contact_name,
    contact_email,
    product_title,
    product_description,
    category,
    product_url,
    retail_price,
    organizer_price,
    discount_percent,
    promo_code,
    emoji,
    badge_text,
    status,
    vouchers_total_count,
    platform_fee_per_voucher
)
SELECT
    'DabHousie',
    'dabhousie.com',
    'DabHousie Rewards Team',
    'rewards@dabhousie.com',
    '$5 Free Game Credit Voucher (Early-5 / Corner Prize)',
    '100% Free Sponsored DabHousie Credit Voucher for your players! Winner can redeem $5 toward hosting their own game.',
    'Shopping Vouchers',
    'https://www.dabhousie.com/pricing.html',
    5.00,
    0.00,
    100,
    'DABFREE5',
    '🎟️',
    '100% FREE FOR HOST',
    'ACTIVE',
    100,
    0.00
WHERE NOT EXISTS (
    SELECT 1 FROM public."MPT_brand_offers" WHERE promo_code = 'DABFREE5'
);

INSERT INTO public."MPT_brand_offers" (
    brand_name,
    brand_domain,
    contact_name,
    contact_email,
    product_title,
    product_description,
    category,
    product_url,
    retail_price,
    organizer_price,
    discount_percent,
    promo_code,
    emoji,
    badge_text,
    status,
    vouchers_total_count,
    platform_fee_per_voucher
)
SELECT
    'DabHousie',
    'dabhousie.com',
    'DabHousie Rewards Team',
    'rewards@dabhousie.com',
    '$10 Free Party Pack Credit Voucher (Row Line Prize)',
    '100% Free Sponsored DabHousie Voucher! Winner receives $10 in hosting credits for their next family or office party.',
    'Shopping Vouchers',
    'https://www.dabhousie.com/pricing.html',
    10.00,
    0.00,
    100,
    'DABFREE10',
    '🎁',
    '100% FREE FOR HOST',
    'ACTIVE',
    100,
    0.00
WHERE NOT EXISTS (
    SELECT 1 FROM public."MPT_brand_offers" WHERE promo_code = 'DABFREE10'
);

INSERT INTO public."MPT_brand_offers" (
    brand_name,
    brand_domain,
    contact_name,
    contact_email,
    product_title,
    product_description,
    category,
    product_url,
    retail_price,
    organizer_price,
    discount_percent,
    promo_code,
    emoji,
    badge_text,
    status,
    vouchers_total_count,
    platform_fee_per_voucher
)
SELECT
    'DabHousie',
    'dabhousie.com',
    'DabHousie Rewards Team',
    'rewards@dabhousie.com',
    '$25 Free Club Gala Credit Voucher (Full House Grand Prize)',
    '100% Free Sponsored Grand Prize Voucher! Winner gets $25 in DabHousie Event Credits at zero cost to the host.',
    'Shopping Vouchers',
    'https://www.dabhousie.com/pricing.html',
    25.00,
    0.00,
    100,
    'DABFREE25',
    '🏆',
    '100% FREE FOR HOST',
    'ACTIVE',
    100,
    0.00
WHERE NOT EXISTS (
    SELECT 1 FROM public."MPT_brand_offers" WHERE promo_code = 'DABFREE25'
);

-- 3. Update MPT_get_active_brand_offers to prioritize 100% Free Sponsored Vouchers first
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
        ),
        '[]'::jsonb
    );
END;
$$;

-- 4. Update MPT_register_brand_offer to accept vouchers_total_count and platform_fee_per_voucher
CREATE OR REPLACE FUNCTION public."MPT_register_brand_offer"(
    p_brand_name TEXT,
    p_brand_domain TEXT,
    p_contact_name TEXT,
    p_contact_email TEXT,
    p_product_title TEXT,
    p_product_description TEXT,
    p_category TEXT,
    p_product_url TEXT,
    p_retail_price NUMERIC,
    p_organizer_price NUMERIC,
    p_promo_code TEXT DEFAULT NULL,
    p_emoji TEXT DEFAULT '🎁',
    p_product_image_url TEXT DEFAULT NULL,
    p_vouchers_total_count INTEGER DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_clean_domain TEXT;
    v_discount INT := 0;
    v_offer_id UUID;
    v_vouchers INT := COALESCE(NULLIF(p_vouchers_total_count, 0), 10);
BEGIN
    IF COALESCE(TRIM(p_brand_name), '') = '' OR COALESCE(TRIM(p_product_title), '') = '' THEN
        RAISE EXCEPTION 'Brand name and product title are required';
    END IF;

    v_clean_domain := LOWER(TRIM(COALESCE(p_brand_domain, '')));
    v_clean_domain := REGEXP_REPLACE(v_clean_domain, '^https?://', '');
    v_clean_domain := REGEXP_REPLACE(v_clean_domain, '^www\.', '');
    v_clean_domain := SPLIT_PART(v_clean_domain, '/', 1);

    IF COALESCE(p_retail_price, 0) > 0 AND COALESCE(p_organizer_price, 0) < COALESCE(p_retail_price, 0) THEN
        v_discount := ROUND(((p_retail_price - p_organizer_price) / p_retail_price) * 100)::INT;
    END IF;

    INSERT INTO public."MPT_brand_offers" (
        brand_name,
        brand_domain,
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
        vouchers_total_count,
        vouchers_consumed_count,
        platform_fee_per_voucher
    ) VALUES (
        TRIM(p_brand_name),
        v_clean_domain,
        TRIM(p_contact_name),
        TRIM(p_contact_email),
        TRIM(p_product_title),
        TRIM(p_product_description),
        COALESCE(NULLIF(TRIM(p_category), ''), 'Shopping Vouchers'),
        NULLIF(TRIM(p_product_image_url), ''),
        TRIM(p_product_url),
        GREATEST(COALESCE(p_retail_price, 0), 0),
        GREATEST(COALESCE(p_organizer_price, 0), 0),
        GREATEST(v_discount, 0),
        NULLIF(TRIM(p_promo_code), ''),
        COALESCE(NULLIF(TRIM(p_emoji), ''), '🎁'),
        CASE
            WHEN COALESCE(p_organizer_price, 0) = 0 THEN '100% FREE FOR HOST'
            WHEN v_discount >= 25 THEN v_discount || '% OFF FOR HOSTS'
            ELSE 'PARTNER DEAL'
        END,
        'ACTIVE',
        GREATEST(v_vouchers, 1),
        0,
        2.00
    )
    RETURNING id INTO v_offer_id;

    RETURN jsonb_build_object(
        'success', true,
        'offer_id', v_offer_id,
        'message', 'Your Brand Gift Offer (' || GREATEST(v_vouchers, 1) || ' vouchers) is now live in the DabHousie Host Catalog!'
    );
END;
$$;

-- 5. Update MPT_archive_concluded_game to include brand_domain in winners_roster
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
                'brand_domain', COALESCE(
                    v_game.prize_gifts_config -> c.prize_type ->> 'brand_domain',
                    bo.brand_domain
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
    LEFT JOIN public."MPT_brand_offers" bo ON bo.id = rw.brand_offer_id
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

-- 6. Backfill 4E196B prize_gifts_config & archive with brand_domain so Brand Logos render in 4E196B
DO $$
DECLARE
    v_game_id UUID;
BEGIN
    SELECT id INTO v_game_id FROM public."MPT_games" WHERE invite_code = '4E196B' LIMIT 1;
    IF v_game_id IS NOT NULL THEN
        UPDATE public."MPT_games"
        SET prize_gifts_config = jsonb_set(
            jsonb_set(
                jsonb_set(
                    jsonb_set(
                        jsonb_set(
                            jsonb_set(
                                COALESCE(prize_gifts_config, '{}'::jsonb),
                                '{FULL_HOUSE,brand_domain}', '"amazon.com"'::jsonb, true
                            ),
                            '{TOP_LINE,brand_domain}', '"ubereats.com"'::jsonb, true
                        ),
                        '{MIDDLE_LINE,brand_domain}', '"ubereats.com"'::jsonb, true
                    ),
                    '{BOTTOM_LINE,brand_domain}', '"ubereats.com"'::jsonb, true
                ),
                '{EARLY_FIVE,brand_domain}', '"starbucks.com"'::jsonb, true
            ),
            '{FOUR_CORNERS,brand_domain}', '"ferrerorocher.com"'::jsonb, true
        )
        WHERE id = v_game_id;

        PERFORM public."MPT_archive_concluded_game"(v_game_id);
    END IF;
END;
$$;
