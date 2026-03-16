#!/usr/bin/env python3
# Copyright (c) 2026 Mike Cirioli. Licensed under CC BY-NC-SA 4.0.
# https://creativecommons.org/licenses/by-nc-sa/4.0/
"""
Generate a JSON list of image URLs for the photo frame slideshow.

Scans the HA media directory for images and writes a JSON array of
browser-accessible URLs to /config/www/photoframe-images.json.

Deploy to: /config/scripts/photoframe_build_list.py
Add to configuration.yaml:
  shell_command:
    photoframe_build_list: "python3 /config/scripts/photoframe_build_list.py"
"""

import json
import os
import sys

# ── Configuration ─────────────────────────────────────────────────
# Filesystem path where the photos live (inside HA container)
MEDIA_DIR = "/media/ciriolisaver"

# URL prefix for serving these files via HA's HTTP server.
# /local/ serves from /config/www/ without authentication.
# Symlink your photo folder into www/: ln -s /media/ciriolisaver /config/www/ciriolisaver
URL_PREFIX = "/local/ciriolisaver/"

# Output path (must be under /config/www/ for HA to serve it)
OUTPUT = "/config/www/photoframe-images.json"

# Supported image extensions
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}
# ──────────────────────────────────────────────────────────────────

def main():
    if not os.path.isdir(MEDIA_DIR):
        print(f"Warning: media directory not found: {MEDIA_DIR}", file=sys.stderr)
        # Write empty list so the slideshow shows the fallback message
        write_list([])
        return

    images = []
    for name in sorted(os.listdir(MEDIA_DIR)):
        ext = os.path.splitext(name)[1].lower()
        if ext in EXTS:
            images.append(URL_PREFIX + name)

    write_list(images)
    print(f"photoframe: wrote {len(images)} images to {OUTPUT}")


def write_list(images):
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(images, f)


if __name__ == "__main__":
    main()
