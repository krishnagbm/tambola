# backend/functions/send_email.py
# DabHousie — API Endpoint to Dispatch Private Party Seat Passcodes Email
# POST /email/private-party or POST /send-email

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from email_ses import send_private_party_otps_email, send_brand_approval_email


def handler(event, context):
    """
    AWS Lambda handler triggered via API Gateway.
    Supports:
      1. Brand Approval Request:
         POST /email/brand-approval (or action: "brand_approval")
         {
             "action": "brand_approval",
             "to_email": "approver@company.com",
             "organization_name": "Acme Corp",
             "game_name": "Friday Fiesta",
             "approval_token": "...",
             "organization_logo_url": "https://...",
             "organizer_name": "Jane Host",
             "capacity": 25
         }

      2. Private Party Passcodes:
         POST /email/private-party
         {
             "to_email": "organizer@example.com",
             "game_name": "Family Diwali Party",
             "invite_code": "DAB888",
             "otps": [{"seat_number": 1, "otp_code": "123456"}, ...],
             "scheduled_at": "2026-09-20T18:00:00Z" (optional)
         }
    """
    # Handle preflight OPTIONS request
    http_method = event.get("httpMethod", "").upper()
    if http_method == "OPTIONS":
        return _r(200, {"status": "ok"})

    try:
        body_raw = event.get("body") or "{}"
        if isinstance(body_raw, str):
            payload = json.loads(body_raw)
        else:
            payload = body_raw

        to_email = payload.get("to_email", "").strip()
        game_name = payload.get("game_name", "DabHousie Game")
        path = event.get("path", "")
        action = payload.get("action", "") or payload.get("type", "")

        if not to_email:
            return _r(400, {"error": "Missing to_email parameter"})

        # Route 1: Brand Approval
        if action == "brand_approval" or "approval_token" in payload or "brand-approval" in path:
            organization_name = payload.get("organization_name", "").strip()
            approval_token = payload.get("approval_token", "").strip()
            organization_logo_url = payload.get("organization_logo_url", "").strip()
            organizer_name = payload.get("organizer_name", "").strip()
            capacity = payload.get("capacity")

            if not organization_name or not approval_token:
                return _r(400, {"error": "Missing organization_name or approval_token parameter"})

            success = send_brand_approval_email(
                to_email=to_email,
                organization_name=organization_name,
                game_name=game_name,
                approval_token=approval_token,
                organization_logo_url=organization_logo_url,
                organizer_name=organizer_name,
                capacity=capacity,
            )

            if success:
                return _r(200, {
                    "success": True,
                    "message": f"Brand approval request successfully sent to {to_email}",
                    "to_email": to_email,
                    "organization_name": organization_name,
                })
            else:
                return _r(500, {
                    "success": False,
                    "error": f"Failed to send brand approval email to {to_email}."
                })

        # Route 2: Private Party Seat Passcodes
        invite_code = payload.get("invite_code", "")
        otps = payload.get("otps", [])
        scheduled_at = payload.get("scheduled_at")

        if not otps:
            return _r(400, {"error": "Missing otps list"})

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
        print(f"  [ send_email Error ] {e}")
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
