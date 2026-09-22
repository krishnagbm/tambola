-- =====================================================================
-- Migration: 20260916000001_mpt_payments_and_stripe.sql
-- Description: 
--   1. Create MPT_payments ledger table for recording Stripe checkout transactions
--   2. Atomic idempotent RPC MPT_process_stripe_payment for payment fulfillment
-- =====================================================================

-- 1. Create MPT_payments table
CREATE TABLE IF NOT EXISTS public."MPT_payments" (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public."MPT_users"(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    pack TEXT NOT NULL,
    credits INT NOT NULL,
    amount_usd NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    currency TEXT NOT NULL DEFAULT 'USD',
    provider TEXT NOT NULL DEFAULT 'stripe',
    provider_ref TEXT NOT NULL UNIQUE, -- Stripe session_id or payment_intent_id
    status TEXT NOT NULL DEFAULT 'completed',
    customer_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for lightning-fast lookups and idempotency validation
CREATE INDEX IF NOT EXISTS idx_mpt_payments_provider_ref ON public."MPT_payments"(provider_ref);
CREATE INDEX IF NOT EXISTS idx_mpt_payments_user_id ON public."MPT_payments"(user_id, created_at DESC);

-- Enable RLS
ALTER TABLE public."MPT_payments" ENABLE ROW LEVEL SECURITY;

-- Allow users to view their own payment receipts
DROP POLICY IF EXISTS "mpt_payments_select_own" ON public."MPT_payments";
CREATE POLICY "mpt_payments_select_own"
    ON public."MPT_payments"
    FOR SELECT
    USING (auth.uid() = user_id);

-- Allow service role full access
DROP POLICY IF EXISTS "mpt_payments_service_role" ON public."MPT_payments";
CREATE POLICY "mpt_payments_service_role"
    ON public."MPT_payments"
    FOR ALL
    USING (auth.role() = 'service_role');


-- 2. Atomic Idempotent RPC to process Stripe payment fulfillment
CREATE OR REPLACE FUNCTION public."MPT_process_stripe_payment"(
    p_user_id UUID,
    p_email TEXT,
    p_pack TEXT,
    p_credits INT,
    p_amount_usd NUMERIC,
    p_currency TEXT,
    p_session_id TEXT,
    p_customer_id TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_existing_payment public."MPT_payments";
    v_current_wallet public."MPT_admin_wallets";
    v_new_balance INT;
    v_payment_id UUID;
    v_tx_id UUID;
BEGIN
    -- 1. Idempotency check: Check if this session has already been fulfilled
    SELECT * INTO v_existing_payment
    FROM public."MPT_payments"
    WHERE provider_ref = p_session_id;

    IF FOUND THEN
        SELECT * INTO v_current_wallet
        FROM public."MPT_admin_wallets"
        WHERE user_id = p_user_id;

        RETURN jsonb_build_object(
            'status', 'already_processed',
            'payment_id', v_existing_payment.id,
            'credits_added', 0,
            'available_credits', COALESCE(v_current_wallet.available_credits, 0),
            'message', 'Payment was previously fulfilled.'
        );
    END IF;

    -- 2. Ensure user record exists
    INSERT INTO public."MPT_users" (id, display_name, avatar, is_anonymous)
    VALUES (p_user_id, COALESCE(SPLIT_PART(p_email, '@', 1), 'Host'), 'avatar_1', FALSE)
    ON CONFLICT (id) DO UPDATE
    SET is_anonymous = FALSE,
        updated_at = NOW();

    -- Ensure admin profile exists with email
    INSERT INTO public."MPT_admin_profiles" (user_id, email, updated_at)
    VALUES (p_user_id, p_email, NOW())
    ON CONFLICT (user_id) DO UPDATE
    SET email = EXCLUDED.email,
        updated_at = NOW();

    -- 3. Update or create wallet balance atomically with 1-year expiry extension
    INSERT INTO public."MPT_admin_wallets" (
        user_id,
        available_credits,
        credits_expire_at,
        updated_at
    )
    VALUES (
        p_user_id,
        p_credits,
        NOW() + INTERVAL '1 year',
        NOW()
    )
    ON CONFLICT (user_id) DO UPDATE
    SET available_credits = public."MPT_admin_wallets".available_credits + EXCLUDED.available_credits,
        credits_expire_at = NOW() + INTERVAL '1 year',
        updated_at = NOW()
    RETURNING available_credits INTO v_new_balance;

    -- 4. Record entry in MPT_payments
    INSERT INTO public."MPT_payments" (
        user_id,
        email,
        pack,
        credits,
        amount_usd,
        currency,
        provider,
        provider_ref,
        status,
        customer_id
    )
    VALUES (
        p_user_id,
        p_email,
        p_pack,
        p_credits,
        COALESCE(p_amount_usd, 0.00),
        UPPER(COALESCE(p_currency, 'USD')),
        'stripe',
        p_session_id,
        'completed',
        p_customer_id
    )
    RETURNING id INTO v_payment_id;

    -- 5. Record entry in MPT_credit_transactions ledger
    INSERT INTO public."MPT_credit_transactions" (
        user_id,
        type,
        amount,
        balance_after,
        reference_id,
        description,
        idempotency_key
    )
    VALUES (
        p_user_id,
        'PURCHASE',
        p_credits,
        v_new_balance,
        v_payment_id::TEXT,
        'Credit purchase: ' || p_pack || ' (+' || p_credits || ' credits)',
        p_session_id
    )
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING id INTO v_tx_id;

    -- 6. Return response payload
    RETURN jsonb_build_object(
        'status', 'success',
        'payment_id', v_payment_id,
        'transaction_id', v_tx_id,
        'credits_added', p_credits,
        'available_credits', v_new_balance,
        'message', 'Payment processed and credits added successfully.'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
