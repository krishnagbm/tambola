import path from 'path';
import fs from 'fs';

const SCREENSHOTS_DIR = path.resolve('tests/multiplayer/screenshots');

export class PlayerSession {
  /**
   * @param {number} id - Player index (1, 2, 3...)
   * @param {string} name - Player display name (e.g. "DabTest Player 1")
   * @param {object} windowBounds - { x, y, width, height }
   */
  constructor(id, name, windowBounds = { x: 0, y: 0, width: 440, height: 780 }) {
    this.id = id;
    this.name = name;
    this.bounds = windowBounds;
    this.context = null;
    this.browser = null;
    this.page = null;
    this.ticketNumbers = [];
    this.dabbedNumbers = new Set();
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
   * Enables Flutter Web Semantics / Accessibility tree
   */
  async enableFlutterSemantics() {
    try {
      await this.page.evaluate(() => {
        const placeholder = document.querySelector('flt-semantics-placeholder');
        if (placeholder) {
          placeholder.click();
          placeholder.dispatchEvent(new MouseEvent('click', { bubbles: true }));
        }
      });
      await this.page.keyboard.press('Tab');
      await this.page.keyboard.press('Enter');
      await this.page.waitForTimeout(400);
    } catch (_) {}
  }

  /**
   * Safe click on text elements across Flutter CanvasKit / HTML modes
   * Sorts matches by text length ascending to ensure the smallest/leaf target is clicked
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
          if (l.includes(targetText)) return true;
          if (t.includes(targetText) && t.length <= targetText.length + 30) return true;
          return false;
        });

        if (matches.length > 0) {
          // Sort by text/aria length ascending so we get the most specific/innermost element
          matches.sort((a, b) => {
            const lenA = (a.getAttribute('aria-label') || a.innerText || '').length;
            const lenB = (b.getAttribute('aria-label') || b.innerText || '').length;
            return lenA - lenB;
          });
          const target = matches[0];
          target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          if (typeof target.click === 'function') target.click();

          const r = target.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
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
      viewport: { width: this.bounds.width, height: this.bounds.height - 80 },
      userAgent: `DabHousie-TestPlayer-${this.id}`,
    });

    // Pre-seed local storage so Flutter's SharedPreferences immediately starts with this real player name
    await this.context.addInitScript((playerName) => {
      try {
        localStorage.setItem('flutter.mpt_player_name', playerName);
        localStorage.setItem('flutter.mpt_player_avatar', 'avatar_lion');
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
        const inputs = this.page.locator('input');
        const count = await inputs.count();
        let filled = false;
        for (let i = count - 1; i >= 0; i--) {
          const inp = inputs.nth(i);
          if (await inp.isVisible().catch(() => false)) {
            await inp.click().catch(() => {});
            await inp.fill(this.name).catch(() => {});
            filled = true;
            break;
          }
        }

        if (!filled) {
          await this.page.keyboard.press('Control+A').catch(() => {});
          await this.page.keyboard.type(this.name).catch(() => {});
        }

        await this.page.waitForTimeout(300);
        this.log('Submitting "Save & Join"...');
        await this.clickFlutterButton('Save & Join', true);
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
    for (let attempt = 1; attempt <= 5; attempt++) {
      const currentUrl = await this.page.evaluate(() => window.location.href);
      if (currentUrl.includes('/game-status/') || currentUrl.includes('/play/')) {
        isRegistered = true;
        break;
      }

      this.registrationAttempts = attempt;
      this.log(`Registering into game (attempt ${attempt})...`);
      await this.clickFlutterButton('Register & Get Ticket');
      await this.page.waitForTimeout(800);

      // Handle mandatory name modal if prompted
      await this.handleMandatoryNameDialog();

      isRegistered = await this.page.evaluate(() => {
        const url = window.location.href;
        const text = document.body.innerText || document.body.textContent || '';
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label]'));
        const labels = all.map(el => (el.getAttribute('aria-label') || el.innerText || '').trim());
        const has = (t) => text.includes(t) || labels.some(l => l.includes(t));

        return (
          url.includes('/game-status/') ||
          url.includes('/play/') ||
          has('SEAT CONFIRMED') ||
          has('Waiting for Organizer')
        );
      });

      if (isRegistered) break;
      await this.page.waitForTimeout(1500);
    }

    try {
      this.finalUrl = await this.page.evaluate(() => window.location.href);
    } catch (_) {
      this.finalUrl = this.page.url();
    }

    const gameIdMatch = this.finalUrl.match(/(?:game-status|play)\/([a-f0-9\-]+)/i);
    if (gameIdMatch) {
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
        await this.page.waitForTimeout(2000);
        await this.enableFlutterSemantics();
        await this.captureScreenshot('game_started');
        return;
      }

      await this.page.waitForTimeout(2000);
    }

    this.log('Timed out waiting for game start after 10 minutes.');
  }

  /**
   * Scrapes and caches the 15 numbers from the player's ticket
   */
  async inspectAndExtractTicketNumbers() {
    this.log('Extracting ticket matrix numbers...');
    
    await this.enableFlutterSemantics();
    await this.page.waitForTimeout(1000);

    for (let attempt = 1; attempt <= 5; attempt++) {
      const numbers = await this.page.evaluate(() => {
        const found = new Set();
        const allElements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], span, p, div, button'));
        
        // 1. Primary: Check for Flutter Semantics label "Ticket number X"
        for (const el of allElements) {
          const aria = (el.getAttribute('aria-label') || '').trim();
          const match = aria.match(/Ticket\s+number\s+(\d{1,2})\b/i);
          if (match) {
            const val = parseInt(match[1], 10);
            if (val >= 1 && val <= 90) {
              found.add(val);
            }
          }
        }

        // 2. Fallback: Search all text nodes if semantics tree had fewer numbers
        if (found.size < 15) {
          const fullHtml = document.body.innerHTML || '';
          const regexAll = /Ticket\s+number\s+(\d{1,2})\b/gi;
          let m;
          while ((m = regexAll.exec(fullHtml)) !== null) {
            const val = parseInt(m[1], 10);
            if (val >= 1 && val <= 90) {
              found.add(val);
            }
          }
        }

        return Array.from(found).sort((a, b) => a - b);
      });

      if (numbers.length >= 15 || attempt === 5) {
        this.ticketNumbers = numbers;
        this.log(`Ticket verified with ${this.ticketNumbers.length} numbers: [${this.ticketNumbers.join(', ')}]`);
        return this.ticketNumbers;
      }

      await this.page.waitForTimeout(1000);
    }

    return this.ticketNumbers;
  }

  /**
   * Observe current called number from the player's screen
   */
  async getCurrentCalledNumber() {
    try {
      const callData = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        if (text.includes('GAME CONCLUDED') || text.includes('GAME COMPLETED') || text.includes('Game Concluded')) {
          return { number: null, isCompleted: true };
        }

        // 1. Look for exact "CURRENT CALL" followed by integer (skip "2 / 90" or "Called")
        const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
        const idx = lines.findIndex(l => l.toUpperCase() === 'CURRENT CALL' || l.includes('CURRENT CALL'));
        if (idx !== -1) {
          for (let i = idx + 1; i < Math.min(lines.length, idx + 6); i++) {
            const l = lines[i];
            if (l.includes('/') || l.includes('Called') || l.includes('DABHOUSIE') || l.includes('TICKET')) {
              continue;
            }
            if (/^\d{1,2}$/.test(l)) {
              const val = parseInt(l, 10);
              if (val >= 1 && val <= 90) {
                return { number: val, isCompleted: false };
              }
            }
          }
        }

        // 2. Fallback to semantics query
        const allSemantics = Array.from(document.querySelectorAll('flt-semantics, [aria-label], span, p, div'));
        for (let i = 0; i < allSemantics.length; i++) {
          const t = (allSemantics[i].getAttribute('aria-label') || allSemantics[i].innerText || '').trim();
          if (t.toUpperCase() === 'CURRENT CALL') {
            for (let j = i + 1; j < Math.min(allSemantics.length, i + 6); j++) {
              const nextText = (allSemantics[j].getAttribute('aria-label') || allSemantics[j].innerText || '').trim();
              if (nextText.includes('/') || nextText.includes('Called')) continue;
              if (/^\d{1,2}$/.test(nextText)) {
                const val = parseInt(nextText, 10);
                if (val >= 1 && val <= 90) {
                  return { number: val, isCompleted: false };
                }
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
      await this.dabNumber(calledNum);
      this.dabbedNumbers.add(calledNum);
      if (callSequence <= 5) {
        await this.captureScreenshot(`call_${callSequence}_dabbed_${calledNum}`);
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
      
      const clicked = await this.page.evaluate((targetNum) => {
        const targetRegex = new RegExp(`Ticket\\s+number\\s+${targetNum}\\b`, 'i');
        const elements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], button, div, span'));
        
        // Find exact semantic ticket cell
        const matching = elements.filter(el => {
          const aria = (el.getAttribute('aria-label') || '').trim();
          return targetRegex.test(aria);
        });

        if (matching.length > 0) {
          const exact = matching[0];
          exact.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          exact.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          exact.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          if (typeof exact.click === 'function') exact.click();

          const r = exact.getBoundingClientRect();
          if (r.width > 0 && r.height > 0) {
            return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
          }
          return { clicked: true };
        }
        return null;
      }, numberToDab);

      if (clicked && clicked.x && clicked.y) {
        await this.page.mouse.click(clicked.x, clicked.y);
      }

      await this.page.waitForTimeout(300);
      this.log(`Dabbed ${numberToDab} successfully.`);
    } catch (err) {
      this.error(`Failed to dab number ${numberToDab}: ${err.message}`);
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
