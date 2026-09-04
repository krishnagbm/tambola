-- =====================================================================
-- Migration: 20260901000001_mpt_core_schema.sql
-- Description: Core schema for Multiplayer Tambola with MPT_ namespace isolation
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. MPT_users: Player & Admin profile metadata
CREATE TABLE IF NOT EXISTS public."MPT_users" (
    id UUID PRIMARY KEY,
    display_name TEXT NOT NULL DEFAULT 'Player',
    avatar TEXT NOT NULL DEFAULT 'avatar_1',
    is_anonymous BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. MPT_admin_profiles: Admin-specific financial receipt profile
CREATE TABLE IF NOT EXISTS public."MPT_admin_profiles" (
    user_id UUID PRIMARY KEY REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    phone TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. MPT_capacity_tiers: Configurable capacity and pricing tiers
CREATE TABLE IF NOT EXISTS public."MPT_capacity_tiers" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    min_players INT NOT NULL,
    max_players INT NOT NULL,
    credits_required INT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed standard capacity tiers if empty
INSERT INTO public."MPT_capacity_tiers" (name, min_players, max_players, credits_required, display_order)
SELECT * FROM (VALUES
    ('Small Party (1–25 Players)', 1, 25, 100, 1),
    ('Standard Event (26–50 Players)', 26, 50, 200, 2),
    ('Large Gala (51–100 Players)', 51, 100, 350, 3),
    ('Mega Event (101–250 Players)', 101, 250, 600, 4)
) AS v(name, min_players, max_players, credits_required, display_order)
WHERE NOT EXISTS (SELECT 1 FROM public."MPT_capacity_tiers");

-- 4. MPT_admin_wallets: Current credit balance summary
CREATE TABLE IF NOT EXISTS public."MPT_admin_wallets" (
    user_id UUID PRIMARY KEY REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    available_credits INT NOT NULL DEFAULT 0 CHECK (available_credits >= 0),
    last_paid_game_at TIMESTAMPTZ,
    credits_expire_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. MPT_credit_transactions: Immutable credit ledger
CREATE TABLE IF NOT EXISTS public."MPT_credit_transactions" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('PURCHASE', 'MOCK_PURCHASE', 'GAME_CHARGE', 'ADJUSTMENT', 'EXPIRY')),
    amount INT NOT NULL,
    balance_after INT NOT NULL,
    reference_id TEXT,
    description TEXT,
    idempotency_key TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. MPT_games: Game rooms and lifecycle states
CREATE TABLE IF NOT EXISTS public."MPT_games" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    invite_code TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('DRAFT', 'OPEN', 'READY_TO_START', 'STARTING', 'IN_PROGRESS', 'COMPLETED', 'CLOSED', 'CANCELLED')),
    planned_capacity_tier_id UUID REFERENCES public."MPT_capacity_tiers"(id),
    initial_funded_capacity INT NOT NULL DEFAULT 25,
    funded_capacity INT NOT NULL DEFAULT 25,
    final_capacity INT,
    scheduled_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    prizes_config JSONB NOT NULL DEFAULT '["EARLY_FIVE", "TOP_LINE", "MIDDLE_LINE", "BOTTOM_LINE", "FOUR_CORNERS", "FULL_HOUSE"]'::jsonb,
    state_version INT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. MPT_game_registrations: Player seat queue with immutable sequence
CREATE TABLE IF NOT EXISTS public."MPT_game_registrations" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    avatar TEXT NOT NULL,
    registration_seq BIGINT NOT NULL,
    seat_status TEXT NOT NULL DEFAULT 'CONFIRMED' CHECK (seat_status IN ('CONFIRMED', 'WAITING', 'ELIGIBLE', 'NOT_ELIGIBLE', 'CANCELLED')),
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT mpt_reg_game_user_unique UNIQUE (game_id, user_id),
    CONSTRAINT mpt_reg_game_seq_unique UNIQUE (game_id, registration_seq)
);

-- 8. MPT_player_tickets: Unique Tambola tickets issued per player
CREATE TABLE IF NOT EXISTS public."MPT_player_tickets" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    ticket_matrix JSONB NOT NULL,
    ticket_number INT NOT NULL DEFAULT 1,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT mpt_ticket_unique UNIQUE (game_id, user_id, ticket_number)
);

-- 9. MPT_game_charges: Immutable record of credit charges for finalized games
CREATE TABLE IF NOT EXISTS public."MPT_game_charges" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    tier_id UUID REFERENCES public."MPT_capacity_tiers"(id),
    player_count INT NOT NULL,
    credits_charged INT NOT NULL,
    charged_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. MPT_called_numbers: Authoritative sequential number caller history
CREATE TABLE IF NOT EXISTS public."MPT_called_numbers" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    number INT NOT NULL CHECK (number >= 1 AND number <= 90),
    call_seq INT NOT NULL,
    called_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT mpt_called_num_unique UNIQUE (game_id, number),
    CONSTRAINT mpt_called_seq_unique UNIQUE (game_id, call_seq)
);

-- 11. MPT_claims: Prize claims submitted by players
CREATE TABLE IF NOT EXISTS public."MPT_claims" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    prize_type TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'SUBMITTED' CHECK (status IN ('SUBMITTED', 'APPROVED', 'REJECTED', 'BOGEY')),
    marked_numbers JSONB,
    rejection_reason TEXT,
    idempotency_key TEXT,
    submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- 12. MPT_rewards: Server-verifiable prize reward vouchers
CREATE TABLE IF NOT EXISTS public."MPT_rewards" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id UUID NOT NULL REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    prize_type TEXT NOT NULL,
    claim_id UUID REFERENCES public."MPT_claims"(id),
    claim_reference TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL DEFAULT 'AVAILABLE_TO_CLAIM' CHECK (status IN ('AVAILABLE_TO_CLAIM', 'CLAIMED', 'VOID')),
    verified_by_admin_id UUID REFERENCES public."MPT_users"(id),
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 13. MPT_notifications: In-app database-backed user notification feed
CREATE TABLE IF NOT EXISTS public."MPT_notifications" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    game_id UUID REFERENCES public."MPT_games"(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('SEAT_CONFIRMED', 'CAPACITY_WARNING', 'GAME_STARTED', 'CLAIM_RESULT', 'REWARD_ISSUED')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    payload JSONB,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_mpt_game_reg_game_seq ON public."MPT_game_registrations"(game_id, registration_seq);
CREATE INDEX IF NOT EXISTS idx_mpt_game_reg_game_status ON public."MPT_game_registrations"(game_id, seat_status);
CREATE INDEX IF NOT EXISTS idx_mpt_credit_tx_user_date ON public."MPT_credit_transactions"(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_mpt_called_nums_game_seq ON public."MPT_called_numbers"(game_id, call_seq);
CREATE INDEX IF NOT EXISTS idx_mpt_claims_game_prize ON public."MPT_claims"(game_id, prize_type, status);
CREATE INDEX IF NOT EXISTS idx_mpt_rewards_user ON public."MPT_rewards"(user_id, status);
CREATE INDEX IF NOT EXISTS idx_mpt_notifications_user ON public."MPT_notifications"(user_id, is_read, created_at DESC);

-- Enable RLS
ALTER TABLE public."MPT_users" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_admin_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_capacity_tiers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_admin_wallets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_credit_transactions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_games" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_game_registrations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_player_tickets" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_game_charges" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_called_numbers" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_claims" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_rewards" ENABLE ROW LEVEL SECURITY;
ALTER TABLE public."MPT_notifications" ENABLE ROW LEVEL SECURITY;

-- Policies
DROP POLICY IF EXISTS "MPT_users_read_all" ON public."MPT_users";
CREATE POLICY "MPT_users_read_all" ON public."MPT_users" FOR SELECT USING (true);

DROP POLICY IF EXISTS "MPT_users_insert_self" ON public."MPT_users";
CREATE POLICY "MPT_users_insert_self" ON public."MPT_users" FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "MPT_users_update_self" ON public."MPT_users";
CREATE POLICY "MPT_users_update_self" ON public."MPT_users" FOR UPDATE USING (auth.uid() = id);

DROP POLICY IF EXISTS "MPT_admin_profiles_self" ON public."MPT_admin_profiles";
CREATE POLICY "MPT_admin_profiles_self" ON public."MPT_admin_profiles" FOR ALL USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "MPT_capacity_tiers_read" ON public."MPT_capacity_tiers";
CREATE POLICY "MPT_capacity_tiers_read" ON public."MPT_capacity_tiers" FOR SELECT USING (true);

DROP POLICY IF EXISTS "MPT_admin_wallets_read_self" ON public."MPT_admin_wallets";
CREATE POLICY "MPT_admin_wallets_read_self" ON public."MPT_admin_wallets" FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "MPT_credit_tx_read_self" ON public."MPT_credit_transactions";
CREATE POLICY "MPT_credit_tx_read_self" ON public."MPT_credit_transactions" FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "MPT_games_read_all" ON public."MPT_games";
CREATE POLICY "MPT_games_read_all" ON public."MPT_games" FOR SELECT USING (true);

DROP POLICY IF EXISTS "MPT_games_insert_admin" ON public."MPT_games";
CREATE POLICY "MPT_games_insert_admin" ON public."MPT_games" FOR INSERT WITH CHECK (auth.uid() = admin_user_id);

DROP POLICY IF EXISTS "MPT_games_update_admin" ON public."MPT_games";
CREATE POLICY "MPT_games_update_admin" ON public."MPT_games" FOR UPDATE USING (auth.uid() = admin_user_id);

DROP POLICY IF EXISTS "MPT_game_reg_read" ON public."MPT_game_registrations";
CREATE POLICY "MPT_game_reg_read" ON public."MPT_game_registrations" FOR SELECT USING (true);

DROP POLICY IF EXISTS "MPT_game_reg_insert_self" ON public."MPT_game_registrations";
CREATE POLICY "MPT_game_reg_insert_self" ON public."MPT_game_registrations" FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "MPT_player_tickets_read" ON public."MPT_player_tickets";
CREATE POLICY "MPT_player_tickets_read" ON public."MPT_player_tickets" FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public."MPT_games" g WHERE g.id = game_id AND g.admin_user_id = auth.uid())
);

DROP POLICY IF EXISTS "MPT_called_numbers_read" ON public."MPT_called_numbers";
CREATE POLICY "MPT_called_numbers_read" ON public."MPT_called_numbers" FOR SELECT USING (true);

DROP POLICY IF EXISTS "MPT_claims_read" ON public."MPT_claims";
CREATE POLICY "MPT_claims_read" ON public."MPT_claims" FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public."MPT_games" g WHERE g.id = game_id AND g.admin_user_id = auth.uid())
);

DROP POLICY IF EXISTS "MPT_rewards_read" ON public."MPT_rewards";
CREATE POLICY "MPT_rewards_read" ON public."MPT_rewards" FOR SELECT USING (
    auth.uid() = user_id OR
    EXISTS (SELECT 1 FROM public."MPT_games" g WHERE g.id = game_id AND g.admin_user_id = auth.uid())
);

DROP POLICY IF EXISTS "MPT_notifications_self" ON public."MPT_notifications";
CREATE POLICY "MPT_notifications_self" ON public."MPT_notifications" FOR ALL USING (auth.uid() = user_id);
