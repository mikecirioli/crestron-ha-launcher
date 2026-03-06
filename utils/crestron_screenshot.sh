#!/usr/bin/env bash
# Take a screenshot from a Crestron TSW panel via SSH, download, and convert to JPG.
#
# Usage:
#   ./crestron_screenshot.sh [output.jpg]
#
# Environment variables (optional, override defaults):
#   CRESTRON_HOST  Panel IP address (default: 192.168.1.58)
#   CRESTRON_USER  Console/SSH username (default: admin)
#   CRESTRON_PASS  Console/SSH password (default: admin)
#
# Requires: sshpass, python3 + Pillow

set -euo pipefail

HOST="${CRESTRON_HOST:-192.168.1.58}"
USER="${CRESTRON_USER:-admin}"
PASS="${CRESTRON_PASS:-admin}"
REMOTE_BMP="/logs/ScreenShot.bmp"
OUTPUT="${1:-screenshot-$(date +%Y%m%d-%H%M%S).jpg}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

echo "Taking screenshot on ${HOST}..."
sshpass -p "${PASS}" ssh ${SSH_OPTS} "${USER}@${HOST}" "SCREENSHOT"

echo "Downloading BMP..."
TMP_BMP=$(mktemp /tmp/crestron-XXXXXX.bmp)
sshpass -p "${PASS}" scp ${SSH_OPTS} "${USER}@${HOST}:${REMOTE_BMP}" "${TMP_BMP}"

echo "Converting to JPG..."
if command -v convert &>/dev/null; then
  convert "${TMP_BMP}" -quality 90 "${OUTPUT}"
else
  python3 -c "from PIL import Image; Image.open('${TMP_BMP}').save('${OUTPUT}', 'JPEG', quality=90)"
fi
rm -f "${TMP_BMP}"

echo "Saved: ${OUTPUT}"
