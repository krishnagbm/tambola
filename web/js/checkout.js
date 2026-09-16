// web/js/checkout.js
// DabHousie — Client-side Stripe Hosted Checkout Controller

(function () {
  'use strict';

  // Configurable Checkout Endpoint: dynamically defaults to deployed API Gateway URL
  const CONFIG = {
    CHECKOUT_ENDPOINT: window.DABHOUSIE_CHECKOUT_API || 'https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/checkout',
    BASE_URL: window.location.origin,
  };

  // Extract query parameters from URL
  function getQueryParams() {
    const params = new URLSearchParams(window.location.search);
    const hashParams = new URLSearchParams(window.location.hash.split('?')[1] || '');
    return {
      userId: params.get('user_id') || hashParams.get('user_id') || localStorage.getItem('dabhousie_user_id') || '',
      email: params.get('email') || hashParams.get('email') || localStorage.getItem('dabhousie_user_email') || '',
      plan: params.get('plan') || hashParams.get('plan') || 'family',
    };
  }

  // Save user context if available
  const queryParams = getQueryParams();
  if (queryParams.userId) {
    localStorage.setItem('dabhousie_user_id', queryParams.userId);
  }
  if (queryParams.email) {
    localStorage.setItem('dabhousie_user_email', queryParams.email);
  }

  /**
   * Initiates Stripe Hosted Checkout Session
   * @param {string} plan - The bundle/plan key ('family', 'starter', 'standard', 'party', 'gala', 'mega')
   * @param {string} [customUserId] - Optional user UUID
   * @param {string} [customEmail] - Optional email
   */
  async function initiateCheckout(plan, customUserId, customEmail) {
    const userId = customUserId || queryParams.userId || localStorage.getItem('dabhousie_user_id');
    const email = customEmail || queryParams.email || localStorage.getItem('dabhousie_user_email');

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

      // Redirect user to Stripe Hosted Checkout
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
   * Modal dialog if user opens pricing.html directly without URL query parameters
   */
  function promptUserCredentials(plan) {
    const modal = document.getElementById('auth-prompt-modal');
    if (modal) {
      modal.style.display = 'flex';
      const form = document.getElementById('auth-prompt-form');
      if (form) {
        form.onsubmit = function (e) {
          e.preventDefault();
          const emailInput = document.getElementById('prompt-email');
          const uidInput = document.getElementById('prompt-uid');
          const email = emailInput ? emailInput.value.trim() : '';
          const userId = uidInput && uidInput.value.trim() ? uidInput.value.trim() : generateGuestUid();

          if (email) {
            localStorage.setItem('dabhousie_user_id', userId);
            localStorage.setItem('dabhousie_user_email', email);
            modal.style.display = 'none';
            initiateCheckout(plan, userId, email);
          }
        };
      }
    } else {
      const email = prompt('Please enter your email to receive your game credits and receipt:');
      if (email) {
        const userId = generateGuestUid();
        localStorage.setItem('dabhousie_user_id', userId);
        localStorage.setItem('dabhousie_user_email', email);
        initiateCheckout(plan, userId, email);
      }
    }
  }

  function generateGuestUid() {
    return 'host-' + Math.random().toString(36).substring(2, 11) + '-' + Date.now().toString(36);
  }

  function showErrorModal(message) {
    const alertBox = document.getElementById('checkout-alert');
    if (alertBox) {
      alertBox.textContent = message;
      alertBox.style.display = 'block';
      setTimeout(() => { alertBox.style.display = 'none'; }, 8000);
    } else {
      alert('Checkout Notice: ' + message);
    }
  }

  // Export globally for HTML button onclick handlers
  window.DabHousieCheckout = {
    buy: initiateCheckout,
    getQueryParams: getQueryParams,
  };

  // Auto-bind click handlers to buttons with [data-plan]
  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-plan]').forEach((btn) => {
      btn.addEventListener('click', (e) => {
        e.preventDefault();
        const plan = btn.getAttribute('data-plan');
        initiateCheckout(plan);
      });
    });
  });
})();
