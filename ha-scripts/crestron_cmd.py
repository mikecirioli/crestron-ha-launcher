#!/usr/bin/env python3
"""
Send a console command to a Crestron panel via SSH.

Uses paramiko (bundled with Home Assistant) so no extra packages are needed.
Survives HA container updates since it lives in the config directory.

Usage:
  python3 crestron_cmd.py <command>

Environment variables (optional, override defaults):
  CRESTRON_HOST  Panel IP address
  CRESTRON_PORT  SSH port (default: 22)
  CRESTRON_USER  Console username (default: admin)
  CRESTRON_PASS  Console password
"""
import os
import sys
import paramiko

HOST = os.environ.get("CRESTRON_HOST", "192.168.1.58")
PORT = int(os.environ.get("CRESTRON_PORT", "22"))
USER = os.environ.get("CRESTRON_USER", "admin")
PASS = os.environ.get("CRESTRON_PASS", "admin")

cmd = " ".join(sys.argv[1:])
if not cmd:
    print("Usage: crestron_cmd.py <command>", file=sys.stderr)
    sys.exit(1)

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

try:
    client.connect(HOST, port=PORT, username=USER, password=PASS,
                   timeout=10, look_for_keys=False, allow_agent=False)
    stdin, stdout, stderr = client.exec_command(cmd, timeout=10)
    out = stdout.read().decode(errors="replace").strip()
    err = stderr.read().decode(errors="replace").strip()
    if out:
        print(out)
    if err:
        print(err, file=sys.stderr)
    sys.exit(stdout.channel.recv_exit_status())
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
finally:
    client.close()
