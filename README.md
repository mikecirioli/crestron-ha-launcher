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

### Step 1: Deploy the SSH Script to Home Assistant

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

### Step 2: Configure the Crestron Panel

The panel setup script (`ha-scripts/panel-setup.sh`) configures the TSW-1060 for optimal dashboard use via SSH. It requires `crestron_cmd.py` to be deployed first (Step 1).

```bash
# Run from the HA host (adjust the config path to match your setup):
./ha-scripts/panel-setup.sh /config

# Or for non-container installs:
./ha-scripts/panel-setup.sh /export/homeassistant
```

The script configures the following settings (reboot required after):

#### Core Settings

| Command | Value | Purpose |
|---------|-------|---------|
| `BROWSERCACHE` | `DISABLE` | Prevents aggressive SD card caching (~100K writes/hour) |
| `APPKEYS` | `ON` | Enables hardware side buttons as JavaScript key events in the browser |
| `DEDICATEDVIDEOSUPPORT` | `DISABLE` | Kills `txrxservice` (AV transport) — saves a full CPU core even with nothing connected |
| `CAMERASTREAMENABLE` | `OFF` | Kills onboard camera driver + `mediaserver` — saves ~70 min CPU time per hour |
| `TIMEZONE` | `014` | Eastern Time (edit script for your timezone; run `TIMEZONE list` for codes) |

#### Memory Management

| Command | Value | Purpose |
|---------|-------|---------|
| `PROJECTMEMORY` | `512` | MB limit for the browser project — prevents runaway memory consumption |
| `MEMCLEANUPCONFIG APP` | `3600` | Runs memory cleanup every 60 minutes |
| `MEMLOWTRIG` | `80` | Schedules reboot when free RAM drops below 80 MB |
| `MEMCRITTRIG` | `30` | Immediate reboot when free RAM drops below 30 MB |
| `MEMTRIGTIME` | `6` | Memory-triggered reboots happen at 6 AM |
| `PERIODICREBOOT` | `ON` | Daily reboot at the configured hour |

#### Display Settings

| Command | Value | Purpose |
|---------|-------|---------|
| `AUTOBRIGHTNESS` | `ON` | Adjusts screen brightness based on ambient light |
| `STBYTO` | `0` | Disables standby timeout (panel stays on) |
| `SCREENSAVER` | `OFF` | Disables built-in screensaver (handled by `crestron-panel.js`) |

#### Browser Settings

| Command | Value | Purpose |
|---------|-------|---------|
| `BROWSERSELECT` | `WEBVIEW` | Required on TSW-1060 — Chromium renders blank pages |
| `BROWSERMOBILE` | `DESKTOP` | Desktop user agent for proper HA rendering |
| `BROWSERHOMEPAGE` | `<HA_URL>` | Sets the browser home page to your HA dashboard |
| `BEEPSTATE` | `OFF` | Disables key click sounds |

> **Note:** `PROJECTMODE`, `BROWMODE`, and `SDCARDCOUNTER` cannot be set via SSH. Configure these from the panel's local console:
> ```
> PROJECTMODE USERPROJECT
> BROWMODE KIOSK
> SDCARDCOUNTER ON
> REBOOT
> ```

### Step 3: Configure Home Assistant

Add to your `configuration.yaml`:

```yaml
# Shell commands for Crestron panel control
shell_command:
  crestron_open_browser: "python3 /config/scripts/crestron_cmd.py 'BROWSEROPEN http://<HA_IP>:8123/crestron-display/home'"
  crestron_close_browser: "python3 /config/scripts/crestron_cmd.py 'BROWSERCLOSE'"
  crestron_standby: "python3 /config/scripts/crestron_cmd.py 'standby'"
  crestron_wake: "python3 /config/scripts/crestron_cmd.py 'standby off'"
  photoframe_build_list: "python3 /config/scripts/photoframe_build_list.py"

# Camera cycling helper
input_select:
  camera_selector:
    name: Camera Selector
    icon: mdi:cctv
    options:
      - camera.frontporch
      - camera.driveway
      - camera.backyard
      - camera.critter
      - camera.armory
      - camera.pancam
      - camera.gatetown

# Load the panel controller JS
frontend:
  extra_js_url_es5:
    - /local/crestron-panel.js

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

See `ha-scripts/configuration-additions.yaml` for the full reference config.

### Step 4: Create the HA Automations

Add the automations from `ha-scripts/automations-crestron.yaml` to your automations (via YAML or the HA UI). These handle:

1. **Boot trigger** — CH5 app fires webhook, HA opens the browser
2. **Periodic browser restart** — every 6 hours, fully restart the browser to clear memory
3. **Camera cycling** — advances the camera selector every 15 seconds
4. **Photo frame image list** — rebuilds on HA startup and every hour

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

With `BROWSERCACHE DISABLE`, write rates stay well within safe limits.

## Dashboard & Photo Frame

The `ha-scripts/` directory includes a complete two-view dashboard designed for the TSW-1060 (1280x800):

- **Home view** — cycling camera snapshots (via `input_select` + conditional cards) with a compact control strip and info sidebar (clock, weather, calendar, recent detections)
- **Photos view** — full-screen photo frame slideshow with clock/weather/forecast overlay

After 2 minutes of no touch, the panel switches to the photo frame. Any touch returns to the dashboard. The photo frame runs in an iframe, completely isolated from the HA frontend.

Camera snapshots use `picture-entity` cards with `camera_view: auto` — lightweight JPEG snapshots instead of live video streams. The TSW-1060's Chromium 95 WebView cannot sustainably decode MJPEG or WebRTC video (the WebView crash-loops after ~20 minutes). A 15-minute hard refresh timer in `crestron-panel.js` reclaims leaked WebView memory by navigating directly to the photos view.

### Deploy the Dashboard

1. Copy the HA scripts and static files:

```bash
cp ha-scripts/crestron-panel.js <ha-config-path>/www/crestron-panel.js
cp ha-scripts/photoframe.html <ha-config-path>/www/photoframe.html
cp ha-scripts/photoframe_build_list.py <ha-config-path>/scripts/photoframe_build_list.py
```

2. Merge `ha-scripts/configuration-additions.yaml` into your `configuration.yaml`. Replace `<HA_IP>` with your Home Assistant IP.

3. Add the automations from `ha-scripts/automations-crestron.yaml` to your automations (via YAML or the HA UI).

4. Create a new dashboard in HA: **Settings > Dashboards > Add Dashboard**. Set the URL to `crestron-display` and mode to **YAML**. Paste the contents of `ha-scripts/dash.yaml` into the raw editor.

5. Edit `dash.yaml` to match your setup — camera entities, control strip entities, etc. See the comments in the file.

6. Create the `input_select.camera_selector` helper (via **Settings > Helpers > Add > Dropdown**) with your camera entity IDs as options.

7. Add photos to `/media/ciriolisaver/` (or change the path in `photoframe_build_list.py`). The image list rebuilds automatically on HA startup and every hour.

8. Restart HA to load everything.

## Side Buttons

With `APPKEYS ON`, the TSW-1060's five hardware side buttons fire standard JavaScript key events directly in the browser. No Node-RED or external tools needed.

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

### Panel Controller (crestron-panel.js)

The panel controller handles side buttons, idle detection, camera cycling, and WebView memory management in one script. It only activates on the `crestron-display` dashboard (guard clause) — inert on all other devices.

Default button mapping:

| Button | Action |
|--------|--------|
| Power / Home | Return to dashboard |
| Up arrow | Next camera (via `input_select.select_next`) |
| Down arrow | Previous camera (via `input_select.select_previous`) |
| Lightbulb | Toggle photo frame |

Deploy: copy to `www/crestron-panel.js` and add to `configuration.yaml` under `frontend > extra_js_url_es5`.

### Simple Version (example)

If you just want basic button-to-service mapping without idle detection or camera cycling, see `ha-scripts/crestron-sidekeys.example.js`. This is a minimal standalone script with three action types: **navigate**, **service**, and **fire**.

## Changing the HA URL

To change the HA URL or webhook ID after initial setup, close the browser to get back to the CH5 app:

```
BROWSERCLOSE
```

The CH5 setup wizard will be visible. Tap **Reconfigure**, enter the new URL, and tap **Launch**.

## Diagnostic Commands

These can be run anytime via `crestron_cmd.py` to check panel health:

| Command | Purpose |
|---------|---------|
| `RAMFREE` | Check free memory (healthy: ~800 MB free) |
| `CPULOAD` | Check CPU usage (healthy: ~30% busy, load ~1.0) |
| `TEMPERATURE` | Check panel temperature |
| `SDCARDSTATUS` | Check SD card write counters |
| `UPTIME` | Check how long since last reboot |
| `TASKSTAT` | Show per-process CPU time (useful for finding runaway services) |

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

**Panel freezes after ~20 minutes**
- Check `TASKSTAT` for high CPU time on `txrxservice`, `mediaserver`, or `CrashpadMain`
- Run `DEDICATEDVIDEOSUPPORT DISABLE` and `CAMERASTREAMENABLE OFF`, then `REBOOT`
- Verify cameras use snapshot mode (`camera_view: auto`), not live streams
- The 15-min refresh timer in `crestron-panel.js` mitigates WebView memory leaks

**Camera not cycling**
- Verify `input_select.camera_selector` exists (**Settings > Helpers**)
- Verify the cycling automation is enabled (**Settings > Automations**)
- Check that the dashboard YAML has conditional cards matching the input_select states

## Known Issues

- **Camera sequence glitch during soak test:** The camera sequence occasionally updates oddly, such as showing "critter", quickly flashing to another camera, and then showing "critter" again. This is a known rendering or timing quirk currently under investigation.

## License

MIT
