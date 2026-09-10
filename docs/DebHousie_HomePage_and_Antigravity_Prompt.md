# DebHousie — Home Page Copy Deck & Antigravity Prompt

Brand colors from the approved kit:
- Navy Blue `#0B3D91` (Primary)
- Yellow `#FFC107` (Accent)
- Game-ball accents: Red `#E63946` · Green `#2ECC71` · Purple `#8E44AD`

---

## PART 1 — HOME PAGE COPY (Dashboard Tab / Web Landing)

### Hero
**Eyebrow:** 🎉 Multiplayer Tambola, Housie & Bingo — Live
**Headline:** Real Tambola Nights. Zero Fuss. Zero Cheating.
**Subhead:** DebHousie brings your Tambola, Housie & Bingo party online — host up to 250 players, call numbers live, and let the server verify every win automatically. No paper tickets. No arguments. No app download for players.
**Primary CTA:** 🎟️ Host a Game — Free
**Secondary CTA:** 🔑 Have a Code? Join Now

**Trust strip (small line under hero):**
✅ 200/200 test tickets — zero duplicates &nbsp;·&nbsp; 🔒 Server-verified wins &nbsp;·&nbsp; 🙅 No sign-up to play &nbsp;·&nbsp; 🌍 Free for players, everywhere

---

### Organizer vs. Player Split (two cards, side by side on wide screens, stacked on mobile)

**Card 1 — Hosting a Party or Event?**
Create a game in 30 seconds, share one invite code or link, and let up to 250 guests join instantly. We handle capacity, waitlists, number calling, and prize verification — you just enjoy the party.
CTA: **Create Your Game →**

**Card 2 — Got an Invite Code?**
Jump straight in — no downloads, no sign-up, no email. Pick a name and avatar, get your ticket, and start dabbing the moment numbers are called.
CTA: **Join a Game →**

---

### Why DebHousie (USP grid — 6 cards, proof-based, not adjectives)

1. **🛡️ Fair Play, Guaranteed**
   Every prize claim is checked against the official called-numbers list on our server — not the honor system. No more disputed wins.

2. **🎫 Every Ticket Truly Unique**
   Our ticket generator was stress-tested across 200 consecutive tickets with zero duplicates — so no two players ever share a winning pattern.

3. **⚡ Join in Seconds**
   Players never create an account. Pick a name and avatar, enter the invite code, and you're playing — on any phone, tablet, or laptop.

4. **📱 QR Prize Pickup**
   Winners get a scannable voucher. Organizers verify it with one tap — perfect for handing out real prizes at in-person parties.

5. **📺 Big-Screen Caller Mode**
   Cast the live board and number caller to a TV or projector so the whole room follows along together.

6. **🪑 Never Turn Guests Away**
   More people show up than planned? Waiting-list players are auto-promoted the moment you add capacity — first come, first served.

*(Card accent colors, rotating: Yellow, Red, Green, Purple, Navy, Yellow — full
party-mode palette, ties the game-ball colors into the grid without needing
extra icons. Each card's icon/emoji sits on a soft tint of its accent color,
not full saturation, so 6 cards side by side don't fight for attention —
the accent shows as a colored icon badge + top border stripe, not a filled
card background.)*

---

### How It Works (3-step strip)
1. **Create your game** — Name it, set capacity, pick your prizes, get an invite code.
2. **Guests join free** — Code or link, no app, no account — ticket in hand instantly.
3. **Call numbers live** — Claims are verified automatically. Winners get their voucher on the spot.

---

### Perfect For (chip row)
Family Get-Togethers · Kitty Parties · Diwali & Festival Nights · Housing Society Events · Office Team Nights · Wedding Sangeet Games · School & College Fests

---

### Footer tagline
**Play • Connect • Win**
DebHousie by Digital App Studio

---

## PART 2 — PROMPT FOR ANTIGRAVITY

```
CONTEXT
The app has been rebranded from "tambola" to "DebHousie." Favicon, app icon, and
web meta tags (title/description/apple-mobile-web-app-title) are already updated
and confirmed live at https://tambola.digitalappstudio.com/. Brand asset files
(app icon, Android icon, favicon, horizontal logo, monogram) have already been
provided and should already be in the project — locate them under web/icons/,
web/favicon.png, and any assets/ or android/ios icon directories; do not
regenerate them, just wire them in wherever still referencing old generic
Flutter placeholders (check web/manifest.json icon paths, android
mipmap/ic_launcher, ios AppIcon.appiconset are all pointing at the new files).

GOAL
Rebuild the Dashboard tab (Tab 0) of lib/features/home/screens/home_screen.dart
into a proper marketing-grade landing/home experience using the copy below,
without breaking the existing Player Hub, Organizer Hub, or Profile tabs, and
without touching backend/Supabase logic, routing, or provider wiring.

BRAND COLOR RECONCILIATION (full replacement — "party mode" approved)
The purple/gold theme is being fully retired in favor of the new brand kit.
This is now a complete palette swap in lib/core/theme/app_theme.dart, not a
partial one. Full disposition below — see the companion document
"DebHousie_MobileApp_Brand_and_Launch.md" for the complete button/component
system this feeds into; this section covers palette only.

  - primaryColor / primaryDark / primaryLight -> Navy Blue family, base
    #0B3D91 (derive lighter/darker consistent with existing pattern). Used
    for AppBar, nav bar, structural chrome, and outlined-button borders.
  - secondaryColor / secondaryDark -> Yellow, base #FFC107 (derive
    secondaryDark). This becomes the PRIMARY ACTION color — main CTA
    buttons (Create Game, Join Game, Call Next Number, Start Game, Register)
    switch from the old purple ElevatedButton fill to Yellow fill with Navy
    text, for high-contrast pop against the dark surface.
  - accentSuccess -> Green #2ECC71 (replaces #10B981 — close enough in hue
    that this is a subtle shift, and it now matches the brand's green game
    ball, so success states and the brand converge naturally).
  - accentDanger -> Red #E63946 (replaces #EF4444 — same convergence logic
    with the brand's red game ball).
  - New: accentPartyPurple = #8E44AD. Not a functional/semantic color —
    use it as a 4th rotating accent alongside Yellow/Red/Green anywhere the
    UI wants a 3-4 color rotation (USP cards, avatar ring colors, winner
    badges, chip backgrounds, ticket "dabbed" cell highlight variety).
  - Keep darkBackground / darkCard / darkSurface as-is (#0F111A / #1B1E2E /
    #262A3F). Full "party mode" saturation reads best against a dark base —
    do not switch to a light theme.
  - Button/component shape: increase default corner radius from 12px to
    16-18px across ElevatedButton / OutlinedButton / Card themes for a more
    playful, pill-leaning feel consistent with the rounded bubble logo.
    Bump button text to font-weight 700-800 (from current w600).
  - Verify contrast throughout: Navy text/icons need to sit on Yellow or
    light surfaces, never navy-on-navy; white/light text stays on dark
    surfaces and on Navy chrome.

CONTENT TO IMPLEMENT (Dashboard tab, top to bottom)
Replace the current _buildDashboardTab content with these sections, in order.
Use the exact copy provided — do not paraphrase headlines/CTAs.

1. HERO
   Eyebrow: "🎉 Multiplayer Tambola, Housie & Bingo — Live"
   Headline: "Real Tambola Nights. Zero Fuss. Zero Cheating."
   Subhead: "DebHousie brings your Tambola, Housie & Bingo party online — host
   up to 250 players, call numbers live, and let the server verify every win
   automatically. No paper tickets. No arguments. No app download for players."
   Primary CTA button: "🎟️ Host a Game — Free" -> pushes '/create-game'
   Secondary CTA button: "🔑 Have a Code? Join Now" -> pushes '/join'
   Trust strip below hero (small text row, can wrap on mobile):
   "✅ 200/200 test tickets — zero duplicates  ·  🔒 Server-verified wins  ·
   🙅 No sign-up to play  ·  🌍 Free for players, everywhere"

2. ORGANIZER VS PLAYER SPLIT
   Two cards, Row on screens >600px wide, Column stacked on narrow mobile.
   Card A "Hosting a Party or Event?" — body copy as provided — CTA "Create
   Your Game" -> '/create-game'
   Card B "Got an Invite Code?" — body copy as provided — CTA "Join a Game"
   -> '/join'
   Give each card a distinct accent border (Card A = Navy, Card B = Yellow)
   so the two paths are visually distinguishable at a glance.

3. USP GRID ("Why DebHousie")
   Replace the existing cramped 84px-tall horizontal scroll USP cards with a
   properly readable grid: 2 columns on mobile width, 3 columns on tablet/
   desktop width (use LayoutBuilder, consistent with existing patterns
   elsewhere in this file e.g. _buildMetricsGrid). Each card needs room for a
   1-line title + 2-line description — do not compress to single-line
   truncation like the current implementation.
   Use the exact 6 USP cards and copy provided in the copy deck (Fair Play
   Guaranteed / Every Ticket Truly Unique / Join in Seconds / QR Prize Pickup
   / Big-Screen Caller Mode / Never Turn Guests Away). Rotate accent colors
   Yellow, Red, Green, Purple, Navy, Yellow across the 6 cards.

4. HOW IT WORKS
   3-step horizontal stepper (stack vertically on narrow mobile) using the
   three steps provided. Numbered circles 1/2/3 in Yellow on Navy.

5. "PERFECT FOR" CHIP ROW
   Horizontally scrollable chip row with the 7 use-case chips provided
   (Family Get-Togethers, Kitty Parties, Diwali & Festival Nights, Housing
   Society Events, Office Team Nights, Wedding Sangeet Games, School &
   College Fests). Reuse existing FilterChip-style visual pattern already
   used elsewhere in this file for consistency.

6. KEEP AS-IS, RESTYLE ONLY
   Keep the existing "Live Game Banner" (if user has an active game),
   "App Download Badges" section, and "How to Play" dialog card — just
   restyle their accent colors to match the new Navy/Yellow palette. Do not
   change their logic or placement relative to the new sections above.

7. FOOTER
   Add a small footer block at the bottom of the Dashboard tab (not
   previously present): tagline "Play • Connect • Win" in bold, with
   "DebHousie by Digital App Studio" beneath in muted text, matching the
   existing footer treatment already used in the Profile tab.

TECHNICAL CONSTRAINTS
- Keep this scoped to lib/features/home/screens/home_screen.dart and
  lib/core/theme/app_theme.dart only, unless a new widget file is clearly
  warranted for size — if so, extract new sections into
  lib/features/home/widgets/ (e.g. hero_section.dart, usp_grid.dart,
  organizer_player_split.dart) rather than growing home_screen.dart further,
  since it is already large. Wire them back into home_screen.dart's
  IndexedStack Dashboard tab.
- Do not modify go_router routes, Riverpod providers, or Supabase
  repository/RPC calls.
- Must remain responsive: test at mobile width (~390px), tablet (~768px),
  and desktop (~1280px+) with no overflow errors or RenderFlex warnings.
- Reuse AppTheme constants and Formatters helpers wherever applicable —
  no new hardcoded hex colors outside app_theme.dart.
- Run flutter analyze and fix any new lints before considering this done.
- Do not change web/index.html meta tags or icon references — those are
  already correct; just confirm nothing in this change reverts them.

ACCEPTANCE CHECK
- Dashboard tab visually leads with the hero + dual CTA before any other
  content, on both first load and after refresh.
- All 6 USP cards are fully readable (no truncated text) at mobile width.
- Organizer/Player split cards route correctly to /create-game and /join.
- No regressions in Player Hub, Organizer Hub, or Profile tabs.
- Existing tests in test/ still pass; add a basic widget test for the new
  hero CTA buttons if reasonable.
```
