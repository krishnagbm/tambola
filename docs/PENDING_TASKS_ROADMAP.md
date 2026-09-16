# DabHousie (Multiplayer Tambola) — Pending Task List & Production Roadmap

*Generated: September 15, 2026*
*Platform: DabHousie (https://www.dabhousie.com)*

---

## 🚀 Executive Summary

This document captures the remaining feature backlog, authentication integrations, access-control policies, infrastructure tasks, and monetization milestones for **DabHousie.com**.

---

## 📌 Phase 1: Authentication & Access Control (High Priority)

### 1.1 Google & Apple Social Sign-In Integration
- [ ] **Supabase Provider Setup**:
  - Enable **Google OAuth** in Supabase Dashboard (Client ID, Client Secret, Authorized Redirect URI `https://itfcnurjrnyalauwwdkj.supabase.co/auth/v1/callback`).
  - Enable **Sign in with Apple** in Supabase Dashboard (Services ID, Apple Team ID, Key ID, Private Key).
- [ ] **Web & Mobile Redirects**:
  - Configure `https://www.dabhousie.com` and `https://www.dabhousie.com/#/` as authorized redirect URLs.
  - Set up deep-link URI schemes for native iOS/Android apps (`dabhousie://login-callback`).
- [ ] **Unified Authentication Modal (`AuthModal` / `SignInDialog`)**:
  - Design a rich, party-themed authentication dialog featuring:
    - 🔵 **Continue with Google**
    - 🍏 **Sign in with Apple**
    - ✉️ **Magic Link / Email OTP**
- [ ] **Seamless Account Linking (Anonymous to Registered)**:
  - Allow anonymous players who joined via invite link to link their Google or Apple account seamlessly without losing their wallet balance, hosted games, or ticket history.
- [ ] **User Profile & Navigation Header**:
  - Show user's profile avatar, signed-in email/badge in the app bar.
  - Provide a "Sign In / Register" button for guests and "Manage Account / Sign Out" for authenticated users.

---

### 1.2 Host & Scheduling Permission Guard (Registered Users Only)
- [ ] **Host / Create Game Restriction**:
  - Restrict **Hosting** and **Scheduling** games strictly to registered/authenticated users (non-anonymous).
  - When an anonymous user taps **"Host a Game"**, **"Schedule for Later"**, or submits the Create Game form:
    - Display a polite modal: *"Please sign in with Google or Apple to host and manage DabHousie games."*
    - Automatically redirect back to the setup flow once authentication succeeds.
- [ ] **Frictionless Guest Player Entry (Preserve Zero-Friction Play)**:
  - Maintain 100% frictionless joining for guest players (`/#/join/:inviteCode`) — guest players do **NOT** need to create an account to play.
- [ ] **Backend Database RLS Enforcement**:
  - Add PostgreSQL RLS check or RPC assertion in `MPT_create_game` to enforce `NOT auth.is_anonymous()` for game organizers.

---

## 💳 Phase 2: Monetization & Web Store Checkout

### 2.1 Credit Pack Purchases & Payment Gateway
- [x] **External Web Checkout Handoff**:
  - Connect Stripe Hosted Checkout (`stripe.checkout.Session.create`) flow to the **"Buy Credits"** button on `/wallet` and `/pricing.html`.
  - Pass `user_id`, `email`, and selected credit bundle.
- [x] **Server-Side Webhook Fulfillment**:
  - Deploy secure Stripe Webhook handler (`POST /webhook`) verifying signatures (`stripe.Webhook.construct_event`).
  - Implement atomic, idempotent fulfillment RPC (`MPT_process_stripe_payment`) to credit `MPT_admin_wallets` balance and record ledger in `MPT_credit_transactions` and `MPT_payments`.
  - Automated HTML purchase confirmation receipt email via AWS SES.

---

## 🎮 Phase 3: Gameplay & Host Control Enhancements

### 3.1 Audio & Atmosphere (Sound System)
- [ ] **Tambola Caller Sound Effects & Voice Synthesizer**:
  - Add optional voice announcement for called numbers (English & Hindi bingo calls, e.g., *"Single number 7 — Lucky Seven!"*).
  - Add audio cues for: Number Call, Winning Claim Announcement, Confetti Fanfare.
  - Provide mute/unmute toggle in the gameplay and admin console.

### 3.2 Custom Winning Patterns (Enterprise & Custom Rules)
- [ ] **Dynamic Pattern Engine**:
  - Allow hosts to configure custom winning patterns (Star, Breakfast/Lunch/Dinner lines, King/Queen, Corner Plus Center, Bullseye).
  - Add pattern preview diagrams in the Game Setup screen.

---

## 📱 Phase 4: Mobile App Store Packaging & PWA Push Notifications

### 4.1 Push Notifications & Event Reminders
- [ ] **Web Push / OneSignal Integration**:
  - Prompt players with: *"Remind me 5 minutes before the game starts"*.
  - Send instant push notification when the Host starts the game or seats are confirmed.

### 4.2 App Store Packaging (iOS & Android)
- [ ] **Android Google Play Store**:
  - Generate signed Android App Bundle (AAB).
  - Configure Google Play Billing (if releasing native in-app purchases).
- [ ] **Apple App Store**:
  - Build signed iOS IPA with Apple Developer certificate.
  - Configure StoreKit / In-App Purchases for iOS.

---

## 🧹 Phase 5: Database Maintenance & Operations

### 5.1 Automated Cleanup & Analytics
- [ ] **Stale Anonymous Session Pruning**:
  - Set up a scheduled pg_cron job in Supabase to prune inactive anonymous user records (`is_anonymous = true`) with 0 games and 0 wallet balance older than 30 days.
- [ ] **Host Analytics Dashboard**:
  - Provide hosts with a summary of past games: total players joined, tickets issued, winners list, and game duration.

---

## 📋 Summary Checklist

| Task Area | Feature / Goal | Status |
| :--- | :--- | :--- |
| **Auth** | Google OAuth Implementation & Profile Sync | ✅ Completed & Live |
| **Auth** | Google Cloud OAuth Branding & Privacy Approval | ✅ 100% Approved by Google |
| **Auth** | Host Permission Guard (Registered Users Only) | ✅ Completed & Guarded |
| **Auth** | Apple OAuth Sign-In (Services ID / Apple Key) | ⏳ Ready to Implement |
| **Auth** | Frictionless Anonymous Joining for Players | ✅ Completed & Live |
| **Capacity** | Instant 0ms Group Size Selector (6 Confirmed Tiers) | ✅ Completed & Live |
| **Brand** | DabHousie Logo, Dark Mode UI & OpenGraph Preview | ✅ Completed & Live |
| **Domain** | Custom Domain (`dabhousie.com`) Live on Amplify | ✅ Completed & Live |
| **Payments** | Stripe Hosted Checkout & Webhook Fulfillment | ✅ Completed & Ready to Deploy |
| **Audio** | Sound Effects & Bingo Call Synthesizer | ⏳ Ready to Plan |
| **Patterns** | Custom Enterprise Winning Patterns | ⏳ Backlog |
| **Mobile** | Native iOS & Android App Store Packaging | ⏳ Backlog |
