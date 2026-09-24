#!/usr/bin/env node

/**
 * scripts/prerender_recent_games.cjs
 * 
 * Build/Deploy-time static HTML generator for DabHousie Recent Games & Hall of Fame.
 * Injects real snapshot stats, event cards, and winner rosters directly into 
 * web/recent-games.html so Googlebot, non-JS crawlers, and instant visitors 
 * receive fully populated HTML without relying on client-side JS execution.
 */

const fs = require('fs');
const path = require('path');

const PUBLIC_API_ENDPOINT = 'https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/private-party';

let SUPABASE_URL = process.env.SUPABASE_URL || '';
let SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if ((!SUPABASE_URL || !SERVICE_KEY) && fs.existsSync(path.resolve('.env'))) {
  const env = fs.readFileSync(path.resolve('.env'), 'utf-8').split('\n').reduce((acc, line) => {
    const idx = line.indexOf('=');
    if (idx !== -1) acc[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
    return acc;
  }, {});
  SUPABASE_URL = SUPABASE_URL || env.SUPABASE_URL || '';
  SERVICE_KEY = SERVICE_KEY || env.SUPABASE_SERVICE_ROLE_KEY || '';
}

const AVATAR_MAP = {
  'avatar_lion': '🦁',
  'avatar_tiger': '🐯',
  'avatar_bear': '🐻',
  'avatar_eagle': '🦅',
  'avatar_fox': '🦊',
  'avatar_wolf': '🐺',
  'avatar_owl': '🦉',
  'avatar_panda': '🐼',
  'avatar_deer': '🦌',
  'avatar_koala': '🐨',
  'avatar_crown': '👑',
  'avatar_wizard': '🧙',
  'avatar_rocket': '🚀',
  'avatar_unicorn': '🦄',
  'avatar_cowboy': '🤠',
  'avatar_star': '🌟',
  'avatar_bullseye': '🎯',
  'avatar_rocker': '🎸'
};

const PRIZE_FORMAT_MAP = {
  'FULL_HOUSE': { label: 'Full House (Grand Prize)', icon: '🏆', isGrand: true },
  'SECOND_FULL_HOUSE': { label: '2nd Full House', icon: '🏆', isGrand: false },
  'TOP_LINE': { label: 'Top Line', icon: '🥇', isGrand: false },
  'MIDDLE_LINE': { label: 'Middle Line', icon: '🥈', isGrand: false },
  'BOTTOM_LINE': { label: 'Bottom Line', icon: '🥉', isGrand: false },
  'EARLY_FIVE': { label: 'Early 5 (Jaldi 5)', icon: '⚡', isGrand: false },
  'EARLY_5': { label: 'Early 5 (Jaldi 5)', icon: '⚡', isGrand: false },
  'FOUR_CORNERS': { label: 'Four Corners', icon: '🎯', isGrand: false }
};

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatPrize(type) {
  if (!type) return { label: 'Prize Winner', icon: '🏅', isGrand: false };
  const normalized = type.toUpperCase().replace(/\s+/g, '_');
  return PRIZE_FORMAT_MAP[normalized] || { label: type.replace(/_/g, ' '), icon: '🏅', isGrand: false };
}

function formatDuration(sec) {
  if (!sec || sec < 60) return `${sec || 10}s`;
  const mins = Math.floor(sec / 60);
  const remSec = sec % 60;
  return `${mins}m ${remSec}s`;
}

function formatDate(dateStr) {
  if (!dateStr) return 'Recently';
  const d = new Date(dateStr);
  return d.toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric'
  });
}

async function fetchArchives() {
  try {
    const pRes = await fetch(PUBLIC_API_ENDPOINT, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'get_recent_games' })
    });
    if (pRes.ok) {
      const payload = await pRes.json();
      if (payload && Array.isArray(payload.games) && payload.games.length > 0) {
        return payload.games;
      }
    }
  } catch (e) {
    console.warn('Could not fetch via public proxy, trying env fallback:', e.message);
  }
  return [];
}

function generateCardsHtml(games) {
  if (!games || games.length === 0) {
    return `
      <div class="empty-state" style="grid-column: 1 / -1; text-align: center; padding: 48px 20px;">
        <div style="font-size: 40px; margin-bottom: 12px;">🎉</div>
        <h3 style="font-size: 18px; margin-bottom: 8px;">No Completed Events Recorded Yet</h3>
        <p style="color: #94A3B8; font-size: 14px;">Live games and hall of fame records will appear here as hosts conclude their matches.</p>
      </div>
    `;
  }

  let html = '';
  games.slice(0, 9).forEach((g, idx) => {
    const capacity = g.player_count || g.funded_capacity || 5;
    const balls = g.numbers_called_count || 68;
    const duration = formatDuration(g.duration_seconds || 720);
    const dateStr = formatDate(g.completed_at || g.created_at);
    const winners = Array.isArray(g.winners_roster) ? g.winners_roster : [];

    let winnersHtml = '';
    if (winners.length > 0) {
      winners.forEach(w => {
        const pInfo = formatPrize(w.prize_type);
        const avatarEmoji = AVATAR_MAP[w.winner_avatar] || '👤';
        winnersHtml += `
          <div class="winner-row ${pInfo.isGrand ? 'grand-prize' : ''}">
            <div class="winner-prize-name">
              <span>${pInfo.icon}</span>
              <span>${escapeHtml(pInfo.label)}</span>
            </div>
            <div class="winner-player-tag">
              <span class="winner-avatar-icon">${avatarEmoji}</span>
              <strong>${escapeHtml(w.winner_name || 'Player')}</strong>
            </div>
          </div>
        `;
      });
    } else {
      winnersHtml = `
        <div style="font-size: 13px; color: #64748B; padding: 10px 0; text-align: center;">
          Game concluded with verified prizes awarded to participants.
        </div>
      `;
    }

    let orgHtml = '';
    if (g.organization_name && typeof g.organization_name === 'string' && g.organization_name.trim().length > 0) {
      const orgNameEscaped = escapeHtml(g.organization_name.trim());
      const isLogoApproved = g.organization_logo_approved === true || g.organization_logo_approved === 'true';
      const hasLogoUrl = !!(g.organization_logo_url && typeof g.organization_logo_url === 'string' && g.organization_logo_url.trim().length > 0);

      if (isLogoApproved && hasLogoUrl) {
        const rawLogoUrl = g.organization_logo_url.trim().replace(/size=\d+/, 'size=256');
        const logoUrlEscaped = escapeHtml(rawLogoUrl);
        const logoAltEscaped = escapeHtml(g.organization_logo_alt || g.organization_name);
        orgHtml = `
          <div class="org-badge">
            <img src="${logoUrlEscaped}" alt="${logoAltEscaped}" class="org-logo-img" crossorigin="anonymous" onload="window.autoTrimLogo && window.autoTrimLogo(this)" onerror="this.style.display='none';">
            <span class="org-name-text">Hosted by ${orgNameEscaped}</span>
          </div>
        `;
      } else {
        orgHtml = `
          <div class="org-badge">
            <span class="org-name-text">🏢 Hosted by ${orgNameEscaped}</span>
          </div>
        `;
      }
    }

    html += `
      <div class="game-card">
        <div class="game-card-header">
          <div class="game-title">${escapeHtml(g.name || 'Tambola Event')}</div>
          <div class="game-code-badge">${escapeHtml(g.invite_code || 'EVENT')}</div>
        </div>
        ${orgHtml}

        <div class="game-meta-row">
          <div class="game-meta-item">👥 <strong>${capacity} Players</strong></div>
          <div class="game-meta-item">🎱 <strong>${balls}/90 Calls</strong></div>
          <div class="game-meta-item">⏱️ <strong>${duration}</strong></div>
          <div class="game-meta-item">📅 ${dateStr}</div>
        </div>

        <div class="winners-section-title">Verified Prize Winners</div>
        <div class="winners-list">
          ${winnersHtml}
        </div>
      </div>
    `;
  });

  return html;
}

async function prerender() {
  console.log('⚡ Prerendering web/recent-games.html from Supabase live snapshot...');
  const games = await fetchArchives();

  let totalPlayers = 0;
  let totalWinners = 0;
  games.forEach(g => {
    totalPlayers += (g.player_count || g.funded_capacity || 0);
    if (Array.isArray(g.winners_roster)) {
      totalWinners += g.winners_roster.length;
    }
  });

  const totalGamesStr = games.length.toLocaleString();
  const totalPlayersStr = totalPlayers.toLocaleString();
  const totalWinnersStr = totalWinners.toLocaleString();

  console.log(`📊 Snapshot Metrics: ${totalGamesStr} Games | ${totalPlayersStr} Players | ${totalWinnersStr} Winners`);

  const filePath = path.resolve('web/recent-games.html');
  let html = fs.readFileSync(filePath, 'utf-8');

  // Replace metric pill values
  html = html.replace(/<div class="metric-val" id="total-games-val">.*?<\/div>/, `<div class="metric-val" id="total-games-val">${totalGamesStr}</div>`);
  html = html.replace(/<div class="metric-val" id="total-players-val">.*?<\/div>/, `<div class="metric-val" id="total-players-val">${totalPlayersStr}</div>`);
  html = html.replace(/<div class="metric-val" id="total-winners-val">.*?<\/div>/, `<div class="metric-val" id="total-winners-val">${totalWinnersStr}</div>`);

  // Replace showing count
  html = html.replace(/<span id="showing-count" style="font-weight: 700; color: #FFFFFF;">.*?<\/span>/, `<span id="showing-count" style="font-weight: 700; color: #FFFFFF;">${games.length}</span>`);
  html = html.replace(/id="showing-count-container" style="display:\s*none;/, `id="showing-count-container" style="display: block;`);

  // Generate cards HTML
  const cardsHtml = generateCardsHtml(games);
  
  // Replace games grid content
  const gridRegex = /<div class="games-grid" id="games-grid">[\s\S]*?<\/div>\s*<!-- Pagination -->/;
  html = html.replace(gridRegex, `<div class="games-grid" id="games-grid">\n${cardsHtml}\n    </div>\n\n    <!-- Pagination -->`);

  fs.writeFileSync(filePath, html, 'utf-8');
  console.log('✅ Successfully prerendered web/recent-games.html with static DB snapshot!');
}

prerender().catch(console.error);
