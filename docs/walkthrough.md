# Walkthrough: Multiplayer Tambola Mobile Application (Flutter / Android & iOS)

We have implemented the complete cross-platform **Multiplayer Tambola Mobile App** adhering to all frozen product decisions, identity rules (Master README v1.2 & Document 9), and database namespace isolation requirements (`MPT_`).

---

## 1. Key Accomplishments

### Database Architecture & Strict `MPT_` Isolation
All tables, views, and RPC functions use the `MPT_` namespace to ensure coexistence and isolation within your shared Supabase project:
- [20260901000001_mpt_core_schema.sql](file:///c:/dev/Tambola/supabase/migrations/20260901000001_mpt_core_schema.sql):
  - Tables: `MPT_users`, `MPT_admin_profiles`, `MPT_capacity_tiers`, `MPT_admin_wallets`, `MPT_credit_transactions`, `MPT_games`, `MPT_game_registrations`, `MPT_player_tickets`, `MPT_game_charges`, `MPT_called_numbers`, `MPT_claims`, `MPT_rewards`, `MPT_notifications`.
  - Indexes & Row Level Security (RLS) policies for secure multi-tenant access.
- [20260901000002_mpt_functions_and_rpcs.sql](file:///c:/dev/Tambola/supabase/migrations/20260901000002_mpt_functions_and_rpcs.sql):
  - `MPT_upsert_user`: Synchronizes anonymous player profile.
  - `MPT_create_game`: Generates 6-character alphanumeric invite code and initializes game.
  - `MPT_register_player`: Server-authoritative sequence assignment with automatic `CONFIRMED` vs `WAITING` assignment.
  - `MPT_increase_game_capacity`: Promotes `WAITING` players First-Come-First-Served (FCFS) by sequence and publishes `SEAT_CONFIRMED` notifications.
  - `MPT_add_mock_credits`: Ledger-backed mock top-up for testing.
  - `MPT_start_game_and_charge`: Atomic transaction that charges credits, freezes capacity, promotes confirmed seats to `ELIGIBLE`, and generates 3x9 tickets.
  - `MPT_call_next_number`: Authoritative server caller broadcasting numbers (1–90).
- [20260901000003_mpt_claims_and_rewards_rpc.sql](file:///c:/dev/Tambola/supabase/migrations/20260901000003_mpt_claims_and_rewards_rpc.sql):
  - `MPT_submit_claim`: Validates marked numbers against authoritative called numbers (detects Bogey vs Valid claims) and generates unique voucher reference codes.
  - `MPT_verify_reward`: Admin reward verification interface.

---

### Core Flutter Mobile Implementation
- **Configuration & Environment**: [AppConfig](file:///c:/dev/Tambola/lib/core/config/app_config.dart) loads credentials from `.env` or `--dart-define` with configurable web purchase URL.
- **Theme**: [AppTheme](file:///c:/dev/Tambola/lib/core/theme/app_theme.dart) provides celebratory, high-contrast dark theme optimized for mobile and projector screens.
- **Ticket Engine**: [TambolaTicketHelper](file:///c:/dev/Tambola/lib/core/utils/tambola_ticket.dart) manages 3x9 grid rules, vertical column ordering, and pattern validation (Early 5, Top/Middle/Bottom Line, Four Corners, Full House).
- **State Management**: [app_providers.dart](file:///c:/dev/Tambola/lib/providers/app_providers.dart) with Riverpod and Supabase Realtime stream bindings.
- **Declarative Navigation**: [app_router.dart](file:///c:/dev/Tambola/lib/router/app_router.dart) with GoRouter deep linking.

---

### Feature Screens & User Flows

1. **Home Screen** ([home_screen.dart](file:///c:/dev/Tambola/lib/features/home/screens/home_screen.dart)):
   - Anonymous player profile bar with avatar/display name editor.
   - Action cards for **Join Game** and **Create Game**.
   - Admin wallet credits summary and quick navigation to Rewards & Verification.
2. **Game Setup** ([create_game_screen.dart](file:///c:/dev/Tambola/lib/features/game_setup/screens/create_game_screen.dart)):
   - Event name, capacity tier selection (1–25, 26–50, 51–100, 101–250), and customizable winning prize rules.
   - Generates invite code with one-tap clipboard copy.
3. **Join Game** ([join_game_screen.dart](file:///c:/dev/Tambola/lib/features/registration/screens/join_game_screen.dart)):
   - Invite code lookup with live game preview and display profile confirmation.
4. **Registration Status** ([registration_status_screen.dart](file:///c:/dev/Tambola/lib/features/registration/screens/registration_status_screen.dart)):
   - Clear, unambiguous distinction between `SEAT CONFIRMED` (green card with registration #) and `WAITING FOR ADMIN CONFIRMATION` (amber card with queue position).
   - Real-time listener: When Admin expands capacity, screen automatically updates to `SEAT CONFIRMED!`.
5. **Admin Lobby** ([admin_lobby_screen.dart](file:///c:/dev/Tambola/lib/features/admin_lobby/screens/admin_lobby_screen.dart)):
   - Live metrics (Registered, Confirmed, Waiting, Capacity, Credits).
   - Capacity warning alert when overflow players are waiting.
   - "+25 Seats Capacity" and "+200 Mock Credits" buttons.
   - "Start Game & Deduct Credits" button.
6. **Player Ticket Screen** ([player_ticket_screen.dart](file:///c:/dev/Tambola/lib/features/gameplay/screens/player_ticket_screen.dart)):
   - Interactive 3x9 grid ticket with tap-to-dab numbers.
   - Latest called ball banner and past called carousel.
   - Instant prize claim buttons with server validation and Bogey detection.
7. **Admin Game Control Screen** ([admin_game_control_screen.dart](file:///c:/dev/Tambola/lib/features/gameplay/screens/admin_game_control_screen.dart)):
   - Number caller button with 1–90 master board matrix and claims queue.
8. **Admin Wallet & Web Checkout** ([wallet_screen.dart](file:///c:/dev/Tambola/lib/features/wallet/screens/wallet_screen.dart)):
   - Credit balance, validity policy (1 year from most recent paid game), pricing tier table, transaction ledger, and external web checkout handoff.
9. **Rewards & Verification** ([rewards_screen.dart](file:///c:/dev/Tambola/lib/features/rewards/screens/rewards_screen.dart), [verify_reward_screen.dart](file:///c:/dev/Tambola/lib/features/rewards/screens/verify_reward_screen.dart)):
   - In-app rewards list with server-generated voucher reference codes and QR codes.
   - Admin voucher lookup and verification screen.
10. **Live Display (Projector Screen)** ([live_game_display_screen.dart](file:///c:/dev/Tambola/lib/features/live_display/screens/live_game_display_screen.dart)):
    - Responsive big-screen view displaying the master board, animated current ball, and live winners ticker.

---

## 2. Test Verification

Automated unit tests verified:
- **Tambola Ticket Generator & Pattern Engine**: Validated 3x9 grid rules, exactly 5 numbers per row, column limits, and winning conditions (Early 5, Top Line, Middle Line, Bottom Line, Four Corners, Full House).
- **Models & Serialization**: Validated JSON serialization for `MptUser`, `MptGame`, `MptRegistration`, `MptWallet`, `MptTicket`, and `MptReward`.
- **App Theme**: Tested Material 3 dark theme tokens and contrast ratios.

```
00:00 +0: C:/dev/Tambola/test/unit/models_test.dart: MptUser serialization
00:00 +1: C:/dev/Tambola/test/unit/models_test.dart: MptGame state logic
00:00 +2: C:/dev/Tambola/test/unit/models_test.dart: MptRegistration seat status checks
00:00 +3: C:/dev/Tambola/test/unit/models_test.dart: MptWallet balance and transactions
00:00 +4: C:/dev/Tambola/test/unit/models_test.dart: MptReward voucher reference
00:00 +5: C:/dev/Tambola/test/unit/tambola_ticket_test.dart: 3x9 grid structure (15 numbers)
00:00 +6: C:/dev/Tambola/test/unit/tambola_ticket_test.dart: Winning patterns detection
00:00 +7: C:/dev/Tambola/test/widget_test.dart: App theme smoke test
00:00 +8: All tests passed!
```

---

## 3. Applying Migrations to Your Supabase Project

To execute the migrations in your existing Supabase project:
1. Open your Supabase Dashboard -> **SQL Editor**.
2. Run the SQL scripts in order:
   - `supabase/migrations/20260901000001_mpt_core_schema.sql`
   - `supabase/migrations/20260901000002_mpt_functions_and_rpcs.sql`
   - `supabase/migrations/20260901000003_mpt_claims_and_rewards_rpc.sql`
3. Update your `.env` file in `c:\dev\Tambola\.env` with your project URL and public anon key:
   ```env
   SUPABASE_URL=https://your-project.supabase.co
   SUPABASE_ANON_KEY=your-supabase-anon-key
   ```
4. Run the app:
   ```bash
   flutter run
   ```
