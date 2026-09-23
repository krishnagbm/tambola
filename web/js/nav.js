// web/js/nav.js
// DabHousie — Shared Navigation & Auth State Controller

(function () {
  'use strict';

  const AVATAR_EMOJIS = {
    'avatar_lion': '🦁',
    'avatar_tiger': '🐯',
    'avatar_crown': '👑',
    'avatar_wizard': '🧙',
    'avatar_rocket': '🚀',
    'avatar_fox': '🦊',
    'avatar_panda': '🐼',
    'avatar_unicorn': '🦄',
    'avatar_cowboy': '🤠',
    'avatar_star': '🌟',
    'avatar_bullseye': '🎯',
    'avatar_rocker': '🎸',
  };

  function getAvatarEmoji(avatarKey) {
    if (!avatarKey) return '🦁';
    if (AVATAR_EMOJIS[avatarKey]) return AVATAR_EMOJIS[avatarKey];
    return '🦁';
  }

  function getUserSession() {
    // 1. Check direct query params or hash
    const params = new URLSearchParams(window.location.search);
    const hashPart = window.location.hash.includes('?') ? window.location.hash.split('?')[1] : '';
    const hashParams = new URLSearchParams(hashPart);

    let userId = params.get('user_id') || hashParams.get('user_id') || localStorage.getItem('dabhousie_user_id') || localStorage.getItem('flutter.dabhousie_user_id') || '';
    let email = params.get('email') || hashParams.get('email') || localStorage.getItem('dabhousie_user_email') || localStorage.getItem('flutter.dabhousie_user_email') || '';
    let name = params.get('name') || hashParams.get('name') || localStorage.getItem('dabhousie_user_name') || localStorage.getItem('flutter.mpt_player_name') || localStorage.getItem('mpt_player_name') || '';
    let avatar = params.get('avatar') || hashParams.get('avatar') || localStorage.getItem('dabhousie_user_avatar') || localStorage.getItem('flutter.mpt_player_avatar') || localStorage.getItem('mpt_player_avatar') || '';
    let balance = params.get('balance') || hashParams.get('balance') || localStorage.getItem('dabhousie_balance') || localStorage.getItem('flutter.dabhousie_balance') || '';

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
                userId = userId || user.id || '';
                email = email || user.email || '';
                name = name || user.user_metadata?.full_name || user.user_metadata?.name || user.user_metadata?.user_name || (user.email ? user.email.split('@')[0] : '');
                avatar = avatar || user.user_metadata?.avatar_url || user.user_metadata?.avatar || user.user_metadata?.picture || '';
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
      userId = localStorage.getItem('flutter.mpt_local_uuid') || localStorage.getItem('mpt_local_uuid') || '';
    }

    // 4. Cache discovered credentials so session stays consistent across pages
    if (userId) localStorage.setItem('dabhousie_user_id', userId);
    if (email) localStorage.setItem('dabhousie_user_email', email);
    if (name) localStorage.setItem('dabhousie_user_name', name);
    if (avatar) localStorage.setItem('dabhousie_user_avatar', avatar);

    return { userId, email, name, avatar, balance };
  }

  function syncNavAuth() {
    const session = getUserSession();
    const authContainer = document.getElementById('nav-auth-container');
    if (!authContainer) return;

    if (session.userId || session.email || session.name) {
      const avatarContent = session.avatar && (session.avatar.startsWith('http://') || session.avatar.startsWith('https://'))
        ? `<img src="${session.avatar}" alt="Avatar" style="width:28px;height:28px;border-radius:50%;object-fit:cover;">`
        : `<span style="font-size:16px;">${getAvatarEmoji(session.avatar)}</span>`;

      const balanceBadge = session.balance
        ? `<a href="/#/wallet" class="nav-balance-badge" title="Organizer Wallet Balance">🪙 ${session.balance} C</a>`
        : '';

      authContainer.innerHTML = `
        <div style="display:flex; align-items:center; gap:8px;">
          ${balanceBadge}
          <a href="/#/profile" class="nav-user-pill" title="View Profile">
            <div class="nav-avatar-circle">${avatarContent}</div>
            <span class="nav-user-name">${session.name || (session.email ? 'Organizer' : 'Player')}</span>
          </a>
        </div>
      `;
    } else {
      authContainer.innerHTML = `
        <a href="/#/" class="nav-signin-btn">
          <span style="font-family:Roboto,sans-serif;font-weight:900;color:#4285F4;background:#fff;border-radius:50%;width:18px;height:18px;display:inline-flex;align-items:center;justify-content:center;font-size:11px;margin-right:6px;">G</span>
          Sign In
        </a>
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
