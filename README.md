# DabHousie™ — Live Multiplayer Tambola, Housie & 90-Ball Bingo Platform

**Production Web Platform:** [https://www.dabhousie.com](https://www.dabhousie.com)  
**Publisher:** Digital App Studio  
**Status:** ✅ Production-Ready & Live (`v1.0`)

---

## 🎯 Overview

**DabHousie™** is an enterprise-ready, real-time multiplayer 90-ball Tambola (Housie / Indian Bingo) platform built with **Flutter Web/Mobile**, **Supabase (PostgreSQL + Realtime + Auth)**, and **AWS Serverless (Lambda + API Gateway + Amazon SES + AWS Amplify)**.

Designed for family game nights, kitty parties, community festivals, and large-scale corporate town halls (up to 250 concurrent players per room), DabHousie provides:
- **Zero-Friction Guest Entry**: Players join via a 6-character invite code, direct room link, or QR scan with zero app installs or sign-up barriers.
- **Enterprise Multi-Provider SSO**: Organizers authenticate via **Google Sign-In**, **Sign in with Apple**, **Microsoft / Microsoft Entra ID (Azure AD)**, or **6-Digit Corporate/Personal Email OTP**.
- **Authoritative Server-Side Game Engine**: 100% ACID-compliant PostgreSQL RPCs (`MPT_` namespace) handle ticket generation, capacity promotion, number calling, and anti-bogey win validation.
- **Domain-Verified Automated Approval (DVAA™)**: Zero-PII corporate branding engine allowing verified company organizers (`@company.com`) to display official organization logos and banners.
- **Sponsored Brand Partner & Gift Marketplace**: Multi-currency prize budget calculator, custom host gift attachments, and a self-service Brand Marketing Partner Portal (`/brand-partners.html`).
- **Broadcast-Grade Live TV Display**: Dedicated big-screen projector/TV mode (`/#/live-display/:gameId`) with Web Speech TTS bingo calls and synthesized sound effects.

---

## 🏗️ System Architecture

```
┌───────────────────────────────────────────────────────────────────────────┐
│                     DabHousie Frontend (AWS Amplify)                      │
│  • Flutter Web SPA (/#/) + Interactive Player Lobby Showcase              │
│  • Static SEO Content Suite (/how-it-works.html, /pricing.html, etc.)     │
└───────────────────┬───────────────────────────────────┬───────────────────┘
                    │ Supabase SDK (WebSockets / HTTPS) │ REST HTTPS
                    ▼                                   ▼
┌───────────────────────────────────────┐ ┌─────────────────────────────────┐
│       Supabase Backend (MPT_*)        │ │  AWS Serverless Backend (SAM)   │
│  • Auth: Anonymous, Google, Apple,    │ │  • Stripe Checkout & Webhooks   │
│    Microsoft Entra ID, Email OTP      │ │  • Amazon SES Transactional     │
│  • PostgreSQL: 33 MPT_ Migrations     │ │    Emails (Receipts, DVAA,      │
│  • Realtime: Live Balls, Claims,      │ │    Brand Partner Approvals)     │
│    Registration Queue Promotions      │ │                                 │
└───────────────────────────────────────┘ └─────────────────────────────────┘
```

---

## ✨ Key Production Features

| Category | Feature Highlights |
| :--- | :--- |
| **Authentication & Identity** | Anonymous guest sessions (with 625 unique default party nicknames) + seamless account linking with **Google**, **Apple**, **Microsoft / Entra ID**, and **6-Digit Email OTP**. |
| **Player Waiting Lobby** | Real-time seat status (`SEAT CONFIRMED` vs. `WAITING FOR ADMIN CONFIRMATION`) + interactive 2-tab animated showcase (**🎯 How to Play & Win** and **🚀 Host a Game Like This**). |
| **Gameplay & Audio Engine** | Validated 3×9 Tambola tickets, instant tap-to-dab, server-side claim verification (Early 5, Top/Middle/Bottom Line, Four Corners, 1st & 2nd Full House), Web Speech TTS caller, and Web Audio sound effects. |
| **Corporate DVAA™ Branding** | Instant domain-owner verification when signed in via corporate email/Microsoft 365, plus delegated executive email approval (`brand-approval.html`) and compliance audit trail. |
| **Private Party Security** | Optional Private Party mode hiding games from public feeds and generating unique 6-digit seat passcodes (`MPT_seat_otps`) per player. |
| **Prizes & Brand Partners** | Multi-currency budget auto-splitter (`USD`, `INR`, `GBP`, `EUR`, `CAD`, `AUD`, `AED`, `SGD`), custom host vouchers, and self-service Brand Partner portal (`brand-partners.html`). |
| **Monetization** | Stripe Hosted Checkout credit packs (`Starter`, `Family`, `Pro`, `Gala`) with idempotent webhook fulfillment + AdSense-compliant ad slots with automatic unfilled collapse. |

---

## 📂 Repository Structure

```text
c:\dev\Tambola\
├── backend/                     # AWS SAM Serverless Python Lambdas (Stripe, SES, DVAA, Brand Offers)
├── docs/                        # Architecture specs, roadmap, and marketing kit (docs/marketting/)
│   ├── PENDING_TASKS_ROADMAP.md # Production readiness checklist & post-launch roadmap
│   ├── STRIPE_INTEGRATION_GUIDE.md
│   ├── walkthrough.md           # Full technical walkthrough & migration reference
│   └── marketting/              # Playbooks, CRM tracker, and 1-page Print-to-PDF brochures
├── lib/                         # Flutter application source code
│   ├── core/                    # AppConfig, AppTheme, AudioService, AuthGuard, DabHousieAppBar
│   ├── features/
│   │   ├── admin_lobby/         # Organizer pre-game lobby, capacity expansion & seat OTP management
│   │   ├── auth/                # AuthDialog (Google, Apple, Microsoft, Email OTP) & Profile editor
│   │   ├── game_setup/          # Create Game, DVAA corporate branding, Prize & Brand Gift picker
│   │   ├── gameplay/            # PlayerTicketScreen & AdminGameControlScreen
│   │   ├── home/                # Home dashboard, My Games, Profile & Wallet tabs
│   │   ├── live_display/        # Projector / Smart TV fullscreen live board
│   │   ├── registration/        # JoinGameScreen, RegistrationStatusScreen & PlayerLobbyShowcasePlayer
│   │   ├── rewards/             # Winner reward vouchers & organizer claim verification
│   │   └── wallet/              # Organizer credit wallet & claims management
│   ├── models/                  # Data models (MptUser, MptGame, MptTicket, BrandOffer, etc.)
│   ├── providers/               # Riverpod state providers & Supabase Realtime streams
│   ├── repositories/            # Auth, Game, Gameplay, Rewards, and Wallet repositories
│   └── router/                  # GoRouter declarative routing
├── supabase/
│   └── migrations/              # 33 sequential SQL migrations (strictly namespaced with MPT_)
└── web/                         # Static SEO HTML pages, legal disclosures, sitemap.xml, ads.txt
```

---

## 🛠️ Local Development & Build Commands

### 1. Run Locally (Chrome)
```bash
flutter pub get
flutter run -d chrome
```

### 2. Static Analysis & Unit Tests
```bash
dart analyze
flutter test
```

### 3. Production Web Build
```bash
flutter build web --release
```
*(Deployed automatically via AWS Amplify on push to `origin/main`.)*
