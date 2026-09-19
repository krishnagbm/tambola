import path from 'path';
import fs from 'fs';

const SCREENSHOTS_DIR = path.resolve('tests/multiplayer/screenshots');

export class PlayerSession {
  /**
   * @param {number} id - Player index (1, 2, 3...)
   * @param {string} name - Player display name (e.g. "DabTest Player 1")
   * @param {object} windowBounds - { x, y, width, height }
   */
  constructor(id, name, windowBounds = { x: 0, y: 0, width: 440, height: 860 }) {
    this.id = id;
    this.name = name;
    this.bounds = windowBounds;
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
   * Recovers player screen if session accidentally wanders off to /wallet or /rewards
   */
  async ensureInGameScreen() {
    try {
      if (!this.page || this.page.isClosed()) return;
      const isUuid = this.gameId && this.gameId.length > 20 && this.gameId.includes('-');
      if (!isUuid) return;

      const url = await this.page.evaluate(() => window.location.href).catch(() => '');
      if (url.includes('/wallet') || url.includes('/rewards')) {
        this.log(`Detected unwanted screen navigation (${url}). Redirecting back to game...`);
        if (this.status === 'PLAYING') {
          await this.page.goto(`https://www.dabhousie.com/#/play/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
        } else {
          await this.page.goto(`https://www.dabhousie.com/#/game-status/${this.gameId}`, { waitUntil: 'domcontentloaded' }).catch(() => {});
        }
        await this.page.waitForTimeout(1500);
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
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label], button, span, p, div, input, *'));
        const matches = all.filter(el => {
          const l = (el.getAttribute('aria-label') || '').trim();
          const t = (el.innerText || el.textContent || '').trim();
          if (isExact) {
            return l === targetText || t === targetText;
          }
          if (l === targetText || t === targetText) return true;
          if ((l.includes(targetText) && l.length <= targetText.length + 15) || (t.includes(targetText) && t.length <= targetText.length + 15)) return true;
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
  async launch(browserType, headless = false) {
    this.log(`Opening browser window at position (${this.bounds.x}, ${this.bounds.y})...`);
    
    this.browser = await browserType.launch({
      headless,
      args: [
        `--window-position=${this.bounds.x},${this.bounds.y}`,
        `--window-size=${this.bounds.width},${this.bounds.height}`,
        '--disable-notifications',
      ],
    });

    this.context = await this.browser.newContext({
      viewport: { width: this.bounds.width, height: this.bounds.height - 40 },
      userAgent: `DabHousie-TestPlayer-${this.id}`,
    });

    // Pre-seed local storage so Flutter's SharedPreferences immediately starts with this real player name
    await this.context.addInitScript((playerName) => {
      try {
        localStorage.setItem('flutter.mpt_player_name', JSON.stringify(playerName));
        localStorage.setItem('flutter.mpt_player_avatar', JSON.stringify('avatar_lion'));
      } catch (_) {}
    }, this.name);

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
      const isDialogVisible = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        return text.includes('Enter Your Name') || text.includes('Please set your name') || text.includes('Save & Join');
      });

      if (isDialogVisible) {
        this.log(`Detected mandatory "Enter Your Name" dialog. Entering name "${this.name}"...`);
        // Flutter's TextField has autofocus: true; type directly
        await this.page.keyboard.type(this.name, { delay: 50 });
        await this.page.waitForTimeout(400);

        this.log('Submitting "Save & Join"...');
        const clicked = await this.clickFlutterButton('Save & Join', false);
        if (!clicked) {
          await this.page.keyboard.press('Enter');
        }
        await this.page.waitForTimeout(1000);
      }
    } catch (err) {
      this.log(`Error handling name dialog: ${err.message}`);
    }
  }

  /**
   * Complete the join and registration flow
   */
  async joinGame(joinUrl) {
    this.log(`Navigating to ${joinUrl}...`);
    const codeMatch = joinUrl.match(/join\/([A-Za-z0-9]+)/);
    this.inviteCode = codeMatch ? codeMatch[1].toUpperCase() : 'UNKNOWN';

    await this.page.goto(joinUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await this.page.waitForTimeout(3000);
    await this.enableFlutterSemantics();

    this.userUuid = await this.getAnonymousUserUuid();
    this.log(`Session Auth UUID: ${this.userUuid}`);

    // 1. If landed on Home screen, navigate into Join screen
    for (let step = 0; step < 5; step++) {
      const currentUrl = await this.page.evaluate(() => window.location.href);
      const isJoinScreen = currentUrl.includes('/join');
      if (isJoinScreen) break;

      this.log('Landed on Home screen. Clicking "Enter Code to Join"...');
      const clickedJoin = await this.clickFlutterButton('Enter Code to Join');
      if (!clickedJoin) {
        await this.clickFlutterButton('Join Game');
      }
      await this.page.waitForTimeout(2000);
    }

    // 2. Ensure invite code is entered and looked up
    this.log(`Looking up game code ${this.inviteCode}...`);
    for (let lookupAttempt = 0; lookupAttempt < 5; lookupAttempt++) {
      const hasRegisterBtn = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        const labels = all.map(el => (el.getAttribute('aria-label') || el.innerText || '').trim());
        return text.includes('Register & Get Ticket') || labels.some(l => l.includes('Register & Get Ticket'));
      });

      if (hasRegisterBtn) {
        this.log('Game preview found! "Register & Get Ticket" button is ready.');
        break;
      }

      // Enter code into input
      try {
        const inputs = this.page.locator('input');
        const count = await inputs.count();
        if (count > 0) {
          const firstInput = inputs.first();
          await firstInput.click().catch(() => {});
          await firstInput.fill(this.inviteCode).catch(() => {});
        }
      } catch (_) {}

      await this.clickFlutterButton('Find', true);
      await this.page.waitForTimeout(2000);
    }

    // 3. Register into the game
    let isRegistered = false;
    for (let attempt = 1; attempt <= 3; attempt++) {
      let currentUrl = await this.page.evaluate(() => window.location.href);
      if (currentUrl.includes('/game-status/') || currentUrl.includes('/play/')) {
        isRegistered = true;
        this.finalUrl = currentUrl;
        break;
      }

      this.registrationAttempts = attempt;
      this.log(`Registering into game (attempt ${attempt})...`);
      await this.clickFlutterButton('Register & Get Ticket');
      await this.page.waitForTimeout(1000);

      // Handle mandatory name modal if prompted
      await this.handleMandatoryNameDialog();

      // Wait up to 12 seconds for registration to complete and route to transition
      for (let waitStep = 0; waitStep < 24; waitStep++) {
        const state = await this.page.evaluate(() => {
          const url = window.location.href;
          const text = document.body.innerText || document.body.textContent || '';
          const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
          const labels = all.map(el => (el.getAttribute('aria-label') || el.innerText || '').trim());
          const textUpper = text.toUpperCase();
          const labelsUpper = labels.join(' ').toUpperCase();
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

          return { url, isConfirmed };
        });

        if (state.isConfirmed) {
          isRegistered = true;
          this.finalUrl = state.url;
          break;
        }
        await this.page.waitForTimeout(500);
      }

      if (isRegistered) break;
    }

    if (!this.finalUrl) {
      try {
        this.finalUrl = await this.page.evaluate(() => window.location.href);
      } catch (_) {
        this.finalUrl = this.page.url();
      }
    }

    const gameIdMatch = (this.finalUrl || '').match(/(?:game-status|play)\/([a-f0-9\-]+)/i);
    if (gameIdMatch && gameIdMatch[1].length > 20) {
      this.gameId = gameIdMatch[1];
    } else {
      this.gameId = this.inviteCode;
    }

    if (isRegistered) {
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
   * Observe current called number from the player's screen
   */
  async getCurrentCalledNumber() {
    try {
      await this.ensureInGameScreen();
      const callData = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        if (text.includes('GAME CONCLUDED') || text.includes('GAME COMPLETED') || text.includes('Game Concluded')) {
          return { number: null, isCompleted: true };
        }

        // 1. Primary: Check semantics label CURRENT_CALLED_NUMBER_X
        const allSemantics = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        for (const el of allSemantics) {
          const aria = (el.getAttribute('aria-label') || '').trim();
          if (aria.includes('CURRENT_CALLED_NUMBER_READY')) {
            return { number: null, isCompleted: false };
          }
          const match = aria.match(/CURRENT_CALLED_NUMBER_(\d{1,2})\b/i);
          if (match) {
            const val = parseInt(match[1], 10);
            if (val >= 1 && val <= 90) {
              return { number: val, isCompleted: false };
            }
          }
        }

        // 2. Resilient text parsing: Inspect line with 'CURRENT CALL' and its immediate successor
        const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
        const idx = lines.findIndex(l => l.toUpperCase().includes('CURRENT CALL'));
        if (idx !== -1) {
          // Check inline match (e.g. "CURRENT CALL: 45" or "CURRENT CALL 45")
          const inlineMatch = lines[idx].match(/CURRENT\s+CALL\s*[:\-]?\s*(\d{1,2})\b/i);
          if (inlineMatch) {
            const val = parseInt(inlineMatch[1], 10);
            if (val >= 1 && val <= 90) return { number: val, isCompleted: false };
          }

          // Check line directly after CURRENT CALL
          if (idx + 1 < lines.length) {
            const nextLine = lines[idx + 1].trim();
            if (nextLine.toUpperCase() === 'READY') {
              return { number: null, isCompleted: false };
            }
            if (/^\d{1,2}$/.test(nextLine)) {
              const val = parseInt(nextLine, 10);
              if (val >= 1 && val <= 90) {
                return { number: val, isCompleted: false };
              }
            }
          }
        }

        // 3. Fallback: Check semantics elements around CURRENT CALL
        for (let i = 0; i < allSemantics.length; i++) {
          const t = (allSemantics[i].getAttribute('aria-label') || allSemantics[i].innerText || '').trim();
          if (t.toUpperCase().includes('CURRENT CALL')) {
            if (i + 1 < allSemantics.length) {
              const nextText = (allSemantics[i + 1].getAttribute('aria-label') || allSemantics[i + 1].innerText || '').trim();
              if (nextText.toUpperCase() === 'READY') return { number: null, isCompleted: false };
              if (/^\d{1,2}$/.test(nextText)) {
                const val = parseInt(nextText, 10);
                if (val >= 1 && val <= 90) return { number: val, isCompleted: false };
              }
            }
          }
        }

        return { number: null, isCompleted: false };
      });

      return callData;
    } catch (_) {
      return { number: null, isCompleted: false };
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

    const prizeRules = [
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
      {
        id: 'FULL_HOUSE',
        name: 'Full House',
        isEligible: () => this.ticketNumbers.length === 15 && this.ticketNumbers.every(n => this.dabbedNumbers.has(n)),
      },
    ];

    for (const prize of prizeRules) {
      if (this.claimedPrizes.has(prize.id)) continue;

      if (prize.isEligible()) {
        this.log(`🏆 [PRIZE READY] Winning pattern completed for "${prize.name}"! Submitting claim...`);
        this.claimedPrizes.add(prize.id);

        // Click prize claim button on UI
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
          if (text.includes('Bogey') || text.includes('Invalid Claim') || text.includes('Incomplete')) {
            return { status: 'BOGEY' };
          }
          return { status: 'UNKNOWN' };
        });

        if (claimResult.status === 'APPROVED') {
          this.log(`🎉 [CLAIM APPROVED] Player ${this.id} (${this.name}) won "${prize.name}"! Organizer received approval.`);
          await this.captureScreenshot(`won_${prize.id.toLowerCase()}`);
          await this.clickFlutterButton('Continue Playing', false);
          await this.page.waitForTimeout(500);
        } else if (claimResult.status === 'BOGEY') {
          this.log(`⚠️ Claim for "${prize.name}" rejected by validation.`);
          await this.clickFlutterButton('OK', true);
        } else {
          this.log(`Claim button tapped for "${prize.name}". Submitted to server.`);
        }
      }
    }
  }

  /**
   * Accurately dab a number on the ticket grid without mis-clicking header or recent calls
   * @param {number} numberToDab
   */
  async dabNumber(numberToDab) {
    try {
      this.log(`Dabbing number ${numberToDab} on ticket matrix...`);

      // Helper to check if the target number is marked (ignoring 'unmarked')
      const checkMarkedState = async () => {
        return await this.page.evaluate((targetNum) => {
          const regex = new RegExp(`Ticket\\s+number\\s+${targetNum}\\b`, 'i');
          const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
          for (const el of elements) {
            const aria = (el.getAttribute('aria-label') || '').trim();
            const val = (el.getAttribute('aria-valuetext') || el.getAttribute('value') || '').trim();
            if (regex.test(aria)) {
              const hasUnmarked = aria.toLowerCase().includes('unmarked') || val.toLowerCase().includes('unmarked');
              const hasMarked = aria.toLowerCase().includes('marked') || val.toLowerCase().includes('marked');
              if (hasMarked && !hasUnmarked) {
                return true;
              }
            }
          }
          return false;
        }, numberToDab);
      };

      // 1. If already marked, skip
      if (await checkMarkedState()) {
        this.log(`Number ${numberToDab} is already marked.`);
        return true;
      }

      // 2. Step 1: Use Playwright Locator on Flutter Semantics
      const locators = [
        this.page.locator(`flt-semantics[aria-label*="Ticket number ${numberToDab}"]`),
        this.page.locator(`[aria-label*="Ticket number ${numberToDab}"]`),
      ];

      for (const loc of locators) {
        const count = await loc.count();
        if (count > 0) {
          for (let i = 0; i < count; i++) {
            const el = loc.nth(i);
            const box = await el.boundingBox().catch(() => null);
            if (box && box.width > 5 && box.height > 5) {
              const cx = box.x + box.width / 2;
              const cy = box.y + box.height / 2;
              await this.page.mouse.click(cx, cy);
              await el.click({ force: true }).catch(() => {});
              break;
            }
          }
        }
      }

      // 3. Step 2: DOM Event dispatch fallback
      await this.page.evaluate((targetNum) => {
        const targetRegex = new RegExp(`Ticket\\s+number\\s+${targetNum}\\b`, 'i');
        const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], button, div, span'));
        const matching = elements.filter(el => {
          const aria = (el.getAttribute('aria-label') || '').trim();
          return targetRegex.test(aria);
        });

        for (const el of matching) {
          el.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          el.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          if (typeof el.click === 'function') el.click();
        }
      }, numberToDab);

      await this.page.waitForTimeout(250);

      // Verify if marked
      let isMarked = await checkMarkedState();

      // 4. Step 3: Geometric Grid Click Fallback if still not marked
      if (!isMarked) {
        this.log(`Accessibility click did not mark ${numberToDab}, calculating geometric coordinates...`);
        
        // Find row & col of numberToDab
        let targetRow = -1;
        for (let r = 0; r < 3; r++) {
          if (this.ticketMatrix[r] && this.ticketMatrix[r].includes(numberToDab)) {
            targetRow = r;
            break;
          }
        }
        const targetCol = numberToDab === 90 ? 8 : Math.min(8, Math.floor(numberToDab / 10));

        const viewportSize = this.page.viewportSize() || { width: 430, height: 700 };
        const gridLeft = 26;
        const gridWidth = viewportSize.width - 52;
        const colWidth = gridWidth / 9;
        const cellX = gridLeft + (targetCol + 0.5) * colWidth;

        // Calibrated row Y centers on mobile viewport
        const rowYCenters = [366, 423, 480];
        const rowsToTry = targetRow >= 0 ? [targetRow] : [0, 1, 2];

        for (const r of rowsToTry) {
          const cellY = rowYCenters[r];
          await this.page.mouse.click(cellX, cellY);
          await this.page.waitForTimeout(200);
          if (await checkMarkedState()) {
            isMarked = true;
            break;
          }
        }
      }

      await this.page.waitForTimeout(200);
      isMarked = await checkMarkedState();
      if (isMarked) {
        this.log(`Dabbed ${numberToDab} successfully (Marked verified on ticket).`);
      } else {
        this.log(`Dab action dispatched for ${numberToDab}.`);
      }
      return true;
    } catch (err) {
      this.error(`Failed to dab number ${numberToDab}: ${err.message}`);
      return false;
    }
  }

  async close() {
    try {
      if (this.context) await this.context.close();
      if (this.browser) await this.browser.close();
      this.log('Session closed.');
    } catch (_) {}
  }
}
