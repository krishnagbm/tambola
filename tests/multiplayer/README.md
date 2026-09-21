# DabHousie Multiplayer Test Harness

A local automated multiplayer test tool for testing live DabHousie games with independent visible or headless browser sessions.

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
1. Open your browser and go to `https://www.dabhousie.com`.
2. Log in / operate as the **Organizer**.
3. Create a game and get the 6-character invite code (e.g. `577873`).

### Step 2: Start the Automated Players

#### Standard (3 Visible Browser Players):
```powershell
# Using npm script:
npm run test:multiplayer -- --game=577873

# Or directly with node:
node tests/multiplayer/runner.js --game=577873
```

#### Custom Number of Players (e.g., 5 Players):
```powershell
node tests/multiplayer/runner.js --game=577873 --players=5
```

#### Full Join URL:
```powershell
node tests/multiplayer/runner.js --url="https://www.dabhousie.com/#/join/577873"
```

#### Headless Mode (Run in Background without Windows):
```powershell
node tests/multiplayer/runner.js --game=577873 --headless
```

#### Local Development Server:
```powershell
node tests/multiplayer/runner.js --game=577873 --base-url="http://localhost:8080"
```

---

## Command-Line Options & Parameters

| Parameter | Alias | Default | Description |
| :--- | :--- | :--- | :--- |
| `--game=<CODE>` | `--game <CODE>` | *None* | 6-character DabHousie game invite code (e.g. `577873`) |
| `--url=<URL>` | `--url <URL>` | *None* | Full direct join URL (e.g. `https://www.dabhousie.com/#/join/577873`) |
| `--players=<N>` | | `3` | Number of automated player sessions to spawn |
| `--headless` | `--hide`, `--headless=true` | `false` | Run headless in the background without opening browser windows |
| `--show` | `--headed`, `--headless=false` | `true` | Open visible browser windows side-by-side (default) |
| `--base-url=<URL>` | | `https://www.dabhousie.com` | Target DabHousie environment or local dev server |

---

## What Happens During Execution

1. **Browser Windows**: Opens separate browser sessions side-by-side (`DabTest Player 1`, `DabTest Player 2`, etc.).
2. **Auto-Join**: Each player independently navigates to the join page, enters its nickname and avatar, registers, and waits in the lobby.
3. **Console Status**:
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
4. **Game Start Detection**: When the Organizer clicks **Start Game**, all player sessions detect `IN_PROGRESS` and enter `/play/{gameId}`.
5. **Ticket Extraction**: The test harness verifies and prints each player's 15 ticket numbers.
6. **Live Auto-Dabbing**:
   - When the Organizer calls numbers on the board, players receive the announced number in real time.
   - If the number exists on their ticket, the player automatically taps and dabs the ticket cell via the UI.
   - Live screenshots are saved to `tests/multiplayer/screenshots/`.
7. **Exit**: Press **Ctrl + C** in your terminal at any time to cleanly close all player windows.
