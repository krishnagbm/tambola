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

        # 3. Scheduled Game Low-Quorum Decision Email
        if action in ("scheduled_game_decision", "low_quorum_decision"):
            to_email = (
                payload.get("to_email")
                or payload.get("host_email")
                or payload.get("organizer_email")
                or ""
            ).strip()
            if not to_email or "@" not in to_email:
                return {
                    "statusCode": 400,
                    "headers": {
                        "Content-Type": "application/json",
                        "Access-Control-Allow-Origin": "*",
                    },
                    "body": json.dumps({"error": "Missing or invalid to_email."}),
                }

            from email_ses import send_low_quorum_decision_email

            success = send_low_quorum_decision_email(
                to_email=to_email,
                game_name=payload.get("game_name") or "Scheduled Game",
                game_id=payload.get("game_id") or "",
                invite_code=payload.get("invite_code") or "",
                confirmed_count=int(payload.get("confirmed_count") or 0),
                quorum_count=int(payload.get("quorum_count") or 1),
                scheduled_at_str=payload.get("scheduled_at_str"),
                grace_period_minutes=int(payload.get("grace_period_minutes") or 5),
                organizer_name=payload.get("organizer_name"),
            )
            return {
                "statusCode": 200 if success else 500,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
                "body": json.dumps({
                    "success": success,
                    "message": "Decision email dispatched" if success else "Failed to send email",
                }),
            }

        # 4. Host Registration Alert Notification (to contact@dabhousie.com)
        if action in ("host_registered", "notify_host_registration", "new_host_alert"):
            host_email = (
                payload.get("host_email")
                or payload.get("email")
                or payload.get("to_email")
                or ""
            ).strip()

            from email_ses import send_host_registered_alert_email

            success = send_host_registered_alert_email(
                host_email=host_email,
                host_name=payload.get("host_name") or payload.get("display_name"),
                game_name=payload.get("game_name"),
                invite_code=payload.get("invite_code"),
                user_id=payload.get("user_id"),
                provider=payload.get("provider"),
                action_type=payload.get("action_type") or "Host Registered / Game Created",
            )
            return {
                "statusCode": 200 if success else 500,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                },
                "body": json.dumps({
                    "success": success,
                    "message": "Host registration alert successfully sent to contact@dabhousie.com" if success else "Failed to send host alert email",
                }),
            }

        # 5. Default to Private Party Passcodes Email
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
