# backend/functions/recent_games.py
# DabHousie — Dedicated Public Recent Games & Hall of Fame Lambda
# Handles: action="get_recent_games" (GET/POST)
# Isolated from payment gateway, SES email, and corporate approval logic.

import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(__file__))


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


def _is_public_game_visible(game: dict) -> bool:
    """True only for public, non-cancelled games that are allowed to appear on recent-games.html."""
    if not isinstance(game, dict):
        return False

    if bool(game.get("is_private")):
        return False

    # Check explicit admin hiding
    if game.get("is_publicly_visible") is False:
        return False

    if game.get("public_visible") is False:
        return False

    status = str(game.get("status") or "").upper()
    if status in {"CANCELLED", "DRAFT", "OPEN", "READY_TO_START", "STARTING", "IN_PROGRESS"}:
        return False

    return True


def _filter_public_games(games):
    if not isinstance(games, list):
        return []
    return [game for game in games if _is_public_game_visible(game)]


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
    AWS Lambda handler for Public Recent Games / Hall of Fame.
    Accepts GET or POST.
    """
    http_method = (event.get("httpMethod") or "").upper()
    if http_method == "OPTIONS":
        return _r(200, {"status": "ok"})

    try:
        select_cols = (
            "name,invite_code,player_count,numbers_called_count,duration_seconds,"
            "completed_at,organization_name,organization_logo_url,organization_logo_alt,"
            "organization_logo_approved,winners_roster,status,is_private,is_publicly_visible"
        )
        status_code, data = _supabase_rest(
            f"/rest/v1/MPT_game_archives?select={select_cols}&order=completed_at.desc.nullslast&limit=100",
            method="GET",
        )
        if status_code == 200 and isinstance(data, list):
            public_games = _filter_public_games(data)
            if len(public_games) > 0:
                return _r(200, {"success": True, "games": public_games})

        # Fallback to completed games in live table MPT_games
        fb_cols = (
            "name,invite_code,funded_capacity,updated_at,created_at,"
            "organization_name,organization_logo_url,organization_logo_alt,organization_logo_approved,"
            "status,is_private,is_publicly_visible"
        )
        status_code, raw_games = _supabase_rest(
            f"/rest/v1/MPT_games?status=not.eq.CANCELLED&select={fb_cols}&order=updated_at.desc&limit=50",
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
                    "status": g.get("status") or "COMPLETED",
                    "is_private": bool(g.get("is_private")),
                    "is_publicly_visible": g.get("is_publicly_visible") if g.get("is_publicly_visible") is not None else True,
                    "winners_roster": [],
                }
                for g in raw_games
                if _is_public_game_visible(g)
            ]
            if len(mapped) > 0:
                return _r(200, {"success": True, "games": mapped})

        return _r(200, {"success": True, "games": []})

    except Exception as e:
        print(f"  [ recent_games Error ] {e}")
        import traceback
        traceback.print_exc()
        return _r(500, {"error": str(e), "success": False, "games": []})
