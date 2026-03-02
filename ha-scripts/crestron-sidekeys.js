// Crestron TSW side button handler for Home Assistant
// Deploy to HA: config/www/crestron-sidekeys.js
// Add to configuration.yaml:
//   frontend:
//     extra_js_url_es5:
//       - /local/crestron-sidekeys.js

(function() {
  'use strict';

  // ==========================================================================
  // BUTTON CONFIGURATION
  //
  // Map each key name to an action. Available action types:
  //
  //   navigate  — go to a dashboard path
  //              { action: 'navigate', path: '/lovelace/0' }
  //
  //   service   — call an HA service
  //              { action: 'service', domain: 'light', service: 'toggle',
  //                data: { entity_id: 'light.living_room' } }
  //
  //   fire      — fire an HA event
  //              { action: 'fire', event: 'my_custom_event',
  //                data: { button: 'mute' } }
  //
  // TSW-1060 side buttons (top to bottom):
  //   1. Power icon      → BrowserBack
  //   2. Home icon       → Home
  //   3. Up arrow icon   → AudioVolumeUp
  //   4. Lightbulb icon  → AudioVolumeMute
  //   5. Down arrow icon → AudioVolumeDown
  //
  // ==========================================================================

  var BUTTON_MAP = {
    // 'Home':            { action: 'navigate', path: '/lovelace/0' },
    // 'BrowserBack':     { action: 'navigate', path: '/lovelace/0' },
    // 'AudioVolumeUp':   { action: 'service', domain: 'light', service: 'turn_on',
    //                      data: { entity_id: 'light.living_room', brightness_step: 25 } },
    // 'AudioVolumeDown': { action: 'service', domain: 'light', service: 'turn_on',
    //                      data: { entity_id: 'light.living_room', brightness_step: -25 } },
    // 'AudioVolumeMute': { action: 'service', domain: 'light', service: 'toggle',
    //                      data: { entity_id: 'light.living_room' } },
  };

  // Set to true to prevent default browser behavior for mapped keys
  // (e.g. prevent volume overlay popup)
  var SUPPRESS_DEFAULT = true;

  // ==========================================================================
  // END CONFIGURATION
  // ==========================================================================

  // Wait for HA frontend to initialize and expose the hass object
  function getHass() {
    var el = document.querySelector('home-assistant');
    return el && el.hass ? el.hass : null;
  }

  function waitForHass(cb) {
    var hass = getHass();
    if (hass) return cb(hass);
    var attempts = 0;
    var interval = setInterval(function() {
      hass = getHass();
      attempts++;
      if (hass) { clearInterval(interval); cb(hass); }
      if (attempts > 300) { clearInterval(interval); } // give up after 30s
    }, 100);
  }

  function handleKey(e) {
    var mapping = BUTTON_MAP[e.key];
    if (!mapping) return;

    if (SUPPRESS_DEFAULT) {
      e.preventDefault();
      e.stopPropagation();
    }

    var hass = getHass();
    if (!hass) return;

    switch (mapping.action) {
      case 'navigate':
        history.pushState(null, '', mapping.path);
        window.dispatchEvent(new PopStateEvent('popstate'));
        break;

      case 'service':
        hass.callService(mapping.domain, mapping.service, mapping.data || {});
        break;

      case 'fire':
        hass.callApi('POST', 'events/' + mapping.event, mapping.data || {});
        break;
    }
  }

  waitForHass(function() {
    document.addEventListener('keydown', handleKey, true);
  });
})();
