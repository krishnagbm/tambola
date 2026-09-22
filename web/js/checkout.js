// web/js/checkout.js
// DabHousie — Client-side Stripe Hosted Checkout & Topbar Sync Controller

(function () {
  'use strict';

  // Configurable Checkout Endpoint: dynamically defaults to deployed API Gateway URL
  const CONFIG = {
    CHECKOUT_ENDPOINT: window.DABHOUSIE_CHECKOUT_API || 'https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/checkout',
    BASE_URL: window.location.origin,
  };

  // Avatar emoji dictionary matching Flutter AppTheme & Home screen
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
    if (avatarKey.startsWith('http://') || avatarKey.startsWith('https://')) return null;
    return '🦁';
  }

  // Extract session parameters from URL Search, Hash, or LocalStorage/Supabase
  function getUserSession() {
    if (window.DabHousieNav && typeof window.DabHousieNav.getUserSession === 'function') {
      const navSession = window.DabHousieNav.getUserSession();
      const params = new URLSearchParams(window.location.search);
      const hashPart = window.location.hash.includes('?') ? window.location.hash.split('?')[1] : '';
      const hashParams = new URLSearchParams(hashPart);
      const plan = params.get('plan') || hashParams.get('plan') || '';
      const cancelled = params.get('cancelled') === 'true' || hashParams.get('cancelled') === 'true';
      return { ...navSession, plan, cancelled };
    }

    const params = new URLSearchParams(window.location.search);
    const hashPart = window.location.hash.includes('?') ? window.location.hash.split('?')[1] : '';
    const hashParams = new URLSearchParams(hashPart);

    let userId = params.get('user_id') || hashParams.get('user_id') || localStorage.getItem('dabhousie_user_id') || localStorage.getItem('flutter.dabhousie_user_id') || '';
    let email = params.get('email') || hashParams.get('email') || localStorage.getItem('dabhousie_user_email') || localStorage.getItem('flutter.dabhousie_user_email') || '';
    let name = params.get('name') || hashParams.get('name') || localStorage.getItem('dabhousie_user_name') || localStorage.getItem('flutter.mpt_player_name') || '';
    let avatar = params.get('avatar') || hashParams.get('avatar') || localStorage.getItem('dabhousie_user_avatar') || localStorage.getItem('flutter.mpt_player_avatar') || '';
    let balance = params.get('balance') || hashParams.get('balance') || localStorage.getItem('dabhousie_balance') || localStorage.getItem('flutter.dabhousie_balance') || '';
    const plan = params.get('plan') || hashParams.get('plan') || '';
    const cancelled = params.get('cancelled') === 'true' || hashParams.get('cancelled') === 'true';

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

    if (!userId) {
      userId = localStorage.getItem('flutter.mpt_local_uuid') || '';
    }

    if (userId) localStorage.setItem('dabhousie_user_id', userId);
    if (email) localStorage.setItem('dabhousie_user_email', email);
    if (name) localStorage.setItem('dabhousie_user_name', name);
    if (avatar) localStorage.setItem('dabhousie_user_avatar', avatar);

    return { userId, email, name, avatar, balance, plan, cancelled };
  }

  const userContext = getUserSession();

  /**
   * Updates the frozen top header bar with user avatar, name, email, and live balance
   */
  function syncTopbarUI() {
    const ctx = getUserSession();

    // 1. Balance Pill
    const balancePill = document.getElementById('topbar-balance');
    const balanceAmount = document.getElementById('balance-amount');
    if (balancePill && balanceAmount && ctx.balance) {
      balanceAmount.textContent = ctx.balance;
      balancePill.style.display = 'inline-flex';
    }

    // 2. User Profile vs Guest Sign-In
    const profileMenu = document.getElementById('user-profile-menu');
    const guestSignIn = document.getElementById('guest-signin-btn');
    const userNameEl = document.getElementById('user-display-name');
    const userEmailEl = document.getElementById('user-display-email');
    const avatarContainer = document.getElementById('avatar-container');

    if (ctx.email || ctx.userId) {
      if (profileMenu) profileMenu.style.display = 'inline-flex';
      if (guestSignIn) guestSignIn.style.display = 'none';

      if (userNameEl) {
        userNameEl.textContent = ctx.name || ctx.email.split('@')[0] || 'Organizer';
      }
      if (userEmailEl) {
        userEmailEl.textContent = ctx.email || 'Host Account';
      }
      if (avatarContainer) {
        if (ctx.avatar && (ctx.avatar.startsWith('http://') || ctx.avatar.startsWith('https://'))) {
          avatarContainer.innerHTML = `<img src="${ctx.avatar}" alt="Avatar">`;
        } else {
          avatarContainer.textContent = getAvatarEmoji(ctx.avatar);
        }
      }
    } else {
      if (profileMenu) profileMenu.style.display = 'none';
      if (guestSignIn) guestSignIn.style.display = 'inline-flex';
    }

    // 3. Cancelled Notice
    if (ctx.cancelled) {
      showInfoNotice('Stripe checkout was cancelled. Your credit balance is unchanged.');
    }
  }

  /**
   * Initiates Stripe Hosted Checkout Session
   * @param {string} plan - The bundle/plan key ('small', 'standard', 'large', 'mega')
   * @param {string} [customUserId] - Optional user UUID
   * @param {string} [customEmail] - Optional email
   */
  async function initiateCheckout(plan, customUserId, customEmail) {
    const ctx = getUserSession();
    const userId = customUserId || ctx.userId || localStorage.getItem('dabhousie_user_id');
    const email = customEmail || ctx.email || localStorage.getItem('dabhousie_user_email');

    // If no credentials found at all, prompt user for email once
    if (!userId || !email) {
      promptUserCredentials(plan);
      return;
    }

    const button = document.querySelector(`[data-plan="${plan}"]`);
    const originalText = button ? button.innerHTML : '';

    if (button) {
      button.disabled = true;
      button.innerHTML = '<span class="spinner"></span> Connecting to Stripe...';
    }

    try {
      const response = await fetch(CONFIG.CHECKOUT_ENDPOINT, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: JSON.stringify({
          user_id: userId,
          email: email,
          plan: plan,
        }),
      });

      const data = await response.json();

      if (!response.ok || !data.checkout_url) {
        throw new Error(data.error || 'Failed to initiate checkout session.');
      }

      // Seamless redirect to Stripe Hosted Checkout
      window.location.href = data.checkout_url;

    } catch (err) {
      console.error('Checkout error:', err);
      showErrorModal(err.message || 'Unable to connect to payment server. Please try again.');
      if (button) {
        button.disabled = false;
        button.innerHTML = originalText;
      }
    }
  }

  /**
   * Modal dialog fallback only if unauthenticated direct visitor
   */
  function promptUserCredentials(plan) {
    const modal = document.getElementById('auth-prompt-modal');
    if (modal) {
      const emailInput = document.getElementById('prompt-email');
      const ctx = getUserSession();
      if (emailInput && ctx.email) {
        emailInput.value = ctx.email;
      }
      modal.style.display = 'flex';
      const form = document.getElementById('auth-prompt-form');
      if (form) {
        form.onsubmit = function (e) {
          e.preventDefault();
          const email = emailInput ? emailInput.value.trim() : '';
          const userId = ctx.userId || generateGuestUid();

          if (email) {
            localStorage.setItem('dabhousie_user_id', userId);
            localStorage.setItem('dabhousie_user_email', email);
            closeModal();
            syncTopbarUI();
            initiateCheckout(plan, userId, email);
          }
        };
      }
    } else {
      const email = prompt('Please sign in or enter your organizer email to receive credits:');
      if (email) {
        const userId = generateGuestUid();
        localStorage.setItem('dabhousie_user_id', userId);
        localStorage.setItem('dabhousie_user_email', email);
        syncTopbarUI();
        initiateCheckout(plan, userId, email);
      }
    }
  }

  function closeModal() {
    const modal = document.getElementById('auth-prompt-modal');
    if (modal) {
      modal.style.display = 'none';
    }
  }

  function generateGuestUid() {
    return 'host-' + Math.random().toString(36).substring(2, 11) + '-' + Date.now().toString(36);
  }

  function showErrorModal(message) {
    const alertBox = document.getElementById('checkout-alert');
    if (alertBox) {
      alertBox.textContent = message;
      alertBox.style.background = 'rgba(239, 68, 68, 0.15)';
      alertBox.style.borderColor = 'rgba(239, 68, 68, 0.4)';
      alertBox.style.color = '#FCA5A5';
      alertBox.style.display = 'block';
      setTimeout(() => { alertBox.style.display = 'none'; }, 8000);
    } else {
      alert('Checkout Notice: ' + message);
    }
  }

  function showInfoNotice(message) {
    const alertBox = document.getElementById('checkout-alert');
    if (alertBox) {
      alertBox.textContent = message;
      alertBox.style.background = 'rgba(255, 193, 7, 0.12)';
      alertBox.style.borderColor = 'rgba(255, 193, 7, 0.35)';
      alertBox.style.color = '#FFC107';
      alertBox.style.display = 'block';
      setTimeout(() => { alertBox.style.display = 'none'; }, 6000);
    }
  }

  // Export globally for HTML button onclick handlers
  window.DabHousieCheckout = {
    buy: initiateCheckout,
    closeModal: closeModal,
    getQueryParams: getUserSession,
  };

  // Close modal on Escape key press
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeModal();
  });

  // Bind click handlers & sync topbar on DOM load
  document.addEventListener('DOMContentLoaded', () => {
    syncTopbarUI();

    document.querySelectorAll('[data-plan]').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const plan = btn.getAttribute('data-plan');
        initiateCheckout(plan);
      });
    });

    // Auto-initiate if plan and credentials are in URL
    const qp = getUserSession();
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get('plan') && (qp.userId || qp.email) && !qp.cancelled) {
      initiateCheckout(urlParams.get('plan'));
    }
  });
})();
