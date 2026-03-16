#!/usr/bin/env python3
# Copyright (c) 2026 Mike Cirioli. Licensed under CC BY-NC-SA 4.0.
# https://creativecommons.org/licenses/by-nc-sa/4.0/
"""
Take a screenshot from a Crestron TSW panel, download via SFTP, convert to JPG.

Uses paramiko (bundled with Home Assistant) for both SSH command and SFTP download.
Requires Pillow (bundled with Home Assistant) for BMP-to-JPG conversion.

Usage:
  python3 crestron_screenshot.py [output_path]

Default output: /config/www/panel-screenshot.jpg (accessible at /local/panel-screenshot.jpg)

Environment variables (optional, override defaults):
  CRESTRON_HOST  Panel IP address
  CRESTRON_PORT  SSH port (default: 22)
  CRESTRON_USER  Console username (default: admin)
  CRESTRON_PASS  Console password
"""
import os
import sys
import paramiko
from PIL import Image

HOST = os.environ.get("CRESTRON_HOST", "192.168.1.58")
PORT = int(os.environ.get("CRESTRON_PORT", "22"))
USER = os.environ.get("CRESTRON_USER", "admin")
PASS = os.environ.get("CRESTRON_PASS", "admin")
REMOTE_BMP = "/logs/ScreenShot.bmp"
DEFAULT_OUTPUT = "/config/www/panel-screenshot.jpg"

output = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_OUTPUT

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    client.connect(HOST, port=PORT, username=USER, password=PASS,
                   timeout=10, look_for_keys=False, allow_agent=False)

    # Take screenshot
    stdin, stdout, stderr = client.exec_command("SCREENSHOT", timeout=15)
    out = stdout.read().decode(errors="replace").strip()
    exit_code = stdout.channel.recv_exit_status()
    stdin.close()
    stdout.close()
    stderr.close()
    if exit_code != 0:
        print(f"SCREENSHOT command failed: {out}", file=sys.stderr)
        sys.exit(1)
    print(out)

    # Download via SFTP
    tmp_bmp = output + ".bmp"
    sftp = client.open_sftp()
    sftp.get(REMOTE_BMP, tmp_bmp)
    sftp.close()

    # Clean up remote BMP to avoid filling panel disk
    stdin2, stdout2, stderr2 = client.exec_command("DELETE /logs/ScreenShot.bmp", timeout=10)
    stdout2.read()
    stdin2.close()
    stdout2.close()
    stderr2.close()

    # Convert BMP to JPG
    with Image.open(tmp_bmp) as img:
        img.save(output, "JPEG", quality=90)
    os.remove(tmp_bmp)

    print(f"Saved: {output}")

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    client.close()
