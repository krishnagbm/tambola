// web/js/nav.js
// DabHousie — Shared Navigation & Auth State Controller

(function () {
  'use strict';

  const AVATAR_EMOJIS = {
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
    'avatar_rocker': '🎸',
  };

  function cleanStorageStr(val) {
    if (val === null || val === undefined) return '';
    let s = String(val).trim();
    // Strip surrounding JSON quotes added by Flutter SharedPreferences Web (e.g. '"Swift Gamer"')
    while (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.slice(1, -1).trim();
    }
    return s;
  }

  function getAvatarEmoji(avatarKey) {
    const key = cleanStorageStr(avatarKey);
    if (!key) return '🦁';
    if (AVATAR_EMOJIS[key]) return AVATAR_EMOJIS[key];
    return '🦁';
  }

  function getUserSession() {
    // 1. Check direct query params or hash
    const params = new URLSearchParams(window.location.search);
    const hashPart = window.location.hash.includes('?') ? window.location.hash.split('?')[1] : '';
    const hashParams = new URLSearchParams(hashPart);

    let userId = cleanStorageStr(
      params.get('user_id') ||
      hashParams.get('user_id') ||
      localStorage.getItem('flutter.dabhousie_user_id') ||
      localStorage.getItem('dabhousie_user_id') ||
      ''
    );
    let email = cleanStorageStr(
      params.get('email') ||
      hashParams.get('email') ||
      localStorage.getItem('flutter.dabhousie_user_email') ||
      localStorage.getItem('dabhousie_user_email') ||
      ''
    );
    let name = cleanStorageStr(
      params.get('name') ||
      hashParams.get('name') ||
      localStorage.getItem('flutter.mpt_player_name') ||
      localStorage.getItem('flutter.dabhousie_user_name') ||
      localStorage.getItem('dabhousie_user_name') ||
      localStorage.getItem('mpt_player_name') ||
      ''
    );
    let avatar = cleanStorageStr(
      params.get('avatar') ||
      hashParams.get('avatar') ||
      localStorage.getItem('flutter.mpt_player_avatar') ||
      localStorage.getItem('flutter.dabhousie_user_avatar') ||
      localStorage.getItem('dabhousie_user_avatar') ||
      localStorage.getItem('mpt_player_avatar') ||
      ''
    );
    let balance = cleanStorageStr(
      params.get('balance') ||
      hashParams.get('balance') ||
      localStorage.getItem('flutter.dabhousie_balance') ||
      localStorage.getItem('dabhousie_balance') ||
      ''
    );
    let unclaimedRaw = cleanStorageStr(
      localStorage.getItem('flutter.dabhousie_unclaimed_rewards') ||
      localStorage.getItem('dabhousie_unclaimed_rewards') ||
      '0'
    );
    let unclaimedCount = parseInt(unclaimedRaw, 10);
    if (isNaN(unclaimedCount) || unclaimedCount < 0) unclaimedCount = 0;

    // 2. Check Supabase token stored in localStorage if not found above
    if (!userId || !email) {
      try {
        for (let i = 0; i < localStorage.length; i++) {
          const key = localStorage.key(i);
          if (key && (key.includes('-auth-token') || key.includes('supabase.auth.token') || key.startsWith('sb-') || key.includes('supabase'))) {
            const raw = localStorage.getItem(key);
            if (!raw) continue;
            try {
              const parsed = JSON.parse(raw);
              const user = parsed?.user || parsed?.currentSession?.user || parsed?.session?.user;
              if (user && (user.id || user.email)) {
                userId = userId || cleanStorageStr(user.id || '');
                email = email || cleanStorageStr(user.email || '');
                name = name || cleanStorageStr(user.user_metadata?.full_name || user.user_metadata?.name || user.user_metadata?.user_name || (user.email ? user.email.split('@')[0] : ''));
                avatar = avatar || cleanStorageStr(user.user_metadata?.avatar_url || user.user_metadata?.avatar || user.user_metadata?.picture || '');
                break;
              }
            } catch (_) {}
          }
        }
      } catch (e) {
        // Ignore localStorage parse errors
      }
    }

    // 3. Fallback: check mpt_local_uuid
    if (!userId) {
      userId = cleanStorageStr(localStorage.getItem('flutter.mpt_local_uuid') || localStorage.getItem('mpt_local_uuid') || '');
    }

    // 4. Cache discovered credentials (clean unquoted strings) so session stays consistent across pages
    if (userId) localStorage.setItem('dabhousie_user_id', userId);
    if (email) localStorage.setItem('dabhousie_user_email', email);
    if (name) localStorage.setItem('dabhousie_user_name', name);
    if (avatar) localStorage.setItem('dabhousie_user_avatar', avatar);
    if (balance) localStorage.setItem('dabhousie_balance', balance);
    localStorage.setItem('dabhousie_unclaimed_rewards', String(unclaimedCount));

    return { userId, email, name, avatar, balance, unclaimedCount };
  }

  function syncNavAuth() {
    const session = getUserSession();
    const unclaimed = session.unclaimedCount || 0;
    const rewardsTooltip = `My Rewards (${unclaimed} Unclaimed)`;

    // Ensure Mobile Nav Drawer also contains My Rewards link
    const mobileDrawer = document.getElementById('mobile-nav-drawer');
    if (mobileDrawer) {
      let rewardsMobileLink = mobileDrawer.querySelector('a[href="/#/rewards"]');
      if (!rewardsMobileLink) {
        rewardsMobileLink = document.createElement('a');
        rewardsMobileLink.href = '/#/rewards';
        rewardsMobileLink.style.color = 'var(--accent)';
        rewardsMobileLink.style.fontWeight = '700';
        const recentGamesLink = mobileDrawer.querySelector('a[href="/recent-games.html"]');
        if (recentGamesLink && recentGamesLink.nextSibling) {
          mobileDrawer.insertBefore(rewardsMobileLink, recentGamesLink.nextSibling);
        } else {
          mobileDrawer.appendChild(rewardsMobileLink);
        }
      }
      rewardsMobileLink.title = rewardsTooltip;
      rewardsMobileLink.textContent = unclaimed > 0
        ? `🏆 My Rewards (${unclaimed} Unclaimed)`
        : '🏆 My Rewards';
    }

    const authContainer = document.getElementById('nav-auth-container');
    if (!authContainer) return;

    const countBadgeHtml = unclaimed > 0
      ? `<span class="nav-rewards-count">${unclaimed}</span>`
      : '';
    const rewardsBtn = `<a href="/#/rewards" class="nav-rewards-btn${unclaimed > 0 ? ' has-unclaimed' : ''}" title="${rewardsTooltip}">🏆 <span>My Rewards</span>${countBadgeHtml}</a>`;

    if (session.userId || session.email || session.name) {
      const avatarContent = session.avatar && (session.avatar.startsWith('http://') || session.avatar.startsWith('https://'))
        ? `<img src="${session.avatar}" alt="Avatar" style="width:26px;height:26px;border-radius:50%;object-fit:cover;">`
        : `<span style="font-size:15px;">${getAvatarEmoji(session.avatar)}</span>`;

      const balanceBadge = session.balance
        ? `<a href="/#/wallet" class="nav-balance-badge" title="Organizer Wallet Balance">🪙 ${session.balance} C</a>`
        : '';

      authContainer.innerHTML = `
        <div style="display:flex; align-items:center; gap:8px;">
          ${rewardsBtn}
          ${balanceBadge}
          <a href="/#/profile" class="nav-user-pill" title="View Profile">
            <div class="nav-avatar-circle">${avatarContent}</div>
            <span class="nav-user-name">${session.name || (session.email ? 'Organizer' : 'Player')}</span>
          </a>
        </div>
      `;
    } else {
      authContainer.innerHTML = `
        <div style="display:flex; align-items:center; gap:8px;">
          ${rewardsBtn}
          <a href="/#/" class="nav-signin-btn">
            <span style="font-family:Roboto,sans-serif;font-weight:900;color:#4285F4;background:#fff;border-radius:50%;width:18px;height:18px;display:inline-flex;align-items:center;justify-content:center;font-size:11px;margin-right:6px;">G</span>
            Sign In
          </a>
        </div>
      `;
    }
  }

  // Mobile menu toggle
  window.toggleMobileNav = function () {
    const menu = document.getElementById('mobile-nav-drawer');
    if (menu) {
      menu.classList.toggle('open');
    }
  };

  // Export globally
  window.DabHousieNav = {
    getUserSession: getUserSession,
    syncNavAuth: syncNavAuth,
    getAvatarEmoji: getAvatarEmoji,
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', syncNavAuth);
  } else {
    syncNavAuth();
  }
})();
