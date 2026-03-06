#!/usr/bin/env python3
"""
Resize and fix photos in-place for TSW-1060 display (1280x800).
Auto-rotates based on EXIF orientation, then shrinks if larger than target.
Strips EXIF metadata to reduce file size.

Deploy to: /config/scripts/resize_photos.py
Add to configuration.yaml:
  shell_command:
    resize_photos: "python3 /config/scripts/resize_photos.py"
"""

import os
import sys
from PIL import Image, ImageOps

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
    rotated = 0
    resized = 0
    skipped = 0
    errors = 0

    for i, name in enumerate(files, 1):
        path = os.path.join(MEDIA_DIR, name)
        try:
            with Image.open(path) as img:
                changed = False
                # Fix EXIF orientation (upside-down, rotated, etc.)
                exif = img.getexif()
                orientation = exif.get(0x0112, 1)  # 1 = normal
                if orientation != 1:
                    img = ImageOps.exif_transpose(img)
                    changed = True
                    rotated += 1

                w, h = img.size
                if w > MAX_W or h > MAX_H:
                    img.thumbnail((MAX_W, MAX_H), Image.LANCZOS)
                    changed = True
                    resized += 1

                if changed:
                    img.save(path, quality=85, optimize=True)
                    print(f"[{i}/{total}] {name} {w}x{h} -> fixed", flush=True)
                else:
                    skipped += 1
                    print(f"[{i}/{total}] {name} {w}x{h} ok", flush=True)
        except Exception as e:
            print(f"[{i}/{total}] {name} ERROR: {e}", file=sys.stderr, flush=True)
            errors += 1

    print(f"\nresize_photos: rotated {rotated}, resized {resized}, skipped {skipped}, errors {errors}")

if __name__ == "__main__":
    main()
