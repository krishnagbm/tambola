# DebHousie — Mobile App Launch Experience & "Party Mode" Component System

Companion to `DebHousie_HomePage_and_Antigravity_Prompt.md`. That document
covers the web Dashboard content; this one covers the native app launch
sequence (splash → opening screen → home) and the full button/component
theme system, since those are a different implementation surface (native
platform config + app-wide theme, not a single page).

Full palette (now applied app-wide, not just the homepage):
- Navy Blue `#0B3D91` — structural/chrome (AppBar, nav, outlined borders)
- Yellow `#FFC107` — primary action color (main CTA buttons everywhere)
- Green `#2ECC71` — success/live states (also a game-ball accent)
- Red `#E63946` — danger/destructive states (also a game-ball accent)
- Purple `#8E44AD` — 4th rotating "party" accent, non-functional use only
- Dark base stays: background `#0F111A`, card `#1B1E2E`, surface `#262A3F`

---

## 1. Native Splash Screen (OS-level, before Flutter paints)

This is the flash of color+logo a user sees the instant they tap the app
icon — before Flutter's engine has even loaded. Handled via the
`flutter_native_splash` package, which generates the actual native Android/
iOS/web launch assets from one config.

**Design:**
- Background: solid Navy `#0B3D91` on all platforms.
- Content (iOS, Android 8–11, Web): the full stacked logo — icon mark above
  the "DebHousie" wordmark, centered, roughly 45% of screen width.
- Content (Android 12+): Android's native splash API is restrictive — it
  only allows a **simple centered icon within a 240×240dp safe zone inside
  a 480×480dp canvas, no text, no fine detail**. Use the monogram/icon mark
  alone here (the "DH" ball-and-ticket mark from the approved brand kit),
  not the full wordmark — text will get clipped or look wrong under the
  Android 12 constraints.
- No loading spinner on the native splash itself — that belongs to the
  in-app opening screen below, since the native splash can't be animated
  reliably across platforms.

**Antigravity implementation notes:**
```yaml
# pubspec.yaml
dev_dependencies:
  flutter_native_splash: ^2.4.1

flutter_native_splash:
  color: "#0B3D91"
  image: assets/branding/splash_logo.png        # full stacked logo, transparent bg
  android_12:
    image: assets/branding/splash_icon_mono.png # monogram/icon mark ONLY, no text
    color: "#0B3D91"
  web: true
  web_image_mode: center
```
Source `splash_logo.png` and `splash_icon_mono.png` by cropping from the
already-approved brand kit sheet (the individual "Monogram (Mark Only)" and
"Horizontal Logo" exports already used for the favicon/app icon work) —
do not regenerate the brand art, just export these two specific crops if
not already available as standalone files. After adding the config, run
`dart run flutter_native_splash:create` and verify on both an Android
emulator and iOS simulator (or physical device) — native splash
misconfiguration can silently break first-launch rendering, so this needs
an actual on-device check, not just a code review.

---

## 2. In-App "Opening Screen" (branded loading state)

**Current gap:** once Flutter takes over from the native splash,
`HomeScreen` immediately renders `userState.when(loading: () =>
const Center(child: CircularProgressIndicator()))` — a bare spinner on an
otherwise empty Scaffold while `AuthRepository.initializeAuth()` runs
(anonymous auth + profile sync). This is currently unbranded dead space.

**Fix:** replace that bare loading branch with a proper branded opening
screen. Extract to a new widget: `lib/features/home/widgets/opening_screen.dart`.

**Content:**
- Full-bleed Navy `#0B3D91` background (visually continuous with the native
  splash so the transition is seamless, not a jarring color-swap).
- Centered: icon mark + "DebHousie" wordmark (same lockup as native splash).
- Tagline below, fading in half a second after the logo: **"Play • Connect • Win"**
- Loading indicator: replace the generic spinner with a row of 4 small dots
  that pulse in sequence through the party palette — Yellow, Red, Green,
  Purple — reusing the brand accent rotation as the loading animation
  instead of a generic Material spinner.
- Optional (nice-to-have, skip if time-constrained): a single rotating tip
  line beneath the dots, cycling every ~2.5s, e.g. "Every ticket is checked
  for uniqueness before you play." / "Host up to 250 players on one game."
  / "No sign-up needed to join a game." — improves perceived wait time and
  does double duty as USP reinforcement. Pull these lines from the USP copy
  already defined in the homepage document rather than writing new copy.

**Constraints:**
- This is a *loading state*, not a fixed-duration splash — it must
  disappear the instant `currentUserProvider` resolves, same as today.
  Do not add artificial `Future.delayed` padding.
- Keep this widget self-contained and stateless/simple (a Timer-driven dot
  animation is enough — no need for a heavy animation package).

---

## 3. Button & Component "Party Mode" System

This is the app-wide theme change referenced in the homepage document's
color-reconciliation section — full detail here since it touches every
screen, not just the homepage.

| Element | Old | New |
|---|---|---|
| Primary button fill | `primaryColor` (purple `#6C47FF`) | `secondaryColor` (Yellow `#FFC107`), text Navy |
| Primary button text/icon color | White | Navy `#0B3D91` (for contrast on Yellow) |
| Outlined button border | `Color(0xFF3B4163)` neutral gray | `primaryColor` (Navy `#0B3D91`) |
| Button corner radius | 12px | 16–18px |
| Button text weight | `w600` | `w700`–`w800` |
| Success accent | `#10B981` | `#2ECC71` (brand green) |
| Danger accent | `#EF4444` | `#E63946` (brand red) |
| 4th rotating accent | *(none)* | Purple `#8E44AD` — non-functional use only |

**Where each color applies — be deliberate, not uniform-rainbow:**
- **Functional/status colors stay legible and consistent.** LIVE badges,
  CONFIRMED/WAITING pills, error states, and the "Won by You" success
  states should keep using the semantic accent constants
  (`accentSuccess`/`accentDanger`/`accentWarning`) so their meaning stays
  instantly readable — do not randomly rotate these through the party
  palette. A red "error" badge must always mean error, not "just this
  card's random color."
- **Decorative/variety colors rotate freely.** USP cards, avatar ring
  colors, ticket "dabbed" cell highlights, chip backgrounds, and the
  opening-screen loading dots can rotate through Yellow/Red/Green/Purple
  for visual energy — these carry no semantic meaning, so variety is good.
- **Primary CTAs are always Yellow.** Every main action button across the
  app (Create Game, Join & Get Ticket, Start Game & Deduct Credits, Call
  Next Number, Register, Verify) switches to the Yellow-fill/Navy-text
  style for a single consistent "this is the button to press" signal.

**Audit note for Antigravity:** most screens already reference
`AppTheme.primaryColor` / `AppTheme.secondaryColor` as constants rather
than hardcoding hex values, so the palette swap in `app_theme.dart` should
propagate automatically in most places. Grep the codebase for any direct
`Color(0xFF6C47FF)` or `Color(0xFFFFB800)` (old brand hex used inline,
bypassing the constant) and replace those specific spots with the proper
`AppTheme` reference so nothing is missed.

---

## 4. PROMPT FOR ANTIGRAVITY

```
CONTEXT
DebHousie's web homepage content/color work is being handled separately
(see DebHousie_HomePage_and_Antigravity_Prompt.md). This task covers the
native app launch experience and the app-wide "party mode" theme system.
The purple/gold theme in lib/core/theme/app_theme.dart is being fully
retired in favor of the DebHousie brand kit (Navy/Yellow/Red/Green/Purple).

GOAL
1. Add a native splash screen via flutter_native_splash.
2. Replace the current bare-spinner loading state in HomeScreen with a
   branded "opening screen" widget.
3. Apply the full party-mode color and button/component system app-wide.

PART A — NATIVE SPLASH
- Add flutter_native_splash as a dev dependency.
- Configure per the YAML block in the design doc: Navy #0B3D91 background,
  full stacked logo for iOS/Android<12/Web, monogram-only icon for
  Android 12+ (respecting its 240x240dp safe-zone/480x480dp canvas
  constraint — no text, simple mark only).
- Source the two required image crops (full logo, monogram-only) from the
  already-approved brand kit assets already in the project (used for the
  favicon/app icon work) — do not regenerate brand art.
- Run `dart run flutter_native_splash:create` and verify visually on an
  Android emulator/device AND iOS simulator/device — this touches native
  launch files directly and must be checked on-device, not just reviewed
  as code.

PART B — IN-APP OPENING SCREEN
- Create lib/features/home/widgets/opening_screen.dart.
- Replace the `loading: () => const Center(child: CircularProgressIndicator())`
  branch in HomeScreen's userState.when(...) with this new widget.
- Content: Navy full-bleed background, centered icon+wordmark lockup
  (same as splash, for a seamless visual handoff), tagline "Play • Connect
  • Win" fading in, and a 4-dot loading indicator that pulses through
  Yellow -> Red -> Green -> Purple in sequence (replace the generic
  Material spinner entirely).
- Optional: rotating one-line tip text beneath the dots, cycling every
  ~2.5s, pulled from the USP copy already defined in the homepage document.
- This must remain a true loading state — disappears the instant
  currentUserProvider resolves. No artificial delays.

PART C — APP-WIDE THEME & BUTTON SYSTEM
In lib/core/theme/app_theme.dart:
- primaryColor/primaryDark/primaryLight -> Navy family, base #0B3D91
- secondaryColor/secondaryDark -> Yellow family, base #FFC107
- accentSuccess -> #2ECC71, accentDanger -> #E63946
- Add a new constant, e.g. `accentPartyPurple = Color(0xFF8E44AD)`, for
  decorative/non-functional rotation use only
- elevatedButtonTheme: fill becomes secondaryColor (Yellow), foreground
  becomes primaryColor (Navy) instead of white, borderRadius 16-18,
  fontWeight increased to w700/w800
- outlinedButtonTheme: border color becomes primaryColor (Navy)
- cardTheme / inputDecorationTheme border radius: bump consistent with the
  more playful/rounded button shape (match existing radius pattern, just
  slightly larger — e.g. 12->16 where currently 12)

Apply the "functional colors stay semantic, decorative colors rotate
freely" rule described in the design doc — do NOT push every badge/chip in
the app through a random color rotation; status pills (LIVE/CONFIRMED/
WAITING/COMPLETED/error states) keep their semantic meaning, while
non-functional decorative elements (USP cards on the homepage, avatar
rings, ticket dab-cell highlight variety, loading dots) get the color
rotation treatment.

Grep the codebase for any inline `Color(0xFF6C47FF)` or `Color(0xFFFFB800)`
(old brand hex bypassing the AppTheme constant) and fix those specific
spots to reference the updated constants instead, so the swap is complete
everywhere, not just where AppTheme.primaryColor/secondaryColor were
already used properly.

ACCEPTANCE CHECK
- Native splash shows correctly on Android 12+ device/emulator (icon-only,
  no clipping) AND on an older Android/iOS target (full logo).
- App launch sequence reads as one continuous branded experience: native
  splash (Navy+logo) -> opening screen (Navy+logo+tagline+dots) -> home,
  with no jarring color flash between steps.
- Every primary CTA button across the app (not just homepage) is now
  Yellow-fill/Navy-text.
- Status/semantic badges (LIVE, CONFIRMED, WAITING, error states) remain
  clearly distinguishable and were not swept into random color rotation.
- flutter analyze passes clean; existing tests in test/ still pass.
```
