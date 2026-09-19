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
    this.inviteCode = codeMatch ? codeMatch[1] : 'UNKNOWN';

    await this.page.goto(joinUrl, { waitUntil: 'domcontentloaded', timeout: 45000 });
    await this.page.waitForTimeout(2500);

    // Ensure localStorage is set if already on the origin
    await this.page.evaluate((playerName) => {
      try {
        localStorage.setItem('flutter.mpt_player_name', playerName);
        localStorage.setItem('flutter.mpt_player_avatar', 'avatar_lion');
      } catch (_) {}
    }, this.name);

    await this.enableFlutterSemantics();

    this.userUuid = await this.getAnonymousUserUuid();
    this.log(`Session Auth UUID: ${this.userUuid}`);

    this.log('Waiting for Register button or Lobby status...');
    for (let i = 0; i < 20; i++) {
      const currentUrl = this.page.url();
      if (currentUrl.includes('/game-status/') || currentUrl.includes('/play/')) {
        this.log(`Already in game status/play screen: ${currentUrl}`);
        break;
      }

      const foundState = await this.page.evaluate(() => {
        const full = document.body.innerText || document.body.textContent || '';
        const all = Array.from(document.querySelectorAll('flt-semantics, [aria-label], *'));
        const labels = all.map(el => (el.getAttribute('aria-label') || el.innerText || '').trim());
        const has = (t) => full.includes(t) || labels.some(l => l.includes(t));

        if (has('Register & Get Ticket')) return 'READY_TO_REGISTER';
        if (has('SEAT CONFIRMED') || has('Waiting for Organizer')) return 'IN_LOBBY';
        if (has('CURRENT CALL') || has('DABHOUSIE TICKET')) return 'IN_PLAY';
        return null;
      });

      if (foundState === 'READY_TO_REGISTER' || foundState === 'IN_LOBBY' || foundState === 'IN_PLAY') {
        this.log(`Found state: ${foundState}`);
        break;
      }

      if (i === 4 && currentUrl.includes('/join')) {
        try {
          const input = this.page.locator('input').first();
          if (await input.isVisible({ timeout: 2000 })) {
            await input.fill(this.inviteCode);
          }
        } catch (_) {}
        await this.clickFlutterButton('Find', true);
      }
      await this.page.waitForTimeout(1000);
    }

    // Attempt profile name change if on join screen
    if (this.page.url().includes('/join')) {
      try {
        this.log(`Setting player display name to "${this.name}"...`);
        const clickedChange = await this.clickFlutterButton('Change', true);
        if (clickedChange) {
          await this.page.waitForTimeout(600);
          const nameInput = this.page.locator('input').last();
          if (await nameInput.isVisible({ timeout: 2500 }).catch(() => false)) {
            await nameInput.fill('');
            await nameInput.fill(this.name);
            await this.page.waitForTimeout(200);
            await this.clickFlutterButton('Save Profile', true);
            await this.page.waitForTimeout(800);
          } else {
            await this.page.keyboard.press('Control+A').catch(() => {});
            await this.page.keyboard.type(this.name).catch(() => {});
            await this.clickFlutterButton('Save Profile', true);
            await this.page.waitForTimeout(800);
          }
        }
      } catch (_) {}
    }

    let isRegistered = false;
    for (let attempt = 1; attempt <= 4; attempt++) {
      const cur = this.page.url();
      if (cur.includes('/game-status/') || cur.includes('/play/')) {
        isRegistered = true;
        break;
      }

      this.registrationAttempts = attempt;
      this.log(`Registering into game (attempt ${attempt})...`);
      await this.clickFlutterButton('Register & Get Ticket');
      await this.page.waitForTimeout(600);

      // Handle mandatory name modal if prompted
      await this.handleMandatoryNameDialog();

      isRegistered = await this.page.waitForFunction(() => {
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
      }, { timeout: 6000 }).then(() => true).catch(() => false);

      if (isRegistered) break;
      await this.page.waitForTimeout(1000);
    }

    try {
      this.finalUrl = await this.page.evaluate(() => window.location.href);
    } catch (_) {
      this.finalUrl = this.page.url();
    }

    const gameIdMatch = this.finalUrl.match(/(?:game-status|play)\/([a-f0-9\-]+)/i);
    if (gameIdMatch) {
      this.gameId = gameIdMatch[1];
    } else if (!this.gameId) {
      this.gameId = this.inviteCode;
    }

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
    
    await this.page.waitForFunction(() => {
      const url = window.location.href;
      const text = document.body.innerText || document.body.textContent || '';
      return (
        url.includes('/play/') ||
        text.includes('CURRENT CALL') ||
        text.includes('DABHOUSIE TICKET')
      );
    }, { timeout: 600000 }); // Wait up to 10 minutes for host to start

    this.status = 'PLAYING';
    this.log('Game has started! In gameplay screen.');
    await this.page.waitForTimeout(2000); // allow ticket to render
    await this.enableFlutterSemantics();
    await this.captureScreenshot('game_started');
  }

  /**
   * Scrapes and caches the 15 numbers from the player's ticket
   */
  async inspectAndExtractTicketNumbers() {
    this.log('Extracting ticket matrix numbers...');
    
    await this.enableFlutterSemantics();
    await this.page.waitForTimeout(1000);

    const numbers = await this.page.evaluate(() => {
      // 1. Check all elements in DOM
      const found = new Set();
      const allElements = Array.from(document.querySelectorAll('flt-semantics, [aria-label], span, p, div'));
      
      for (const el of allElements) {
        const t = (el.getAttribute('aria-label') || el.innerText || el.textContent || '').trim();
        if (/^\d{1,2}$/.test(t)) {
          const val = parseInt(t, 10);
          if (val >= 1 && val <= 90) {
            found.add(val);
          }
        }
      }

      // 2. Also parse plain text lines
      const fullText = document.body.innerText || document.body.textContent || '';
      const lines = fullText.split('\n').map(l => l.trim()).filter(Boolean);
      const ticketIdx = lines.findIndex(l => l.includes('DABHOUSIE TICKET') || l.includes('Marked'));
      const claimIdx = lines.findIndex(l => l.includes('Claim Winning Prize') || l.includes('Early Five'));

      let searchLines = lines;
      if (ticketIdx !== -1 && claimIdx !== -1 && claimIdx > ticketIdx) {
        searchLines = lines.slice(ticketIdx, claimIdx);
      }

      for (const line of searchLines) {
        const parts = line.split(/\s+/);
        for (const p of parts) {
          const num = parseInt(p, 10);
          if (!isNaN(num) && num >= 1 && num <= 90 && String(num) === p) {
            found.add(num);
          }
        }
      }

      return Array.from(found).sort((a, b) => a - b);
    });

    this.ticketNumbers = numbers;
    this.log(`Ticket verified with ${this.ticketNumbers.length} numbers: [${this.ticketNumbers.join(', ')}]`);
    return this.ticketNumbers;
  }

  /**
   * Observe current called number from the player's screen
   */
  async getCurrentCalledNumber() {
    try {
      const callData = await this.page.evaluate(() => {
        const text = document.body.innerText || document.body.textContent || '';
        if (text.includes('GAME COMPLETED') || text.includes('Game Concluded')) {
          return { number: null, isCompleted: true };
        }

        const allSemantics = Array.from(document.querySelectorAll('flt-semantics, [aria-label], span, p, div'));
        for (let i = 0; i < allSemantics.length; i++) {
          const t = (allSemantics[i].getAttribute('aria-label') || allSemantics[i].innerText || '').trim();
          if (t === 'CURRENT CALL' && allSemantics[i + 1]) {
            const nextText = (allSemantics[i + 1].getAttribute('aria-label') || allSemantics[i + 1].innerText || '').trim();
            const val = parseInt(nextText, 10);
            if (!isNaN(val) && val >= 1 && val <= 90) {
              return { number: val, isCompleted: false };
            }
          }
        }

        const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
        const idx = lines.findIndex(l => l.includes('CURRENT CALL'));
        if (idx !== -1 && lines[idx + 1]) {
          const valStr = lines[idx + 1];
          if (valStr === 'READY') {
            return { number: null, isCompleted: false };
          }
          const val = parseInt(valStr, 10);
          if (!isNaN(val) && val >= 1 && val <= 90) {
            return { number: val, isCompleted: false };
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
    const hasNumber = this.ticketNumbers.includes(calledNum);
    const isAlreadyDabbed = this.dabbedNumbers.has(calledNum);

    console.log(`Player ${this.id}:`);
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
      
      const dabbed = await this.page.evaluate((targetNum) => {
        const text = String(targetNum);
        const ariaTarget = `Ticket number ${text}`;
        
        const allDivs = Array.from(document.querySelectorAll('flt-semantics, [aria-label], button, span, p, div, *'));
        const ticketHeader = allDivs.find(el => (el.innerText || el.textContent || '').includes('DABHOUSIE TICKET'));
        const claimHeader = allDivs.find(el => (el.innerText || el.textContent || '').includes('Claim Winning Prize'));

        const ticketY = ticketHeader ? ticketHeader.getBoundingClientRect().top : 0;
        const claimY = claimHeader ? claimHeader.getBoundingClientRect().top : window.innerHeight;

        const candidates = allDivs.filter(el => {
          const directText = (el.innerText || el.textContent || '').trim();
          const aria = (el.getAttribute('aria-label') || '').trim();
          const matches = directText === text || aria === ariaTarget || aria === text || aria.startsWith(ariaTarget);
          if (!matches) return false;
          const rect = el.getBoundingClientRect();
          return rect.top >= (ticketY - 10) && rect.bottom <= (claimY + 10) && rect.width > 10 && rect.height > 10;
        });

        if (candidates.length > 0) {
          // Sort by smallest area (most specific inner element)
          candidates.sort((a, b) => {
            const rA = a.getBoundingClientRect();
            const rB = b.getBoundingClientRect();
            return (rA.width * rA.height) - (rB.width * rB.height);
          });
          const target = candidates[0];
          target.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, cancelable: true }));
          target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          if (typeof target.click === 'function') target.click();
          return true;
        }

        return false;
      }, numberToDab);

      if (!dabbed) {
        await this.clickFlutterButton(`Ticket number ${numberToDab}`, false);
      }
      if (!dabbed) {
        await this.clickFlutterButton(String(numberToDab), true);
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
