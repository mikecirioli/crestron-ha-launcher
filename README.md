# Crestron HA Launcher

Display a Home Assistant dashboard on a Crestron TSW-1060 (or similar) touch panel — without killing the SD card.

## The Problem

Crestron TSW panels can display web pages in two ways:

- **EMS mode** — simple URL config, but aggressive disk caching generates 100K+ writes/hour, destroying the SD card
- **Browser (UserProject) mode** — cache can be disabled, but the panel insists on booting into a CH5 app, not a browser

The CH5 WebView has broken `localStorage` (returns `null`), which crashes Home Assistant's frontend JavaScript. The standalone browser works fine, but there's no way to auto-launch it on boot.

## The Solution

A minimal CH5 app that acts as a boot trigger:

1. Panel boots into the CH5 app (guaranteed by UserProject mode)
2. CH5 app fires a webhook to Home Assistant
3. HA automation SSH's into the panel and runs `BROWSEROPEN <url>`
4. The standalone browser opens with the full HA dashboard
5. `localStorage` works natively — no polyfills needed

The result: auto-launching HA dashboard, ~46K writes/hour (2.5% of the danger threshold), full JS support, and hardware side button access.

## Architecture

```
┌──────────────────┐         ┌──────────────────┐
│  Crestron Panel   │         │  Home Assistant   │
│                   │         │                   │
│  1. Panel boots   │         │                   │
│  2. CH5 app loads │─webhook─▶ 3. Automation     │
│                   │         │    triggers       │
│  5. Browser opens │◀──SSH───│ 4. shell_command  │
│     with HA       │         │    runs BROWSEROPEN│
│                   │         │                   │
│  6. Full HA       │         │                   │
│     dashboard!    │         │                   │
└──────────────────┘         └──────────────────┘
```

## Prerequisites

- Crestron TSW-1060 (or similar TSW panel) with network access
- Home Assistant instance on the same network
- Node.js (for building the CH5 app)
- SSH access to your HA host (for deploying scripts)

## Setup

### Step 1: Configure the Crestron Panel

Connect to the panel's console via SSH or the web UI (`https://<panel-ip>`) and run these commands:

```
# Switch to UserProject mode (required for CH5 apps and cache control)
PROJECTMODE USERPROJECT

# Disable browser cache (protects the SD card)
BROWSERCACHE OFF

# Kiosk mode — no URL bar, no navigation chrome
BROWMODE KIOSK

# Enable side button key events in the browser
APPKEYS ON

# Enable SD card write monitoring (optional, for verification)
SDCARDCOUNTER ON

# Reboot to apply
REBOOT
```

After reboot, verify settings:

```
PROJECTMODE
# Should show: User Project Mode

BROWSERCACHE
# Should show: Browser Cache is OFF

BROWMODE
# Should show: Kiosk

APPKEYS
# Should show: App Keys is ON
```

### Step 2: Deploy the SSH Script to Home Assistant

This Python script uses `paramiko` (bundled with HA) to send console commands to the panel. No extra packages needed — survives container updates.

Copy `ha-scripts/crestron_cmd.py` to your HA config directory:

```bash
# If HA config is at /config/ inside the container:
cp ha-scripts/crestron_cmd.py <ha-config-path>/scripts/crestron_cmd.py
```

Edit the defaults at the top of the script to match your panel:

```python
HOST = os.environ.get("CRESTRON_HOST", "192.168.1.58")    # your panel IP
USER = os.environ.get("CRESTRON_USER", "admin")            # console username
PASS = os.environ.get("CRESTRON_PASS", "admin")            # console password
```

Test it:

```bash
# From inside the HA container:
python3 /config/scripts/crestron_cmd.py "ver"
```

You should see the panel's firmware version.

### Step 3: Configure Home Assistant

Add to your `configuration.yaml`:

```yaml
# Shell commands for Crestron panel control
shell_command:
  crestron_open_browser: "python3 /config/scripts/crestron_cmd.py 'BROWSEROPEN http://<HA_IP>:8123'"
  crestron_standby: "python3 /config/scripts/crestron_cmd.py 'standby'"
  crestron_wake: "python3 /config/scripts/crestron_cmd.py 'standby off'"

# Allow iframe embedding and trust Docker network proxy
http:
  use_x_frame_options: false
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
    - "::1"
    - 172.19.0.0/16    # Docker bridge network — needed for trusted_networks auth
```

If you want the panel to auto-login without credentials, add trusted_networks auth:

```yaml
homeassistant:
  auth_providers:
    - type: trusted_networks
      trusted_networks:
        - <PANEL_IP>/32       # e.g. 192.168.1.58/32
      allow_bypass_login: true
    - type: homeassistant     # keep normal login for other devices
```

### Step 4: Create the HA Automation

In the HA UI: **Settings > Automations > Create Automation > Create new automation**, click the three dots > **Edit in YAML**, and paste:

```yaml
alias: Crestron open browser
description: Opens HA dashboard in the Crestron panel's standalone browser
triggers:
  - trigger: webhook
    webhook_id: crestron-open-browser
actions:
  - action: shell_command.crestron_open_browser
```

Save, then test:

```bash
curl -X POST http://<HA_IP>:8123/api/webhook/crestron-open-browser
```

The browser should open on the panel.

### Step 5: Build and Deploy the CH5 App

```bash
# Install dependencies
npm install

# Build the CH5 archive
npm run archive

# Deploy to the panel
npx --package=@crestron/ch5-utilities-cli ch5-cli deploy \
  -p -H <PANEL_IP> -t touchscreen archive/crestron-ha-launcher.ch5z
```

The panel will reboot. When the CH5 app loads, it shows a setup wizard. Enter your HA URL and webhook ID, tap **Launch**, and the browser will open with your dashboard.

On subsequent reboots, the app remembers your settings (stored in a cookie) and fires the webhook automatically.

## SD Card Health

Monitor write rates from the panel console:

```
SDCARDSTATUS
```

Run it twice, 10 seconds apart, and compare `Current Boot Counter`. Typical results:

| State | Writes/sec | Writes/hour | % of max |
|-------|-----------|-------------|----------|
| Idle (no browser) | ~3-4 | ~12K | 0.7% |
| HA dashboard loaded | ~13 | ~46K | 2.5% |
| EMS mode (bad) | ~30+ | ~100K+ | 5.5%+ |
| **Danger threshold** | — | **1.8M** | **100%** |

With `BROWSERCACHE OFF`, write rates stay well within safe limits.

## Side Buttons

With `APPKEYS ON`, the TSW-1060's five hardware side buttons fire standard JavaScript key events directly in the browser. No Node-RED or external tools needed — a small JS script intercepts the keys and calls HA services.

### Discover Key Codes

Copy the key test page to your HA `www/` folder:

```bash
cp utils/keytest.html <ha-config-path>/www/keytest.html
```

Open `http://<HA_IP>:8123/local/keytest.html` on the panel and press each button. TSW-1060 key names:

| Position | Icon | Key Name |
|----------|------|----------|
| 1 (top) | Power | `BrowserBack` |
| 2 | Home | `Home` |
| 3 | Up arrow | `AudioVolumeUp` |
| 4 | Lightbulb | `AudioVolumeMute` |
| 5 (bottom) | Down arrow | `AudioVolumeDown` |

### Install the Side Button Handler

1. Copy the script to your HA `www/` folder:

```bash
cp ha-scripts/crestron-sidekeys.js <ha-config-path>/www/crestron-sidekeys.js
```

2. Add to `configuration.yaml`:

```yaml
frontend:
  extra_js_url_es5:
    - /local/crestron-sidekeys.js
```

3. Edit `www/crestron-sidekeys.js` and uncomment/configure the `BUTTON_MAP` at the top of the file. Three action types are available:

**Navigate** — go to a dashboard view:
```javascript
'Home': { action: 'navigate', path: '/lovelace/0' },
```

**Service** — call any HA service:
```javascript
'AudioVolumeMute': { action: 'service', domain: 'light', service: 'toggle',
                     data: { entity_id: 'light.living_room' } },
```

**Fire** — fire a custom HA event (for advanced automations):
```javascript
'BrowserBack': { action: 'fire', event: 'crestron_button',
                 data: { button: 'back' } },
```

4. Restart HA to load the script.

## Troubleshooting

**Panel shows CH5 setup wizard but browser never opens**
- Test the webhook manually: `curl -X POST http://<HA_IP>:8123/api/webhook/crestron-open-browser`
- Check HA logs for shell_command errors
- Verify SSH works: `python3 /config/scripts/crestron_cmd.py "ver"`

**Browser opens but HA shows login screen (trusted_networks not working)**
- Add your Docker bridge network to `trusted_proxies` (see Step 3)
- Check HA logs for "untrusted proxy" errors
- Verify the panel IP is in your `trusted_networks` list

**High SD card write rate**
- Verify cache is off: `BROWSERCACHE` in the panel console
- Check `SDCARDSTATUS` — `Current Boot Counter` should grow slowly

**SSH script fails with "Error: Authentication failed"**
- Verify panel credentials: try SSH manually from the HA container
- Check that the panel's SSH server is enabled

## Files

```
dist/index.html                CH5 bootstrap app (setup wizard + webhook trigger)
dist/appui/manifest             CH5 app type declaration
ha-scripts/crestron_cmd.py     Paramiko SSH script for panel commands
ha-scripts/crestron-sidekeys.js Side button handler (deploy to HA www/)
utils/keytest.html              Key code discovery page
utils/diag.html                 WebView diagnostics page
package.json                    npm project config + build scripts
```

## License

MIT
