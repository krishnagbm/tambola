# Technical Walkthrough: DabHousie™ Multiplayer Tambola Platform

*Last Updated: September 26, 2026*  
*Production URL: [https://www.dabhousie.com](https://www.dabhousie.com)*

We have implemented and deployed the complete cross-platform **DabHousie™ (Multiplayer Tambola, Housie & 90-Ball Bingo)** platform adhering to all product, security, identity, monetization, and database namespace isolation requirements (`MPT_`).

---

## 1. Key Architectural Accomplishments

### A. Database Architecture & Strict `MPT_` Isolation (33 Migrations)
All tables, views, triggers, and RPC functions use the `MPT_` namespace within Supabase PostgreSQL:
- **Core Schema & Gameplay Engine** ([20260901000001_mpt_core_schema.sql](file:///c:/dev/Tambola/supabase/migrations/20260901000001_mpt_core_schema.sql) – [20260914000001_sync_custom_capacity_tiers.sql](file:///c:/dev/Tambola/supabase/migrations/20260914000001_sync_custom_capacity_tiers.sql)):
  - Tables: `MPT_users`, `MPT_admin_profiles`, `MPT_capacity_tiers`, `MPT_admin_wallets`, `MPT_credit_transactions`, `MPT_games`, `MPT_game_registrations`, `MPT_player_tickets`, `MPT_game_charges`, `MPT_called_numbers`, `MPT_claims`, `MPT_rewards`, `MPT_notifications`.
  - Authoritative RPCs: `MPT_upsert_user`, `MPT_create_game`, `MPT_register_player`, `MPT_increase_game_capacity`, `MPT_start_game_and_charge`, `MPT_call_next_number`, `MPT_submit_claim`, `MPT_verify_reward`, `MPT_organizer_close_claim`.
- **Stripe Payments & Ledger** ([20260916000001_mpt_payments_and_stripe.sql](file:///c:/dev/Tambola/supabase/migrations/20260916000001_mpt_payments_and_stripe.sql)):
  - `MPT_payments` table and idempotent `MPT_process_stripe_payment` RPC.
- **Private Party Passcodes** ([20260920000001_mpt_private_parties_otps.sql](file:///c:/dev/Tambola/supabase/migrations/20260920000001_mpt_private_parties_otps.sql)):
  - `MPT_seat_otps` and `MPT_verify_seat_otp` for private events.
- **60-Day Game Archives & DVAA™ Corporate Brand Approvals** ([20260922000001_mpt_game_archives_and_purge.sql](file:///c:/dev/Tambola/supabase/migrations/20260922000001_mpt_game_archives_and_purge.sql) – [20260924000003_fix_archive_and_dvaa_sync.sql](file:///c:/dev/Tambola/supabase/migrations/20260924000003_fix_archive_and_dvaa_sync.sql)):
  - `MPT_game_archives`, `MPT_brand_approvals`, and automated 60-day operational data purge preserving Hall of Fame winner records.
- **Sponsored Brand Partner & Voucher Marketplace** ([20260925000001_brand_gifts_marketplace.sql](file:///c:/dev/Tambola/supabase/migrations/20260925000001_brand_gifts_marketplace.sql) – [20260925000009_fix_uber_gift_card_url.sql](file:///c:/dev/Tambola/supabase/migrations/20260925000009_fix_uber_gift_card_url.sql)):
  - `MPT_brand_offers`, `MPT_brand_vouchers`, `MPT_register_brand_offer`, and `MPT_approve_brand_offer`.

---

### B. Multi-Provider Identity & Access Control
- **Organizer Authentication** ([auth_dialog.dart](file:///c:/dev/Tambola/lib/features/auth/widgets/auth_dialog.dart), [auth_repository.dart](file:///c:/dev/Tambola/lib/repositories/auth_repository.dart)):
  - **Google Sign-In** (OAuth 2.0)
  - **Sign in with Apple** (OAuth 2.0 + Apple Private Relay support)
  - **Microsoft / Microsoft Entra ID** (Azure AD Multitenant + Personal Microsoft Accounts with `email profile openid` scopes)
  - **6-Digit Email OTP** (Amazon SES SMTP for corporate work emails and personal emails)
- **Zero-Friction Guest Entry**:
  - Players join via `/#/join/:inviteCode` or `/join.html` using anonymous Supabase sessions and automatic collision-free party nicknames (625 combinations).

---

### C. Core Flutter Screens & User Flows
1. **Home Dashboard** ([home_screen.dart](file:///c:/dev/Tambola/lib/features/home/screens/home_screen.dart)):
   - Quick join/host actions, active & recent games feed, organizer wallet summary, rewards tab, and profile/SSO management.
2. **Game Setup & Corporate Branding** ([create_game_screen.dart](file:///c:/dev/Tambola/lib/features/game_setup/screens/create_game_screen.dart), [brand_gift_picker_dialog.dart](file:///c:/dev/Tambola/lib/features/game_setup/widgets/brand_gift_picker_dialog.dart)):
   - 6 instant capacity tiers (`1–5 Free`, `15`, `25`, `50`, `100`, `250`), Private Party toggle, DVAA™ corporate branding verification, and multi-currency prize & brand gift allocator (`USD`, `INR`, `GBP`, `EUR`, `CAD`, `AUD`, `AED`, `SGD`).
3. **Player Waiting Lobby & Interactive Showcase** ([registration_status_screen.dart](file:///c:/dev/Tambola/lib/features/registration/screens/registration_status_screen.dart), [player_lobby_showcase_player.dart](file:///c:/dev/Tambola/lib/features/registration/widgets/player_lobby_showcase_player.dart)):
   - Real-time `SEAT CONFIRMED` / `WAITING FOR ADMIN CONFIRMATION` status banner.
   - Dual-tab auto-playing animated showcase (**🎯 How to Play & Win** and **🚀 Host a Game Like This**).
4. **Admin Pre-Game Lobby** ([admin_lobby_screen.dart](file:///c:/dev/Tambola/lib/features/admin_lobby/screens/admin_lobby_screen.dart)):
   - Live player roster, 1-click capacity expansion, WhatsApp/QR sharing, private seat OTP distribution, and atomic game start.
5. **Live Gameplay & Audio Engine** ([player_ticket_screen.dart](file:///c:/dev/Tambola/lib/features/gameplay/screens/player_ticket_screen.dart), [admin_game_control_screen.dart](file:///c:/dev/Tambola/lib/features/gameplay/screens/admin_game_control_screen.dart), [audio_service.dart](file:///c:/dev/Tambola/lib/core/services/audio_service.dart)):
   - Interactive 3×9 ticket with tap-to-dab, auto-caller timer, Web Speech TTS number announcements, synthesized sound effects, and instant server-side claim validation.
6. **Big-Screen TV / Projector Display** ([live_game_display_screen.dart](file:///c:/dev/Tambola/lib/features/live_display/screens/live_game_display_screen.dart)):
   - Fullscreen 90-ball master board, 3D animated current ball, live winners podium, and join QR code.
7. **Rewards, Claims & Wallet** ([rewards_screen.dart](file:///c:/dev/Tambola/lib/features/rewards/screens/rewards_screen.dart), [verify_reward_screen.dart](file:///c:/dev/Tambola/lib/features/rewards/screens/verify_reward_screen.dart), [organizer_claims_screen.dart](file:///c:/dev/Tambola/lib/features/wallet/screens/organizer_claims_screen.dart), [wallet_screen.dart](file:///c:/dev/Tambola/lib/features/wallet/screens/wallet_screen.dart)):
   - Digital winner reward cards with `DBH-` verification codes, brand voucher redemption links, and Stripe credit pack top-ups.
