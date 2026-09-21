import { chromium } from 'playwright';
import { PlayerSession } from './player_session.js';
import { generateTestReport } from './report_generator.js';

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
  DABHOUSIE MULTIPLAYER TEST HARNESS & STRESS SUITE
===================================================================
  Target Game Code : ${options.gameCode}
  Target Join URL  : ${options.joinUrl}
  Automated Players: ${options.playersCount}
  Mode             : ${options.headless ? 'Headless (Background)' : 'Headed (Visible Windows)'}
===================================================================
`);

  const windowWidth = 430;
  const windowHeight = 860;
  const players = [];
  const drawnCallsList = [];
  const startTime = Date.now();

  const REAL_NAMES = [
    'Aarav', 'Priya', 'Rohan', 'Maya', 'Liam', 'Sophia', 'Noah', 'Ananya',
    'Kabir', 'Emma', 'Oliver', 'Diya', 'Carlos', 'Chloe', 'Arjun', 'Sneha',
    'Vikram', 'Aisha', 'Ethan', 'Mia', 'Rahul', 'Zara', 'Siddharth', 'Elena',
    'Kavya', 'Leo', 'Tara', 'Aditya', 'Meera', 'Sam', 'Rhea', 'Lucas'
  ];
  const shuffledNames = [...REAL_NAMES].sort(() => 0.5 - Math.random());

  function saveFinalReport(status = 'COMPLETED') {
    try {
      const playersData = players.map(p => p.getSessionSummary());
      const allClaims = players.flatMap(p => p.claimsHistory || []);
      const durationSec = Math.round((Date.now() - startTime) / 1000);
      const gameMetadata = {
        gameCode: options.gameCode,
        gameId: players[0]?.gameId || options.gameCode,
        status,
        durationSeconds: durationSec,
      };
      generateTestReport(gameMetadata, playersData, drawnCallsList, allClaims);
    } catch (err) {
      console.error('Error generating final test report:', err.message);
    }
  }

  let browserInstance = null;

  // Register clean shutdown
  let isShuttingDown = false;
  async function cleanup() {
    if (isShuttingDown) return;
    isShuttingDown = true;
    console.log('\nStopping automated player sessions...');
    saveFinalReport('STOPPED');
    await Promise.allSettled(players.map(p => p.close()));
    if (browserInstance) {
      try { await browserInstance.close(); } catch (_) {}
    }
    console.log('All player sessions stopped cleanly.');
    process.exit(0);
  }

  process.on('SIGINT', cleanup);
  process.on('SIGTERM', cleanup);

  try {
    // 1. Launch shared Chromium browser
    console.log(`\n[BROWSER] Launching Chromium browser (${options.headless ? 'Headless' : 'Headed'})...`);
    browserInstance = await chromium.launch({
      headless: options.headless,
      args: [
        '--disable-notifications',
        '--disable-dev-shm-usage',
      ],
    });

    // 2. Connect and register players into game room
    console.log('\n[CONNECTING] Connecting and registering players into game room...');
    const joinResults = [];

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

      await player.launch(browserInstance, options.headless);
      players.push(player);

      const tStart = Date.now();
      try {
        const res = await player.joinGame(options.joinUrl);
        player.registrationTimeMs = Date.now() - tStart;
        joinResults.push({ status: res ? 'fulfilled' : 'rejected' });
      } catch (err) {
        joinResults.push({ status: 'rejected', reason: err });
      }
      await new Promise(r => setTimeout(r, 400));
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
    const processedCallSeqs = new Set();
    const processedNumbers = new Set();
    let isGameCompleted = false;

    while (!isGameCompleted && !isShuttingDown) {
      let activeCallsList = [];
      let singleActiveNum = null;

      for (const p of successfulJoins) {
        const status = await p.getCurrentCalledNumber();
        if (status.isCompleted) {
          isGameCompleted = true;
          break;
        }
        if (status.allCalls && status.allCalls.length > 0) {
          activeCallsList = status.allCalls;
        }
        if (status.number) {
          singleActiveNum = status.number;
        }
      }

      if (activeCallsList.length > 0) {
        for (const call of activeCallsList) {
          const seq = call.call_seq || (processedCallSeqs.size + 1);
          const num = call.number;
          if (!processedCallSeqs.has(seq)) {
            processedCallSeqs.add(seq);
            processedNumbers.add(num);
            drawnCallsList.push({ sequence: seq, number: num, timestamp: new Date().toISOString() });
            console.log(`\n>>> [CALL #${seq}] NUMBER ANNOUNCED: ${num} <<<`);
            for (const p of successfulJoins) {
              await p.processCalledNumber(num, seq);
            }
          }
        }
      } else if (singleActiveNum && !processedNumbers.has(singleActiveNum)) {
        const seq = processedCallSeqs.size + 1;
        processedCallSeqs.add(seq);
        processedNumbers.add(singleActiveNum);
        drawnCallsList.push({ sequence: seq, number: singleActiveNum, timestamp: new Date().toISOString() });
        console.log(`\n>>> [CALL #${seq}] NUMBER ANNOUNCED: ${singleActiveNum} <<<`);
        for (const p of successfulJoins) {
          await p.processCalledNumber(singleActiveNum, seq);
        }
      }

      await new Promise(r => setTimeout(r, 1000));
    }

    if (isGameCompleted) {
      console.log(`
=====================================================
Game status: COMPLETED
All numbers called or game concluded.
=====================================================
`);
      saveFinalReport('COMPLETED');
    }

    console.log('Test run finished. Press Ctrl+C to close player windows.');
    while (!isShuttingDown) {
      await new Promise(r => setTimeout(r, 5000));
    }

  } catch (err) {
    console.error('\nMultiplayer test runner encountered an error:', err.message);
    saveFinalReport('ERROR');
    console.log('Keeping any active browser sessions open for inspection. Press Ctrl+C to exit.');
    while (!isShuttingDown) {
      await new Promise(r => setTimeout(r, 5000));
    }
  }
}

main();
