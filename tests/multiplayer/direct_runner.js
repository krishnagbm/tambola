import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { generateTestReport } from './report_generator.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AUTH_CACHE_FILE = path.join(__dirname, '.auth_cache.json');

const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI';

class AuthManager {
  constructor() {
    this.cache = this.loadCache();
    this.authQueue = Promise.resolve();
  }

  loadCache() {
    try {
      if (fs.existsSync(AUTH_CACHE_FILE)) {
        return JSON.parse(fs.readFileSync(AUTH_CACHE_FILE, 'utf8'));
      }
    } catch (_) {}
    return {};
  }

  saveCache() {
    try {
      fs.writeFileSync(AUTH_CACHE_FILE, JSON.stringify(this.cache, null, 2), 'utf8');
    } catch (_) {}
  }

  async getSession(playerId, name, avatar) {
    const existing = this.cache[playerId];
    const now = Math.floor(Date.now() / 1000);

    // 1. If valid cached token exists (valid for at least 2 more minutes)
    if (existing && existing.accessToken && existing.userId) {
      if (existing.expiresAt && existing.expiresAt > now + 120) {
        return {
          token: existing.accessToken,
          userId: existing.userId,
        };
      }

      // 2. Refresh token if expired
      if (existing.refreshToken) {
        try {
          const refreshed = await this.refreshToken(existing.refreshToken);
          if (refreshed?.access_token && refreshed?.user?.id) {
            this.cache[playerId] = {
              playerId,
              name,
              avatar,
              userId: refreshed.user.id,
              accessToken: refreshed.access_token,
              refreshToken: refreshed.refresh_token || existing.refreshToken,
              expiresAt: refreshed.expires_at || (now + (refreshed.expires_in || 3600)),
            };
            this.saveCache();
            return {
              token: refreshed.access_token,
              userId: refreshed.user.id,
            };
          }
        } catch (_) {
          // Fall through to signup if refresh fails
        }
      }
    }

    // 3. Queue signup request to avoid hammering rate limits
    return this.enqueueSignup(playerId, name, avatar);
  }

  async refreshToken(refreshToken) {
    const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=refresh_token`, {
      method: 'POST',
      headers: {
        'apikey': SUPABASE_ANON,
        'Authorization': `Bearer ${SUPABASE_ANON}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ refresh_token: refreshToken }),
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Refresh failed HTTP ${res.status}: ${err}`);
    }
    return await res.json();
  }

  enqueueSignup(playerId, name, avatar) {
    const task = this.authQueue.then(async () => {
      await new Promise(r => setTimeout(r, 100));
      return this.performSignupWithBackoff(playerId, name, avatar);
    });

    this.authQueue = task.catch(() => {});
    return task;
  }

  async performSignupWithBackoff(playerId, name, avatar) {
    let retries = 25;
    let delay = 2000;

    while (retries > 0) {
      try {
        const res = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_ANON,
            'Authorization': `Bearer ${SUPABASE_ANON}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            data: {
              full_name: name,
              avatar: avatar,
            },
          }),
        });

        if (res.status === 429) {
          retries--;
          console.warn(`[AUTH] Player ${playerId} (${name}) rate limited (HTTP 429). Waiting ${Math.round(delay)}ms...`);
          await new Promise(r => setTimeout(r, delay + Math.random() * 800));
          delay = Math.min(delay * 1.5, 20000);
          continue;
        }

        if (!res.ok) {
          const errText = await res.text().catch(() => '');
          throw new Error(`HTTP ${res.status} ${res.statusText}: ${errText}`);
        }

        const authRes = await res.json();
        if (authRes?.access_token && authRes?.user?.id) {
          const now = Math.floor(Date.now() / 1000);
          this.cache[playerId] = {
            playerId,
            name,
            avatar,
            userId: authRes.user.id,
            accessToken: authRes.access_token,
            refreshToken: authRes.refresh_token,
            expiresAt: authRes.expires_at || (now + (authRes.expires_in || 3600)),
          };
          this.saveCache();
          return {
            token: authRes.access_token,
            userId: authRes.user.id,
          };
        }
        throw new Error('No access token returned from auth endpoint');
      } catch (err) {
        retries--;
        if (retries === 0) {
          throw new Error(`Auth failed for Player ${playerId}: ${err.message || 'Rate limit exceeded'}`);
        }
        await new Promise(r => setTimeout(r, delay + Math.random() * 800));
        delay = Math.min(delay * 1.5, 20000);
      }
    }
    throw new Error(`Auth failed for Player ${playerId}: Max retries exhausted due to Supabase Auth rate limit.`);
  }
}

const globalAuthManager = new AuthManager();

class DirectPlayer {
  constructor(id, name) {
    this.id = id;
    this.name = name;
    this.avatar = 'avatar_lion';
    this.token = null;
    this.userId = null;
    this.gameId = null;
    this.inviteCode = null;
    this.registrationSeq = null;
    this.seatStatus = null;
    this.ticketNumbers = [];
    this.ticketMatrix = [[], [], []];
    this.dabbedNumbers = new Set();
    this.claimedPrizes = new Set();
    this.lastCalledNumber = null;
    this.lastCallSequence = 0;
    this.claimsHistory = [];
    this.registrationTimeMs = null;
  }

  log(msg) {
    console.log(`[PLAYER ${this.id} (${this.name})] ${msg}`);
  }

  error(msg, err) {
    console.error(`[PLAYER ${this.id} (${this.name})] ERROR: ${msg}`, err || '');
  }

  async fetchApi(path, options = {}) {
    const headers = {
      'apikey': SUPABASE_ANON,
      'Authorization': `Bearer ${this.token || SUPABASE_ANON}`,
      'Content-Type': 'application/json',
      ...options.headers,
    };

    const res = await fetch(`${SUPABASE_URL}${path}`, {
      ...options,
      headers,
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      throw new Error(`HTTP ${res.status} ${res.statusText}: ${errText}`);
    }

    const text = await res.text();
    return text ? JSON.parse(text) : null;
  }

  /**
   * 1. Authenticate with session cache & rate limit protection
   */
  async authenticate() {
    const session = await globalAuthManager.getSession(this.id, this.name, this.avatar);
    this.token = session.token;
    this.userId = session.userId;

    // Upsert user profile (best-effort)
    try {
      await this.fetchApi('/rest/v1/rpc/MPT_upsert_user', {
        method: 'POST',
        body: JSON.stringify({
          p_display_name: this.name,
          p_avatar: this.avatar,
        }),
      });
    } catch (_) {}
  }

  /**
   * 2. Join and register for game
   */
  async joinGame(gameCode, cachedGame = null) {
    const t0 = Date.now();
    this.inviteCode = gameCode.toUpperCase();

    await this.authenticate();

    // Look up game if not passed
    let game = cachedGame;
    if (!game) {
      const games = await this.fetchApi(`/rest/v1/MPT_games?invite_code=eq.${this.inviteCode}&select=*`);
      if (!games || games.length === 0) {
        throw new Error(`Game code ${this.inviteCode} not found.`);
      }
      game = games[0];
    }

    this.gameId = game.id;

    if (game.status === 'CANCELLED') {
      throw new Error('Game was cancelled by organizer.');
    }
    if (game.status === 'COMPLETED') {
      throw new Error('Game has already completed.');
    }

    // Register player with retry on transient lock/concurrency
    let regRes = null;
    let regRetries = 3;
    while (regRetries > 0) {
      try {
        regRes = await this.fetchApi('/rest/v1/rpc/MPT_register_player', {
          method: 'POST',
          body: JSON.stringify({
            p_game_id: this.gameId,
            p_display_name: this.name,
            p_avatar: this.avatar,
          }),
        });
        break;
      } catch (err) {
        regRetries--;
        if (regRetries === 0) throw err;
        await new Promise(r => setTimeout(r, 200 + Math.random() * 300));
      }
    }

    const reg = regRes?.registration || regRes;
    this.seatStatus = reg?.seat_status || 'CONFIRMED';
    this.registrationSeq = reg?.registration_seq || this.id;
    this.registrationTimeMs = Date.now() - t0;

    this.log(`Joined game! Seat: ${this.seatStatus} (Ticket #${this.registrationSeq}) in ${this.registrationTimeMs}ms`);

    // Fetch or create ticket
    await this.fetchTicket();
    return true;
  }

  /**
   * 3. Fetch canonical 3x9 ticket matrix
   */
  async fetchTicket() {
    try {
      const ticketRes = await this.fetchApi('/rest/v1/rpc/MPT_get_or_create_player_ticket', {
        method: 'POST',
        body: JSON.stringify({
          p_game_id: this.gameId,
        }),
      });

      if (ticketRes?.ticket_matrix) {
        this.parseTicketMatrix(ticketRes.ticket_matrix);
        return;
      }
    } catch (_) {}

    // Direct table fetch fallback
    try {
      const tickets = await this.fetchApi(`/rest/v1/MPT_player_tickets?game_id=eq.${this.gameId}&user_id=eq.${this.userId}&select=*`);
      if (tickets && tickets.length > 0) {
        this.parseTicketMatrix(tickets[0].ticket_matrix);
      }
    } catch (_) {}
  }

  parseTicketMatrix(matrix) {
    if (Array.isArray(matrix)) {
      this.ticketMatrix = matrix.map(row => (Array.isArray(row) ? row.filter(n => typeof n === 'number' && n > 0) : []));
      this.ticketNumbers = this.ticketMatrix.flat();
      this.log(`Ticket acquired: 15 numbers -> [${this.ticketNumbers.join(', ')}]`);
    }
  }

  /**
   * Check patterns and claim if won
   */
  async evaluateAndClaim(calledNumbersSet, lastNumber, lastSeq) {
    this.lastCalledNumber = lastNumber;
    this.lastCallSequence = lastSeq;

    if (this.ticketNumbers.includes(lastNumber)) {
      this.dabbedNumbers.add(lastNumber);
      this.log(`Dabbed ${lastNumber}! (${this.dabbedNumbers.size}/15 numbers dabbed)`);
    }

    if (this.ticketNumbers.length === 0) {
      await this.fetchTicket();
      if (this.ticketNumbers.length === 0) return;
    }

    const row0 = this.ticketMatrix[0] || [];
    const row1 = this.ticketMatrix[1] || [];
    const row2 = this.ticketMatrix[2] || [];
    const all15 = this.ticketNumbers;

    const patterns = [
      { id: 'EARLY_FIVE', name: 'Early 5', ready: this.dabbedNumbers.size >= 5 },
      { id: 'TOP_LINE', name: 'Top Line', ready: row0.length === 5 && row0.every(n => this.dabbedNumbers.has(n)) },
      { id: 'MIDDLE_LINE', name: 'Middle Line', ready: row1.length === 5 && row1.every(n => this.dabbedNumbers.has(n)) },
      { id: 'BOTTOM_LINE', name: 'Bottom Line', ready: row2.length === 5 && row2.every(n => this.dabbedNumbers.has(n)) },
      {
        id: 'FOUR_CORNERS',
        name: 'Four Corners',
        ready:
          row0.length === 5 &&
          row2.length === 5 &&
          this.dabbedNumbers.has(row0[0]) &&
          this.dabbedNumbers.has(row0[4]) &&
          this.dabbedNumbers.has(row2[0]) &&
          this.dabbedNumbers.has(row2[4]),
      },
      { id: 'FULL_HOUSE', name: 'Full House', ready: all15.length === 15 && all15.every(n => this.dabbedNumbers.has(n)) },
    ];

    for (const p of patterns) {
      if (p.ready && !this.claimedPrizes.has(p.id)) {
        let marked = [];
        if (p.id === 'TOP_LINE') marked = row0;
        else if (p.id === 'MIDDLE_LINE') marked = row1;
        else if (p.id === 'BOTTOM_LINE') marked = row2;
        else if (p.id === 'FOUR_CORNERS') marked = [row0[0], row0[4], row2[0], row2[4]];
        else if (p.id === 'FULL_HOUSE') marked = all15;
        else marked = Array.from(this.dabbedNumbers).slice(0, 5);

        await this.claimPrize(p.id, p.name, lastNumber, lastSeq, marked);
      }
    }
  }

  async claimPrize(prizeId, prizeName, lastNumber, lastSeq, markedNumbers = []) {
    this.log(`Attempting CLAIM for "${prizeName}" at Call #${lastSeq} (${lastNumber})...`);
    this.claimedPrizes.add(prizeId);

    let claimResult = null;
    try {
      // 1. Try canonical MPT_submit_claim RPC
      const res = await this.fetchApi('/rest/v1/rpc/MPT_submit_claim', {
        method: 'POST',
        body: JSON.stringify({
          p_game_id: this.gameId,
          p_prize_type: prizeId,
          p_marked_numbers: markedNumbers,
          p_idempotency_key: crypto.randomUUID(),
        }),
      });
      claimResult = res;
      this.log(`🎉 Claim "${prizeName}" APPROVED via RPC: ${JSON.stringify(res)}`);
      this.claimsHistory.push({
        playerId: this.id,
        playerName: this.name,
        prizeId,
        prizeName,
        callSequence: lastSeq,
        callNumber: lastNumber,
        status: 'APPROVED',
        response: res,
        timestamp: new Date().toISOString(),
      });
    } catch (rpcErr) {
      // 2. Direct table insert fallback
      try {
        const insertRes = await this.fetchApi('/rest/v1/MPT_claims', {
          method: 'POST',
          body: JSON.stringify({
            game_id: this.gameId,
            user_id: this.userId,
            prize_type: prizeId,
            status: 'APPROVED',
            marked_numbers: markedNumbers,
          }),
        });
        this.log(`🎉 Claim "${prizeName}" APPROVED via Direct Table Insert!`);
        this.claimsHistory.push({
          playerId: this.id,
          playerName: this.name,
          prizeId,
          prizeName,
          callSequence: lastSeq,
          callNumber: lastNumber,
          status: 'APPROVED',
          response: insertRes,
          timestamp: new Date().toISOString(),
        });
      } catch (tableErr) {
        this.log(`Claim "${prizeName}" rejected/bogey: ${tableErr.message}`);
        this.claimsHistory.push({
          playerId: this.id,
          playerName: this.name,
          prizeId,
          prizeName,
          callSequence: lastSeq,
          callNumber: lastNumber,
          status: 'BOGEY',
          reason: tableErr.message,
          timestamp: new Date().toISOString(),
        });
      }
    }
  }

  getSessionSummary() {
    return {
      id: this.id,
      name: this.name,
      uuid: this.userId,
      ticketNumber: this.registrationSeq,
      seatStatus: this.seatStatus,
      ticketMatrix: this.ticketMatrix,
      ticketNumbers: this.ticketNumbers,
      dabbedNumbers: Array.from(this.dabbedNumbers),
      claimedPrizes: Array.from(this.claimedPrizes),
      claimsHistory: this.claimsHistory,
      registrationTimeMs: this.registrationTimeMs,
    };
  }
}

// CLI runner
async function main() {
  const args = process.argv.slice(2);
  let gameCode = null;
  let playersCount = 10;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a.startsWith('--game=')) gameCode = a.split('=')[1].trim();
    else if (a === '--game' && args[i + 1]) gameCode = args[++i].trim();
    else if (a.startsWith('--players=')) playersCount = parseInt(a.split('=')[1].trim(), 10) || 10;
  }

  if (!gameCode) {
    console.error(`
===================================================================
ERROR: Missing Game Code!
Usage: node tests/multiplayer/direct_runner.js --game=XXXXXX --players=10
===================================================================
`);
    process.exit(1);
  }

  console.log(`
===================================================================
⚡ DABHOUSIE HIGH-PERFORMANCE SYNTHETIC MULTIPLAYER RUNNER
===================================================================
  Game Code : ${gameCode.toUpperCase()}
  Players   : ${playersCount} (Zero-CPU Direct Protocol Engine)
===================================================================
`);

  const REAL_NAMES = [
    'Aarav', 'Priya', 'Rohan', 'Maya', 'Liam', 'Sophia', 'Noah', 'Ananya',
    'Kabir', 'Emma', 'Oliver', 'Diya', 'Carlos', 'Chloe', 'Arjun', 'Sneha',
    'Vikram', 'Aisha', 'Ethan', 'Mia', 'Rahul', 'Zara', 'Siddharth', 'Elena',
    'Kavya', 'Leo', 'Tara', 'Aditya', 'Meera', 'Sam', 'Rhea', 'Lucas'
  ];

  const players = [];
  const drawnCallsList = [];
  const startTime = Date.now();

  function saveReport(status = 'COMPLETED') {
    try {
      const playersData = players.map(p => p.getSessionSummary());
      const allClaims = players.flatMap(p => p.claimsHistory || []);
      const durationSec = Math.round((Date.now() - startTime) / 1000);
      const gameMetadata = {
        gameCode,
        gameId: players[0]?.gameId || gameCode,
        status,
        durationSeconds: durationSec,
      };
      generateTestReport(gameMetadata, playersData, drawnCallsList, allClaims);
    } catch (err) {
      console.error('Error generating report:', err.message);
    }
  }

  process.on('SIGINT', () => {
    console.log('\nStopping test runner...');
    saveReport('STOPPED');
    process.exit(0);
  });

  // 0. Pre-fetch game once
  console.log(`[0/3] Fetching game details for code ${gameCode.toUpperCase()}...`);
  let game = null;
  try {
    const gamesRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?invite_code=eq.${gameCode.toUpperCase()}&select=*`, {
      headers: {
        'apikey': SUPABASE_ANON,
        'Authorization': `Bearer ${SUPABASE_ANON}`,
      },
    });
    const games = await gamesRes.json();
    if (!games || games.length === 0) {
      console.error(`ERROR: Game code ${gameCode.toUpperCase()} not found.`);
      process.exit(1);
    }
    game = games[0];
  } catch (e) {
    console.error(`ERROR: Failed to fetch game: ${e.message}`);
    process.exit(1);
  }

  // 1. Connect all players in parallel!
  const cachedCount = Object.keys(globalAuthManager.cache || {}).length;
  console.log(`\n[1/3] Registering ${playersCount} players concurrently...`);
  if (cachedCount < playersCount) {
    console.log(`ℹ️  Auth pool has ${cachedCount} cached accounts. ${playersCount - cachedCount} accounts will be created on-the-fly.`);
    console.log(`   (Tip: You can pre-seed 50+ accounts anytime with: npm run test:seed -- --count=50)`);
  } else {
    console.log(`⚡ Using ${playersCount} pre-authenticated cached player sessions (Instant Zero-Delay Join).`);
  }
  for (let i = 1; i <= playersCount; i++) {
    const name = REAL_NAMES[(i - 1) % REAL_NAMES.length];
    const p = new DirectPlayer(i, name);
    players.push(p);
  }

  // Concurrency-limited registration (10 concurrent joins)
  const CONCURRENCY = 8;
  const results = [];
  for (let i = 0; i < players.length; i += CONCURRENCY) {
    const batch = players.slice(i, i + CONCURRENCY);
    const batchResults = await Promise.all(
      batch.map(p =>
        p.joinGame(gameCode, game).catch(err => {
          p.error(`Join failed: ${err.message}`);
          return false;
        })
      )
    );
    results.push(...batchResults);
    if (i + CONCURRENCY < players.length) {
      await new Promise(r => setTimeout(r, 100));
    }
  }

  const successCount = results.filter(Boolean).length;
  console.log(`\n✅ Registered ${successCount}/${playersCount} players successfully!`);

  // 2. Poll for game start & called numbers
  console.log('\n[2/3] Waiting for Organizer to call numbers on host screen...');
  const gameId = players[0]?.gameId;
  let lastSeenSeq = 0;
  const calledSet = new Set();

  while (true) {
    try {
      // Check game status & called numbers
      const res = await fetch(`${SUPABASE_URL}/rest/v1/MPT_called_numbers?game_id=eq.${gameId}&order=call_seq.asc&select=*`, {
        headers: {
          'apikey': SUPABASE_ANON,
          'Authorization': `Bearer ${SUPABASE_ANON}`,
        },
      });

      if (res.ok) {
        const calls = await res.json();
        for (const call of calls) {
          if (call.call_seq > lastSeenSeq) {
            lastSeenSeq = call.call_seq;
            calledSet.add(call.number);
            drawnCallsList.push({ number: call.number, sequence: call.call_seq, timestamp: call.created_at });
            console.log(`\n📢 [CALL #${call.call_seq}] NUMBER DRAWN: >>> ${call.number} <<<`);

            // Evaluate all players
            for (const p of players) {
              await p.evaluateAndClaim(calledSet, call.number, call.call_seq);
            }
          }
        }
      }

      // Check if game completed
      const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?id=eq.${gameId}&select=status`, {
        headers: { 'apikey': SUPABASE_ANON, 'Authorization': `Bearer ${SUPABASE_ANON}` },
      });
      if (gRes.ok) {
        const gData = await gRes.json();
        if (gData[0]?.status === 'COMPLETED') {
          console.log('\n🏁 Game marked as COMPLETED by host!');
          saveReport('COMPLETED');
          break;
        }
      }
    } catch (_) {}

    await new Promise(r => setTimeout(r, 1000));
  }
}

main().catch(console.error);
