#!/bin/bash
# Resize photos in-place to fit TSW-1060 display (1280x800).
# Only shrinks images larger than the target; never upscales.
# Strips EXIF metadata to reduce file size.
#
# Deploy to: /config/scripts/resize_photos.sh
# Add to configuration.yaml:
#   shell_command:
#     resize_photos: "bash /config/scripts/resize_photos.sh"

MEDIA_DIR="/media/ciriolisaver"
MAX="1280x800"

if [ ! -d "$MEDIA_DIR" ]; then
  echo "resize_photos: directory not found: $MEDIA_DIR" >&2
  exit 1
fi

count=0
skipped=0
for f in "$MEDIA_DIR"/*.jpg "$MEDIA_DIR"/*.jpeg "$MEDIA_DIR"/*.png "$MEDIA_DIR"/*.webp "$MEDIA_DIR"/*.JPG "$MEDIA_DIR"/*.JPEG "$MEDIA_DIR"/*.PNG; do
  [ -f "$f" ] || continue
  dims=$(identify -format '%wx%h' "$f" 2>/dev/null) || continue
  w=${dims%x*}
  h=${dims#*x}
  if [ "$w" -gt 1280 ] || [ "$h" -gt 800 ]; then
    convert "$f" -resize "${MAX}>" -strip "$f"
    count=$((count + 1))
  else
    skipped=$((skipped + 1))
  fi
done

echo "resize_photos: resized $count, skipped $skipped (already ≤${MAX})"
