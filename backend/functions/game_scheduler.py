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
import time
from datetime import datetime, timezone, timedelta
from typing import Dict, Any, List, Optional

sys.path.insert(0, os.path.dirname(__file__))

from db import get_supabase
from email_ses import send_low_quorum_decision_email, send_scheduled_game_cancelled_email


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

            # HARD SAFEGUARD: Minimum quorum must ALWAYS be at least 1 player (playing with 0 participants makes no sense)
            quorum_count = max(1, quorum_count)

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

            # Low quorum if below threshold OR if 0 players in room
            is_low_quorum = confirmed_count < quorum_count or confirmed_count < 1
            grace_deadline = sched_dt + timedelta(minutes=grace_minutes)
            is_grace_passed = now >= grace_deadline

            # ── Scenario A: Low Quorum at / after Kickoff ───────────────────
            if is_low_quorum:
                # 1. Send decision email once AFTER grace period buffer (e.g. 3 minutes) has elapsed
                if is_grace_passed and not decision_email_sent_at:
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
                            print(f"  [ SCHEDULER ] Sent decision email to {host_email} for game {g.get('invite_code')} after {grace_minutes}m buffer")

                # 2. Check if the 10th minute from scheduled kickoff has elapsed
                cancel_deadline = sched_dt + timedelta(minutes=max(10, grace_minutes))
                is_10th_minute_passed = now >= cancel_deadline

                if is_10th_minute_passed:
                    if confirmed_count < 1 or low_quorum_action == "AUTO_CANCEL":
                        sb.from_("MPT_games").update({
                            "status": "CANCELLED",
                            "is_publicly_visible": False,
                            "completed_at": now.isoformat(),
                        }).eq("id", g["id"]).execute()

                        reason = (
                            "No participants joined the room during the scheduled start time and 10-minute waiting window."
                            if confirmed_count < 1
                            else f"Player quorum was not reached ({confirmed_count}/{quorum_count} players) after 10-minute window."
                        )

                        summary["games_cancelled"].append({
                            "invite_code": g.get("invite_code"),
                            "reason": reason,
                        })
                        print(f"  [ SCHEDULER ] Auto-cancelled game {g.get('invite_code')} at 10th minute ({reason}).")

                        # Dispatch cancellation email to host
                        host_email = _get_host_email(sb, g.get("admin_user_id"))
                        if host_email:
                            sched_str = sched_dt.strftime("%b %d, %I:%M %p UTC")
                            send_scheduled_game_cancelled_email(
                                to_email=host_email,
                                game_name=g.get("name") or "Scheduled Game",
                                game_id=g["id"],
                                invite_code=g.get("invite_code") or "",
                                scheduled_at_str=sched_str,
                                grace_period_minutes=grace_minutes,
                                organizer_name="Event Organizer",
                                reason=reason,
                            )
                            print(f"  [ SCHEDULER ] Sent cancellation email to {host_email} for game {g.get('invite_code')}")

                    elif low_quorum_action == "START_ANYWAY" and autonomous_enabled:
                        if confirmed_count >= 1:
                            # Start anyway with current participants
                            print(f"  [ SCHEDULER ] Launching game {g.get('invite_code')} with {confirmed_count} player(s) (START_ANYWAY).")
                            _start_game(sb, g["id"])

                            summary["games_launched"].append({
                                "invite_code": g.get("invite_code"),
                                "reason": "START_ANYWAY low quorum action",
                            })
                            print(f"  [ SCHEDULER ] Launched game {g.get('invite_code')} anyway under START_ANYWAY policy")
                        else:
                            print(f"  [ SCHEDULER ] Cannot launch game {g.get('invite_code')} with 0 players even under START_ANYWAY")

            # ── Scenario B: Quorum Met at Kickoff ────────────────────────────
            else:
                if autonomous_enabled and confirmed_count >= 1:
                    _start_game(sb, g["id"])

                    summary["games_launched"].append({
                        "invite_code": g.get("invite_code"),
                        "reason": f"Quorum reached ({confirmed_count}/{quorum_count}) with autonomous host",
                    })
                    print(f"  [ SCHEDULER ] Autonomous kickoff for game {g.get('invite_code')} ({confirmed_count}/{quorum_count})")

        # ── Step 2: 100% Autonomous Authoritative Cloud Calling ──────────────
        # Call balls for any active in-progress autonomous games every 15 seconds
        _auto_call_autonomous_games(sb, summary)

    except Exception as e:
        import traceback
        traceback.print_exc()
        summary["status"] = "error"
        summary["error"] = str(e)

    return summary


def _auto_call_autonomous_games(sb: Any, summary: Dict[str, Any]) -> None:
    """
    100% Autonomous Authoritative Cloud Caller for active in-progress games.
    Ensures games configured with autonomous host or scheduled runs never wait
    for a host browser to be open. Steps balls forward periodically (every ~15s).
    """
    try:
        # Fetch active in-progress games
        res = (
            sb.from_("MPT_games")
            .select("id, name, invite_code, status, prize_gifts_config")
            .eq("status", "IN_PROGRESS")
            .execute()
        )
        active_games = res.data or []
        summary["active_games_evaluated"] = len(active_games)
        if not active_games:
            return

        # Filter for autonomous enabled games
        auto_games = []
        for g in active_games:
            p_gifts = g.get("prize_gifts_config") or {}
            dabby_cfg = p_gifts.get("_dabby_orchestration") or {}
            # Autonomous if explicitly enabled or if scheduled game
            is_auto = dabby_cfg.get("autonomous_host_enabled", True)
            if is_auto:
                auto_games.append(g)

        summary["autonomous_games_running"] = len(auto_games)
        if not auto_games:
            return

        start_time = time.time()
        # In a 60s Lambda window, step through up to 3 balls spaced 15s apart
        for step in range(3):
            # Safe cutoff before Lambda timeout expires
            if time.time() - start_time > 40:
                break

            still_active = False
            for g in auto_games:
                game_id = g["id"]
                code = g.get("invite_code")

                # Check if Full House is already claimed and approved
                claims_res = (
                    sb.from_("MPT_claims")
                    .select("id")
                    .eq("game_id", game_id)
                    .eq("claim_type", "FULL_HOUSE")
                    .eq("status", "APPROVED")
                    .limit(1)
                    .execute()
                )
                if claims_res.data:
                    # Conclude game
                    sb.from_("MPT_games").update({
                        "status": "COMPLETED",
                        "completed_at": datetime.now(timezone.utc).isoformat(),
                    }).eq("id", game_id).execute()
                    print(f"  [ AUTONOMOUS CALLER ] Game {code} has Full House awarded. Game completed.")
                    continue

                # Authoritative server-side ball call via MPT_call_next_number RPC
                try:
                    call_res = sb.rpc("MPT_call_next_number", {"p_game_id": game_id}).execute()
                    call_data = call_res.data
                    if isinstance(call_data, dict):
                        if call_data.get("game_completed"):
                            print(f"  [ AUTONOMOUS CALLER ] Game {code} finished: {call_data.get('message')}")
                        else:
                            still_active = True
                            num = call_data.get("number")
                            seq = call_data.get("call_seq")
                            print(f"  [ AUTONOMOUS CALLER ] Called ball #{seq}: {num} for {code}")
                            summary.setdefault("numbers_called", []).append({
                                "invite_code": code,
                                "number": num,
                                "seq": seq,
                            })
                except Exception as err:
                    print(f"  [ AUTONOMOUS CALLER ] Ball call error for {code}: {err}")

            if not still_active:
                break

            # Standard 15-second pacing between numbers
            if step < 2:
                time.sleep(15)

    except Exception as e:
        print(f"  [ AUTONOMOUS CALLER ] Auto caller exception: {e}")


def _start_game(sb: Any, game_id: str) -> bool:
    """Authoritative game start via MPT_start_game_and_charge RPC with fallback."""
    try:
        sb.rpc("MPT_start_game_and_charge", {"p_game_id": game_id}).execute()
        print(f"  [ SCHEDULER ] MPT_start_game_and_charge RPC successfully executed for {game_id}")
        return True
    except Exception as e:
        print(f"  [ SCHEDULER ] MPT_start_game_and_charge RPC failed for {game_id}: {e}")
        try:
            sb.from_("MPT_games").update({
                "status": "IN_PROGRESS",
                "started_at": datetime.now(timezone.utc).isoformat(),
            }).eq("id", game_id).execute()
            return True
        except Exception as e2:
            print(f"  [ SCHEDULER ] Fallback direct status update failed for {game_id}: {e2}")
            return False


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
