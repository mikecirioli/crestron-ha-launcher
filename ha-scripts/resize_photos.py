#!/usr/bin/env python3
"""
Resize photos in-place to fit TSW-1060 display (1280x800).
Only shrinks images larger than the target; never upscales.
Strips EXIF metadata to reduce file size.

Deploy to: /config/scripts/resize_photos.py
Add to configuration.yaml:
  shell_command:
    resize_photos: "python3 /config/scripts/resize_photos.py"
"""

import os
import sys
from PIL import Image

MEDIA_DIR = "/media/ciriolisaver"
MAX_W = 1280
MAX_H = 800
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"}

def main():
    if not os.path.isdir(MEDIA_DIR):
        print(f"resize_photos: directory not found: {MEDIA_DIR}", file=sys.stderr)
        sys.exit(1)

    files = [n for n in sorted(os.listdir(MEDIA_DIR))
             if os.path.splitext(n)[1].lower() in EXTS]
    total = len(files)
    count = 0
    skipped = 0
    errors = 0

    for i, name in enumerate(files, 1):
        path = os.path.join(MEDIA_DIR, name)
        try:
            with Image.open(path) as img:
                w, h = img.size
                if w > MAX_W or h > MAX_H:
                    img.thumbnail((MAX_W, MAX_H), Image.LANCZOS)
                    img.save(path, quality=85, optimize=True)
                    count += 1
                    print(f"[{i}/{total}] {name} {w}x{h} -> resized", flush=True)
                else:
                    skipped += 1
                    print(f"[{i}/{total}] {name} {w}x{h} ok", flush=True)
        except Exception as e:
            print(f"[{i}/{total}] {name} ERROR: {e}", file=sys.stderr, flush=True)
            errors += 1

    print(f"\nresize_photos: resized {count}, skipped {skipped}, errors {errors}")

if __name__ == "__main__":
    main()
