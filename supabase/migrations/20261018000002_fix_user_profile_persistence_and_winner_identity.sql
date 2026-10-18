-- =====================================================================
-- Migration: 20261018000002_fix_user_profile_persistence_and_winner_identity.sql
-- Description:
--   1. Fixes MPT_upsert_user so that registered user profiles preserve their 
--      chosen/saved display name across sessions and syncs is_anonymous from auth.users.
--   2. Updates MPT_get_game_rewards_for_host to join auth.users so organizers
--      can see player emails and identify registered prize winners directly.
-- =====================================================================

-- 1. Update MPT_upsert_user with profile persistence and auth status
CREATE OR REPLACE FUNCTION public."MPT_upsert_user"(
    p_display_name TEXT DEFAULT 'Player',
    p_avatar TEXT DEFAULT 'avatar_1'
)
RETURNS public."MPT_users" AS $$
DECLARE
    v_user public."MPT_users";
    v_uid UUID;
    v_wallet_exists BOOLEAN;
    v_is_anon BOOLEAN := TRUE;
    v_auth_email TEXT;
BEGIN
    v_uid := auth.uid();
    IF v_uid IS NULL THEN
        RAISE EXCEPTION 'AUTH_REQUIRED: User must be authenticated';
    END IF;

    -- Inspect auth.users to determine registered status & email
    SELECT 
        COALESCE(au.is_anonymous, FALSE),
        au.email
    INTO 
        v_is_anon,
        v_auth_email
    FROM auth.users au
    WHERE au.id = v_uid;

    IF v_auth_email IS NOT NULL AND v_auth_email <> '' THEN
        v_is_anon := FALSE;
    END IF;

    INSERT INTO public."MPT_users" (id, display_name, avatar, is_anonymous, updated_at)
    VALUES (
        v_uid, 
        COALESCE(NULLIF(TRIM(p_display_name), ''), 'Player'), 
        COALESCE(NULLIF(TRIM(p_avatar), ''), 'avatar_1'), 
        v_is_anon, 
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
    SET display_name = CASE
            -- Preserve existing custom name if caller passes generic fallback or empty
            WHEN public."MPT_users".display_name IS NOT NULL 
                 AND public."MPT_users".display_name NOT IN ('Player', 'My Name', '')
                 AND (EXCLUDED.display_name IS NULL OR EXCLUDED.display_name IN ('Player', 'My Name', ''))
            THEN public."MPT_users".display_name
            ELSE COALESCE(NULLIF(TRIM(EXCLUDED.display_name), ''), public."MPT_users".display_name)
        END,
        avatar = COALESCE(NULLIF(TRIM(EXCLUDED.avatar), ''), public."MPT_users".avatar),
        is_anonymous = v_is_anon,
        updated_at = NOW()
    RETURNING * INTO v_user;

    -- Check if admin wallet already exists
    SELECT EXISTS (SELECT 1 FROM public."MPT_admin_wallets" WHERE user_id = v_uid) INTO v_wallet_exists;

    IF NOT v_wallet_exists THEN
        -- Create wallet with 0 initial credits
        INSERT INTO public."MPT_admin_wallets" (user_id, available_credits, credits_expire_at)
        VALUES (v_uid, 0, NOW() + INTERVAL '1 year')
        ON CONFLICT (user_id) DO NOTHING;
    END IF;

    RETURN v_user;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public."MPT_upsert_user"(TEXT, TEXT) TO authenticated, anon;

-- 2. Update MPT_get_game_rewards_for_host to join auth.users for winner identification
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
                'winner_email', COALESCE(ap.email, au.email),
                'is_guest', CASE 
                    WHEN au.email IS NOT NULL AND au.email <> '' THEN FALSE
                    WHEN au.is_anonymous IS NOT NULL THEN au.is_anonymous
                    ELSE COALESCE(u.is_anonymous, TRUE)
                END,
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
                'prize_value', COALESCE(
                    r.prize_value,
                    (g.prize_gifts_config->r.prize_type->>'prize_value')::NUMERIC,
                    (g.prize_gifts_config->r.prize_type->>'retail_price')::NUMERIC,
                    (arch.prize_gifts_config->r.prize_type->>'prize_value')::NUMERIC,
                    (arch.prize_gifts_config->r.prize_type->>'retail_price')::NUMERIC
                ),
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
    LEFT JOIN auth.users au ON au.id = r.user_id
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
