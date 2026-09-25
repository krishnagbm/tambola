# backend/functions/send_email.py
# DabHousie — API Endpoint to Dispatch Private Party Seat Passcodes Email
# POST /email/private-party or POST /send-email

import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(__file__))

from email_ses import (
    send_private_party_otps_email,
    send_brand_approval_email,
    send_brand_acknowledgement_email,
    send_brand_approved_confirmation_email,
    send_winner_gift_email,
    send_brand_offer_registered_email,
)


def _supabase_rest(endpoint_path: str, method: str = "GET", payload: dict = None):
    """Executes a server-side request against Supabase REST API using Lambda env credentials."""
    sb_url = (os.getenv("SUPABASE_URL") or "").rstrip("/")
    sb_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY") or ""
    if not sb_url or not sb_key:
        raise RuntimeError("Server database configuration is missing.")

    url = f"{sb_url}{endpoint_path}"
    headers = {
        "apikey": sb_key,
        "Authorization": f"Bearer {sb_key}",
        "Content-Type": "application/json",
    }
    data_bytes = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data_bytes, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as he:
        err_raw = he.read().decode("utf-8") if he.fp else ""
        try:
            return he.code, json.loads(err_raw) if err_raw else {"error": str(he)}
        except Exception:
            return he.code, {"error": err_raw or str(he)}


def handler(event, context):
    """
    AWS Lambda handler triggered via API Gateway.
    Supports:
      0. Public Web Proxy Actions (keeps Supabase URLs/keys/paths out of public HTML):
         - action: "get_recent_games"
         - action: "get_brand_approval_preview"
         - action: "verify_and_approve_brand"
         - action: "get_brand_offers"
         - action: "register_brand_offer"
         - action: "track_brand_offer_click"
         - action: "send_winner_gift_email"
      1. Brand Approval Request / Acknowledgement / Confirmation
      2. Private Party Passcodes
    """
    # Handle preflight OPTIONS request
    http_method = event.get("httpMethod", "").upper()
    if http_method == "OPTIONS":
        return _r(200, {"status": "ok"})

    try:
        body_raw = event.get("body") or "{}"
        if isinstance(body_raw, str):
            payload = json.loads(body_raw) if body_raw.strip() else {}
        else:
            payload = body_raw or {}

        qs = event.get("queryStringParameters") or {}
        path = event.get("path", "")
        action = (
            payload.get("action", "")
            or payload.get("type", "")
            or qs.get("action", "")
        ).strip()

        # Route 0A: Public Hall of Fame / Recent Games proxy
        if action == "get_recent_games":
            select_cols = (
                "name,invite_code,player_count,numbers_called_count,duration_seconds,"
                "completed_at,organization_name,organization_logo_url,organization_logo_alt,"
                "organization_logo_approved,winners_roster"
            )
            status_code, data = _supabase_rest(
                f"/rest/v1/MPT_game_archives?select={select_cols}&order=completed_at.desc.nullslast&limit=100",
                method="GET",
            )
            if status_code == 200 and isinstance(data, list) and len(data) > 0:
                return _r(200, {"success": True, "games": data})

            # Fallback to completed games
            fb_cols = (
                "name,invite_code,funded_capacity,updated_at,created_at,"
                "organization_name,organization_logo_url,organization_logo_alt,organization_logo_approved"
            )
            status_code, raw_games = _supabase_rest(
                f"/rest/v1/MPT_games?status=eq.COMPLETED&select={fb_cols}&order=updated_at.desc&limit=50",
                method="GET",
            )
            if status_code == 200 and isinstance(raw_games, list):
                mapped = [
                    {
                        "name": g.get("name") or "Tambola Party Event",
                        "invite_code": g.get("invite_code") or "------",
                        "player_count": g.get("funded_capacity") or 5,
                        "numbers_called_count": 68,
                        "duration_seconds": 720,
                        "completed_at": g.get("updated_at") or g.get("created_at"),
                        "organization_name": g.get("organization_name"),
                        "organization_logo_url": g.get("organization_logo_url"),
                        "organization_logo_alt": g.get("organization_logo_alt"),
                        "organization_logo_approved": bool(g.get("organization_logo_approved")),
                        "winners_roster": [],
                    }
                    for g in raw_games
                ]
                return _r(200, {"success": True, "games": mapped})

            return _r(200, {"success": True, "games": []})

        # Route 0B: Public DVAA Brand Approval Preview proxy
        if action == "get_brand_approval_preview":
            token = (payload.get("token") or payload.get("p_token") or qs.get("token") or "").strip()
            if not token:
                return _r(400, {"success": False, "message": "Missing authorization token."})
            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_get_brand_approval_preview",
                method="POST",
                payload={"p_token": token},
            )
            return _r(status_code if status_code in (200, 400, 404) else 200, data if isinstance(data, dict) else {"success": False})

        # Route 0C: Public DVAA Brand Verify & Approve proxy
        if action == "verify_and_approve_brand":
            token = (payload.get("token") or payload.get("p_token") or "").strip()
            if not token:
                return _r(400, {"success": False, "message": "Missing authorization token."})
            req_ctx = event.get("requestContext") or {}
            identity = req_ctx.get("identity") or {}
            client_ip = identity.get("sourceIp") or payload.get("p_ip") or "Web Approver"
            user_agent = payload.get("user_agent") or payload.get("p_user_agent") or "Web Approver"
            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_verify_and_approve_brand",
                method="POST",
                payload={
                    "p_token": token,
                    "p_ip": client_ip,
                    "p_user_agent": user_agent,
                },
            )
            return _r(status_code if status_code in (200, 400, 404) else 200, data if isinstance(data, dict) else {"success": False})

        # Route 0D: Get Active Brand Gift Offers (Public & Host Catalog)
        if action == "get_brand_offers":
            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_get_active_brand_offers",
                method="POST",
                payload={},
            )
            if status_code == 200 and isinstance(data, list):
                return _r(200, {"success": True, "offers": data})
            return _r(200, {"success": True, "offers": []})

        # Route 0E: Register Brand Gift Offer (from Hall of Fame / Brand Marketer Portal)
        if action == "register_brand_offer":
            brand_name = (payload.get("brand_name") or "").strip()
            brand_domain = (payload.get("brand_domain") or "").strip().lower()
            brand_logo_url = (payload.get("brand_logo_url") or "").strip()
            marketer_name = (payload.get("marketer_name") or payload.get("contact_name") or "").strip()
            marketer_email = (payload.get("marketer_email") or payload.get("contact_email") or "").strip().lower()
            gift_title = (payload.get("gift_title") or payload.get("product_title") or "").strip()
            gift_description = (payload.get("gift_description") or payload.get("product_description") or "").strip()
            category = (payload.get("category") or "Shopping Vouchers").strip()
            retail_value = float(payload.get("retail_value") or payload.get("retail_price") or 0)
            organizer_price = float(payload.get("organizer_price") or retail_value)
            product_url = (payload.get("product_url") or "").strip()
            product_image_url = (payload.get("product_image_url") or "").strip()
            promo_code = (payload.get("promo_code") or "").strip()
            emoji = (payload.get("emoji") or "🎁").strip()

            BLOCKED_FREE_DOMAINS = {
                "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "hotmail.com",
                "outlook.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
                "aol.com", "zoho.com", "proton.me", "protonmail.com", "mail.com", "gmx.com",
            }
            email_domain = marketer_email.split("@")[-1] if "@" in marketer_email else ""
            if not email_domain or email_domain in BLOCKED_FREE_DOMAINS:
                return _r(400, {
                    "success": False,
                    "message": "Please use your official corporate work email (e.g. name@brand.com) to register a Brand Gift offer.",
                })

            if not brand_domain:
                brand_domain = email_domain
            if not brand_logo_url and brand_domain:
                brand_logo_url = f"https://img.logo.dev/{brand_domain}?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png"

            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_register_brand_offer",
                method="POST",
                payload={
                    "p_brand_name": brand_name,
                    "p_brand_domain": brand_domain,
                    "p_brand_logo_url": brand_logo_url,
                    "p_contact_name": marketer_name,
                    "p_contact_email": marketer_email,
                    "p_product_title": gift_title,
                    "p_product_description": gift_description or None,
                    "p_category": category,
                    "p_product_url": product_url,
                    "p_product_image_url": product_image_url or None,
                    "p_retail_price": retail_value,
                    "p_organizer_price": organizer_price,
                    "p_promo_code": promo_code or None,
                    "p_emoji": emoji,
                },
            )
            if status_code == 200 and isinstance(data, dict) and data.get("success"):
                try:
                    send_brand_offer_registered_email(
                        to_email=marketer_email,
                        marketer_name=marketer_name or brand_name,
                        brand_name=brand_name,
                        gift_title=gift_title,
                        retail_value=retail_value,
                        organizer_price=organizer_price,
                        product_url=product_url,
                        promo_code=promo_code or None,
                        brand_logo_url=brand_logo_url,
                    )
                except Exception as e_mail:
                    print(f"  [ SES ] Non-fatal brand offer email error: {e_mail}")
                return _r(200, data)
            return _r(400, data if isinstance(data, dict) else {"success": False, "message": "Could not register brand offer."})

        # Route 0F: Track Brand Offer Product Link Click (from Hall of Fame / Rewards)
        if action == "track_brand_offer_click":
            offer_id = (payload.get("offer_id") or payload.get("p_offer_id") or "").strip()
            if not offer_id:
                return _r(200, {"success": False})
            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_track_brand_offer_click",
                method="POST",
                payload={"p_offer_id": offer_id},
            )
            return _r(200, data if isinstance(data, dict) else {"success": True})

        # Route 0G: Send Winner Brand Gift & Prize Voucher Email
        if action == "send_winner_gift_email":
            to_email_winner = (payload.get("to_email") or "").strip()
            if not to_email_winner or "@" not in to_email_winner:
                return _r(400, {"success": False, "error": "Please provide a valid recipient email address."})
            ok = send_winner_gift_email(
                to_email=to_email_winner,
                player_name=(payload.get("player_name") or "DabHousie Winner").strip(),
                game_name=(payload.get("game_name") or "DabHousie Event").strip(),
                invite_code=(payload.get("invite_code") or "------").strip(),
                prize_type=(payload.get("prize_type") or "Prize").strip(),
                verification_code=(payload.get("verification_code") or "Dab-Housie").strip(),
                prize_value=payload.get("prize_value"),
                brand_name=payload.get("brand_name"),
                gift_title=payload.get("gift_title"),
                product_url=payload.get("product_url"),
                fulfilled_code=payload.get("fulfilled_code"),
                brand_logo_url=payload.get("brand_logo_url"),
            )
            if ok:
                return _r(200, {"success": True, "message": f"Prize & Brand Gift voucher emailed to {to_email_winner}!"})
            return _r(500, {"success": False, "error": "Failed to dispatch prize email via AWS SES."})

        to_email = payload.get("to_email", "").strip()
        game_name = payload.get("game_name", "DabHousie Game")

        if not to_email:
            return _r(400, {"error": "Missing to_email parameter"})

        # Route 1A: Brand Acknowledgement (DVAA Auto-Approval)
        if action in ("brand_acknowledgement", "brand_acknowledgment"):
            organization_name = payload.get("organization_name", "").strip()
            organization_logo_url = payload.get("organization_logo_url", "").strip()
            organizer_name = payload.get("organizer_name", "").strip()
            capacity = payload.get("capacity")
            host_email = payload.get("host_email", "").strip().lower()
            invite_code = payload.get("invite_code", "").strip()

            if not organization_name:
                return _r(400, {"error": "Missing organization_name parameter"})

            success = send_brand_acknowledgement_email(
                to_email=to_email,
                organization_name=organization_name,
                game_name=game_name,
                organization_logo_url=organization_logo_url,
                organizer_name=organizer_name,
                capacity=capacity,
                host_email=host_email,
                invite_code=invite_code,
                audit_email="contact@dabhousie.com",
            )

            if success:
                return _r(200, {
                    "success": True,
                    "message": f"DVAA™ Brand acknowledgement successfully sent to {to_email} and copied to contact@dabhousie.com",
                    "to_email": to_email,
                    "organization_name": organization_name,
                })
            else:
                return _r(500, {
                    "success": False,
                    "error": f"Failed to send DVAA™ brand acknowledgement email to {to_email}."
                })

        # Route 1B: Brand Approved Confirmation (Sent after approver confirms on web or email)
        if action in ("brand_approved_confirmation", "brand_approval_complete"):
            organization_name = payload.get("organization_name", "").strip()
            organization_logo_url = payload.get("organization_logo_url", "").strip()
            organizer_name = payload.get("organizer_name", "").strip()
            capacity = payload.get("capacity")
            host_email = payload.get("host_email", "").strip().lower()
            approver_email = payload.get("approver_email", to_email).strip().lower()
            approved_at = payload.get("approved_at")
            approved_ip = payload.get("approved_ip")
            invite_code = payload.get("invite_code", "").strip()

            if not organization_name:
                return _r(400, {"error": "Missing organization_name parameter"})

            success = send_brand_approved_confirmation_email(
                to_email=to_email,
                organization_name=organization_name,
                game_name=game_name,
                organization_logo_url=organization_logo_url,
                organizer_name=organizer_name,
                capacity=capacity,
                host_email=host_email,
                approver_email=approver_email,
                approved_at=approved_at,
                approved_ip=approved_ip,
                invite_code=invite_code,
                audit_email="contact@dabhousie.com",
            )

            if success:
                return _r(200, {
                    "success": True,
                    "message": f"Brand confirmation audit email successfully delivered to contact@dabhousie.com and {to_email}",
                    "to_email": to_email,
                })
            else:
                return _r(500, {
                    "success": False,
                    "error": f"Failed to send brand approval confirmation audit email."
                })

        # Route 1C: Brand Approval Request
        if action == "brand_approval" or "approval_token" in payload or "brand-approval" in path:
            organization_name = payload.get("organization_name", "").strip()
            approval_token = payload.get("approval_token", "").strip()
            organization_logo_url = payload.get("organization_logo_url", "").strip()
            organizer_name = payload.get("organizer_name", "").strip()
            capacity = payload.get("capacity")
            host_email = payload.get("host_email", "").strip().lower()
            invite_code = payload.get("invite_code", "").strip()

            if not organization_name or not approval_token:
                return _r(400, {"error": "Missing organization_name or approval_token parameter"})

            # Anti-Spam Gate: Validate Host Domain against Corporate Approver Domain
            approver_domain = to_email.split("@")[-1].lower() if "@" in to_email else ""
            host_domain = host_email.split("@")[-1].lower() if "@" in host_email else ""

            BLOCKED_PERSONAL_DOMAINS = {
                "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "hotmail.com", 
                "outlook.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com", 
                "aol.com", "zoho.com", "proton.me", "protonmail.com", "mail.com", "gmx.com"
            }

            if host_domain in BLOCKED_PERSONAL_DOMAINS:
                return _r(403, {
                    "success": False,
                    "error": "Anti-Spam Protection: Corporate branding emails can only be dispatched by hosts with a verified corporate domain (e.g. you@company.com). Personal accounts (@gmail, @yahoo, etc.) cannot trigger emails to corporations."
                })

            if host_domain and approver_domain and host_domain != approver_domain:
                return _r(403, {
                    "success": False,
                    "error": f"Anti-Spam Protection: Host domain (@{host_domain}) must match corporate approver domain (@{approver_domain})."
                })

            success = send_brand_approval_email(
                to_email=to_email,
                organization_name=organization_name,
                game_name=game_name,
                approval_token=approval_token,
                organization_logo_url=organization_logo_url,
                organizer_name=organizer_name,
                capacity=capacity,
                host_email=host_email,
                invite_code=invite_code,
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
