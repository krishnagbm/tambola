import { chromium } from 'playwright';
import { PlayerSession } from './player_session.js';

// Parse command line arguments
function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    gameCode: null,
    joinUrl: null,
    playersCount: 3,
    headless: false,
    baseUrl: 'https://www.dabhousie.com',
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg.startsWith('--game=')) {
      options.gameCode = arg.split('=')[1].trim();
    } else if (arg === '--game' && args[i + 1]) {
      options.gameCode = args[++i].trim();
    } else if (arg.startsWith('--url=')) {
      options.joinUrl = arg.split('=')[1].trim();
    } else if (arg === '--url' && args[i + 1]) {
      options.joinUrl = args[++i].trim();
    } else if (arg.startsWith('--players=')) {
      options.playersCount = parseInt(arg.split('=')[1].trim(), 10) || 3;
    } else if (arg === '--headless' || arg === '--hide' || arg === '--headless=true') {
      options.headless = true;
    } else if (arg === '--show' || arg === '--headed' || arg === '--headless=false') {
      options.headless = false;
    } else if (arg.startsWith('--base-url=')) {
      options.baseUrl = arg.split('=')[1].trim();
    }
  }

  // Extract game code from url if provided
  if (options.joinUrl) {
    const match = options.joinUrl.match(/join\/([A-Za-z0-9]+)/);
    if (match) {
      options.gameCode = match[1];
    }
  } else if (options.gameCode) {
    options.joinUrl = `${options.baseUrl}/#/join/${options.gameCode}`;
  }

  return options;
}

async function main() {
  const options = parseArgs();

  if (!options.gameCode && !options.joinUrl) {
    console.error(`
===================================================================
ERROR: Missing Game Code or URL!

Usage:
  npm run test:multiplayer -- --game=XXXXXX
  npm run test:multiplayer -- --url="https://www.dabhousie.com/#/join/XXXXXX"

Options:
  --game=<CODE>      6-character DabHousie invite code
  --url=<URL>        Full join URL
  --players=<N>      Number of automated players (default: 3)
  --show / --headed  Run with visible browser windows (default)
  --hide / --headless Run in background without windows
===================================================================
`);
    process.exit(1);
  }

  console.log(`
===================================================================
  DABHOUSIE MULTIPLAYER TEST HARNESS (Phase 1)
===================================================================
  Target Game Code : ${options.gameCode}
  Target Join URL  : ${options.joinUrl}
  Automated Players: ${options.playersCount}
  Mode             : ${options.headless ? 'Headless' : 'Headed (Visible Windows)'}
===================================================================
`);

  const windowWidth = 430;
  const windowHeight = 780;
  const players = [];

  const REAL_NAMES = [
    'Aarav', 'Priya', 'Rohan', 'Maya', 'Liam', 'Sophia', 'Noah', 'Ananya',
    'Kabir', 'Emma', 'Oliver', 'Diya', 'Carlos', 'Chloe', 'Arjun', 'Sneha',
    'Vikram', 'Aisha', 'Ethan', 'Mia', 'Rahul', 'Zara', 'Siddharth', 'Elena',
    'Kavya', 'Leo', 'Tara', 'Aditya', 'Meera', 'Sam', 'Rhea', 'Lucas'
  ];
  const shuffledNames = [...REAL_NAMES].sort(() => 0.5 - Math.random());

  // Register clean shutdown
  let isShuttingDown = false;
  async function cleanup() {
    if (isShuttingDown) return;
    isShuttingDown = true;
    console.log('\nStopping automated player sessions...');
    await Promise.allSettled(players.map(p => p.close()));
    console.log('All player sessions stopped cleanly.');
    process.exit(0);
  }

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  try {
    // 1. Launch players with side-by-side desktop positioning
    for (let i = 1; i <= options.playersCount; i++) {
      const xPos = (i - 1) * (windowWidth + 15) + 30;
      const yPos = 40;
      const playerName = shuffledNames[(i - 1) % shuffledNames.length];
      const player = new PlayerSession(i, playerName, {
        x: xPos,
        y: yPos,
        width: windowWidth,
        height: windowHeight,
      });

      await player.launch(chromium, options.headless);
      players.push(player);
    }

    // 2. Join all players to the game
    console.log('\n[CONNECTING] Connecting and registering players into game room...');
    const joinResults = [];
    for (const p of players) {
      try {
        const res = await p.joinGame(options.joinUrl);
        joinResults.push({ status: res ? 'fulfilled' : 'rejected' });
      } catch (err) {
        joinResults.push({ status: 'rejected', reason: err });
      }
      await new Promise(r => setTimeout(r, 600));
    }

    const successfulJoins = players.filter((p, idx) => 
      joinResults[idx]?.status === 'fulfilled' && 
      (p.successfulRegistrations > 0 || p.seatStatus === 'CONFIRMED' || p.status.includes('REGISTERED'))
    );

    // 3. Print Detailed Registration Diagnostics
    console.log(`
=====================================================
REGISTRATION DIAGNOSTICS
=====================================================`);
    for (let i = 0; i < players.length; i++) {
      const p = players[i];
      const diag = p.getDiagnostics();
      console.log(`Player ${diag.playerId}
  UUID: ${diag.userUuid}
  Name: ${diag.displayName}
  Game ID: ${diag.gameId}
  Invite Code: ${diag.inviteCode}
  Registration attempts: ${diag.registrationAttempts}
  Successful registrations: ${diag.successfulRegistrations}
  Seat Status: ${diag.seatStatus} (Ticket #${diag.ticketNumber})
  Final URL: ${diag.finalUrl}
`);
    }
    console.log(`=====================================================
Expected registrations : ${options.playersCount}
Successful in test     : ${successfulJoins.length}
=====================================================
`);

    if (successfulJoins.length === 0) {
      console.error('No players successfully registered into the lobby. Please verify game code and status.');
      return;
    }

    console.log('\nWaiting for Organizer to start game...\n');

    // 4. Wait for Organizer to Start Game
    await Promise.all(successfulJoins.map(p => p.waitForGameStart()));

    console.log(`
=====================================================
Game status: IN_PROGRESS
=====================================================
`);
    for (const p of successfulJoins) {
      console.log(`Player ${p.id}: PLAYING`);
    }

    // 5. Inspect and extract ticket numbers for each player
    console.log('\n--- VERIFYING PLAYER TICKETS ---');
    for (const p of successfulJoins) {
      await p.inspectAndExtractTicketNumbers();
    }
    console.log('--------------------------------\n');

    // 6. Realtime Game Loop: Observe called numbers and auto-dab
    console.log('--- OBSERVING CALLED NUMBERS ---');
    let callSequence = 0;
    let isGameCompleted = false;
    let roomLastCalledNumber = null;

    while (!isGameCompleted && !isShuttingDown) {
      let activeCall = null;

      for (const p of successfulJoins) {
        const status = await p.getCurrentCalledNumber();
        if (status.isCompleted) {
          isGameCompleted = true;
          break;
        }
        if (status.number && status.number !== roomLastCalledNumber) {
          activeCall = status.number;
          break;
        }
      }

      if (activeCall) {
        callSequence++;
        roomLastCalledNumber = activeCall;
        console.log(`\n>>> [CALL #${callSequence}] NUMBER ANNOUNCED: ${activeCall} <<<`);
        
        // Process this called number for all players
        for (const p of successfulJoins) {
          await p.processCalledNumber(activeCall, callSequence);
        }
      }

      await new Promise(r => setTimeout(r, 1200));
    }

    if (isGameCompleted) {
      console.log(`
=====================================================
Game status: COMPLETED
All 90 numbers called or game concluded.
=====================================================
`);
    }

    console.log('Test run finished. Press Ctrl+C to close player windows.');
    while (!isShuttingDown) {
      await new Promise(r => setTimeout(r, 5000));
    }

  } catch (err) {
    console.error('\nMultiplayer test runner encountered an error:', err.message);
    console.log('Keeping any active browser sessions open for inspection. Press Ctrl+C to exit.');
    while (!isShuttingDown) {
      await new Promise(r => setTimeout(r, 5000));
    }
  }
}

main();
