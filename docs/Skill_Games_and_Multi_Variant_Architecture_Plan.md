# DabHousie Next-Gen Platform Plan: FlashHousie™ (5 / 10 / 15) & NeuroWave™ Engine

**Document Version:** 5.2 (Finalized Spec — `FlashHousie™` & `NeuroWave™`)  
**Date:** September 26, 2026  
**Prepared For:** Digital App Studio — Architecture & Product Review  
**Branch:** `memory-bingo` (`main` locked for production)  

---

## 1. Executive Summary & Core Design Decisions

**Digital App Studio's FlashHousie™ (`FlashHousie 5`, `FlashHousie 10`, `FlashHousie 15` — internal code `Bingo5 / Bingo10 / Bingo15`)** transforms the classic $3 \times 9$ web Tambola card into a **100% Pure-Skill, Zero-Question-Bank Multiplayer Memory & Reflex Game**:

> **PUBLIC UI vs. INTERNAL DOCS RULE:**  
> - **Internal Engineering Rationale:** The **Random Suspense Trigger + Column-by-Column Wave** is designed as an **anti-photo / anti-screenshot defense** (because all 5 or 9 numbers are never visible on screen in the same frame, and the random launch after the 5th second defeats camera timing).  
> - **Public Web UI & Player Copy:** **Never mention "anti-photo", "anti-screenshot", or "cheating" on any public page or in-app label** so we never give players hints or ideas to try workarounds. On all public UI/guides, present it strictly under its clean proprietary name: **`NeuroWave™`** (or **`NeuroWave™ Spotlight`**).

1. **Zero Luck (Symmetric Competition):** Every player in the room receives the **exact same $3 \times 9$ ticket matrix**. Winning depends strictly on **Working Memory + Spatial Column Recall + Reaction Speed**.
2. **Full $3 \times 9$ Card Layout Preserved (Minimal Backend & CI/CD Footprint):**
   - Players always see the familiar $3 \times 9$ card (`Q1: Cols 1–3`, `Q2: Cols 4–6`, `Q3: Cols 7–9`).
   - Active quadrant(s) for the current cycle are highlighted while inactive quadrants are visually dimmed (`opacity: 0.35`).
   - One single $3 \times 9$ ticket in `MPT_player_tickets` powers all 3 quadrant rounds toward Full House with zero duplicate ball conflicts in `MPT_called_numbers`.
3. **Proprietary `NeuroWave™` Spotlight (Internal Anti-Photo / Anti-Screenshot Engine):**
   - **Random Suspense Trigger (`10–15s` timer):** Launches the reveal unpredictably at a random second after the `5th second` (prevents timing a camera shot).
   - **Column-by-Column Wave:** Within each active quadrant, **only 1 column is visible at any instant** (`Col 1` for `1.8s` $\rightarrow$ `Col 2` for `1.8s` $\rightarrow$ `Col 3` for `1.8s`), masking each column (`?`) as it advances. No single screenshot or photo ever captures the full quadrant.
   - **Memory Consolidation Interval (for `FlashHousie 10` & `FlashHousie 15`):** Each active quadrant completes its `NeuroWave™` sweep followed by a **5-second Memory Lock-In Pause** before the next quadrant spotlight begins.
4. **Multi-Cycle Round Prizes (`Rx-Qx`) + Cumulative Grand Prizes (`Full House`):**
   - **Host Selects Cycles ($R$):** Each cycle crowns a **Round Winner (`Rx-Qx` Minor Prize)** based on **Max Correct Recalls** (tiebreaker: fewest wrong/decoy taps $\rightarrow$ fastest cumulative tap speed).
   - **1st & 2nd Full House (Grand Prizes):** Awarded at the end of all cycles to the players with the **Maximum Cumulative Correct Numbers across all rounds combined**.
5. **Option-B Live TV Board (`MPT_memory_round_scores`):**
   - Powered by the standalone additive table ([MPT_memory_round_scores_migration.sql](file:///c:/dev/Tambola/docs/sql/MPT_memory_round_scores_migration.sql)), preserving the Live TV / Projector Display USP with real-time fastest-recall tickers, round leaderboards, and cumulative Full House standings.

---

## 2. Mode Breakdown (`FlashHousie™ 5`, `FlashHousie™ 10`, `FlashHousie™ 15`)

| Public Mode Name (Internal Code) | Active Quadrants per Cycle | Occupied Cells per Quadrant | Caller Ball Pool per Cycle (`True` + `1–2 Decoys/Col`) | `NeuroWave™` Spotlight Sequence (Internal Anti-Photo Wave) |
| :--- | :--- | :--- | :--- | :--- |
| **FlashHousie™ 5** (`Bingo5`) | **1 Quadrant** (`Q1`, `Q2`, *or* `Q3`) | **5 of 9 cells** *(or **9 of 9** in Full mode)* | **8–9 balls** (`5` true + `3–4` decoys)<br>*(Full: `9` true + `3–5` decoys = `12–14` balls)* | Random Suspense (`>5s`) $\rightarrow$ `Col 1` (`1.8s`) $\rightarrow$ `Col 2` (`1.8s`) $\rightarrow$ `Col 3` (`1.8s`) |
| **FlashHousie™ 10** (`Bingo10`) | **2 Quadrants** (`Q1+Q2`, `Q1+Q3`, *or* `Q2+Q3`) | **10 of 18 cells** ($5+5$)<br>*(or **18 of 18** in Full mode)* | **16–18 balls** (`10` true + `6–8` decoys) | `Quad A` `NeuroWave™` (`5.4s`) $\rightarrow$ **5s Memory Pause** $\rightarrow$ `Quad B` `NeuroWave™` (`5.4s`) |
| **FlashHousie™ 15** (`Bingo15`) | **All 3 Quadrants** (`Q1 + Q2 + Q3`) | **15 of 27 cells** ($5+5+5$)<br>*(or **27 of 27** in Full mode)* | **24–27 balls** (`15` true + `9–12` decoys) | `Q1` `NeuroWave™` (`5.4s`) $\rightarrow$ **5s Pause** $\rightarrow$ `Q2` `NeuroWave™` (`5.4s`) $\rightarrow$ **5s Pause** $\rightarrow$ `Q3` `NeuroWave™` (`5.4s`) |

---

## 3. End-to-End Gameplay Sequence

```mermaid
sequenceDiagram
    participant Host as Host / Auto-Pilot Caller
    participant Server as Supabase (MPT_games + MPT_memory_round_scores)
    participant Web as Player Web Screen (3x9 Card)
    participant TV as Live TV Board (LiveGameDisplayScreen)

    loop For Each Cycle Rx (Round 1 .. Round N)
        Note over Host,TV: 1. Highlight Active Quadrant(s) on 3x9 Card (Rx-Qx)
        Server->>Web: Sync active quadrant(s); dim inactive quadrants (opacity 0.35)
        
        Note over Web: 2. NeuroWave™ Spotlight (Internal Anti-Photo: Random Trigger + 1 Col at a time)
        Web->>Web: 10–15s Suspense Timer -> Triggers randomly after 5th second
        Web->>Web: NeuroWave™ Col 1 (1.8s) -> Lock [?] -> Col 2 (1.8s) -> Lock [?] -> Col 3 (1.8s) -> Lock [?]
        Note over Web: (If FlashHousie 10/15: 5s Memory Consolidation Pause before next Quadrant Wave)

        Note over Host,TV: 3. True + Decoy Ball Calling Loop (1–2 Decoys/Col)
        Host->>Server: Draw next ball from Rx pool
        Server->>Web: Announce Ball (e.g., "Number 24!")
        Server->>TV: Show Ball 24 + Live Recall Ticker
        
        alt Player clicks CORRECT hidden cell [row, col] for 24
            Web->>Server: Upsert MPT_memory_round_scores (+1 correct, +reaction_ms)
            Web->>Web: Flip cell permanently open [ 24 ✅ ]
            Server->>TV: Update Live Round & Full House Leaderboards
        else Player clicks WRONG cell OR clicks on a DECOY ball
            Web->>Web: Trigger 3-Second Freeze Lockout (❄️ "3s Cooldown")
            Web->>Server: Increment wrong_tap_count in MPT_memory_round_scores
        end

        Note over Host,TV: 4. End of Cycle Rx -> Crown Round Winner (Rx-Qx)
        Server->>TV: Announce Round Rx-Qx Winner (Max Correct -> Fewest Wrong -> Fastest ms)
    end

    Note over Host,TV: 5. End of Final Cycle -> Crown 1st & 2nd Full House Champions!
    Server->>TV: Sum correct_count across all cycles -> Award Full House Vouchers!
```

---

## 4. Implementation Checklist (`memory-bingo` Branch)

1. **Database Setup ([MPT_memory_round_scores_migration.sql](file:///c:/dev/Tambola/docs/sql/MPT_memory_round_scores_migration.sql)):**
   - Run the additive SQL script in Supabase SQL Editor to create `public."MPT_memory_round_scores"`.
2. **Ticket & Pool Generator ([`TambolaTicketHelper`](file:///c:/dev/Tambola/lib/core/utils/tambola_ticket.dart)):**
   - Add deterministic symmetric $3 \times 9$ generator (5-cell standard & 9-cell full quadrant modes) + `True + 1–2 Decoys/Col` caller pool builder.
3. **Host Game Setup ([`CreateGameScreen`](file:///c:/dev/Tambola/lib/features/game_setup/screens/create_game_screen.dart)):**
   - Add Game Mode selector (`Classic 90-Ball`, `FlashHousie™ 5`, `FlashHousie™ 10`, `FlashHousie™ 15`), Cycle selector (`2–6 Cycles`), and dynamic `Rx-Qx` + `Full House` prize labels.
4. **Player Web UI ([`PlayerTicketScreen`](file:///c:/dev/Tambola/lib/features/gameplay/screens/player_ticket_screen.dart)):**
   - Keep the $3 \times 9$ card layout; add Quadrant headers, inactive quadrant dimming, the **`NeuroWave™` Spotlight** timer (internal random suspense + column wave), `?` masked tiles, and the **3-second freeze**.
5. **Admin & Live TV Display ([`AdminGameControlScreen`](file:///c:/dev/Tambola/lib/features/gameplay/screens/admin_game_control_screen.dart) & [`LiveGameDisplayScreen`](file:///c:/dev/Tambola/lib/features/live_display/screens/live_game_display_screen.dart)):**
   - Restrict caller draws to the active cycle's `True + Decoy` pool, advance cycles, and display the real-time **`Rx-Qx` Round Leaderboard** and **Cumulative Full House Leaderboard** on the Live TV screen.
