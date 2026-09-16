# 💳 DabHousie — Stripe Payment Processing & Deployment Guide

This guide details how to configure, test, and deploy the Stripe Hosted Checkout and Webhook-driven fulfillment system for **DabHousie** using the same battle-tested architectural pattern as **PocketBull**.

---

## 🏗️ Architecture Summary

```
[ User in Flutter App / Web Store ]
               │
               ▼
   [ GET /pricing.html or in-app dialog ]
               │
               ▼  (POST /checkout)
  [ AWS Lambda: create_checkout.py ]
               │
               ▼  (stripe.checkout.Session.create)
   [ Stripe Hosted Checkout Page ]
               │
               ▼  (Card Payment Completed)
  [ Stripe Webhook Event: checkout.session.completed ]
               │
               ▼  (POST /webhook with Stripe-Signature)
  [ AWS Lambda: stripe_webhook.py ]
               │
               ├─► 1. Verify webhook signature (stripe.Webhook.construct_event)
               ├─► 2. Check Idempotency (MPT_payments lookup)
               ├─► 3. Atomic RPC (MPT_process_stripe_payment in Supabase)
               │      ├── Increments MPT_admin_wallets.available_credits
               │      ├── Inserts entry in MPT_credit_transactions
               │      └── Inserts record in MPT_payments
               └─► 4. Send Confirmation Email (AWS SES via email_ses.py)
```

---

## ⚙️ 1. Stripe Dashboard Setup

### A. Create Products & Price IDs
In your **DabHousie Stripe Account** (under **Product Catalog**), create the following one-time products:

| Product Name | Suggested Price | Suggested Credits | Environment Variable Key |
| :--- | :--- | :--- | :--- |
| **Starter Pack** | $5.00 | 50 Credits | `STRIPE_PRICE_STARTER` |
| **Family & Party Pack** | $12.00 | 150 Credits | `STRIPE_PRICE_FAMILY` |
| **Pro Host Pack** | $20.00 | 300 Credits | `STRIPE_PRICE_PRO` |
| **Mega Gala Pack** | $45.00 | 750 Credits | `STRIPE_PRICE_GALA` |

Copy the generated `price_1T...` IDs into your SAM `template.yaml` / backend environment variables.

---

### B. Obtain API Keys
1. Go to **Developers → API Keys**.
2. Copy your **Secret Key** (`sk_test_...` or `sk_live_...`).
3. Set it in `STRIPE_SECRET_KEY`.

---

### C. Configure Webhooks
1. Go to **Developers → Webhooks → Add Endpoint**.
2. **Endpoint URL**: `https://<your-api-id>.execute-api.us-east-1.amazonaws.com/Prod/webhook`
3. **Events to listen for**:
   - `checkout.session.completed`
4. Copy the **Signing Secret** (`whsec_...`) and set it in `STRIPE_WEBHOOK_SECRET`.

---

## 🚀 2. Backend Serverless Deployment (AWS SAM)

### Prerequisites
- [AWS CLI](https://aws.amazon.com/cli/) configured (`aws configure`)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) installed (`sam --version`)
- Python 3.11 installed

### Build & Deploy Commands
From the project root (`c:\dev\Tambola`):

```bash
# 1. Build the serverless package
sam build

# 2. Deploy with guided interactive setup (first time)
sam deploy --guided

# 3. Subsequent fast deployments
sam deploy
```

During `sam deploy --guided`:
- **Stack Name**: `dabhousie-payments-backend`
- **AWS Region**: `us-east-1` (or your preferred region)
- **Confirm changes before deploy**: `Y`
- **Allow SAM CLI IAM role creation**: `Y`
- **Disable rollback**: `N`

---

## 🗄️ 3. Apply Supabase Migration

Apply the payment ledger and atomic fulfillment migration to your Supabase project:
- File: `supabase/migrations/20260916000001_mpt_payments_and_stripe.sql`
- Can be run in **Supabase Dashboard → SQL Editor** or via Supabase CLI (`supabase db push`).

This establishes:
1. `MPT_payments` table for recording Stripe transactions.
2. `MPT_process_stripe_payment` stored procedure with built-in idempotency protection.

---

## 🧪 4. Testing the Checkout Flow

### Local or Cloud Webhook Testing with Stripe CLI
You can test the entire flow locally using the [Stripe CLI](https://docs.stripe.com/stripe-cli):

```bash
# 1. Login with Stripe CLI
stripe login

# 2. Forward webhook events to your local handler or API Gateway
stripe listen --forward-to https://<api-id>.execute-api.us-east-1.amazonaws.com/Prod/webhook

# 3. Trigger a test checkout session completed event
stripe trigger checkout.session.completed
```

### End-to-End Browser Flow
1. Open the DabHousie App or navigate to `https://www.dabhousie.com/pricing.html?user_id=<YOUR_UID>&email=<YOUR_EMAIL>`.
2. Select any credit bundle (e.g. Family Pack).
3. Complete payment on the Stripe Hosted Checkout test page using Stripe's test card numbers (e.g. `4242 4242 4242 4242`).
4. Stripe redirects you to `https://www.dabhousie.com/success.html`.
5. Check your DabHousie wallet (`/#/wallet`) — your credits are updated instantly!
