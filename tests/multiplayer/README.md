# DabHousie Multiplayer Test Harness (Phase 1)

A local automated multiplayer testing tool for testing the live DabHousie game with independent visible browser sessions.

---

## Prerequisites

1. **Node.js** (v18 or higher recommended)
2. **Playwright & Chromium**

---

## Installation

From the project root:

```powershell
# 1. Install dependencies
npm --prefix tests/multiplayer install

# 2. Install Playwright Chromium browser binary (one-time setup)
npx --prefix tests/multiplayer playwright install chromium
```

---

## How to Run

### Step 1: Create a Game as Organizer
1. Open your standard browser and go to `https://www.dabhousie.com`.
2. Log in / operate as the **Organizer**.
3. Create a game and get the 6-character invite code (e.g. `577873`).

### Step 2: Start the Automated Players
Run the test command with your game code:

```powershell
# Using npm script from root:
npm run test:multiplayer -- --game=577873

# Or directly with node:
node tests/multiplayer/runner.js --game=577873
```

You can also pass the full join URL:

```powershell
npm run test:multiplayer -- --url="https://www.dabhousie.com/#/join/577873"
```

---

## What Happens

1. **3 Separate Headed Browser Windows** open side-by-side on your desktop:
   - Window 1: `DabTest Player 1`
   - Window 2: `DabTest Player 2`
   - Window 3: `DabTest Player 3`
2. Each player independently joins the game, enters its name, registers, and waits in the lobby.
3. The terminal displays:
   ```
   ========================================
   DABHOUSIE MULTIPLAYER TEST
   3 PLAYERS CONNECTED
   ========================================
   Player 1: CONNECTED / REGISTERED (DabTest Player 1)
   Player 2: CONNECTED / REGISTERED (DabTest Player 2)
   Player 3: CONNECTED / REGISTERED (DabTest Player 3)

   Waiting for Organizer to start game...
   ```
4. As the Organizer, you click **Start Game**.
5. All 3 player windows detect `IN_PROGRESS` and enter `/play/{gameId}`.
6. The test harness verifies and prints each player's 15 ticket numbers.
7. As you call numbers from the Organizer board:
   - All players receive the announced number in real-time.
   - The test logs whether the number exists on each player's ticket.
   - Players with matching numbers automatically dab their ticket cell via the real UI.
   - Screenshots are captured in `tests/multiplayer/screenshots/`.
8. Press **Ctrl+C** to cleanly close all player windows.
