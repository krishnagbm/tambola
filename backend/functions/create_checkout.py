# backend/functions/create_checkout.py
# DabHousie — Create Stripe Checkout Session
# POST /checkout or POST /credits/checkout
# Accepts payload: { "user_id": "<uuid>", "email": "<email>", "plan": "<plan_key>" }

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import stripe

stripe.api_key = os.getenv("STRIPE_SECRET_KEY")
BASE_URL = os.getenv("BASE_URL", "https://www.dabhousie.com")

# Price mapping for the 4 core DabHousie packs ($2/15c, $5/40c, $10/100c, $20/300c)
def get_price_map():
    return {
        "small": {
            "price_id": os.getenv("STRIPE_PRICE_SMALL") or os.getenv("STRIPE_PRICE_STARTER"),
            "credits": int(os.getenv("STRIPE_CREDITS_SMALL", "15")),
            "label": "Small Pack (15 Credits)",
        },
        "starter": {
            "price_id": os.getenv("STRIPE_PRICE_SMALL") or os.getenv("STRIPE_PRICE_STARTER"),
            "credits": int(os.getenv("STRIPE_CREDITS_STARTER", "15")),
            "label": "Small Pack (15 Credits)",
        },
        "standard": {
            "price_id": os.getenv("STRIPE_PRICE_STANDARD") or os.getenv("STRIPE_PRICE_FAMILY"),
            "credits": int(os.getenv("STRIPE_CREDITS_STANDARD", "40")),
            "label": "Standard Pack (40 Credits)",
        },
        "family": {
            "price_id": os.getenv("STRIPE_PRICE_STANDARD") or os.getenv("STRIPE_PRICE_FAMILY"),
            "credits": int(os.getenv("STRIPE_CREDITS_FAMILY", "40")),
            "label": "Standard Pack (40 Credits)",
        },
        "family_plan": {
            "price_id": os.getenv("STRIPE_PRICE_STANDARD") or os.getenv("STRIPE_PRICE_FAMILY"),
            "credits": int(os.getenv("STRIPE_CREDITS_FAMILY", "40")),
            "label": "Standard Pack (40 Credits)",
        },
        "large": {
            "price_id": os.getenv("STRIPE_PRICE_LARGE") or os.getenv("STRIPE_PRICE_PRO"),
            "credits": int(os.getenv("STRIPE_CREDITS_LARGE", "100")),
            "label": "Large Gala Pack (100 Credits)",
        },
        "pro": {
            "price_id": os.getenv("STRIPE_PRICE_LARGE") or os.getenv("STRIPE_PRICE_PRO"),
            "credits": int(os.getenv("STRIPE_CREDITS_PRO", "100")),
            "label": "Large Gala Pack (100 Credits)",
        },
        "mega": {
            "price_id": os.getenv("STRIPE_PRICE_MEGA"),
            "credits": int(os.getenv("STRIPE_CREDITS_MEGA", "300")),
            "label": "Mega Event Pack (300 Credits)",
        },
        "gala": {
            "price_id": os.getenv("STRIPE_PRICE_MEGA"),
            "credits": int(os.getenv("STRIPE_CREDITS_MEGA", "300")),
            "label": "Mega Event Pack (300 Credits)",
        },
    }


def handler(event, context):
    """
    AWS Lambda handler for Stripe Checkout creation.
    """
    # CORS preflight OPTIONS check
    http_method = event.get("httpMethod") or event.get("requestContext", {}).get("http", {}).get("method", "")
    if http_method.upper() == "OPTIONS":
        return _r(200, {"status": "ok"})

    try:
        raw_body = event.get("body", "{}")
        if isinstance(raw_body, str):
            body = json.loads(raw_body) if raw_body else {}
        else:
            body = raw_body or {}

        user_id = body.get("user_id")
        email = body.get("email")
        plan = (body.get("plan") or body.get("pack") or "family").lower().strip()

        if not user_id or not email:
            return _r(400, {"error": "user_id and email are required fields"})

        price_map = get_price_map()
        if plan not in price_map:
            valid_plans = ", ".join(price_map.keys())
            return _r(400, {"error": f"Invalid plan: '{plan}'. Valid plans: {valid_plans}"})

        plan_info = price_map[plan]
        price_id = plan_info["price_id"]

        if not price_id:
            return _r(
                500,
                {
                    "error": f"Stripe Price ID for '{plan}' is not configured in backend environment variables (STRIPE_PRICE_{plan.upper()})."
                },
            )

        if not stripe.api_key:
            return _r(500, {"error": "STRIPE_SECRET_KEY is not configured on the server."})

        # Build Stripe Checkout Session
        session = stripe.checkout.Session.create(
            payment_method_types=["card"],
            line_items=[
                {
                    "price": price_id,
                    "quantity": 1,
                }
            ],
            mode="payment",
            customer_email=email,
            success_url=(
                f"{BASE_URL}/success.html"
                f"?session_id={{CHECKOUT_SESSION_ID}}"
                f"&plan={plan}"
                f"&credits={plan_info['credits']}"
            ),
            cancel_url=f"{BASE_URL}/pricing.html?cancelled=true",
            metadata={
                "user_id": user_id,
                "email": email,
                "plan": plan,
                "credits": str(plan_info["credits"]),
                "product_name": "DabHousie",
            },
        )

        print(f"  [ Stripe Checkout ] Session created: {session.id} | User: {user_id} | Plan: {plan} ({plan_info['credits']} credits)")

        return _r(
            200,
            {
                "checkout_url": session.url,
                "session_id": session.id,
                "plan": plan,
                "credits": plan_info["credits"],
            },
        )

    except stripe.error.StripeError as e:
        print(f"  [ Stripe Error ] {e}")
        return _r(400, {"error": str(e.user_message or e)})
    except Exception as e:
        print(f"  [ create_checkout Error ] {e}")
        import traceback

        traceback.print_exc()
        return _r(500, {"error": str(e)})


def _r(status_code: int, body: dict):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Requested-With",
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
        },
        "body": json.dumps(body),
    }
