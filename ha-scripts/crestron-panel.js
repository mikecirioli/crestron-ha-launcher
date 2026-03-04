// ═══════════════════════════════════════════════════════════════════
// Crestron TSW Panel Controller for Home Assistant
// ═══════════════════════════════════════════════════════════════════
// Combines idle detection, view switching, and side button handling
// into one lightweight script. Replaces WallPanel screensaver.
//
// Deploy to HA: /config/www/crestron-panel.js
// Add to configuration.yaml:
//   frontend:
//     extra_js_url_es5:
//       - /local/crestron-panel.js
// ═══════════════════════════════════════════════════════════════════

(function() {
  'use strict';

  // ── Guard clause: only run on the Crestron dashboard ───────────
  // This script loads globally but immediately exits on other
  // dashboards, phones, tablets, desktops, etc.
  var DASHBOARD = 'crestron-display';
  if (location.pathname.indexOf(DASHBOARD) === -1) return;

  // ── Configuration ──────────────────────────────────────────────
  var IDLE_TIMEOUT      = 120000;  // 2 min of no touch → photo frame
  var REFRESH_INTERVAL  = 900000;  // 15 min — hard refresh to combat WebView memory leaks
  var HOME_PATH      = '/' + DASHBOARD + '/home';
  var PHOTOS_PATH    = '/' + DASHBOARD + '/photos';

  // TSW-1060 side buttons (top to bottom):
  //   1. Power icon      → BrowserBack     → go to dashboard
  //   2. Home icon       → Home            → go to dashboard
  //   3. Up arrow        → AudioVolumeUp   → next camera
  //   4. Lightbulb       → AudioVolumeMute → toggle photo frame
  //   5. Down arrow      → AudioVolumeDown → previous camera
  var BUTTON_MAP = {
    'BrowserBack':     { action: 'go-home' },
    'Home':            { action: 'go-home' },
    'AudioVolumeUp':   { action: 'camera', direction: 'next' },
    'AudioVolumeDown': { action: 'camera', direction: 'previous' },
    'AudioVolumeMute': { action: 'toggle-photos' }
  };

  // ── State ──────────────────────────────────────────────────────
  var idleTimer = null;
  var refreshTimer = null;
  var debounceTimer = null;
  var manualPhotos = false;  // true when user explicitly chose photos

  // ── Helpers ────────────────────────────────────────────────────
  function getHass() {
    var el = document.querySelector('home-assistant');
    return el && el.hass ? el.hass : null;
  }

  function navigateTo(path) {
    if (location.pathname !== path) {
      history.pushState(null, '', path);
      window.dispatchEvent(new PopStateEvent('popstate'));
    }
  }

  function isOnPhotos() {
    return location.pathname.indexOf('/photos') !== -1;
  }

  function startIdleTimer() {
    clearTimeout(idleTimer);
    cancelRefresh();
    // SOAK TEST: disabled idle→photos to isolate dashboard stability
    // idleTimer = setTimeout(function() {
    //   navigateTo(PHOTOS_PATH);
    //   scheduleRefresh();
    // }, IDLE_TIMEOUT);
  }

  // ── WebView memory management ──────────────────────────────────
  // Chromium 95 on Android 5.1 leaks memory over time. A periodic
  // hard navigation while on photos reclaims everything without
  // a visible interruption — it reloads directly into the photos view.
  function scheduleRefresh() {
    clearTimeout(refreshTimer);
    refreshTimer = setTimeout(function() {
      // Hard navigation (not pushState) — forces full page teardown
      // and rebuilds the WebView state from scratch.
      // Navigates directly to photos so user sees no interruption.
      window.location.href = PHOTOS_PATH;
    }, REFRESH_INTERVAL);
  }

  function cancelRefresh() {
    clearTimeout(refreshTimer);
  }

  // ── Camera switching ───────────────────────────────────────────
  // Cycle the input_select.camera_selector via HA service calls.

  function cycleCamera(direction) {
    var hass = getHass();
    if (!hass) return;
    var service = direction === 'next' ? 'select_next' : 'select_previous';
    hass.callService('input_select', service, {
      cycle: true
    }, { entity_id: 'input_select.camera_selector' });
  }

  // ── Side button handler ────────────────────────────────────────
  function handleButton(e) {
    var mapping = BUTTON_MAP[e.key];
    if (!mapping) return;

    e.preventDefault();
    e.stopPropagation();

    switch (mapping.action) {
      case 'go-home':
        manualPhotos = false;
        cancelRefresh();
        navigateTo(HOME_PATH);
        startIdleTimer();
        break;

      case 'toggle-photos':
        if (isOnPhotos()) {
          // On photos → go back to dashboard
          manualPhotos = false;
          cancelRefresh();
          navigateTo(HOME_PATH);
          startIdleTimer();
        } else {
          // On dashboard → go to photos (manual override)
          manualPhotos = true;
          navigateTo(PHOTOS_PATH);
          clearTimeout(idleTimer);
          scheduleRefresh();
        }
        break;

      case 'camera':
        // If on photos, switch to dashboard first
        if (isOnPhotos()) {
          manualPhotos = false;
          cancelRefresh();
          navigateTo(HOME_PATH);
          // Small delay to let the view load before cycling
          setTimeout(function() { cycleCamera(mapping.direction); }, 500);
        } else {
          cycleCamera(mapping.direction);
        }
        startIdleTimer();
        break;

      case 'service':
        var hass = getHass();
        if (hass) {
          hass.callService(mapping.domain, mapping.service, mapping.data || {});
        }
        startIdleTimer();
        break;
    }
  }

  // ── Touch/mouse idle detection ─────────────────────────────────
  // Only listens for touch and mouse events (NOT keydown) to avoid
  // conflicts with the button handler above.
  function onActivity() {
    if (manualPhotos) return;

    // Debounce: process at most once per second
    if (debounceTimer) return;
    debounceTimer = setTimeout(function() { debounceTimer = null; }, 1000);

    // If on photos, go back to dashboard
    if (isOnPhotos()) {
      navigateTo(HOME_PATH);
    }

    startIdleTimer();
  }

  // ── Initialize ─────────────────────────────────────────────────
  function init() {
    // Side buttons via keydown
    document.addEventListener('keydown', handleButton, true);

    // Idle detection via touch/mouse only
    ['touchstart', 'mousedown', 'mousemove'].forEach(function(evt) {
      document.addEventListener(evt, onActivity, { capture: true, passive: true });
    });

    // Start the idle timer
    startIdleTimer();
  }

  // Wait for HA frontend to be ready
  function waitForHass(cb) {
    var el = document.querySelector('home-assistant');
    if (el && el.hass) return cb();
    var attempts = 0;
    var interval = setInterval(function() {
      el = document.querySelector('home-assistant');
      if (el && el.hass) { clearInterval(interval); cb(); }
      if (++attempts > 300) clearInterval(interval);
    }, 100);
  }

  waitForHass(init);
})();
