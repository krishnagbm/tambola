# DabHousie™ (Multiplayer Tambola) — Production Readiness & Roadmap

*Last Updated: September 26, 2026*  
*Platform: DabHousie ([https://www.dabhousie.com](https://www.dabhousie.com))*  
*Release Status: ✅ **100% Ready for Production Go-Live***

---

## 🚀 Executive Summary

All core gameplay, multi-provider authentication, monetization, corporate security (DVAA™), brand partner marketplace, SEO content, legal compliance, and player onboarding features planned for the **DabHousie™ v1.0 Production Launch** are **completed, verified, and live on `main`**.

---

## ✅ Completed Production Milestones (v1.0 Go-Live)

### 1. Authentication, SSO & Access Control
- [x] **Google OAuth Sign-In**:
  - Configured in Supabase & Google Cloud Console; OAuth branding and privacy policy 100% approved by Google.
- [x] **Sign in with Apple**:
  - Configured and live in `AuthDialog` and the Profile tab with full Apple Private Relay (`@privaterelay.appleid.com`) support.
- [x] **Microsoft / Microsoft Entra ID (Azure AD) Sign-In**:
  - Multitenant + Personal Microsoft account app registered in Azure Portal (`https://itfcnurjrnyalauwwdkj.supabase.co/auth/v1/callback`), enabled in Supabase with `email profile openid` scopes, and live across `AuthDialog` and `HomeScreen`.
- [x] **6-Digit Passwordless Email OTP**:
  - Powered by Amazon SES custom SMTP for both corporate work emails (unlocking DVAA™ company branding) and personal emails.
- [x] **Host & Scheduling Permission Guard (`AuthGuard`)**:
  - Restricts game creation, scheduling, and credit wallet actions strictly to authenticated organizers while preserving 100% frictionless anonymous guest entry for players (`/#/join/:inviteCode` and `/join.html`).
- [x] **625 Default Party Nicknames**:
  - Automatic collision-free party nickname assignment (`Lucky Dabber`, `Cosmic Tiger`, etc.) for guests joining without typing a name.

---

### 2. Player Waiting Lobby & Interactive Onboarding
- [x] **Real-Time Registration Queue (`RegistrationStatusScreen`)**:
  - Instant live status updates between `SEAT CONFIRMED` and `WAITING FOR ADMIN CONFIRMATION` with automatic First-Come-First-Served (FCFS) promotion when the host expands room capacity.
- [x] **Interactive Waiting Lobby Showcase (`PlayerLobbyShowcasePlayer`)**:
  - Auto-playing, zero-asset animated walkthrough keeping players engaged while waiting for game start:
    - **Tab A (`🎯 How to Play & Win`)**: Interactive 3×9 ticket dabbing animation, live pattern tracker (Early 5, Lines, Full House), and 1-tap instant claim verification.
    - **Tab B (`🚀 Host a Game Like This`)**: 3-step visual showcase for prospective hosts (Create Room in 60s, Custom Brand Prizes & DVAA™ Corporate Branding, Big-Screen TV Display & Auto Caller).

---

### 3. Authoritative Gameplay, Audio & Live TV Display
- [x] **Server-Authoritative 90-Ball Engine**:
  - Deterministic, validated 3×9 ticket generation (`MPT_start_game_and_charge`), server-side number calling (`MPT_call_next_number`), and instant anti-bogey claim verification (`MPT_submit_claim`).
- [x] **Synthesized Sound Effects & Voice Caller (`AudioService`)**:
  - Web Speech API Text-to-Speech (TTS) announcing numbers with classic Tambola/Bingo calls + Web Audio API synthesized sound effects and mute/unmute controls.
- [x] **Projector / Smart TV Live Display (`/#/live-display/:gameId`)**:
  - Dedicated fullscreen broadcast view with animated current ball, 1–90 master board, live winners podium, join QR code, and casting guide.

---

### 4. Enterprise Features: Private Parties, DVAA™ & Brand Partner Marketplace
- [x] **Private Party Mode & Seat Passcodes (`MPT_seat_otps`)**:
  - Excludes private events from public feeds/Hall of Fame and generates 6-digit individual seat passcodes for verified player entry.
- [x] **Domain-Verified Automated Approval (DVAA™) Corporate Branding**:
  - Zero-PII corporate identity verification: instant auto-approval when host email domain matches organization domain (via Email OTP or Microsoft Entra ID), or 1-click executive email approval (`brand-approval.html`) with immutable compliance audit logs.
- [x] **Sponsored Brand Partner & Gift Marketplace**:
  - Multi-currency prize budget auto-allocator (`USD`, `INR`, `GBP`, `EUR`, `CAD`, `AUD`, `AED`, `SGD`).
  - Host custom voucher/gift configuration (`BrandGiftPickerDialog`).
  - Public self-service **Brand Marketing Partner Portal** (`/brand-partners.html`) with one-click admin approval workflow (`brand-offer-approval.html`) and automated winner voucher fulfillment.

---

### 5. Monetization, SEO Content, Legal Compliance & Marketing Suite
- [x] **Stripe Hosted Checkout & Webhook Fulfillment**:
  - Serverless AWS Lambda checkout creator (`create_checkout.py`) and signed webhook processor (`stripe_webhook.py`) crediting `MPT_admin_wallets` atomically via `MPT_process_stripe_payment` and sending AWS SES HTML receipts.
- [x] **AdSense-Safe Integration**:
  - Google AdSense publisher tags (`ca-pub-6136000774092015`) and `web/ads.txt` deployed; empty/unfilled placeholder boxes are automatically collapsed (`ins.adsbygoogle[data-ad-status="unfilled"] { display: none !important; }`) so the UI stays clean before and after AdSense review.
- [x] **Static SEO Content Suite & Sitemap**:
  - Full static HTML suite (`how-it-works.html`, `how-to-play-tambola.html`, `how-to-play-housie.html`, `90-ball-bingo.html`, `pricing.html`, `recent-games.html`, `brand-partners.html`, `join.html`, `terms-conditions.html`, `privacy-policy.html`) indexed in `sitemap.xml` and linked across both the Flutter Canvas app bar and static headers/footers.
- [x] **60-Day Automated Game Archival (`MPT_game_archives`)**:
  - Preserves Hall of Fame winner summaries while purging heavy operational ticket/ball rows after 60 days.
- [x] **Complete Marketing & Sales Kit (`docs/marketting/`)**:
  - Playbooks (`00`–`04`), Word strategy guides, Excel CRM outreach tracker, and strictly 1-page Print-to-PDF brochures (`DabHousie_Organizer_Corporate_One_Pager.pdf`, `DabHousie_Brand_Partner_One_Pager.pdf`, `DabHousie_Executive_Media_Kit_2Pages.pdf`).

---

## ⏳ External Review & Post-Launch Phase 2 Backlog (Non-Blocking)

### A. External Third-Party Review (No Code Action Needed)
| Item | Current State | Notes |
| :--- | :--- | :--- |
| **Google AdSense Approval** | ⏳ Pending Google Review | Script & `ads.txt` are live; unfilled ad containers are hidden automatically until Google activates ad serving. |

### B. Optional Phase 2 Post-Launch Enhancements
These items are **not required** for web go-live and can be scheduled based on user feedback after launch:
- [ ] **Native Mobile App Store Packaging (iOS `.ipa` & Android `.aab`)**:
  - Package the Flutter project for Google Play Store and Apple App Store distribution (web app already works natively on all mobile browsers with zero install).
- [ ] **Additional Custom Enterprise Winning Patterns**:
  - Expand beyond the 7 core patterns (Early 5, Top/Middle/Bottom Line, Four Corners, 1st & 2nd Full House) to include optional novelty patterns (Star, Bullseye, Breakfast/Lunch/Dinner).
- [ ] **Web Push Notifications (OneSignal / FCM)**:
  - Optional browser push reminders 5 minutes before a scheduled game starts.

---

## 📋 Production Go-Live Summary Matrix

| Task Area | Feature / Goal | Status |
| :--- | :--- | :--- |
| **Auth** | Google OAuth Implementation & Google Cloud Verification | ✅ Completed & Live |
| **Auth** | Apple OAuth Sign-In (Services ID / Apple Key) | ✅ Completed & Live |
| **Auth** | Microsoft / Entra ID OAuth Sign-In (Work & Personal) | ✅ Completed & Live |
| **Auth** | 6-Digit Email OTP via Amazon SES | ✅ Completed & Live |
| **Auth** | Host Permission Guard & Frictionless Anonymous Guest Join | ✅ Completed & Live |
| **Lobby** | Interactive Waiting Lobby Showcase (How to Play + Host Promo) | ✅ Completed & Live |
| **Gameplay** | 90-Ball Engine, Audio/TTS Caller & Big-Screen TV Display | ✅ Completed & Live |
| **Enterprise** | Private Party Passcodes & DVAA™ Corporate Brand Verification | ✅ Completed & Live |
| **Marketplace** | Brand Partner Portal (`brand-partners.html`) & Multi-Currency Gifts | ✅ Completed & Live |
| **Payments** | Stripe Hosted Checkout, Webhook Fulfillment & SES Receipts | ✅ Completed & Live |
| **Ads** | AdSense Setup (`ads.txt` + Unfilled Placeholder Hiding) | ✅ Completed & Live (Review Pending) |
| **Legal & SEO** | Privacy Policy, Terms (incl. Microsoft & Brand Partners) & Sitemap | ✅ Completed & Live |
| **Marketing** | Complete Marketing Kit, CRM Tracker & 1-Page PDF Brochures | ✅ Completed & Ready |
