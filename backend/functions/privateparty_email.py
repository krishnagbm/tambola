# backend/functions/privateparty_email.py
# DabHousie — API Endpoint to Dispatch Private Party Seat Passcodes & Notifications
# Handles:
#   - action: "private_party_passcodes" or default POST with invite_code & otps

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from email_ses import send_private_party_otps_email


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


def handler(event, context):
    """
    AWS Lambda handler triggered via API Gateway for Private Party passcodes.
    """
    http_method = (event.get("httpMethod") or "").upper()
    if http_method == "OPTIONS":
        return _r(200, {"status": "ok"})

    try:
        body_raw = event.get("body") or "{}"
        if isinstance(body_raw, str):
            payload = json.loads(body_raw) if body_raw.strip() else {}
        else:
            payload = body_raw or {}

        to_email = (payload.get("to_email") or "").strip()
        game_name = (payload.get("game_name") or "DabHousie Game").strip()
        invite_code = (payload.get("invite_code") or "").strip()
        otps = payload.get("otps") or []
        scheduled_at = payload.get("scheduled_at")

        if not to_email or "@" not in to_email:
            return _r(400, {"error": "Missing or invalid to_email parameter."})

        if not otps:
            return _r(400, {"error": "Missing otps list."})

        success = send_private_party_otps_email(
            to_email=to_email,
            game_name=game_name,
            invite_code=invite_code,
            otps_list=otps,
            scheduled_at=scheduled_at,
        )

        if success:
            return _r(200, {
                "success": True,
                "message": f"Private party passcodes successfully sent to {to_email}",
                "to_email": to_email,
                "count": len(otps)
            })
        else:
            return _r(500, {
                "success": False,
                "error": f"Failed to send email to {to_email}. Please ensure the email address is verified if SES is in sandbox mode."
            })

    except Exception as e:
        print(f"  [ privateparty_email Error ] {e}")
        import traceback
        traceback.print_exc()
        return _r(500, {"error": str(e)})
