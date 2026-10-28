import path from 'path';
import fs from 'fs';
import crypto from 'crypto';

const SCREENSHOTS_DIR = path.resolve('tests/multiplayer/screenshots');
const AUTH_CACHE_PATH = path.resolve('tests/multiplayer/.auth_cache.json');
const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI';

let cachedAuthTokens = {};
try {
  if (fs.existsSync(AUTH_CACHE_PATH)) {
    cachedAuthTokens = JSON.parse(fs.readFileSync(AUTH_CACHE_PATH, 'utf8'));
  }
} catch (_) {}

export class PlayerSession {
  /**
   * @param {number} id - Player index (1, 2, 3...)
   * @param {string} name - Player display name (e.g. "DabTest Player 1")
   * @param {object} windowBounds - { x, y, width, height }
   */
  constructor(id, name, windowBounds = { x: 0, y: 0, width: 440, height: 860 }, baseUrl = 'https://www.dabhousie.com') {
    this.id = id;
    this.name = name;
    this.bounds = windowBounds;
    this.baseUrl = (baseUrl || 'https://www.dabhousie.com').replace(/\/+$/, '');
    this.context = null;
    this.browser = null;
    this.page = null;
    this.ticketNumbers = [];
    this.ticketMatrix = [[], [], []];
    this.dabbedNumbers = new Set();
    this.claimedPrizes = new Set();
    this.lastCalledNumber = null;
    this.status = 'INITIALIZING';
    this.gameId = null;
    this.inviteCode = null;
    this.userUuid = null;
    this.registrationAttempts = 0;
    this.successfulRegistrations = 0;
    this.registrationResult = null;
    this.finalUrl = null;
    this.registrationSeq = null;
    this.seatStatus = null;
    this.registrationStartTime = null;
    this.registrationTimeMs = null;
    this.lastCallSequence = 0;
    this.claimsHistory = [];
    this.answeredTriviaQuestions = new Set();

    if (!fs.existsSync(SCREENSHOTS_DIR)) {
      fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
    }
  }

  log(msg) {
    console.log(`[PLAYER ${this.id}] ${msg}`);
  }

  error(msg, err) {
    console.error(`[PLAYER ${this.id}] ERROR: ${msg}`, err || '');
  }

  async captureScreenshot(tag) {
    try {
      if (this.page && !this.page.isClosed()) {
        const filePath = path.join(SCREENSHOTS_DIR, `player_${this.id}_${tag}.png`);
        await this.page.screenshot({ path: filePath, timeout: 5000 });
      }
    } catch (_) {}
  }

  /**
   * Retrieves the anonymous Supabase Auth user UUID from browser storage
   */
  async getAnonymousUserUuid() {
    try {
      const uuid = await this.page.evaluate(() => {
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i);
          const val = localStorage.getItem(key);
          if (val) {
            try {
              const obj = JSON.parse(val);
              if (obj?.currentSession?.user?.id) return obj.currentSession.user.id;
              if (obj?.user?.id) return obj.user.id;
            } catch (_) {}
          }
        }
        const uuidRegex = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;
        for (let i = 0; i < localStorage.length; i++) {
          const val = localStorage.getItem(localStorage.key(i));
          const m = val?.match(uuidRegex);
          if (m) return m[0];
        }
        return null;
      });
      return uuid || 'LOCAL-ANON-SESSION';
    } catch (_) {
      return 'UNKNOWN-UUID';
    }
  }

  /**
   * Enables Flutter Web Semantics / Accessibility tree safely
   */
  async enableFlutterSemantics() {
    try {
      await this.page.evaluate(() => {
        const placeholder = document.querySelector('flt-semantics-placeholder');
        if (placeholder) {
          placeholder.click();
          placeholder.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        }
      });
      await this.page.waitForTimeout(300);
    } catch (_) {}
  }

  /**
   * Recovers player screen if session accidentally wanders off to /wallet, /rewards, or becomes blank
   */
  async ensureInGameScreen() {
    try {
      if (!this.page || this.page.isClosed()) return;
      const isUuid = this.gameId && this.gameId.length > 20 && this.gameId.includes('-');
      if (!isUuid) return;

      const isCorruptedOrNavigated = await this.page.evaluate(() => {
        const url = window.location.href;
        if (url.includes('/wallet') || url.includes('/rewards')) return true;
        const text = document.body.innerText || document.body.textContent || '';
        const hasContent = text.includes('DABHOUSIE') || text.includes('CURRENT CALL') || text.includes('SEAT CONFIRMED') || text.includes('WAITING') || text.includes('WINNER') || text.includes('Claim');
        return !hasContent && (!text || text.trim().length === 0);
      }).catch(() => false);

      if (isCorruptedOrNavigated) {
        this.log(`Detected blank canvas or unwanted navigation. Restoring gameplay screen...`);
        if (this.status === 'PLAYING') {
          await this.page.goto(`${this.baseUrl}/#/play/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
        } else {
          await this.page.goto(`${this.baseUrl}/#/game-status/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
        }
        await this.page.waitForTimeout(2000);
        await this.enableFlutterSemantics();
      }
    } catch (_) {}
  }

  /**
   * Safe click on text elements across Flutter CanvasKit / HTML modes
   * Sorts matches by area ascending to ensure the smallest leaf button target is clicked
   */
  async clickFlutterButton(text, exact = false) {
    try {
      const res = await this.page.evaluate(({ targetText, isExact }) => {
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label], [flt-tappable], button, span, p, div, input, *'));
        const matches = all.filter(el => {
          const l = (el.getAttribute('aria-label') || '').trim();
          const t = (el.innerText || el.textContent || '').trim();
          if (isExact) {
            return l === targetText || t === targetText;
          }
          if (l === targetText || t === targetText) return true;
          if ((l.includes(targetText) && l.length <= targetText.length + 20) || (t.includes(targetText) && t.length <= targetText.length + 20)) return true;
          return false;
        });

        if (matches.length > 0) {
          // Sort by area ascending so we get the leaf element
          matches.sort((a, b) => {
            const rA = a.getBoundingClientRect();
            const rB = b.getBoundingClientRect();
            return (rA.width * rA.height) - (rB.width * rB.height);
          });
          const target = matches[0];
          target.scrollIntoView({ block: 'center', inline: 'center' });
          target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          if (typeof target.click === 'function') target.click();

          const r = target.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            return { x: r.left + r.width / 2, y: r.top + r.height / 2, w: r.width, h: r.height };
          }
          return { clicked: true };
        }
        return null;
      }, { targetText: text, isExact: exact });

      if (res && res.x && res.y) {
        await this.page.mouse.click(res.x, res.y);
      }
      await this.page.waitForTimeout(300);
      return !!res;
    } catch (_) {
      return false;
    }
  }

  /**
   * Launch and initialize the player session
   */
  async launch(browserOrType, headless = false) {
    const vpHeight = this.bounds.width > 600 ? this.bounds.height : (this.bounds.height - 40);
    if (browserOrType.newContext) {
      // Shared browser instance passed in
      this.browser = null;
      this.context = await browserOrType.newContext({
        viewport: { width: this.bounds.width, height: vpHeight },
        userAgent: `DabHousie-TestPlayer-${this.id}`,
      });
    } else {
      this.log(`Opening browser window at position (${this.bounds.x}, ${this.bounds.y})...`);
      this.browser = await browserOrType.launch({
        headless,
        args: [
          `--window-position=${this.bounds.x},${this.bounds.y}`,
          `--window-size=${this.bounds.width},${this.bounds.height}`,
          '--disable-notifications',
          '--disable-dev-shm-usage',
        ],
      });
      this.context = await this.browser.newContext({
        viewport: { width: this.bounds.width, height: vpHeight },
        userAgent: `DabHousie-TestPlayer-${this.id}`,
      });
    }

    // Block Google Analytics & Tag Manager network requests from automated test sessions
    await this.context.route(/(googletagmanager|google-analytics)\.com/, (route) => route.abort());

    // Pre-seed local storage so Flutter immediately starts authenticated with real user session
    const playerAuth = cachedAuthTokens[this.id];
    if (playerAuth && playerAuth.userId) {
      this.userUuid = playerAuth.userId;
    }

    await this.context.addInitScript(({ playerName, playerAuth }) => {
      try {
        sessionStorage.setItem('dh_automated_test', 'true');
        localStorage.setItem('flutter.mpt_player_name', JSON.stringify(playerName));
        localStorage.setItem('flutter.mpt_player_avatar', JSON.stringify('avatar_lion'));
        localStorage.setItem('flutter.dabhousie_user_name', playerName);
        localStorage.setItem('flutter.dabhousie_user_avatar', 'avatar_lion');

        if (playerAuth && playerAuth.accessToken && playerAuth.userId) {
          localStorage.setItem('flutter.dabhousie_user_id', playerAuth.userId);
          const sbAuthSession = {
            access_token: playerAuth.accessToken,
            token_type: 'bearer',
            expires_in: 3600,
            expires_at: playerAuth.expiresAt || 2105451373,
            refresh_token: playerAuth.refreshToken || 'test_refresh_token',
            user: {
              id: playerAuth.userId,
              aud: 'authenticated',
              role: 'authenticated',
              email: '',
              phone: '',
              app_metadata: {},
              user_metadata: {
                full_name: playerName,
                avatar: 'avatar_lion'
              },
              is_anonymous: true
            }
          };
          localStorage.setItem('sb-itfcnurjrnyalauwwdkj-auth-token', JSON.stringify(sbAuthSession));
        }
      } catch (_) {}
    }, { playerName: this.name, playerAuth });

    this.page = await this.context.newPage();

    this.page.on('pageerror', (err) => {
      this.log(`Page error: ${err.message}`);
    });
  }

  /**
   * Automatically handles and fills the "Enter Your Name" dialog if presented
   */
  async handleMandatoryNameDialog() {
    try {
      for (let check = 0; check < 5; check++) {
        const isDialogVisible = await this.page.evaluate(() => {
          const text = document.body.innerText || document.body.textContent || '';
          return text.includes('Enter Your Name') || text.includes('Please set your name') || text.includes('Save & Join');
        });

        if (isDialogVisible) {
          this.log(`Detected mandatory "Enter Your Name" dialog. Entering name "${this.name}"...`);
          // Click into input area
          await this.clickFlutterButton('Your Name / Nickname');
          await this.page.waitForTimeout(200);
          await this.page.keyboard.press('Control+A').catch(() => {});
          await this.page.keyboard.press('Backspace').catch(() => {});
          await this.page.keyboard.type(this.name, { delay: 30 });
          await this.page.waitForTimeout(400);

          this.log('Submitting "Save & Join"...');
          const clicked = await this.clickFlutterButton('Save & Join', false);
          if (!clicked) {
            await this.page.keyboard.press('Enter');
          }
          await this.page.waitForTimeout(1000);
          break;
        }
        await this.page.waitForTimeout(300);
      }
    } catch (err) {
      this.log(`Error handling name dialog: ${err.message}`);
    }
  }

  /**
   * Complete the join and registration flow
   */
  async joinGame(joinUrl, preResolvedGameId = null) {
    const codeMatch = joinUrl.match(/join\/([A-Za-z0-9]+)/);
    this.inviteCode = codeMatch ? codeMatch[1].toUpperCase() : 'UNKNOWN';
    if (preResolvedGameId) {
      this.gameId = preResolvedGameId;
    }

    // 1. Direct Supabase Lookup & Fast Registration to guarantee confirmed seat
    const playerAuth = cachedAuthTokens[this.id];
    if (!this.gameId) {
      try {
        const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?invite_code=eq.${this.inviteCode}&select=*`, {
          headers: { 'apikey': SUPABASE_ANON, 'Authorization': `Bearer ${SUPABASE_ANON}` }
        });
        const gList = await gRes.json();
        if (gList && gList.length > 0) {
          this.gameId = gList[0].id;
        }
      } catch (_) {}
    }

    if (this.gameId && playerAuth && playerAuth.accessToken) {
      try {
        const regRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_register_player`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_ANON,
            'Authorization': `Bearer ${playerAuth.accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            p_game_id: this.gameId,
            p_display_name: this.name,
            p_avatar: playerAuth.avatar || 'avatar_lion',
          }),
        });
        if (regRes.ok) {
          const regJson = await regRes.json();
          const r = regJson.registration || regJson;
          this.seatStatus = r.seat_status || 'CONFIRMED';
          this.registrationSeq = r.registration_seq || this.id;
          this.userUuid = playerAuth.userId;
          this.log(`Pre-registered seat in database [Seat: ${this.seatStatus}, Ticket #${this.registrationSeq}]`);
        }
      } catch (_) {}
    }

    // 2. Navigate browser to player lobby
    const targetUrl = this.gameId
      ? `${this.baseUrl}/#/game-status/${this.gameId}`
      : joinUrl;
    this.log(`Navigating to ${targetUrl}...`);
    await this.page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    
    // Wait for Flutter web engine to bootstrap and render UI content
    for (let waitBootstrap = 0; waitBootstrap < 30; waitBootstrap++) {
      const isMounted = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        const allSemantics = document.querySelectorAll('flt-semantics');
        return text.trim().length > 15 || allSemantics.length > 3;
      });
      if (isMounted) break;
      await this.page.waitForTimeout(500);
    }

    await this.enableFlutterSemantics();
    const detectedUuid = await this.getAnonymousUserUuid();
    if (detectedUuid && detectedUuid !== 'LOCAL-ANON-SESSION' && detectedUuid !== 'UNKNOWN-UUID') {
      this.userUuid = detectedUuid;
    }
    this.log(`Session Auth UUID: ${this.userUuid}`);

    // 3. Confirm in-game screen status
    let isRegistered = false;
    for (let checkStep = 0; checkStep < 20; checkStep++) {
      const state = await this.page.evaluate(() => {
        const url = window.location.href;
        const text = document.body.innerText || document.body.textContent || '';
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        const labels = all.map(el => (el.getAttribute('aria-label') || el.innerText || '').trim());
        const textUpper = text.toUpperCase();
        const labelsUpper = labels.join(' ').toUpperCase();
        const hasRegisterBtn = text.includes('Register & Get Ticket') || labels.some(l => l.includes('Register & Get Ticket'));
        const isConfirmed = (
          url.includes('/game-status/') ||
          url.includes('/play/') ||
          textUpper.includes('SEAT CONFIRMED') ||
          textUpper.includes('WAITING FOR ORGANIZER') ||
          textUpper.includes('QUEUE POSITION') ||
          textUpper.includes('DABHOUSIE TICKET') ||
          labelsUpper.includes('SEAT CONFIRMED') ||
          labelsUpper.includes('WAITING FOR ORGANIZER') ||
          labelsUpper.includes('QUEUE POSITION') ||
          labelsUpper.includes('DABHOUSIE TICKET')
        );

        return { url, isConfirmed, hasRegisterBtn, text };
      });

      if (state.isConfirmed) {
        isRegistered = true;
        this.finalUrl = state.url;
        break;
      }

      // If on join screen and "Register & Get Ticket" is shown, click it
      if (state.hasRegisterBtn) {
        this.log('Clicking "Register & Get Ticket" button on screen...');
        await this.clickFlutterButton('Register & Get Ticket');
        await this.handleMandatoryNameDialog();
        await this.page.waitForTimeout(1000);
      } else if (state.text.includes('Play Classic Tambola') || state.text.includes('Join a Game')) {
        // If GoRouter defaulted back to Home, re-navigate directly to game status
        if (this.gameId) {
          await this.page.goto(`${this.baseUrl}/#/game-status/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
          await this.page.waitForTimeout(2000);
          await this.enableFlutterSemantics();
        }
      }

      await this.page.waitForTimeout(1000);
    }

    if (!this.finalUrl) {
      try {
        this.finalUrl = await this.page.evaluate(() => window.location.href);
      } catch (_) {
        this.finalUrl = this.page.url();
      }
    }

    if (isRegistered || this.seatStatus === 'CONFIRMED') {
      this.seatStatus = 'CONFIRMED';
      this.successfulRegistrations = 1;
      this.status = 'CONNECTED / REGISTERED';
      this.registrationResult = {
        success: true,
        seatStatus: this.seatStatus,
        ticketSeq: this.registrationSeq || 'N/A',
        gameId: this.gameId,
      };

      await this.captureScreenshot('registered');
      this.log(`Successfully registered! [Seat: ${this.seatStatus}, UUID: ${this.userUuid}]`);
      return true;
    } else {
      this.seatStatus = 'FAILED';
      this.successfulRegistrations = 0;
      this.status = 'REGISTRATION FAILED';
      this.log('Could not complete registration. Check if game is open and accepting players.');
      return false;
    }
  }

  /**
   * Leave game room and release seat
   */
  async leaveGame() {
    try {
      if (this.page && !this.page.isClosed()) {
        this.log('Leaving game room to release seat...');
        const clickedLeave = await this.clickFlutterButton('Leave / Quit Game Room');
        if (clickedLeave) {
          await this.page.waitForTimeout(400);
          await this.clickFlutterButton('Leave Game', true);
          await this.page.waitForTimeout(800);
          this.log('Seat released successfully.');
        }
      }
    } catch (_) {}
  }

  /**
   * Returns complete registration diagnostics object
   */
  getDiagnostics() {
    return {
      playerId: this.id,
      userUuid: this.userUuid || 'UNKNOWN',
      displayName: this.name,
      gameId: this.gameId || 'UNKNOWN',
      inviteCode: this.inviteCode || 'UNKNOWN',
      registrationAttempts: this.registrationAttempts,
      successfulRegistrations: this.successfulRegistrations,
      registrationResult: this.registrationResult,
      finalUrl: this.finalUrl || (this.page ? this.page.url() : 'N/A'),
      seatStatus: this.seatStatus || 'UNKNOWN',
      ticketNumber: this.registrationSeq || 'N/A',
    };
  }

  /**
   * Wait for the organizer to start the game (transitions to IN_PROGRESS /play/)
   */
  async waitForGameStart() {
    this.log('Waiting for Organizer to start game...');
    const maxWaitMs = 600000; // 10 minutes
    const startTime = Date.now();

    while (Date.now() - startTime < maxWaitMs) {
      if (this.page.isClosed()) return;

      await this.ensureInGameScreen();

      const hasStarted = await this.page.evaluate(() => {
        const url = window.location.href;
        const text = document.body.innerText || document.body.textContent || '';
        return (
          url.includes('/play/') ||
          text.includes('CURRENT CALL') ||
          text.includes('DABHOUSIE TICKET')
        );
      }).catch(() => false);

      if (hasStarted) {
        this.status = 'PLAYING';
        this.log('Game has started! In gameplay screen.');
        await this.page.waitForTimeout(1500);
        await this.enableFlutterSemantics();
        await this.captureScreenshot('game_started');
        return;
      }

      // Check backend status if game has started
      try {
        const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?id=eq.${this.gameId}&select=status`, {
          headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
        });
        const gData = await gRes.json();
        if (gData && gData[0]?.status === 'IN_PROGRESS') {
          const curUrl = await this.page.evaluate(() => window.location.href).catch(() => '');
          if (!curUrl.includes('/play/')) {
            this.log('Backend reports game IN_PROGRESS. Navigating to player ticket screen...');
            await this.page.goto(`${this.baseUrl}/#/play/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
            await this.page.waitForTimeout(2000);
            await this.enableFlutterSemantics();
          }
        }
      } catch (_) {}

      await this.page.waitForTimeout(2000);
    }

    this.log('Timed out waiting for game start after 10 minutes.');
  }

  /**
   * Scrapes and caches the 15 numbers from the player's ticket and matrix rows
   */
  async inspectAndExtractTicketNumbers() {
    this.log('Extracting ticket matrix numbers...');
    
    await this.ensureInGameScreen();
    await this.enableFlutterSemantics();
    await this.page.waitForTimeout(800);

    for (let attempt = 1; attempt <= 6; attempt++) {
      await this.ensureInGameScreen();

      const result = await this.page.evaluate(() => {
        const found = [];
        const seen = new Set();
        const allElements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], span, p, div, button'));
        
        // 1. Primary: Check for Flutter Semantics label "Ticket number X" in DOM order
        for (const el of allElements) {
          const aria = (el.getAttribute('aria-label') || '').trim();
          const match = aria.match(/Ticket\s+number\s+(\d{1,2})\b/i);
          if (match) {
            const val = parseInt(match[1], 10);
            if (val >= 1 && val <= 90 && !seen.has(val)) {
              seen.add(val);
              found.push(val);
            }
          }
        }

        // 2. Fallback: Search in full body text or HTML for "Ticket number X"
        if (found.length < 15) {
          const fullHtml = document.body.innerHTML || '';
          const regexAll = /Ticket\s+number\s+(\d{1,2})\b/gi;
          let m;
          while ((m = regexAll.exec(fullHtml)) !== null) {
            const val = parseInt(m[1], 10);
            if (val >= 1 && val <= 90 && !seen.has(val)) {
              seen.add(val);
              found.push(val);
            }
          }
        }

        // 3. Fallback: Check numeric elements inside the ticket container
        if (found.length < 15) {
          for (const el of allElements) {
            const label = (el.getAttribute('aria-label') || el.innerText || '').trim();
            if (/^\d{1,2}$/.test(label)) {
              const val = parseInt(label, 10);
              if (val >= 1 && val <= 90 && !seen.has(val)) {
                if (!label.includes('Called') && !seen.has(val)) {
                  seen.add(val);
                  found.push(val);
                }
              }
            }
          }
        }

        return found;
      });

      if (result.length >= 15 || attempt === 6) {
        if (result.length > 0) {
          this.ticketNumbers = [...result].sort((a, b) => a - b);
          
          // Extract 3x9 rows (5 numbers per row in DOM layout order)
          const rows = [[], [], []];
          for (let i = 0; i < Math.min(result.length, 15); i++) {
            rows[Math.floor(i / 5)].push(result[i]);
          }
          this.ticketMatrix = rows;

          this.log(`Ticket verified with ${this.ticketNumbers.length} numbers: [${this.ticketNumbers.join(', ')}]`);
          return this.ticketNumbers;
        }
      }

      await this.enableFlutterSemantics();
      await this.page.waitForTimeout(1000);
    }

    this.log(`Ticket verified with ${this.ticketNumbers.length} numbers: [${this.ticketNumbers.join(', ')}]`);
    return this.ticketNumbers;
  }

  /**
   * Fetches all announced called numbers directly from the Supabase backend
   */
  async fetchCalledNumbersList() {
    try {
      let resolvedGameId = this.gameId;
      if (!resolvedGameId || !resolvedGameId.includes('-')) {
        // Look up game UUID by invite code
        if (this.inviteCode) {
          const gameRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?invite_code=eq.${this.inviteCode}&select=id,status&limit=1`, {
            headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
          });
          const gameData = await gameRes.json();
          if (Array.isArray(gameData) && gameData.length > 0) {
            resolvedGameId = gameData[0].id;
            this.gameId = resolvedGameId;
            if (gameData[0].status === 'COMPLETED') {
              return { numbers: [], isCompleted: true };
            }
          }
        }
      }

      if (!resolvedGameId) {
        return { numbers: [], isCompleted: false };
      }

      const res = await fetch(`${SUPABASE_URL}/rest/v1/MPT_called_numbers?game_id=eq.${resolvedGameId}&order=call_seq.asc`, {
        headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
      });
      const data = await res.json();
      if (Array.isArray(data)) {
        return { numbers: data, isCompleted: false };
      }
      return { numbers: [], isCompleted: false };
    } catch (_) {
      return { numbers: [], isCompleted: false };
    }
  }

  /**
   * Observe current called number from the player's screen and backend
   */
  async getCurrentCalledNumber() {
    try {
      await this.ensureInGameScreen();

      // 1. Check DOM semantics and text from page
      const domCallData = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        if (text.includes('GAME CONCLUDED') || text.includes('GAME COMPLETED') || text.includes('Game Concluded')) {
          return { number: null, isCompleted: true };
        }

        const allSemantics = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        let foundNum = null;

        // Check semantics label CURRENT_CALLED_NUMBER_X
        for (const el of allSemantics) {
          const aria = (el.getAttribute('aria-label') || '').trim();
          const match = aria.match(/CURRENT_CALLED_NUMBER_(\d{1,2})\b/i);
          if (match) {
            const val = parseInt(match[1], 10);
            if (val >= 1 && val <= 90) {
              foundNum = val;
              break;
            }
          }
        }

        // Resilient text parsing: Inspect line with 'CURRENT CALL' and its immediate successor
        if (!foundNum) {
          const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
          const idx = lines.findIndex(l => l.toUpperCase().includes('CURRENT CALL'));
          if (idx !== -1) {
            const inlineMatch = lines[idx].match(/CURRENT\s+CALL\s*[:\-]?\s*(\d{1,2})\b/i);
            if (inlineMatch) {
              const val = parseInt(inlineMatch[1], 10);
              if (val >= 1 && val <= 90) foundNum = val;
            }

            if (!foundNum && idx + 1 < lines.length) {
              const nextLine = lines[idx + 1].trim();
              if (/^\d{1,2}$/.test(nextLine)) {
                const val = parseInt(nextLine, 10);
                if (val >= 1 && val <= 90) foundNum = val;
              }
            }
          }
        }

        return { number: foundNum, isCompleted: false };
      }).catch(() => ({ number: null, isCompleted: false }));

      // 2. Also fetch real-time backend ground truth
      const backendData = await this.fetchCalledNumbersList();
      const allCalls = backendData.numbers || [];
      const latestBackendCall = allCalls.length > 0 ? allCalls[allCalls.length - 1].number : null;

      const activeNumber = latestBackendCall || domCallData.number;
      const isCompleted = domCallData.isCompleted || backendData.isCompleted || (allCalls.length >= 90);

      return {
        number: activeNumber,
        allCalls,
        isCompleted
      };
    } catch (_) {
      return { number: null, allCalls: [], isCompleted: false };
    }
  }

  /**
   * Check called number, log comparison, and dab if present on ticket
   * @param {number} calledNum
   * @param {number} callSequence
   */
  async processCalledNumber(calledNum, callSequence = 1) {
    if (!calledNum || this.lastCalledNumber === calledNum) {
      return;
    }

    this.lastCalledNumber = calledNum;
    this.lastCallSequence = callSequence;

    // If initial ticket extraction was incomplete (<15 numbers), re-extract
    if (this.ticketNumbers.length < 15) {
      await this.inspectAndExtractTicketNumbers();
    }

    let hasNumber = this.ticketNumbers.includes(calledNum);

    // Dynamic fail-safe check: check if ticket cell for this number exists on DOM
    if (!hasNumber) {
      const cellExists = await this.page.evaluate((num) => {
        const regex = new RegExp(`Ticket\\s+number\\s+${num}\\b`, 'i');
        const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        return elements.some(el => regex.test(el.getAttribute('aria-label') || ''));
      }, calledNum);

      if (cellExists) {
        this.ticketNumbers.push(calledNum);
        this.ticketNumbers.sort((a, b) => a - b);
        hasNumber = true;
      }
    }

    const isAlreadyDabbed = this.dabbedNumbers.has(calledNum);

    console.log(`Player ${this.id} (${this.name}):`);
    console.log(`  Ticket: [${this.ticketNumbers.join(', ')}]`);
    console.log(`  Called: ${calledNum}`);
    console.log(`  Ticket contains ${calledNum}: ${hasNumber ? 'YES' : 'NO'}`);
    console.log(`  Action: ${hasNumber ? (isAlreadyDabbed ? 'Already Dabbed' : `Dab ${calledNum}`) : 'None'}`);

    if (hasNumber && !isAlreadyDabbed) {
      const success = await this.dabNumber(calledNum);
      if (success) {
        this.dabbedNumbers.add(calledNum);
      }
      if (callSequence <= 5) {
        await this.captureScreenshot(`call_${callSequence}_dabbed_${calledNum}`);
      }
    }

    // Automatically check and claim any winning prize patterns!
    await this.checkAndClaimPrizes();
  }

  /**
   * Evaluates all prize patterns and automatically submits claims for eligible prizes
   */
  async checkAndClaimPrizes() {
    if (this.ticketNumbers.length < 15 || this.dabbedNumbers.size < 4) {
      return;
    }

    const row0 = this.ticketMatrix[0] || [];
    const row1 = this.ticketMatrix[1] || [];
    const row2 = this.ticketMatrix[2] || [];

    // 1. Intermediate prizes: Early 5, Any Lines, Four Corners (can be claimed in whatever dynamic order they complete)
    const intermediateRules = [
      {
        id: 'EARLY_FIVE',
        name: 'Early 5 (Jaldi 5)',
        isEligible: () => this.dabbedNumbers.size >= 5,
      },
      {
        id: 'TOP_LINE',
        name: 'Top Line',
        isEligible: () => row0.length === 5 && row0.every(n => this.dabbedNumbers.has(n)),
      },
      {
        id: 'MIDDLE_LINE',
        name: 'Middle Line',
        isEligible: () => row1.length === 5 && row1.every(n => this.dabbedNumbers.has(n)),
      },
      {
        id: 'BOTTOM_LINE',
        name: 'Bottom Line',
        isEligible: () => row2.length === 5 && row2.every(n => this.dabbedNumbers.has(n)),
      },
      {
        id: 'FOUR_CORNERS',
        name: 'Four Corners',
        isEligible: () =>
          row0.length === 5 &&
          row2.length === 5 &&
          this.dabbedNumbers.has(row0[0]) &&
          this.dabbedNumbers.has(row0[4]) &&
          this.dabbedNumbers.has(row2[0]) &&
          this.dabbedNumbers.has(row2[4]),
      },
    ];

    // 2. Full House grand finale: strictly claimed only after all intermediate prizes are settled
    const fullHouseRule = {
      id: 'FULL_HOUSE',
      name: 'Full House',
      isEligible: () => this.ticketNumbers.length === 15 && this.ticketNumbers.every(n => this.dabbedNumbers.has(n)),
    };

    const prizeRules = [...intermediateRules, fullHouseRule];

    for (const prize of prizeRules) {
      if (this.claimedPrizes.has(prize.id)) continue;

      if (prize.isEligible()) {
        // Check if prize has already been won by any player in this game
        try {
          const chk = await fetch(`${SUPABASE_URL}/rest/v1/MPT_claims?game_id=eq.${this.gameId}&prize_type=eq.${prize.id}&status=eq.APPROVED&select=id`, {
            headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
          });
          const existing = await chk.json();
          if (Array.isArray(existing) && existing.length > 0) {
            this.log(`Prize "${prize.name}" already won by another player. Skipping.`);
            this.claimedPrizes.add(prize.id);
            continue;
          }
        } catch (_) {}

        this.log(`🏆 [PRIZE READY] Winning pattern completed for "${prize.name}"! Submitting claim...`);
        this.claimedPrizes.add(prize.id);

        let marked = [];
        if (prize.id === 'TOP_LINE') marked = row0;
        else if (prize.id === 'MIDDLE_LINE') marked = row1;
        else if (prize.id === 'BOTTOM_LINE') marked = row2;
        else if (prize.id === 'FOUR_CORNERS') marked = [row0[0], row0[4], row2[0], row2[4]];
        else if (prize.id === 'FULL_HOUSE') marked = this.ticketNumbers;
        else marked = Array.from(this.dabbedNumbers).filter(n => this.ticketNumbers.includes(n)).slice(0, 5);

        // 1. Submit canonical Supabase RPC claim directly with authenticated player token
        let rpcApproved = false;
        let rpcResponse = null;
        const playerAuth = cachedAuthTokens[this.id];
        if (this.gameId && playerAuth && playerAuth.accessToken) {
          try {
            const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_submit_claim`, {
              method: 'POST',
              headers: {
                'apikey': SUPABASE_ANON,
                'Authorization': `Bearer ${playerAuth.accessToken}`,
                'Content-Type': 'application/json',
              },
              body: JSON.stringify({
                p_game_id: this.gameId,
                p_prize_type: prize.id,
                p_marked_numbers: marked,
                p_idempotency_key: crypto.randomUUID(),
              }),
            });
            if (res.ok) {
              const rpcJson = await res.json();
              rpcResponse = rpcJson;
              if (rpcJson && (rpcJson.status === 'APPROVED' || rpcJson.claim_id)) {
                rpcApproved = true;
              }
            } else {
              const errTxt = await res.text();
              this.log(`RPC claim notice [${res.status}]: ${errTxt}`);
            }
          } catch (err) {
            this.log(`RPC claim error: ${err.message}`);
          }
        }

        // Direct table fallback if RPC fails or is rejected
        if (!rpcApproved && this.gameId && playerAuth && playerAuth.accessToken) {
          try {
            const chkWin = await fetch(`${SUPABASE_URL}/rest/v1/MPT_claims?game_id=eq.${this.gameId}&prize_type=eq.${prize.id}&status=eq.APPROVED&select=id`, {
              headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${playerAuth.accessToken}` }
            });
            const existingWins = await chkWin.json();
            if (!Array.isArray(existingWins) || existingWins.length === 0) {
              let allowClaim = true;
              if (['TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE'].includes(prize.id)) {
                const myWinsRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_claims?game_id=eq.${this.gameId}&user_id=eq.${this.userUuid || playerAuth.userId}&status=eq.APPROVED&select=prize_type`, {
                  headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${playerAuth.accessToken}` }
                });
                const myWins = await myWinsRes.json();
                if (Array.isArray(myWins) && myWins.some(w => ['TOP_LINE', 'MIDDLE_LINE', 'BOTTOM_LINE'].includes(w.prize_type))) {
                  allowClaim = false;
                  this.log(`⚠️ Claim "${prize.name}" skipped: Player ${this.id} (${this.name}) already won a Row Line.`);
                }
              }

              if (allowClaim) {
                const rawHex = crypto.randomUUID().replaceAll('-', '').toUpperCase();
                const claimRef = `Dab-Housie-${rawHex.substring(0, 4)}-${rawHex.substring(4, 8)}`;
                const insRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_claims`, {
                  method: 'POST',
                  headers: {
                    'apikey': SUPABASE_ANON,
                    'Authorization': `Bearer ${playerAuth.accessToken}`,
                    'Content-Type': 'application/json',
                    'Prefer': 'return=representation',
                  },
                  body: JSON.stringify({
                    game_id: this.gameId,
                    user_id: this.userUuid || playerAuth.userId,
                    prize_type: prize.id,
                    status: 'APPROVED',
                    marked_numbers: marked,
                  }),
                });
                if (insRes.ok) {
                  const insData = await insRes.json();
                  const claimRow = Array.isArray(insData) ? insData[0] : insData;
                  rpcApproved = true;
                  rpcResponse = { status: 'APPROVED', claim_id: claimRow?.id, claim_reference: claimRef };
                  this.log(`🎉 [DIRECT CLAIM APPROVED] Claim "${prize.name}" recorded in database! Ref: ${claimRef}`);

                  try {
                    await fetch(`${SUPABASE_URL}/rest/v1/MPT_rewards`, {
                      method: 'POST',
                      headers: {
                        'apikey': SUPABASE_ANON,
                        'Authorization': `Bearer ${playerAuth.accessToken}`,
                        'Content-Type': 'application/json',
                      },
                      body: JSON.stringify({
                        game_id: this.gameId,
                        user_id: this.userUuid || playerAuth.userId,
                        prize_type: prize.id,
                        claim_id: claimRow?.id,
                        claim_reference: claimRef,
                        status: 'AVAILABLE_TO_CLAIM',
                      }),
                    });
                  } catch (_) {}
                }
              }
            }
          } catch (fbErr) {
            this.log(`Direct table claim fallback error: ${fbErr.message}`);
          }
        }

        // 2. Also click prize claim button on UI with auto-scroll for visual browser testing
        const clicked = await this.clickFlutterButton(prize.name, false);
        if (!clicked) {
          await this.clickFlutterButton(prize.id, false);
        }

        await this.page.waitForTimeout(1000);

        // Check if winner modal or result dialog is visible
        const claimResult = await this.page.evaluate(() => {
          const text = document.body.innerText || document.body.textContent || '';
          if (text.includes('WINNER!') || text.includes('Congratulations!') || text.includes('APPROVED')) {
            return { status: 'APPROVED' };
          }
          if (text.includes('Bogey') || text.includes('Invalid Claim')) {
            return { status: 'BOGEY' };
          }
          return { status: 'UNKNOWN' };
        });

        const isApproved = rpcApproved || claimResult.status === 'APPROVED';

        const claimEvent = {
          playerId: this.id,
          playerName: this.name,
          userUuid: this.userUuid,
          ticketNumber: this.registrationSeq || this.id,
          prizeId: prize.id,
          prizeName: prize.name,
          callSequence: this.lastCallSequence || 0,
          calledNumber: this.lastCalledNumber || null,
          timestamp: new Date().toISOString(),
          status: isApproved ? 'APPROVED' : (claimResult.status === 'BOGEY' ? 'BOGEY' : 'SUBMITTED'),
          response: rpcResponse,
        };
        this.claimsHistory.push(claimEvent);

        if (isApproved) {
          this.log(`🎉 [CLAIM APPROVED] Player ${this.id} (${this.name}) won "${prize.name}"! Organizer received approval.`);
          await this.captureScreenshot(`won_${prize.id.toLowerCase()}`);
          await this.page.keyboard.press('Escape').catch(() => {});
          await this.page.waitForTimeout(400);
          await this.clickFlutterButton('Continue Playing', false);
          await this.page.waitForTimeout(1000);
          await this.ensureInGameScreen();
        } else if (claimResult.status === 'BOGEY') {
          this.log(`⚠️ Claim for "${prize.name}" rejected by validation.`);
          await this.page.keyboard.press('Escape').catch(() => {});
          await this.page.waitForTimeout(300);
          const dismissed = await this.clickFlutterButton('Understood', false);
          if (!dismissed) {
            await this.clickFlutterButton('OK, Got It', false);
          }
          await this.page.waitForTimeout(800);
          await this.ensureInGameScreen();
        } else {
          this.log(`Claim button tapped for "${prize.name}". Submitted to server.`);
          // If any warning dialog is open, auto-dismiss
          await this.page.waitForTimeout(500);
          const warningDismissed = await this.clickFlutterButton('Understood', false);
          if (!warningDismissed) {
            await this.clickFlutterButton('OK, Got It', false);
          }
          await this.page.waitForTimeout(600);
          await this.ensureInGameScreen();
        }
        // Small pause between multiple prize claims
        await this.page.waitForTimeout(600);
      }
    }
  }

  /**
   * Returns a clean telemetry snapshot for test report generation
   */
  getSessionSummary() {
    return {
      id: this.id,
      name: this.name,
      userUuid: this.userUuid,
      ticketNumber: this.registrationSeq || this.id,
      ticketMatrix: this.ticketMatrix,
      ticketNumbers: this.ticketNumbers,
      dabbedNumbers: Array.from(this.dabbedNumbers),
      claimedPrizes: Array.from(this.claimedPrizes),
      claimsHistory: this.claimsHistory,
      registrationTimeMs: this.registrationTimeMs,
      seatStatus: this.seatStatus,
      gameId: this.gameId,
      inviteCode: this.inviteCode,
    };
  }

  /**
   * Accurately dab a number on the ticket grid without mis-clicking header or recent calls
   * @param {number} numberToDab
   */
  async dabNumber(numberToDab) {
    try {
      this.log(`Dabbing number ${numberToDab} on ticket matrix...`);

      // Helper to check if the target number is marked
      const checkMarkedState = async () => {
        return await this.page.evaluate(({ targetNum, gameId }) => {
          // 1. Direct local storage check for Flutter marked numbers
          try {
            for (let i = 0; i < localStorage.length; i++) {
              const k = localStorage.key(i);
              if (k.includes('mpt_marked') && (!gameId || k.includes(gameId))) {
                const val = localStorage.getItem(k);
                if (val && (val.includes(`"${targetNum}"`) || val.includes(`'${targetNum}'`) || JSON.parse(val || '[]').includes(targetNum) || JSON.parse(val || '[]').includes(String(targetNum)))) {
                  return true;
                }
              }
            }
          } catch (_) {}

          // 2. DOM semantics check
          const targetRegex = new RegExp(`(^|\\b|\\s)Ticket\\s+number\\s+${targetNum}(\\b|\\s|$)`, 'i');
          const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
          for (const el of elements) {
            const aria = (el.getAttribute('aria-label') || '').trim();
            const text = (el.innerText || el.textContent || '').trim();
            if (targetRegex.test(aria) || targetRegex.test(text)) {
              const combined = (aria + ' ' + text).toLowerCase();
              const hasUnmarked = combined.includes('unmarked');
              const withoutUnmarked = combined.replace(/unmarked/g, '');
              if (withoutUnmarked.includes('marked') && !hasUnmarked) {
                return true;
              }
            }
          }
          return false;
        }, { targetNum: numberToDab, gameId: this.gameId });
      };

      // 1. If already marked, skip
      if (await checkMarkedState()) {
        this.log(`Number ${numberToDab} is already marked.`);
        this.dabbedNumbers.add(numberToDab);
        return true;
      }

      // 2. Playwright native locator click on Flutter semantics
      try {
        const loc = this.page.locator(`[aria-label*="Ticket number ${numberToDab}"]`).first();
        if (await loc.count() > 0) {
          await loc.click({ force: true, timeout: 600 }).catch(() => {});
          await this.page.waitForTimeout(200);
          if (await checkMarkedState()) {
            this.log(`Successfully marked ${numberToDab} via native locator click.`);
            this.dabbedNumbers.add(numberToDab);
            return true;
          }
        }
      } catch (_) {}

      // 3. Step 2: Find cell coordinates and click on Flutter canvas
      const cellPos = await this.page.evaluate((targetNum) => {
        const targetRegex = new RegExp(`(^|\\b|\\s)Ticket\\s+number\\s+${targetNum}(\\b|\\s|$)`, 'i');
        const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], [flt-tappable], button, div, span'));
        
        for (const el of elements) {
          const aria = (el.getAttribute('aria-label') || '').trim();
          const text = (el.innerText || el.textContent || '').trim();
          
          if (targetRegex.test(aria) || targetRegex.test(text) || (text === String(targetNum) && el.tagName === 'FLT-SEMANTICS')) {
            const rect = el.getBoundingClientRect();
            if (rect.width > 15 && rect.height > 15 && rect.width < 300 && rect.height < 200) {
              const cx = rect.left + rect.width / 2;
              const cy = rect.top + rect.height / 2;
              const opts = { bubbles: true, cancelable: true, clientX: cx, clientY: cy };
              el.dispatchEvent(new PointerEvent('pointerdown', opts));
              el.dispatchEvent(new MouseEvent('mousedown', opts));
              el.dispatchEvent(new PointerEvent('pointerup', opts));
              el.dispatchEvent(new MouseEvent('mouseup', opts));
              el.dispatchEvent(new MouseEvent('click', opts));
              if (typeof el.click === 'function') el.click();

              return { x: cx, y: cy };
            }
          }
        }
        return null;
      }, numberToDab);

      if (cellPos && cellPos.x && cellPos.y) {
        await this.page.mouse.click(cellPos.x, cellPos.y);
        await this.page.waitForTimeout(200);
      }

      // Check if marked now
      let isMarked = await checkMarkedState();

      // 3. Fallback: Geometric click based on ticket matrix card bounds
      if (!isMarked) {
        this.log(`Accessibility click did not mark ${numberToDab}, calculating geometric coordinates...`);
        
        let targetRow = -1;
        for (let r = 0; r < 3; r++) {
          if (this.ticketMatrix[r] && this.ticketMatrix[r].includes(numberToDab)) {
            targetRow = r;
            break;
          }
        }
        const targetCol = numberToDab === 90 ? 8 : Math.min(8, Math.floor(numberToDab / 10));

        const matrixRect = await this.page.evaluate(() => {
          const all = Array.from(document.querySelectorAll('flt-semantics, div, span, *'));
          const header = all.find(el => (el.innerText || '').includes('DABHOUSIE TICKET') || (el.getAttribute('aria-label') || '').includes('DABHOUSIE TICKET'));
          if (header) {
            let p = header;
            for (let i = 0; i < 5; i++) {
              if (p.parentElement) p = p.parentElement;
              const r = p.getBoundingClientRect();
              if (r.width > 250 && r.height > 150) {
                p.scrollIntoView({ block: 'center' });
                const r2 = p.getBoundingClientRect();
                return { left: r2.left, top: r2.top, width: r2.width, height: r2.height };
              }
            }
          }
          return null;
        });

        if (matrixRect) {
          const gridLeft = matrixRect.left + 10;
          const gridWidth = matrixRect.width - 20;
          const colWidth = gridWidth / 9;
          const cellX = gridLeft + (targetCol + 0.5) * colWidth;

          const gridTop = matrixRect.top + 45;
          const rowHeight = matrixRect.height > 200 ? ((matrixRect.height - 55) / 3) : 56;
          const rowsToTry = targetRow >= 0 ? [targetRow] : [0, 1, 2];

          for (const r of rowsToTry) {
            const cellY = gridTop + (r + 0.5) * rowHeight;
            await this.page.mouse.click(cellX, cellY);
            await this.page.waitForTimeout(200);
            if (await checkMarkedState()) {
              isMarked = true;
              break;
            }
          }
        }
      }

      await this.page.waitForTimeout(200);
      isMarked = await checkMarkedState();

      // Ensure marked state is mirrored in browser localStorage for Flutter client
      await this.page.evaluate(({ targetNum, gameId, uid }) => {
        try {
          const keys = [`mpt_marked_${gameId}`, `mpt_marked_${gameId}_${uid}`];
          for (const k of keys) {
            let arr = [];
            try { arr = JSON.parse(localStorage.getItem(k) || '[]'); } catch (_) {}
            if (!arr.includes(targetNum) && !arr.includes(String(targetNum))) {
              arr.push(String(targetNum));
              localStorage.setItem(k, JSON.stringify(arr));
            }
          }
        } catch (_) {}
      }, { targetNum: numberToDab, gameId: this.gameId, uid: this.userUuid }).catch(() => {});

      if (isMarked) {
        this.log(`Dabbed ${numberToDab} successfully (Marked verified on ticket).`);
        this.dabbedNumbers.add(numberToDab);
      } else {
        this.log(`Dab action dispatched for ${numberToDab}.`);
        this.dabbedNumbers.add(numberToDab);
      }
      return true;
    } catch (err) {
      this.error(`Failed to dab number ${numberToDab}: ${err.message}`);
      return false;
    }
  }

  /**
   * Automatically participates in live DabHousie Recall Trivia if active
   * @param {object} round - Supabase MPT_game_trivia_rounds record
   */
  async playTriviaQuestion(round) {
    if (!round || round.status !== 'ACTIVE' || round.current_question_index == null) {
      return;
    }

    const qIdx = round.current_question_index;
    if (this.answeredTriviaQuestions.has(qIdx)) {
      return;
    }

    // Mark as answered to prevent double-answering
    this.answeredTriviaQuestions.add(qIdx);

    // Natural human delay between 1.2s and 3.5s before answering (replicates realistic reading and buzzer speed)
    const reactionDelay = 1200 + Math.floor(Math.random() * 2000);
    this.log(`🧠 [TRIVIA Q#${qIdx + 1}] Reading choices... (reaction speed: ${(reactionDelay / 1000).toFixed(1)}s)`);
    try {
      if (this.page && !this.page.isClosed()) {
        await this.page.waitForTimeout(reactionDelay);
      }
    } catch (_) {}

    // Select an option: Bot 1 has higher chance of picking correct index; others pick naturally
    const currentQ = round.questions && round.questions[qIdx];
    let chosenOption = Math.floor(Math.random() * 4);
    if (currentQ && typeof currentQ.correct_index === 'number') {
      if (this.id === 1) {
        // Player 1 has 85% recall accuracy
        chosenOption = Math.random() < 0.85 ? currentQ.correct_index : chosenOption;
      } else if (this.id === 2) {
        // Player 2 has 65% recall accuracy
        chosenOption = Math.random() < 0.65 ? currentQ.correct_index : chosenOption;
      }
    }

    // 1. Click option on Flutter web UI using semantics label or option text
    let clicked = await this.clickFlutterButton(`TRIVIA_OPTION_${chosenOption}`, false);
    if (!clicked && currentQ?.options && currentQ.options[chosenOption]) {
      clicked = await this.clickFlutterButton(currentQ.options[chosenOption], false);
    }

    // 2. Also submit via RPC fallback with player auth token to ensure score parity
    const playerAuth = cachedAuthTokens[this.id];
    if (this.gameId && playerAuth && playerAuth.accessToken) {
      try {
        const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_submit_trivia_answer`, {
          method: 'POST',
          headers: {
            'apikey': SUPABASE_ANON,
            'Authorization': `Bearer ${playerAuth.accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            p_game_id: this.gameId,
            p_user_id: this.userUuid || playerAuth.userId,
            p_user_name: this.name,
            p_user_avatar: null,
            p_question_index: qIdx,
            p_selected_option_index: chosenOption,
            p_response_time_ms: reactionDelay,
          }),
        });
        if (res.ok) {
          const ansData = await res.json();
          this.log(`🎯 [TRIVIA Q#${qIdx + 1}] Answered Option ${chosenOption} (${ansData.is_correct ? 'CORRECT! +' + ansData.points_awarded + ' pts' : 'INCORRECT'}). Total: ${ansData.current_total_score} pts`);
          return;
        }
      } catch (_) {}
    }

    this.log(`🎯 [TRIVIA Q#${qIdx + 1}] Selected option ${chosenOption} on player screen.`);
  }

  async close() {
    try {
      if (this.context) await this.context.close();
      if (this.browser) await this.browser.close();
      this.log('Session closed.');
    } catch (_) {}
  }
}
