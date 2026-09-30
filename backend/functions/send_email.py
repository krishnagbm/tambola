# backend/functions/send_email.py
# Backward-compatible proxy router.
# Routes requests to dedicated micro-handlers:
#   - recent_games.py
#   - dvaa_brand_approval.py
#   - privateparty_email.py

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

import recent_games
import dvaa_brand_approval
import privateparty_email


def handler(event, context):
    try:
        body_raw = event.get("body") or "{}"
        if isinstance(body_raw, str):
            payload = json.loads(body_raw) if body_raw.strip() else {}
        else:
            payload = body_raw or {}

        qs = event.get("queryStringParameters") or {}
        path = event.get("path") or ""
        action = (
            payload.get("action", "")
            or payload.get("type", "")
            or qs.get("action", "")
        ).strip()

        # 1. Recent Games
        if action == "get_recent_games" or "/recent-games" in path:
            return recent_games.handler(event, context)

        # 2. DVAA & Brand Approval
        if (
            action in (
                "get_brand_approval_preview",
                "verify_and_approve_brand",
                "get_brand_offers",
                "register_brand_offer",
                "track_brand_offer_click",
                "track_brand_offer_view",
                "send_winner_gift_email",
                "brand_acknowledgement",
                "brand_acknowledgment",
                "brand_approved_confirmation",
                "brand_approval_complete",
                "brand_approval",
            )
            or "approval_token" in payload
            or "brand-approval" in path
        ):
            return dvaa_brand_approval.handler(event, context)

        # 3. Default to Private Party Passcodes Email
        return privateparty_email.handler(event, context)

    except Exception as e:
        import traceback
        traceback.print_exc()
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
            },
            "body": json.dumps({"error": str(e)}),
        }
