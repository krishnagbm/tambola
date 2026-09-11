# Prompt for Antigravity — Mega-Event-Ready Ticket Issuance Path (logic only, no infra/capacity changes)

```
CONTEXT
We validated the ticket-collision math: the current generation algorithm and
uniqueness-retry pattern is mathematically sound at any realistic scale
(collision risk stays negligible even at N=100,000+ tickets compared against
each other). That part needs no change, ever.

The actual scaling gate is architectural, not mathematical: 
MPT_start_game_and_charge generates tickets for every ELIGIBLE player in a
single sequential loop inside one transaction, at the moment the organizer
hits "Start Game." That's fine at today's capacity tiers (max 250) but would
not hold up for a hypothetical future mega event (1000+ players in one game).

We are NOT changing capacity tiers, pricing, or infrastructure right now.
This task is purely: make the ticket-issuance LOGIC ready so that switching
a future large game onto a lazy/on-demand issuance path is a simple
threshold flip later, not a redesign done under pressure.

GOAL
Introduce a second, lazy/on-demand ticket issuance path alongside the
existing eager bulk path, gated by a capacity threshold constant — with
NO behavior change for any game at or under that threshold (i.e. every
game running today keeps working exactly as it does now).

REQUIRED FIX #1 — Unify ticket generation behind one server-side RPC
Currently there are two different, inconsistent ways a ticket gets created:
  a) Bulk path: MPT_start_game_and_charge loops over ELIGIBLE players and
     calls MPT_generate_ticket_matrix() server-side, with a per-game
     uniqueness check-and-retry loop (EXIT WHEN NOT EXISTS ... up to 100
     attempts), and sets ticket_number = registration_seq.
  b) Lazy/fallback path: GameplayRepository.getOrCreatePlayerTicket() (Dart)
     generates the ticket client-side via TambolaTicketHelper.generateTicket(),
     with NO per-game uniqueness check against already-issued tickets, and
     sets ticket_number = (count of existing tickets for the game) + 1.

These must be unified into ONE canonical path before any mega-event logic
is added, because the uniqueness guarantee only currently exists in (a).
Specifically:
  - Create a new RPC, e.g. MPT_get_or_create_player_ticket(p_game_id UUID),
    that: verifies the caller is ELIGIBLE for that game, returns the
    existing ticket if one already exists for (game_id, user_id), and
    otherwise generates one via MPT_generate_ticket_matrix() with the SAME
    per-game uniqueness check-and-retry loop already used in the bulk path
    (reuse that exact logic — do not reimplement it separately), assigns
    ticket_number = registration_seq (matching the bulk path's convention,
    not a count-based sequence), inserts, and returns it.
  - Update GameplayRepository.getOrCreatePlayerTicket() (Dart) to call this
    new RPC first, following the same RPC-first-then-direct-fallback
    pattern already used elsewhere in this repository class. The existing
    direct-table-insert code becomes the fallback only, same role the RPC
    fallback pattern plays elsewhere in the codebase — but note the
    fallback should also mirror the same registration_seq-based
    ticket_number and, if practical, a basic pre-insert existence check to
    reduce (not eliminate) the fallback's exposure to the missing-uniqueness
    gap. The RPC path is the one expected to run in the vast majority of
    cases.
  - The existing RLS policy MPT_player_tickets_insert_self already permits
    a player to insert their own ticket while ELIGIBLE — confirm this still
    covers the new RPC's insert (RPC runs as SECURITY DEFINER so this may
    not even apply, but verify no regression either way).

REQUIRED FIX #2 — Threshold-gated bulk generation
In MPT_start_game_and_charge:
  - Add a named constant, e.g. v_bulk_ticket_threshold INT := 300 (set
    comfortably above the current max capacity tier of 250, so this is a
    no-op for every game running today — confirm the exact value against
    current MPT_capacity_tiers max before finalizing).
  - If v_confirmed_count <= v_bulk_ticket_threshold: keep today's exact
    behavior — eager bulk loop generates all tickets at game start, unchanged.
  - If v_confirmed_count > v_bulk_ticket_threshold: SKIP the bulk
    ticket-generation loop entirely. Seat status transitions, credit
    charging, and game status transition to IN_PROGRESS still happen
    exactly as today. Tickets simply are not pre-generated — each player's
    client will call the new MPT_get_or_create_player_ticket RPC the first
    time they open PlayerTicketScreen, which already happens automatically
    today via playerTicketProvider -> getOrCreatePlayerTicket(). No new
    client-side trigger logic is needed for this part; it already exists,
    it just currently lacks the uniqueness guarantee fixed in #1 above.

WHAT NOT TO DO
  - Do not change MPT_capacity_tiers, pricing, or any organizer-facing
    capacity UI. This threshold is an internal implementation detail, not
    a currently-selectable game size.
  - Do not add any new user-facing option to "enable mega mode" — this is
    invisible plumbing for now, activated only by the threshold constant.
  - Do not touch polling intervals, claim logic, or infrastructure/scaling
    config — explicitly out of scope for this task.

ACCEPTANCE CHECK
  - A normal game (<=250 confirmed players, i.e. today's real-world range)
    behaves identically to today: tickets appear immediately in
    MPT_player_tickets right after game start, ticket_number =
    registration_seq, no client-side generation ever triggers.
  - Simulate the mega-event path in a test by temporarily lowering the
    threshold constant (do not change it permanently): confirm no tickets
    are bulk-created at game start above the threshold, confirm each
    player's client successfully lazy-generates a unique ticket on first
    ticket-screen load via the new RPC, confirm ticket_number still equals
    registration_seq (not a count-based value), and confirm two players
    who join in quick succession never receive colliding tickets (test
    with at least a handful of concurrent lazy requests, not just one).
  - flutter analyze and existing tests in test/ still pass; the existing
    tambola_ticket_test.dart uniqueness test is unaffected since it tests
    the Dart generator directly, not this RPC — note in your PR whether a
    companion SQL-side or integration test is warranted for the new RPC's
    uniqueness-retry behavior.
```
