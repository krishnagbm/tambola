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
    keepOpen: false,
    desktop: false,
    hd: false,
    width: null,
    height: null,
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
    } else if (arg === '--keep-open' || arg === '--keepOpen' || arg === '--no-close') {
      options.keepOpen = true;
    } else if (arg === '--desktop' || arg === '--desktop=true') {
      options.desktop = true;
    } else if (arg === '--hd' || arg === '--fhd' || arg === '--1080p') {
      options.hd = true;
    } else if (arg.startsWith('--width=')) {
      options.width = parseInt(arg.split('=')[1].trim(), 10);
    } else if (arg.startsWith('--height=')) {
      options.height = parseInt(arg.split('=')[1].trim(), 10);
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

  const isHd = options.hd;
  const isDesktop = options.desktop || isHd || (options.playersCount === 1 && !options.width);
  const windowWidth = options.width || (isHd ? 1920 : (isDesktop ? 1280 : 430));
  const windowHeight = options.height || (isHd ? 1080 : (isDesktop ? 800 : 860));
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

  let lastReportStatus = null;
  function saveFinalReport(status = 'COMPLETED') {
    try {
      lastReportStatus = status;
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
    if (lastReportStatus !== 'COMPLETED') {
      saveFinalReport('STOPPED');
    }
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
    console.log(`\n[BROWSER] Launching Chromium browser (${options.headless ? 'Headless' : 'Headed'}) [${windowWidth}x${windowHeight} viewport]...`);
    const launchArgs = [
      '--disable-notifications',
      '--disable-dev-shm-usage',
    ];
    if (isDesktop) {
      launchArgs.push(`--window-size=${windowWidth + 16},${windowHeight + 84}`);
    }
    browserInstance = await chromium.launch({
      headless: options.headless,
      args: launchArgs,
    });

    // 2. Resolve game ID upfront from Supabase and fetch existing registrations
    let resolvedGameId = null;
    let existingRegs = [];
    try {
      const gRes = await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_games?invite_code=eq.${options.gameCode.toUpperCase()}&select=id,status,name,funded_capacity`, {
        headers: {
          'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
          'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
        }
      });
      const gList = await gRes.json();
      if (gList && gList.length > 0) {
        resolvedGameId = gList[0].id;
        console.log(`[ROOM] Resolved game "${gList[0].name}" [UUID: ${resolvedGameId}, Capacity: ${gList[0].funded_capacity}]`);

        const rRes = await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_game_registrations?game_id=eq.${resolvedGameId}&order=registration_seq.asc&select=*`, {
          headers: {
            'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
            'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
          }
        });
        existingRegs = await rRes.json();
      }
    } catch (_) {}

    // 3. Connect and register players into game room
    console.log('\n[CONNECTING] Connecting and registering players into game room...');
    const joinResults = [];

    for (let i = 1; i <= options.playersCount; i++) {
      const xPos = (i - 1) * (windowWidth + 15) + 30;
      const yPos = 40;
      const matchedReg = Array.isArray(existingRegs) ? (existingRegs.find(r => r.registration_seq === i) || existingRegs[i - 1]) : null;
      const playerName = matchedReg?.display_name || shuffledNames[(i - 1) % shuffledNames.length];
      const player = new PlayerSession(i, playerName, {
        x: xPos,
        y: yPos,
        width: windowWidth,
        height: windowHeight,
      }, options.baseUrl);

      await player.launch(browserInstance, options.headless);
      players.push(player);

      const tStart = Date.now();
      try {
        const res = await player.joinGame(options.joinUrl, resolvedGameId);
        player.registrationTimeMs = Date.now() - tStart;
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
Game status: COMPLETED (Main Tambola Game Concluded)
=====================================================
`);

      // Check if DabHousie Recall Trivia is enabled for this game (Corporate packs)
      console.log('[POST-GAME] Checking for DabHousie Recall Trivia...');
      let triviaRound = null;
      try {
        const trRes = await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_game_trivia_rounds?game_id=eq.${resolvedGameId}&select=*`, {
          headers: {
            'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
            'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
          }
        });
        if (trRes.ok) {
          const list = await trRes.json();
          if (Array.isArray(list) && list.length > 0 && list[0].status !== 'CANCELLED') {
            triviaRound = list[0];
          }
        }
      } catch (_) {}

      if (triviaRound) {
        console.log(`
=====================================================
🧠 DABHOUSIE RECALL TRIVIA DETECTED (Corporate Event)
Total Questions: ${triviaRound.total_questions || triviaRound.questions?.length || 4}
Timing Gap: ${triviaRound.time_gap_seconds || 15}s
=====================================================
Waiting for Trivia countdown and questions...
`);

        let triviaDone = false;
        let lastReportedQIdx = -1;

        while (!triviaDone && !isShuttingDown) {
          try {
            const trPoll = await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_game_trivia_rounds?id=eq.${triviaRound.id}&select=*`, {
              headers: {
                'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
                'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
              }
            });
            if (trPoll.ok) {
              const updatedList = await trPoll.json();
              const updated = updatedList ? updatedList[0] : null;
              if (!updated || updated.status === 'COMPLETED' || updated.status === 'CANCELLED') {
                triviaDone = true;
                break;
              }

              if (updated.status === 'ACTIVE' && updated.current_question_index != null) {
                if (updated.current_question_index !== lastReportedQIdx) {
                  lastReportedQIdx = updated.current_question_index;
                  const totalQ = updated.questions?.length || updated.total_questions || 4;
                  console.log(`\n📢 [TRIVIA Q#${lastReportedQIdx + 1}/${totalQ}] "${curQ?.question}"`);
                }

                // Have all automated players evaluate and answer
                for (const p of successfulJoins) {
                  await p.playTriviaQuestion(updated);
                }

                // If running without Live Display open, auto-advance question after the window
                const qDuration = (updated.seconds_per_question || 15);
                console.log(`⏱️ Question window open for ${qDuration}s...`);
                await new Promise(r => setTimeout(r, qDuration * 1000));

                const nextIdx = updated.current_question_index + 1;
                const totalQ = updated.questions ? updated.questions.length : 4;
                if (nextIdx >= totalQ) {
                  console.log('\n🏁 Final question completed! Finalizing Trivia Podium...');
                  await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/rpc/MPT_finalize_game_trivia`, {
                    method: 'POST',
                    headers: {
                      'Content-Type': 'application/json',
                      'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
                      'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
                    },
                    body: JSON.stringify({ p_game_id: resolvedGameId })
                  });
                } else {
                  console.log(`\n➡️ Advancing to Question ${nextIdx + 1}/${totalQ}...`);
                  await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_game_trivia_rounds?id=eq.${triviaRound.id}`, {
                    method: 'PATCH',
                    headers: {
                      'Content-Type': 'application/json',
                      'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
                      'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
                      'Prefer': 'return=minimal'
                    },
                    body: JSON.stringify({ current_question_index: nextIdx })
                  });
                }
              } else if (updated.status === 'COUNTDOWN') {
                process.stdout.write('.');
              }
            }
          } catch (_) {}

          await new Promise(r => setTimeout(r, 1000));
        }

        // Fetch final Trivia Winners Podium
        try {
          const wRes = await fetch(`https://itfcnurjrnyalauwwdkj.supabase.co/rest/v1/MPT_trivia_winners?game_id=eq.${resolvedGameId}&order=rank.asc&select=*`, {
            headers: {
              'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI',
              'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI'
            }
          });
          if (wRes.ok) {
            const winners = await wRes.json();
            if (winners && winners.length > 0) {
              console.log(`
=====================================================
🏆 DABHOUSIE TRIVIA OFFICIAL PODIUM
=====================================================`);
              for (const w of winners) {
                const medal = w.rank === 1 ? '🥇' : (w.rank === 2 ? '🥈' : (w.rank === 3 ? '🥉' : (w.rank === 4 ? '🎖️' : (w.rank === 5 ? '🌟' : `#${w.rank}`))));
                console.log(`  ${medal} Rank ${w.rank}: ${w.user_name} (${w.title}) — ${w.total_score} pts`);
              }
              console.log('=====================================================\n');
            }
          }
        } catch (_) {}

      } else {
        console.log('[POST-GAME] No Trivia round active (Family Pack or Trivia disabled). Game concluded.');
      }

      saveFinalReport('COMPLETED');
      if (options.headless) {
        console.log('\n[COMPLETE] Headless test run finished. Cleaning up...');
        await cleanup();
        return;
      }

      console.log('\n=====================================================');
      console.log('🎉 GAME & TRIVIA CONCLUDED!');
      console.log('Browser window remains open for podium review & recording.');
      console.log('👉 Press Ctrl+C in this terminal when you are finished.');
      console.log('=====================================================\n');
      while (!isShuttingDown) {
        await new Promise(r => setTimeout(r, 2000));
      }
    }

  } catch (err) {
    console.error('\nMultiplayer test runner encountered an error:', err.message);
    saveFinalReport('ERROR');
    if (options.keepOpen) {
      console.log('Keeping active browser sessions open for inspection. Press Ctrl+C to exit.');
      while (!isShuttingDown) {
        await new Promise(r => setTimeout(r, 5000));
      }
    } else {
      await cleanup();
    }
  }
}

main();
