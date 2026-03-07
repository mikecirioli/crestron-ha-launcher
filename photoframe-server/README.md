# Photo Frame Server

A minimal HTTP server that serves random photos from a directory. Designed for digital signage and touch panel photo frames — works great with Crestron TSW panels, wall-mounted tablets, or any device with a browser.

![Dashboard](../docs/images/panel-lite-dashboard.jpg)
![Screensaver](../docs/images/panel-lite-screensaver.jpg)

## Endpoints

| Endpoint | Returns | Use Case |
|----------|---------|----------|
| `/` | Full-screen HTML page with fade transitions and clock overlay | Point any browser or kiosk at this |
| `/random` | A random image file with proper content-type | API endpoint for custom dashboards |
| `/random?w=1280&h=800` | Random image resized on the fly (requires Pillow) | Bandwidth-friendly for constrained devices |
| `/health` | `ok` | Container/load balancer health check |

## Quick Start

### Docker (recommended)

```bash
docker compose up -d
```

Edit `docker-compose.yaml` to point at your photos directory:

```yaml
services:
  photoframe:
    build: .
    container_name: photoframe-server
    restart: unless-stopped
    ports:
      - "8099:8099"
    volumes:
      - /path/to/your/photos:/media:ro
    environment:
      - REFRESH=30
```

Then open `http://<host-ip>:8099/` in a browser.

### Standalone

```bash
pip install Pillow  # optional, needed for on-the-fly resize
PHOTO_DIR=/path/to/photos python3 server.py
```

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `PHOTO_DIR` | `/media` | Directory containing images (jpg, png, webp, gif, bmp) |
| `PORT` | `8099` | Listen port |
| `REFRESH` | `30` | Seconds between photo changes on the HTML page |
| `TITLE` | _(empty)_ | Optional text shown in the clock overlay |

## HTML Page URL Parameters

The built-in HTML page (`/`) accepts optional URL parameters for Home Assistant integration:

| Parameter | Description |
|-----------|-------------|
| `ha_url` | Home Assistant base URL (e.g. `http://homeassistant.local:8123`) |
| `token` | HA long-lived access token |
| `weather` | Weather entity ID (default: `weather.forecast_home`) |

**Without HA params:** Clock and date overlay only — works standalone.

**With HA params:** Adds current temperature, conditions, and 3-day forecast to the overlay.

Example: `http://<host>:8099/?ha_url=http://homeassistant.local:8123&token=YOUR_TOKEN`

The clock overlay slowly drifts across the screen (~1px/sec bounce) for burn-in prevention on always-on displays.

## Supported Image Formats

jpg, jpeg, png, webp, gif, bmp — any mix in the same directory.

File names don't matter. Just drop images in the folder and they're in rotation. New images are picked up automatically when the directory changes.

## Use Cases

### Crestron TSW Panel — EMS Mode Photo Frame

The simplest possible setup. No CH5 app, no Home Assistant, no webhooks.

1. Deploy the container on any machine on your network
2. On the panel console: `EMS <host-ip>:8099`
3. Done — full-screen photo frame with clock overlay

> **Note:** EMS mode generates heavy SD card writes (~100K/hour) due to browser caching. For long-term use, consider UserProject mode with the CH5 launcher app instead.

### Crestron TSW Panel — Dashboard Screensaver

If you're running the Panel Lite dashboard from the [crestron-ha-launcher](../) project, the screensaver can fetch photos from this server instead of a static JSON list:

- No `photoframe_build_list.py` needed
- No numbered files or JSON manifests
- Drop photos in the folder, they appear automatically
- Optional server-side resize saves bandwidth and panel memory

### Wall Tablet / Kiosk

Point any Android tablet, iPad, Fire tablet, or old laptop at `http://<host-ip>:8099/` in kiosk/full-screen mode. The page handles everything — photo cycling, fade transitions, clock, and auto-recovery on network errors.

## On-the-Fly Resize

If Pillow is installed (included in the Docker image), you can request resized images:

```
/random?w=1280&h=800
```

The server resizes to fit within the given dimensions (preserving aspect ratio), applies EXIF rotation, and serves the result. Original files are never modified.

Without Pillow, resize parameters are ignored and the original file is served.
