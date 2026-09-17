# backend/functions/stripe_webhook.py
# DabHousie — Stripe Webhook Handler
# POST /webhook or POST /credits/webhook
# Receives and verifies Stripe webhook events, granting credits and sending receipts

import base64
import json
import os
import sys
from typing import Any

sys.path.insert(0, os.path.dirname(__file__))

import stripe
from db import check_payment_exists, fulfill_stripe_payment, get_user_wallet_balance
from email_ses import send_purchase_email

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
WEBHOOK_SECRET = os.getenv("STRIPE_WEBHOOK_SECRET")
BASE_URL = os.getenv("BASE_URL", "https://www.dabhousie.com")


def handler(event, context):
    """
    AWS Lambda handler for Stripe webhook fulfillment.
    """
    try:
        body = event.get("body", "")
        if event.get("isBase64Encoded"):
            try:
                body = base64.b64decode(body).decode("utf-8")
            except Exception as e:
                print(f"  [ webhook ] Error decoding base64 body: {e}")
                return _r(400, {"error": "Invalid base64 payload"})

        headers = event.get("headers") or {}
        # Extract signature case-insensitively
        sig = headers.get("stripe-signature") or headers.get("Stripe-Signature") or ""

        print(f"  [ webhook ] Incoming event received. Body length: {len(body)} | Sig present: {bool(sig)}")

        if not WEBHOOK_SECRET:
            print("  [ webhook ERROR ] STRIPE_WEBHOOK_SECRET is not configured.")
            return _r(500, {"error": "Webhook secret not configured on server"})

        # Verify event signature
        try:
            stripe_event = stripe.Webhook.construct_event(
                payload=body,
                sig_header=sig,
                secret=WEBHOOK_SECRET,
            )
        except stripe.error.SignatureVerificationError as e:
            print(f"  [ webhook ] Invalid signature verification failed: {e}")
            return _r(400, {"error": "Invalid webhook signature"})
        except Exception as e:
            print(f"  [ webhook ] JSON / Payload parse error: {e}")
            import traceback

            traceback.print_exc()
            return _r(400, {"error": f"Parse error: {str(e)}"})

        # Convert Stripe Event to standard Python dict for safe dictionary access
        if hasattr(stripe_event, "to_dict"):
            event_dict = stripe_event.to_dict()
        elif isinstance(stripe_event, dict):
            event_dict = stripe_event
        else:
            event_dict = dict(stripe_event)

        event_type = event_dict.get("type", "")
        print(f"  [ webhook ] Verified Stripe event type: '{event_type}'")

        if event_type == "checkout.session.completed":
            session = event_dict.get("data", {}).get("object") or {}
            _handle_checkout_session_completed(session)
        else:
            print(f"  [ webhook ] Unhandled event type: '{event_type}' (ignored cleanly).")

        return _r(200, {"status": "ok"})
    except Exception as top_err:
        print(f"  [ webhook FATAL ERROR ] Unhandled exception in handler: {top_err}")
        import traceback
        traceback.print_exc()
        return _r(500, {"error": f"Webhook handler error: {str(top_err)}"})


def _handle_checkout_session_completed(session: Any):
    """
    Processes completed checkout session:
    1. Extracts metadata & payment amounts
    2. Performs idempotency check
    3. Credits user wallet & records transaction in Supabase
    4. Sends confirmation receipt email via SES
    """
    try:
        if hasattr(session, "to_dict"):
            session = session.to_dict()
        elif not isinstance(session, dict):
            session = dict(session)

        sess_id = session.get("id", "")
        metadata = session.get("metadata") or {}

        user_id = metadata.get("user_id")
        customer_details = session.get("customer_details") or {}
        email = (
            metadata.get("email")
            or session.get("customer_email")
            or customer_details.get("email")
        )
        plan = metadata.get("plan") or metadata.get("pack") or "family"
        credits_str = metadata.get("credits")

        # Amount & currency calculation
        amount_total = session.get("amount_total", 0)  # in cents
        amount_usd = float(amount_total) / 100.0 if amount_total else 0.0
        currency = session.get("currency", "usd").upper()
        customer_id = session.get("customer")

        print(f"  [ webhook ] Processing session: {sess_id} | User: {user_id} | Email: {email} | Plan: {plan} | Amount: {amount_usd} {currency}")

        # Fallback credit parsing if metadata was omitted
        if not credits_str or not str(credits_str).isdigit():
            credits_fallback_map = {
                "small": 15,
                "starter": 15,
                "standard": 40,
                "family": 40,
                "family_plan": 40,
                "party": 40,
                "large": 100,
                "pro": 100,
                "gala": 300,
                "mega": 300,
            }
            credits = credits_fallback_map.get(plan, 15)
        else:
            credits = int(credits_str)

        if not user_id or not email:
            print(f"  [ webhook WARNING ] Missing user_id ({user_id}) or email ({email}). Skipping fulfillment.")
            return

        # Idempotency Check
        if check_payment_exists(sess_id):
            print(f"  [ webhook ] Idempotency Check: Session {sess_id} already processed. Skipping duplicate execution.")
            return

        # Fulfill payment atomically in database
        fulfillment_res = fulfill_stripe_payment(
            user_id=user_id,
            email=email,
            pack=plan,
            credits=credits,
            amount_usd=amount_usd,
            currency=currency,
            session_id=sess_id,
            customer_id=customer_id,
        )

        new_balance = fulfillment_res.get("available_credits") if isinstance(fulfillment_res, dict) else None
        if new_balance is None or new_balance == 0:
            new_balance = get_user_wallet_balance(user_id)

        print(f"  [ webhook ] Fulfillment completed: +{credits} credits granted to {user_id} ({email}). New Balance: {new_balance}")

        # Send receipt email via SES
        try:
            send_purchase_email(
                to_email=email,
                pack=plan,
                credits=credits,
                new_balance=new_balance,
                amount_paid=amount_usd,
                currency=currency,
                session_id=sess_id,
            )
        except Exception as e:
            print(f"  [ webhook ] Non-fatal error sending receipt email: {e}")
    except Exception as e:
        print(f"  [ webhook ERROR ] Exception during checkout fulfillment: {e}")
        import traceback
        traceback.print_exc()
        raise e


def _r(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(body),
    }
