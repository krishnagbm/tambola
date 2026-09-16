# backend/functions/db.py
# DabHousie — Database helpers (Supabase)
# Provides secure database access using the service role key for backend fulfillment

import os
import sys
from typing import Optional, Dict, Any

try:
    from supabase import create_client, Client
except ImportError:
    create_client = None
    Client = None

_supabase_client: Optional[Any] = None


def get_supabase() -> Any:
    """Initializes or returns cached Supabase service role client."""
    global _supabase_client
    if _supabase_client is not None:
        return _supabase_client

    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY")

    if not url or not key:
        print("  [ DB WARNING ] SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing in environment variables.")
        return None

    if create_client is None:
        print("  [ DB WARNING ] 'supabase' package is not installed.")
        return None

    try:
        _supabase_client = create_client(url, key)
        return _supabase_client
    except Exception as e:
        print(f"  [ DB ERROR ] Failed to initialize Supabase client: {e}")
        return None


def check_payment_exists(provider_ref: str) -> bool:
    """Checks if a payment provider reference (session_id) has already been logged."""
    sb = get_supabase()
    if not sb:
        return False
    try:
        res = (
            sb.from_("MPT_payments")
            .select("id")
            .eq("provider_ref", provider_ref)
            .execute()
        )
        return bool(res.data and len(res.data) > 0)
    except Exception as e:
        print(f"  [ DB ] Error checking existing payment: {e}")
        return False


def fulfill_stripe_payment(
    user_id: str,
    email: str,
    pack: str,
    credits: int,
    amount_usd: float,
    currency: str,
    session_id: str,
    customer_id: Optional[str] = None,
) -> Dict[str, Any]:
    """
    Executes the atomic MPT_process_stripe_payment stored procedure
    to grant credits, record transactions, and save payment record.
    """
    sb = get_supabase()
    if not sb:
        return {
            "status": "error",
            "message": "Database client unavailable",
            "available_credits": 0,
        }

    try:
        rpc_params = {
            "p_user_id": user_id,
            "p_email": email,
            "p_pack": pack,
            "p_credits": int(credits),
            "p_amount_usd": float(amount_usd),
            "p_currency": currency.upper(),
            "p_session_id": session_id,
            "p_customer_id": customer_id,
        }
        res = sb.rpc("MPT_process_stripe_payment", rpc_params).execute()
        if res.data:
            return res.data
        return {
            "status": "error",
            "message": "No data returned from RPC",
            "available_credits": 0,
        }
    except Exception as e:
        print(f"  [ DB ERROR ] fulfill_stripe_payment failed: {e}")
        import traceback

        traceback.print_exc()
        return {
            "status": "error",
            "message": str(e),
            "available_credits": 0,
        }


def get_user_wallet_balance(user_id: str) -> int:
    """Fetches user's current available credits balance."""
    sb = get_supabase()
    if not sb:
        return 0
    try:
        res = (
            sb.from_("MPT_admin_wallets")
            .select("available_credits")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if res and res.data and "available_credits" in res.data:
            return int(res.data["available_credits"])
        return 0
    except Exception as e:
        print(f"  [ DB ] Error fetching user balance: {e}")
        return 0
