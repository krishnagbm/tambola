# Feature: Quick Dabby — Mathematical Validation, Testing and Implementation

## Objective

Implement **Quick Dabby** as an optional host-selected calling mode in DabHousie, the existing 90-ball Tambola/Housie platform.

Before making code changes, inspect the existing architecture, ticket-generation algorithm, number-calling engine, claim validation, game lifecycle and host configuration.

**Important:** Do not assume the game requires all 90 numbers to be called. Do not change the rules, ticket structure, prize definitions or player-facing experience.

## 1. Existing Game Rules — Preserve Exactly

DabHousie uses 90-ball Tambola tickets:
- 3 rows × 9 columns.
- 15 numbers per ticket.
- 5 numbers per row.
- Standard existing ticket number distribution and validation rules.

The game has seven claims:
1. Early 5
2. Four Corners
3. Top Row
4. Middle Row
5. Bottom Row
6. First Full House
7. Second Full House

Use the actual existing definitions and claim-validation implementation. Do not recreate or approximate these rules.

Preserve claim eligibility, duplicate-claim prevention, winner verification, prize allocation, event logging, result display and game-ending behavior.

## 2. Host Configuration

Add a host-only calling-mode choice during game creation or in the existing appropriate host configuration screen.

**Classic Calling**
- Existing behavior.
- Draw numbers from the complete 1–90 pool.
- No behavioral changes whatsoever.

**Quick Dabby**
- Build a pool from the union of the 15 numbers on every eligible ticket participating in the game.
- Remove duplicate numbers across tickets.
- Shuffle the resulting unique-number pool fairly.
- Call numbers without replacement from that shuffled pool.
- Use the existing number-calling interface, announcements, ticket marking, claim validation and game lifecycle.

Only the host needs to know which calling mode is selected. Do not expose the optimization, hidden number pool or internal algorithm to players.

Set Classic Calling as the default for existing and new games unless the host explicitly selects Quick Dabby.

Persist the mode using the existing game configuration and storage conventions. Ensure reconnects, refreshes and resumed games retain the selected mode and current draw state.

## 3. Mathematical Basis

For N tickets, there are 15N number entries, but the unique-number pool cannot exceed 90.

Let U be the set of all numbers appearing on eligible tickets.

- Classic pool: {1, 2, ..., 90}
- Quick Dabby pool: U
- Quick Dabby pool size: |U|, between 15 and 90 for one or more valid tickets.

Every number required to complete a pattern on an eligible ticket is in U. Therefore, eliminating numbers outside U cannot prevent that ticket's existing number-based patterns from being completed.

However, do not assume the game finishes in 40–45 calls. The actual number of calls required to complete all seven claims depends on ticket composition, number overlap, the order of calls and claim/game-ending logic.

**Critical distinction:** A reduced pool does not automatically mean the same number of calls is saved. Measure the actual finishing-call count under the real game rules.

## 4. Required Mathematical Simulation Before Implementation

Build a reproducible simulation or test harness using the actual DabHousie ticket-generation logic and claim definitions wherever possible.

Test at least these player counts:
- 2
- 5
- 10
- 20
- 50
- 100

If the platform supports multiple tickets per player, include representative configurations and clearly distinguish players from tickets.

For each generated game:
1. Generate valid tickets using the actual production ticket generator.
2. Create a Classic draw by randomly shuffling all 90 numbers.
3. Create a Quick Dabby draw by randomly shuffling the union of all ticket numbers.
4. Apply the same ticket marking and winning-claim logic to both modes.
5. Track when each of the seven claims is completed.
6. Stop according to the existing game's actual termination rules, including the second Full House.
7. Record the number of calls and simulated calling time for each mode.

Run at least 10,000 randomized games per configuration, preferably 100,000 where practical. Use reproducible seeds, report the sample size and verify that the simulation agrees with production behavior.

For each player-count configuration, report:
- Average and median number of calls in both modes.
- 10th and 90th percentile call counts.
- Average unique-number pool size.
- Percentage of games where the union contains all 90 numbers.
- Average calling time at 10 seconds per call.
- Average time saved in seconds and as a percentage.
- Percentage of games in which Quick Dabby actually reduces the number of calls.
- Completion statistics for each of the seven claims.
- Any games that fail to reach all seven claims or expose an existing game-ending limitation.

Calculate percentage savings as:

Savings % = (Classic calls − Quick Dabby calls) / Classic calls × 100

Use paired comparisons on the same generated tickets wherever possible. Use independent, valid randomized draw orders for each mode and clearly document the methodology.

Do not invent results, hardcode expected outcomes or present theoretical estimates as measured simulation data.

## 5. Important Edge Cases

Test the following:
- Multiple tickets share the same numbers.
- Every number from 1–90 appears across the participating tickets.
- Small games where the unique pool is substantially below 90.
- Large games where the pool approaches or equals 90.
- Claims completed by the same call.
- Early 5 and Four Corners eligibility under existing rules.
- Both Full House prizes and multiple simultaneous winning conditions.
- Duplicate claims, rejected claims and late claims.
- Disconnected or reconnected players.
- Ticket changes, ticket additions or removals before and after the draw begins.
- No valid tickets, invalid tickets or malformed game configuration.
- Draw exhaustion, retries, refreshes and resumed games.

Freeze the eligible-ticket set at the appropriate existing game-start boundary. Never rebuild or shrink the pool in a way that changes the draw unfairly after the game starts.

If the game permits tickets to join after the draw begins, follow existing admission rules and design a safe, explicit policy for Quick Dabby. Do not silently exclude eligible tickets or alter a started draw.

## 6. Fairness and Security

- Use the project's existing secure random-number-generation approach where appropriate.
- Ensure the Quick Dabby sequence is uniformly shuffled without replacement.
- Do not favor any player or ticket.
- Never reveal the remaining pool to players.
- Do not allow clients to alter the calling mode, number sequence or winning status.
- Perform authoritative draw and claim validation on the trusted side of the application, consistent with the existing architecture.
- Preserve auditability and existing anti-cheating protections.
- Confirm that a number absent from every eligible ticket cannot contribute to any of the seven number-based claims.

If any existing claim or game-ending rule depends on something other than ticket numbers, investigate it before implementing the reduced pool.

## 7. Host UI and Disclaimer

Add the following copy near the host's calling-mode selection:

**Classic Calling**
Traditional 90-ball number calling.

**Quick Dabby ⚡**
Calls only numbers appearing on participating tickets, helping reduce waiting time.

Disclaimer:
“Quick Dabby may reduce calling time by up to 50%, particularly in games with fewer players. Actual time savings depend on the number of players, ticket numbers and winning claims. No time saving is guaranteed.”

Keep the UI consistent with the existing DabHousie design. Do not redesign unrelated screens or alter the official Dabby mascot or branding.

The “up to 50%” figure is a proposed marketing statement, not a verified result. Compare it against the completed simulation. If the evidence does not support it, flag this to the developer and recommend revised wording rather than silently treating it as proven.

## 8. Regression Testing

Confirm that Classic Calling remains unchanged for existing games.

Run regression tests for:
- All seven claims and winner validation.
- Ticket marking and number announcements.
- Host controls and game creation.
- Game persistence, reconnection and recovery.
- Simultaneous claims and Full House resolution.
- Existing credit handling and event completion.
- Mobile and desktop interfaces.
- Existing reporting and audit data.

Do not modify unrelated game logic, pricing, credits or player access.

## 9. Deliverables

Before implementation, provide a brief architecture assessment and identify the exact files/functions involved.

Then implement the feature, subject to the project's normal workflow, and provide:

1. Files changed and a concise description of each change.
2. The simulation methodology and assumptions.
3. A results table for all tested player counts.
4. Actual average calls and time savings for each mode.
5. Automated tests added and their results.
6. Any discovered limitations or unresolved edge cases.
7. Confirmation that Classic Calling is unchanged.
8. A recommendation on whether the “up to 50%” disclaimer is supported by evidence.

Do not claim that tests passed unless they were actually executed. Do not deploy to production, migrate production data or make unrelated changes without authorization.

**Implementation principle:** Preserve DabHousie's existing game rules and player experience. Quick Dabby is an optimization of the calling-number pool, not a different game.