#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
# Crestron TSW-1060 Panel Setup Script
# ═══════════════════════════════════════════════════════════════════
# Configures a TSW-1060 for use as an HA dashboard / photo frame.
# Uses crestron_cmd.py (must be deployed to HA first).
#
# Usage:
#   ./panel-setup.sh [ha-config-path]
#
# Example:
#   ./panel-setup.sh /config
#   ./panel-setup.sh /export/homeassistant
#
# Prerequisites:
#   - crestron_cmd.py deployed to <ha-config-path>/scripts/
#   - Python 3 + paramiko available
#   - Network access to the panel
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail

HA_CONFIG="${1:-/config}"
CMD="python3 ${HA_CONFIG}/scripts/crestron_cmd.py"

# ── Configuration ────────────────────────────────────────────────
# Edit these to match your setup.
TIMEZONE="014"              # 014 = Eastern Time (US & Canada). Run TIMEZONE list for codes.
HA_URL="http://192.168.1.245:8123/crestron-display/home"
REBOOT_HOUR="6"           # Hour (0-23) for scheduled/memory-triggered reboots
PROJECT_MEMORY="512"      # MB — memory limit for project (test with RAMFREE)
MEM_LOW_TRIGGER="80"      # MB free — schedule reboot when below this
MEM_CRIT_TRIGGER="30"     # MB free — immediate reboot when below this
MEM_CLEANUP_INTERVAL="3600" # Seconds between memory cleanup cycles (3600 = 60 min)
# ─────────────────────────────────────────────────────────────────

echo "=== Crestron TSW-1060 Panel Setup ==="
echo "Using crestron_cmd.py at: ${HA_CONFIG}/scripts/"
echo ""

run_cmd() {
    local desc="$1"
    local cmd="$2"
    echo "  ${desc}..."
    $CMD "$cmd" 2>&1 | sed 's/^/    /'
}

# ── Core settings ───────────────────────────────────────────────
# NOTE: PROJECTMODE, BROWMODE, and SDCARDCOUNTER cannot be set via SSH.
# Configure these from the panel's local console if needed.
echo "[1/6] Core settings"
run_cmd "Browser cache off"         "BROWSERCACHE DISABLE"
run_cmd "Side button key events"    "APPKEYS ON"
run_cmd "Disable AV transport"      "DEDICATEDVIDEOSUPPORT DISABLE"
run_cmd "Disable onboard camera"   "CAMERASTREAMENABLE OFF"
run_cmd "Set timezone"              "TIMEZONE ${TIMEZONE}"
echo ""

# ── Memory management ────────────────────────────────────────────
echo "[2/6] Memory management"
run_cmd "Project memory limit"      "PROJECTMEMORY ${PROJECT_MEMORY}"
run_cmd "Memory cleanup interval"   "MEMCLEANUPCONFIG APP ${MEM_CLEANUP_INTERVAL}"
run_cmd "Low memory reboot trigger" "MEMLOWTRIG ${MEM_LOW_TRIGGER}"
run_cmd "Critical memory reboot"    "MEMCRITTRIG ${MEM_CRIT_TRIGGER}"
run_cmd "Reboot hour"               "MEMTRIGTIME ${REBOOT_HOUR}"
run_cmd "Daily periodic reboot"     "PERIODICREBOOT ON"
echo ""

# ── Display settings ─────────────────────────────────────────────
# NOTE: PROXIMITYWAKE is not supported on TSW-1060.
echo "[3/6] Display settings"
run_cmd "Auto brightness"           "AUTOBRIGHTNESS ON"
run_cmd "Standby timeout off"       "STBYTO 0"
run_cmd "Screensaver off"           "SCREENSAVER OFF"
echo ""

# ── Browser settings ─────────────────────────────────────────────
# NOTE: Must use WEBVIEW on TSW-1060 — Chromium renders blank pages.
echo "[4/6] Browser settings"
run_cmd "Select WebView browser"    "BROWSERSELECT WEBVIEW"
run_cmd "Desktop user agent"        "BROWSERMOBILE DESKTOP"
run_cmd "Browser home page"         "BROWSERHOMEPAGE ${HA_URL}"
echo ""

# ── Side buttons & audio ─────────────────────────────────────────
echo "[5/6] Side buttons & audio"
run_cmd "Key click sounds off"      "BEEPSTATE OFF"
# Side button backlights stay on (default) — do not set KEYBKL 0
echo ""

# ── Verify settings ──────────────────────────────────────────────
echo ""
echo "=== Verifying ==="
run_cmd "Browser cache"             "BROWSERCACHE"
run_cmd "Browser engine"            "BROWSERSELECT"
run_cmd "Browser user agent"        "BROWSERMOBILE"
run_cmd "App keys"                  "APPKEYS"
run_cmd "AV transport"              "DEDICATEDVIDEOSUPPORT"
run_cmd "Timezone"                  "TIMEZONE"
run_cmd "Project memory"            "PROJECTMEMORY"
run_cmd "RAM free"                  "RAMFREE"
run_cmd "CPU load"                  "CPULOAD"
run_cmd "Temperature"               "TEMPERATURE"
echo ""

echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Review the output above for any errors"
echo "  2. Check RAMFREE to see if PROJECTMEMORY took effect"
echo "  3. Reboot the panel: $CMD 'REBOOT'"
echo ""
echo "Diagnostic commands (run anytime):"
echo "  $CMD 'RAMFREE'       — check free memory"
echo "  $CMD 'CPULOAD'       — check CPU usage"
echo "  $CMD 'TEMPERATURE'   — check panel temp"
echo "  $CMD 'SDCARDSTATUS'  — check SD card writes"
echo "  $CMD 'UPTIME'        — check uptime"
