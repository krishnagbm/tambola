# backend/functions/game_scheduler.py
# DabHousie — Autonomous Game Scheduler & Lobby Monitor
# Evaluates scheduled games in Supabase for:
#   1. Low-quorum alert decision email dispatch to the organizer at kickoff
#   2. Low-quorum automatic cancellation once grace period expires (AUTO_CANCEL)
#   3. Autonomous game kickoff when quorum is reached (isAutonomousHostEnabled)
#   4. Low-quorum auto-start when configured (START_ANYWAY)

import json
import math
import os
import sys
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

sys.path.insert(0, os.path.dirname(__file__))

from db import get_supabase
from email_ses import send_low_quorum_decision_email


def evaluate_scheduled_games() -> Dict[str, Any]:
    """
    Main evaluation routine. Fetches all OPEN games with scheduled_at,
    evaluates attendance against quorum and grace period, and takes appropriate action.
    """
    sb = get_supabase()
    if not sb:
        return {"status": "error", "message": "Database client unavailable"}

    now = datetime.now(timezone.utc)
    summary = {
        "status": "ok",
        "evaluated_at": now.isoformat(),
        "games_inspected": 0,
        "emails_sent": [],
        "games_cancelled": [],
        "games_launched": [],
    }

    try:
        # Fetch open scheduled games
        res = (
            sb.from_("MPT_games")
            .select("id, name, invite_code, admin_user_id, status, funded_capacity, scheduled_at, prize_gifts_config")
            .eq("status", "OPEN")
            .not_.is_("scheduled_at", "null")
            .execute()
        )
        games = res.data or []
        summary["games_inspected"] = len(games)

        for g in games:
            raw_sched = g.get("scheduled_at")
            if not raw_sched:
                continue

            try:
                # Handle various ISO string formats (with Z or +00:00)
                sched_clean = raw_sched.replace("Z", "+00:00")
                sched_dt = datetime.fromisoformat(sched_clean)
                if sched_dt.tzinfo is None:
                    sched_dt = sched_dt.replace(tzinfo=timezone.utc)
            except Exception as e:
                print(f"  [ SCHEDULER ] Failed to parse scheduled_at for {g.get('invite_code')}: {e}")
                continue

            # Only act if scheduled kickoff time has arrived or passed
            if now < sched_dt:
                continue

            prize_gifts = g.get("prize_gifts_config") or {}
            dabby_config = prize_gifts.get("_dabby_orchestration") or {}

            # Parse quorum configuration
            funded_capacity = int(g.get("funded_capacity") or 5)
            quorum_pct = float(dabby_config.get("quorum_percentage") or 0.67)
            quorum_count = dabby_config.get("quorum_count")
            if quorum_count is None:
                quorum_count = math.ceil(quorum_pct * funded_capacity) if quorum_pct > 0 else 1
            else:
                quorum_count = int(quorum_count)

            grace_minutes = int(dabby_config.get("grace_period_minutes") or 5)
            low_quorum_action = str(dabby_config.get("low_quorum_action") or "AUTO_CANCEL").upper()
            autonomous_enabled = dabby_config.get("autonomous_host_enabled", True)
            decision_email_sent_at = dabby_config.get("decision_email_sent_at")

            # Count confirmed players in lobby
            reg_res = (
                sb.from_("MPT_game_registrations")
                .select("id", count="exact")
                .eq("game_id", g["id"])
                .eq("seat_status", "CONFIRMED")
                .execute()
            )
            confirmed_count = reg_res.count or 0

            is_low_quorum = confirmed_count < quorum_count
            grace_deadline = sched_dt + timedelta(minutes=grace_minutes)
            is_grace_passed = now >= grace_deadline

            # ── Scenario A: Low Quorum at / after Kickoff ───────────────────
            if is_low_quorum:
                # 1. Send decision email once
                if not decision_email_sent_at:
                    host_email = _get_host_email(sb, g.get("admin_user_id"))
                    if host_email:
                        # Format kickoff time label
                        sched_str = sched_dt.strftime("%b %d, %I:%M %p UTC")
                        email_sent = send_low_quorum_decision_email(
                            to_email=host_email,
                            game_name=g.get("name") or "Scheduled Game",
                            game_id=g["id"],
                            invite_code=g.get("invite_code") or "",
                            confirmed_count=confirmed_count,
                            quorum_count=quorum_count,
                            scheduled_at_str=sched_str,
                            grace_period_minutes=grace_minutes,
                            organizer_name="Event Organizer",
                        )
                        if email_sent:
                            # Persist decision_email_sent_at into prize_gifts_config._dabby_orchestration
                            dabby_config["decision_email_sent_at"] = now.isoformat()
                            prize_gifts["_dabby_orchestration"] = dabby_config
                            sb.from_("MPT_games").update({
                                "prize_gifts_config": prize_gifts
                            }).eq("id", g["id"]).execute()

                            summary["emails_sent"].append({
                                "invite_code": g.get("invite_code"),
                                "to_email": host_email,
                                "confirmed": confirmed_count,
                                "quorum": quorum_count,
                            })
                            print(f"  [ SCHEDULER ] Sent decision email to {host_email} for game {g.get('invite_code')}")

                # 2. Check if grace period buffer has elapsed
                if is_grace_passed:
                    if low_quorum_action == "AUTO_CANCEL":
                        sb.from_("MPT_games").update({
                            "status": "CANCELLED",
                            "is_publicly_visible": False,
                            "completed_at": now.isoformat(),
                        }).eq("id", g["id"]).execute()

                        summary["games_cancelled"].append({
                            "invite_code": g.get("invite_code"),
                            "reason": f"Low quorum ({confirmed_count}/{quorum_count}) after {grace_minutes}m grace",
                        })
                        print(f"  [ SCHEDULER ] Auto-cancelled game {g.get('invite_code')} due to unmet quorum")

                    elif low_quorum_action == "START_ANYWAY" and autonomous_enabled:
                        sb.from_("MPT_games").update({
                            "status": "IN_PROGRESS",
                            "started_at": now.isoformat(),
                        }).eq("id", g["id"]).execute()

                        summary["games_launched"].append({
                            "invite_code": g.get("invite_code"),
                            "reason": "START_ANYWAY low quorum action",
                        })
                        print(f"  [ SCHEDULER ] Launched game {g.get('invite_code')} anyway under START_ANYWAY policy")

            # ── Scenario B: Quorum Met at Kickoff ────────────────────────────
            else:
                if autonomous_enabled:
                    sb.from_("MPT_games").update({
                        "status": "IN_PROGRESS",
                        "started_at": now.isoformat(),
                    }).eq("id", g["id"]).execute()

                    summary["games_launched"].append({
                        "invite_code": g.get("invite_code"),
                        "reason": f"Quorum reached ({confirmed_count}/{quorum_count}) with autonomous host",
                    })
                    print(f"  [ SCHEDULER ] Autonomous kickoff for game {g.get('invite_code')} ({confirmed_count}/{quorum_count})")

    except Exception as e:
        import traceback
        traceback.print_exc()
        summary["status"] = "error"
        summary["error"] = str(e)

    return summary


def _get_host_email(sb: Any, user_id: Optional[str]) -> Optional[str]:
    """Helper to look up host email from MPT_admin_profiles."""
    if not user_id:
        return None
    try:
        prof = (
            sb.from_("MPT_admin_profiles")
            .select("email")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if prof and prof.data and prof.data.get("email"):
            return prof.data["email"].strip()
    except Exception as e:
        print(f"  [ SCHEDULER ] Failed looking up admin email for user {user_id}: {e}")
    return None


def handler(event, context):
    """
    AWS Lambda entry point. Triggered by EventBridge CloudWatch schedule
    or direct API Gateway invocation.
    """
    result = evaluate_scheduled_games()
    return {
        "statusCode": 200 if result.get("status") == "ok" else 500,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(result),
    }


if __name__ == "__main__":
    res = evaluate_scheduled_games()
    print(json.dumps(res, indent=2))
