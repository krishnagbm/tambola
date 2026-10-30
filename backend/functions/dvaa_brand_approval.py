# backend/functions/dvaa_brand_approval.py
# DabHousie — Dedicated DVAA™ Corporate Brand Approval & Marketing Partner Hub
# Handles:
#   - action: "get_brand_approval_preview"
#   - action: "verify_and_approve_brand"
#   - action: "brand_approval"
#   - action: "brand_acknowledgement"
#   - action: "brand_approved_confirmation"
#   - action: "get_brand_offers"
#   - action: "register_brand_offer"
#   - action: "track_brand_offer_click"
#   - action: "track_brand_offer_view"
#   - action: "send_winner_gift_email"

import json
import os
import sys
import re
import hmac
import hashlib
import time
import secrets
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(__file__))

from email_ses import (
    send_brand_approval_email,
    send_brand_acknowledgement_email,
    send_brand_approved_confirmation_email,
    send_winner_gift_email,
    send_brand_offer_registered_email,
    send_brand_partner_otp_email,
    send_partner_confirmed_to_dabhousie_email,
)

OTP_HMAC_SECRET = os.getenv("OTP_HMAC_SECRET") or os.getenv("SUPABASE_SERVICE_ROLE_KEY") or "dabhousie_brand_otp_secret_key"
BLOCKED_FREE_DOMAINS = {
    "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "hotmail.com",
    "outlook.com", "live.com", "msn.com", "icloud.com", "me.com", "mac.com",
    "aol.com", "zoho.com", "proton.me", "protonmail.com", "mail.com", "gmx.com",
    "rediffmail.com", "yandex.com",
}

def _clean_domain(domain_str: str) -> str:
    clean = (domain_str or "").strip().lower()
    clean = re.sub(r"^https?://", "", clean)
    clean = re.sub(r"^www\.", "", clean)
    return clean.split("/")[0].split(":")[0].strip()

def _make_verification_token(email: str, domain: str) -> str:
    """Generates an HMAC verification token valid for 2 hours once OTP is verified."""
    exp = int(time.time()) + 7200
    msg = f"{email}:{domain}:{exp}".encode("utf-8")
    sig = hmac.new(OTP_HMAC_SECRET.encode("utf-8"), msg, hashlib.sha256).hexdigest()
    return f"{exp}:{sig}"

def _verify_token(token: str, email: str, domain: str) -> bool:
    """Verifies that the token was signed with OTP_HMAC_SECRET and has not expired."""
    try:
        parts = token.split(":")
        if len(parts) != 2:
            return False
        exp = int(parts[0])
        sig = parts[1]
        if time.time() > exp:
            return False
        msg = f"{email}:{domain}:{exp}".encode("utf-8")
        expected = hmac.new(OTP_HMAC_SECRET.encode("utf-8"), msg, hashlib.sha256).hexdigest()
        return hmac.compare_digest(sig, expected)
    except Exception:
        return False


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
    AWS Lambda handler for DVAA™ Brand Approval, Brand Marketing Partner Offers, and Winner Gift vouchers.
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

        qs = event.get("queryStringParameters") or {}
        path = event.get("path", "")
        action = (
            payload.get("action", "")
            or payload.get("type", "")
            or qs.get("action", "")
        ).strip()

        # 1. Public DVAA Brand Approval Preview proxy
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

        # 2. Public DVAA Brand Verify & Approve proxy
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

        # 3. Get Brand Gift Offers
        if action == "get_brand_offers":
            def _sanitize_public_offers(raw_list):
                sanitized = []
                for item in (raw_list or []):
                    if not isinstance(item, dict):
                        continue
                    clean = dict(item)
                    clean["has_promo_code"] = bool(clean.get("promo_code") and str(clean.get("promo_code")).strip())
                    clean.pop("promo_code", None)
                    clean.pop("verification_token", None)
                    clean.pop("contact_email", None)
                    clean.pop("contact_name", None)
                    clean.pop("contact_role", None)
                    clean.pop("crm_notes", None)
                    clean.pop("outreach_response", None)
                    sanitized.append(clean)
                return sanitized

            filter_status = (payload.get("status") or "ACTIVE").strip().upper()
            if filter_status not in ("ACTIVE", "EXPIRED"):
                filter_status = "ACTIVE"
            filter_country = (payload.get("country") or payload.get("target_region") or "").strip()
            if filter_status != "ACTIVE" or filter_country:
                status_code, data = _supabase_rest(
                    "/rest/v1/rpc/MPT_get_brand_offers_filtered",
                    method="POST",
                    payload={
                        "p_status": filter_status,
                        "p_country": filter_country or None,
                    },
                )
                if status_code == 200 and isinstance(data, list):
                    return _r(200, {"success": True, "offers": _sanitize_public_offers(data)})

            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_get_active_brand_offers",
                method="POST",
                payload={},
            )
            if status_code == 200 and isinstance(data, list):
                return _r(200, {"success": True, "offers": _sanitize_public_offers(data)})
            return _r(200, {"success": True, "offers": []})

        # 3b. Send Brand Partner Domain OTP
        if action == "send_brand_partner_otp":
            contact_email = (payload.get("contact_email") or payload.get("email") or "").strip().lower()
            brand_name = (payload.get("brand_name") or "").strip()
            brand_domain = _clean_domain(payload.get("brand_domain") or "")
            rep_name = (payload.get("contact_name") or payload.get("name") or "").strip()

            if not contact_email or "@" not in contact_email:
                return _r(400, {"success": False, "message": "Please enter a valid work email address."})

            email_domain = contact_email.split("@")[-1].lower()
            if not brand_domain:
                brand_domain = email_domain

            if email_domain in BLOCKED_FREE_DOMAINS:
                return _r(400, {
                    "success": False,
                    "message": "Personal/free email addresses (@gmail, @yahoo, etc.) cannot register official brand offers. Please use your corporate work email.",
                })

            # Strictest anti-spoofing check: work email domain must match claimed brand domain
            if email_domain != brand_domain and not email_domain.endswith(f".{brand_domain}"):
                return _r(400, {
                    "success": False,
                    "message": f"Domain Mismatch: Your work email (@{email_domain}) does not match your brand domain ({brand_domain}).",
                })

            # Generate 6-digit numeric OTP
            otp_code = f"{secrets.randbelow(900000) + 100000}"
            otp_hash = hashlib.sha256(f"{otp_code}:{contact_email}:{brand_domain}".encode("utf-8")).hexdigest()

            # Store in Supabase MPT_brand_domain_verifications table
            sc, ins_res = _supabase_rest(
                "/rest/v1/MPT_brand_domain_verifications",
                method="POST",
                payload={
                    "email": contact_email,
                    "domain": brand_domain,
                    "otp_hash": otp_hash,
                    "status": "PENDING",
                    "expires_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 600)),
                },
            )

            # Send OTP email via Amazon SES
            mail_sent = send_brand_partner_otp_email(
                to_email=contact_email,
                otp_code=otp_code,
                brand_name=brand_name or brand_domain,
                brand_domain=brand_domain,
                rep_name=rep_name,
            )

            if not mail_sent:
                return _r(500, {"success": False, "message": "Could not deliver verification email. Please check the address and try again."})

            return _r(200, {
                "success": True,
                "message": f"Verification code sent to {contact_email}. Please check your inbox.",
                "brand_domain": brand_domain,
            })

        # 3c. Verify Brand Partner Domain OTP
        if action == "verify_brand_partner_otp":
            contact_email = (payload.get("contact_email") or payload.get("email") or "").strip().lower()
            brand_domain = _clean_domain(payload.get("brand_domain") or "")
            otp_code = (payload.get("otp_code") or payload.get("otp") or "").strip()

            if not contact_email or not otp_code:
                return _r(400, {"success": False, "message": "Email and 6-digit verification code are required."})

            email_domain = contact_email.split("@")[-1].lower() if "@" in contact_email else ""
            if not brand_domain:
                brand_domain = email_domain

            expected_hash = hashlib.sha256(f"{otp_code}:{contact_email}:{brand_domain}".encode("utf-8")).hexdigest()

            # Query database for recent matching pending OTP
            now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            sc, rows = _supabase_rest(
                f"/rest/v1/MPT_brand_domain_verifications?email=eq.{urllib.parse.quote(contact_email)}&domain=eq.{urllib.parse.quote(brand_domain)}&status=eq.PENDING&expires_at=gte.{now_iso}&order=created_at.desc&limit=1",
                method="GET",
            )

            if sc == 200 and isinstance(rows, list) and len(rows) > 0:
                record = rows[0]
                if record.get("otp_hash") == expected_hash:
                    # Mark record as VERIFIED
                    _supabase_rest(
                        f"/rest/v1/MPT_brand_domain_verifications?id=eq.{record['id']}",
                        method="PATCH",
                        payload={"status": "VERIFIED", "verified_at": now_iso},
                    )
                    verification_token = _make_verification_token(contact_email, brand_domain)
                    return _r(200, {
                        "success": True,
                        "verified": True,
                        "verification_token": verification_token,
                        "message": f"Official domain ownership confirmed for @{brand_domain}!",
                        "brand_domain": brand_domain,
                    })

            return _r(400, {
                "success": False,
                "message": "Invalid or expired verification code. Please check your code or request a new one.",
            })

        # 4. Register Brand Marketing Partner Offer
        if action == "register_brand_offer":
            brand_name = (payload.get("brand_name") or "").strip()
            brand_domain = _clean_domain(payload.get("brand_domain") or "")
            brand_logo_url = (payload.get("brand_logo_url") or "").strip()
            marketer_name = (payload.get("marketer_name") or payload.get("contact_name") or "").strip()
            marketer_email = (payload.get("marketer_email") or payload.get("contact_email") or "").strip().lower()
            verification_token = (payload.get("verification_token") or "").strip()
            contact_role = (payload.get("contact_role") or "").strip()
            gift_title = (payload.get("gift_title") or payload.get("product_title") or "").strip()
            gift_description = (payload.get("gift_description") or payload.get("product_description") or payload.get("description") or "").strip()
            category = (payload.get("category") or "Shopping Vouchers").strip()
            retail_value = float(payload.get("retail_value") or payload.get("retail_price") or 0)
            raw_org_price = payload.get("organizer_price")
            organizer_price = float(raw_org_price) if raw_org_price is not None and str(raw_org_price).strip() != "" else 0.0
            vouchers_total_count = int(payload.get("vouchers_total_count") or 10)
            product_url = (payload.get("product_url") or "").strip()
            product_image_url = (payload.get("product_image_url") or "").strip()
            promo_code = (payload.get("promo_code") or "").strip()
            emoji = (payload.get("emoji") or "🎁").strip()
            offer_type = (payload.get("offer_type") or "GIFT_VOUCHER").strip().upper()
            target_region = (payload.get("target_region") or "Global").strip()
            raw_countries = payload.get("target_countries")
            if isinstance(raw_countries, list) and len(raw_countries) > 0:
                target_countries = [str(c).strip() for c in raw_countries if str(c).strip()]
            elif target_region:
                target_countries = [c.strip() for c in target_region.split(",") if c.strip()]
            else:
                target_countries = ["Global"]
            currency = (payload.get("currency") or "USD").strip().upper()
            voucher_code_type = (payload.get("voucher_code_type") or "SHARED_PROMO_CODE").strip().upper()
            expiration_date = (payload.get("expiration_date") or "").strip() or None
            redemption_restrictions = (payload.get("redemption_restrictions") or "").strip() or None
            minimum_purchase = (payload.get("minimum_purchase") or "").strip() or None
            new_customers_only = bool(payload.get("new_customers_only", False))
            redemption_channel = (payload.get("redemption_channel") or "ONLINE").strip().upper()

            email_domain = marketer_email.split("@")[-1] if "@" in marketer_email else ""
            if not email_domain or email_domain in BLOCKED_FREE_DOMAINS:
                return _r(400, {
                    "success": False,
                    "message": "Please use your official corporate work email (e.g. marketing@yourcompany.com) to register a Brand Marketing Partner offer.",
                })

            if not brand_domain:
                brand_domain = email_domain

            # If a verification token is provided, verify it; otherwise ensure email domain matches brand domain
            is_domain_verified = False
            if verification_token and _verify_token(verification_token, marketer_email, brand_domain):
                is_domain_verified = True
            elif email_domain == brand_domain or email_domain.endswith(f".{brand_domain}"):
                is_domain_verified = True

            if not is_domain_verified:
                return _r(403, {
                    "success": False,
                    "message": f"Brand Domain Unverified: You must complete the email OTP verification step for @{brand_domain} before registering this offer.",
                })

            if not brand_logo_url and brand_domain:
                brand_logo_url = f"https://img.logo.dev/{brand_domain}?token=pk_VAZ6tvAVQHCDwKeaNRVyjQ&size=256&format=png"

            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_register_brand_offer",
                method="POST",
                payload={
                    "p_brand_name": brand_name,
                    "p_brand_domain": brand_domain,
                    "p_contact_name": marketer_name,
                    "p_contact_email": marketer_email,
                    "p_contact_role": contact_role or None,
                    "p_product_title": gift_title,
                    "p_product_description": gift_description or None,
                    "p_category": category,
                    "p_product_url": product_url,
                    "p_product_image_url": product_image_url or None,
                    "p_retail_price": retail_value,
                    "p_organizer_price": organizer_price,
                    "p_promo_code": promo_code or None,
                    "p_emoji": emoji,
                    "p_vouchers_total_count": vouchers_total_count,
                    "p_offer_type": offer_type,
                    "p_target_region": target_region,
                    "p_target_countries": target_countries,
                    "p_currency": currency,
                    "p_voucher_code_type": voucher_code_type,
                    "p_expiration_date": expiration_date,
                    "p_redemption_restrictions": redemption_restrictions,
                    "p_minimum_purchase": minimum_purchase,
                    "p_new_customers_only": new_customers_only,
                    "p_redemption_channel": redemption_channel,
                },
            )
            if status_code == 200 and isinstance(data, dict) and data.get("success"):
                offer_id = str(data.get("offer_id") or "")
                token = _make_verification_token(marketer_email, brand_domain)
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
                        vouchers_total_count=vouchers_total_count,
                        target_region=target_region,
                        currency=currency,
                        offer_id=offer_id,
                        approval_token=token,
                    )
                except Exception as e_mail:
                    print(f"  [ SES ] Non-fatal brand offer email error: {e_mail}")
                return _r(200, {**data, "approval_token": token})
            return _r(400, data if isinstance(data, dict) else {"success": False, "message": "Could not register partner offer."})

        # 4b. Partner Authorizes or Rejects Submitted Offer via Email Action Link
        if action in ("partner_authorize_offer", "partner_confirm_offer", "partner_reject_offer"):
            offer_id = (payload.get("offer_id") or "").strip()
            token = (payload.get("token") or "").strip()
            decision = "REJECT" if "reject" in action or payload.get("decision") == "REJECT" else "APPROVE"

            if not offer_id or not token:
                return _r(400, {"success": False, "message": "Missing offer_id or security token."})

            # Fetch the offer
            sc, rows = _supabase_rest(f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}&limit=1", method="GET")
            if sc != 200 or not isinstance(rows, list) or len(rows) == 0:
                return _r(404, {"success": False, "message": "Offer not found."})

            offer = rows[0]
            contact_email = offer.get("contact_email", "")
            brand_domain = offer.get("brand_domain", "")

            # Verify security token
            if not _verify_token(token, contact_email, brand_domain):
                return _r(403, {"success": False, "message": "Invalid or expired authorization token."})

            if decision == "REJECT":
                _supabase_rest(
                    f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}",
                    method="PATCH",
                    payload={"status": "ARCHIVED", "outreach_status": "PARTNER_REJECTED", "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())},
                )
                return _r(200, {
                    "success": True,
                    "status": "ARCHIVED",
                    "decision": "REJECT",
                    "message": f"Brand offer '{offer.get('product_title')}' has been cancelled by {contact_email}.",
                })

            # Decision is APPROVE: Mark as PARTNER_CONFIRMED (waiting for DabHousie SuperAdmin approval)
            now_iso = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            _supabase_rest(
                f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}",
                method="PATCH",
                payload={
                    "outreach_status": "PARTNER_CONFIRMED",
                    "verified_at": now_iso,
                    "updated_at": now_iso,
                },
            )

            # Notify DabHousie Partnerships team
            try:
                send_partner_confirmed_to_dabhousie_email(
                    brand_name=offer.get("brand_name", brand_domain),
                    brand_domain=brand_domain,
                    gift_title=offer.get("product_title", "Brand Gift"),
                    contact_name=offer.get("contact_name") or offer.get("brand_name"),
                    contact_email=contact_email,
                    retail_value=float(offer.get("retail_price") or 0),
                    vouchers_total_count=int(offer.get("vouchers_total_count") or 10),
                    offer_id=offer_id,
                )
            except Exception as e_notif:
                print(f"  [ SES ] Non-fatal partner confirmation alert error: {e_notif}")

            return _r(200, {
                "success": True,
                "status": "PARTNER_CONFIRMED",
                "decision": "APPROVE",
                "message": f"Offer successfully authorized by {offer.get('brand_name')}! DabHousie Partnerships has been notified for final review and catalog publishing.",
                "offer": offer,
            })

        # 4c. Partner Portal: Fetch Partner Campaigns
        if action == "get_partner_campaigns":
            contact_email = (payload.get("contact_email") or payload.get("email") or "").strip().lower()
            token = (payload.get("token") or payload.get("verification_token") or "").strip()

            if not contact_email or "@" not in contact_email:
                return _r(400, {"success": False, "message": "Valid corporate email is required."})

            email_domain = contact_email.split("@")[-1].lower()
            if not token or not _verify_token(token, contact_email, email_domain):
                return _r(403, {"success": False, "message": "Session expired or invalid verification token. Please verify OTP again."})

            sc, rows = _supabase_rest(
                f"/rest/v1/MPT_brand_offers?contact_email=eq.{urllib.parse.quote(contact_email)}&order=created_at.desc",
                method="GET",
            )
            if sc == 200 and isinstance(rows, list):
                return _r(200, {"success": True, "offers": rows})
            return _r(200, {"success": True, "offers": []})

        # 4d. Partner Portal: Update or Retire Brand Gift
        if action == "update_partner_campaign":
            offer_id = (payload.get("offer_id") or "").strip()
            contact_email = (payload.get("contact_email") or "").strip().lower()
            token = (payload.get("token") or payload.get("verification_token") or "").strip()

            if not offer_id or not contact_email:
                return _r(400, {"success": False, "message": "Missing offer_id or contact_email."})

            email_domain = contact_email.split("@")[-1].lower()
            if not token or not _verify_token(token, contact_email, email_domain):
                return _r(403, {"success": False, "message": "Unauthorized or session expired."})

            # Check existing offer
            sc, rows = _supabase_rest(f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}&limit=1", method="GET")
            if sc != 200 or not isinstance(rows, list) or len(rows) == 0:
                return _r(404, {"success": False, "message": "Offer not found."})

            curr = rows[0]
            if curr.get("contact_email", "").lower() != contact_email:
                return _r(403, {"success": False, "message": "You can only edit offers registered under your corporate email."})

            assigned_count = int(curr.get("games_assigned_count") or 0)
            consumed_count = int(curr.get("vouchers_consumed_count") or 0)
            has_been_used = assigned_count > 0 or consumed_count > 0

            # Handle Retire Action
            if payload.get("retire") is True or payload.get("status") in ("PAUSED", "ARCHIVED"):
                new_status = "PAUSED" if payload.get("status") == "PAUSED" else "ARCHIVED"
                _supabase_rest(
                    f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}",
                    method="PATCH",
                    payload={"status": new_status, "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())},
                )
                return _r(200, {"success": True, "message": f"Brand gift status updated to {new_status}."})

            # Update mutable fields
            patch_data = {"updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}

            if "product_url" in payload:
                patch_data["product_url"] = str(payload["product_url"]).strip()
            if "promo_code" in payload:
                patch_data["promo_code"] = str(payload["promo_code"]).strip()
            if "expiration_date" in payload:
                patch_data["expiration_date"] = payload["expiration_date"] or None
            if "redemption_restrictions" in payload:
                patch_data["redemption_restrictions"] = payload["redemption_restrictions"] or None
            if "minimum_purchase" in payload:
                patch_data["minimum_purchase"] = payload["minimum_purchase"] or None
            if "description" in payload or "product_description" in payload:
                patch_data["product_description"] = (payload.get("description") or payload.get("product_description") or "").strip()

            # Safety Rule: Retail price & Organizer price are locked if gift has already been used in live games
            if "retail_price" in payload:
                if has_been_used and float(payload["retail_price"]) != float(curr.get("retail_price") or 0):
                    return _r(400, {
                        "success": False,
                        "message": "Offer Value Locked: Retail value cannot be modified because this gift is already active/assigned in DabHousie games.",
                    })
                elif not has_been_used:
                    patch_data["retail_price"] = float(payload["retail_price"])

            sc_up, up_res = _supabase_rest(
                f"/rest/v1/MPT_brand_offers?id=eq.{urllib.parse.quote(offer_id)}",
                method="PATCH",
                payload=patch_data,
            )

            return _r(200, {
                "success": True,
                "message": "Brand gift details updated successfully!",
                "has_been_used": has_been_used,
            })

        # 5. Track Brand Offer Product Link Click
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

        # 6. Track Brand Offer Impression / View
        if action == "track_brand_offer_view":
            offer_id = (payload.get("offer_id") or payload.get("p_offer_id") or "").strip()
            if not offer_id:
                return _r(200, {"success": False})
            status_code, data = _supabase_rest(
                "/rest/v1/rpc/MPT_track_brand_offer_view",
                method="POST",
                payload={"p_offer_id": offer_id},
            )
            return _r(200, data if isinstance(data, dict) else {"success": True})

        # 7. Send Winner Brand Gift & Prize Voucher Email
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

        # 8. Corporate Brand Approvals
        to_email = payload.get("to_email", "").strip()
        game_name = payload.get("game_name", "DabHousie Game")

        if not to_email:
            return _r(400, {"error": "Missing to_email parameter"})

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
                    "error": "Anti-Spam Protection: Corporate branding emails can only be dispatched by hosts with a verified corporate domain (e.g. you@company.com)."
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

        return _r(400, {"error": f"Unknown DVAA / Brand action: '{action}'"})

    except Exception as e:
        print(f"  [ dvaa_brand_approval Error ] {e}")
        import traceback
        traceback.print_exc()
        return _r(500, {"error": str(e)})
