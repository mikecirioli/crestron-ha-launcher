#!/usr/bin/env python3
"""
Minimal HTTP server that serves random photos from a directory,
with optional Frigate API proxy and HA state endpoints.

Endpoints:
  /              HTML page — full-screen photo frame with auto-refresh and clock overlay
  /random        Returns a random image file (JPEG/PNG/WebP) with proper content-type
  /random?w=1280&h=800  Resize on the fly (requires Pillow)
  /frigate/*     Proxy to Frigate API (requires FRIGATE_URL env var, adds CORS headers)
  /ha/weather    Plain text: current weather summary
  /ha/forecast   Plain text: 3-day forecast
  /ha/event      Plain text: next calendar event
  /ha/thermostat Plain text: thermostat status
  /health        Health check

Environment variables:
  PHOTO_DIR      Directory containing images (default: /media)
  PORT           Listen port (default: 8099)
  REFRESH        Seconds between photo changes on the HTML page (default: 30)
  TITLE          Page title / overlay text (default: empty)
  FRIGATE_URL    Frigate base URL for proxy (e.g. http://192.168.1.207:5000)
  HA_URL         Home Assistant URL (e.g. http://192.168.1.245:8123)
  HA_TOKEN       Long-lived access token for HA REST API

Usage:
  python3 server.py
  docker run -v /path/to/photos:/media -p 8099:8099 photoframe-server
"""

import os
import sys
import random
import mimetypes
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn
from urllib.parse import urlparse, parse_qs
from io import BytesIO

try:
    from urllib.request import urlopen, Request
    from urllib.error import URLError
except ImportError:
    from urllib2 import urlopen, Request, URLError

PHOTO_DIR = os.environ.get("PHOTO_DIR", "/media")
PORT = int(os.environ.get("PORT", "8099"))
REFRESH = int(os.environ.get("REFRESH", "30"))
TITLE = os.environ.get("TITLE", "")
FRIGATE_URL = os.environ.get("FRIGATE_URL", "")  # e.g. http://192.168.1.207:5000
HA_URL = os.environ.get("HA_URL", "").rstrip("/")
HA_TOKEN = os.environ.get("HA_TOKEN", "")
EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"}

# Cache the file list, refresh periodically
_photo_cache = []
_cache_mtime = 0


def get_photos():
    """Return list of photo paths, refreshing if directory has changed."""
    global _photo_cache, _cache_mtime
    try:
        stat = os.stat(PHOTO_DIR)
        if stat.st_mtime != _cache_mtime or not _photo_cache:
            _cache_mtime = stat.st_mtime
            _photo_cache = [
                os.path.join(PHOTO_DIR, f)
                for f in os.listdir(PHOTO_DIR)
                if os.path.splitext(f)[1].lower() in EXTS
            ]
    except OSError:
        pass
    return _photo_cache


def resize_image(path, max_w, max_h):
    """Resize image to fit within max_w x max_h. Returns (bytes, content_type)."""
    try:
        from PIL import Image, ImageOps
        with Image.open(path) as img:
            img = ImageOps.exif_transpose(img)
            img.thumbnail((max_w, max_h), Image.LANCZOS)
            buf = BytesIO()
            fmt = "JPEG" if path.lower().endswith((".jpg", ".jpeg")) else "PNG"
            img.save(buf, fmt, quality=85)
            ct = "image/jpeg" if fmt == "JPEG" else "image/png"
            return buf.getvalue(), ct
    except ImportError:
        # No Pillow — serve original
        return None, None



# ── HA data cache ─────────────────────────────────────────────
# Server-side caching: fetch from HA at most once per interval,
# serve plain text to clients with zero processing on their end.

import json
import time
import threading

_ha_cache = {}       # key → {"text": str, "ts": float}
_ha_cache_ttl = 120  # seconds
_ha_lock = threading.Lock()


def _ha_get(path):
    """GET from HA REST API. Returns parsed JSON or None."""
    if not HA_URL or not HA_TOKEN:
        return None
    url = HA_URL + path
    req = Request(url)
    req.add_header("Authorization", "Bearer " + HA_TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        resp = urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception:
        return None


def _ha_post(path, body, return_response=False):
    """POST to HA REST API. Returns parsed JSON or None."""
    if not HA_URL or not HA_TOKEN:
        return None
    url = HA_URL + path
    if return_response:
        url += "?return_response"
    data = json.dumps(body).encode()
    req = Request(url, data=data, method="POST")
    req.add_header("Authorization", "Bearer " + HA_TOKEN)
    req.add_header("Content-Type", "application/json")
    try:
        resp = urlopen(req, timeout=10)
        return json.loads(resp.read())
    except Exception:
        return None


def _cached(key, fetch_fn):
    """Return cached text or call fetch_fn to refresh."""
    with _ha_lock:
        entry = _ha_cache.get(key)
        if entry and (time.time() - entry["ts"]) < _ha_cache_ttl:
            return entry["text"]
    text = fetch_fn() or ""
    with _ha_lock:
        _ha_cache[key] = {"text": text, "ts": time.time()}
    return text


def ha_weather():
    def fetch():
        data = _ha_get("/api/states/weather.forecast_home")
        if not data:
            return ""
        a = data.get("attributes", {})
        temp = a.get("temperature")
        unit = a.get("temperature_unit", "\u00b0F")
        cond = (data.get("state", "") or "").replace("-", " ").replace("_", " ").title()
        humid = a.get("humidity")
        parts = []
        if temp is not None:
            parts.append("{}{}".format(round(temp), unit))
        if cond:
            parts.append(cond)
        if humid is not None:
            parts.append("{}% humidity".format(humid))
        return "  \u00b7  ".join(parts)
    return _cached("weather", fetch)


def ha_forecast():
    def fetch():
        data = _ha_post("/api/services/weather/get_forecasts", {
            "type": "daily",
            "entity_id": "weather.forecast_home"
        }, return_response=True)
        if not data:
            return ""
        forecasts = []
        resp = data.get("service_response", data.get("response", data))
        for v in (resp.values() if isinstance(resp, dict) else []):
            if isinstance(v, dict) and "forecast" in v:
                forecasts = v["forecast"]
                break
        if not forecasts:
            return ""
        days = forecasts[:3]
        parts = []
        day_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        for d in days:
            dt = d.get("datetime", "")
            try:
                from datetime import datetime
                dn = day_names[datetime.fromisoformat(dt.replace("Z", "+00:00")).weekday()]
            except Exception:
                dn = "?"
            hi = round(d.get("temperature", 0))
            lo = round(d.get("templow", 0))
            parts.append("{} {}/{}".format(dn, hi, lo))
        return "  \u00b7  ".join(parts)
    return _cached("forecast", fetch)


def ha_thermostat():
    def fetch():
        data = _ha_get("/api/states/climate.upper_level")
        if not data:
            return ""
        a = data.get("attributes", {})
        current = a.get("current_temperature")
        action = a.get("hvac_action", data.get("state", ""))
        target = a.get("temperature")
        if target is None:
            hi = a.get("target_temp_high")
            lo = a.get("target_temp_low")
            if hi is not None and lo is not None:
                target = "{}-{}".format(round(lo), round(hi))
        else:
            target = str(round(target))
        parts = []
        if current is not None:
            parts.append("{}\u00b0".format(round(current)))
        if action:
            parts.append(action.replace("_", " ").title())
        if target and data.get("state") != "off":
            parts.append("Set: {}\u00b0".format(target))
        return "  \u00b7  ".join(parts)
    return _cached("thermostat", fetch)


def ha_next_event():
    def fetch():
        if not HA_URL or not HA_TOKEN:
            return ""
        from datetime import datetime, timedelta, timezone
        now = datetime.now(timezone.utc)
        calendars = [
            "calendar.home",
            "calendar.mikecirioli_gmail_com",
            "calendar.birthdays",
            "calendar.mcirioli_cloudbees_com",
        ]
        best = None
        best_start = None
        for cal in calendars:
            # Check if calendar is available first
            state = _ha_get("/api/states/" + cal)
            if not state or state.get("state") == "unavailable":
                continue
            data = _ha_post("/api/services/calendar/get_events", {
                "entity_id": cal,
                "duration": {"days": 7}
            }, return_response=True)
            if not data:
                continue
            resp = data.get("service_response", data.get("response", data))
            events = []
            for v in (resp.values() if isinstance(resp, dict) else []):
                if isinstance(v, dict) and "events" in v:
                    events = v["events"]
                    break
            for ev in events:
                st = ev.get("start")
                if not st:
                    continue
                try:
                    if "T" in st:
                        evt_dt = datetime.fromisoformat(st.replace("Z", "+00:00"))
                    else:
                        evt_dt = datetime.fromisoformat(st + "T00:00:00+00:00")
                except Exception:
                    continue
                if evt_dt < now:
                    continue
                if best_start is None or evt_dt < best_start:
                    best_start = evt_dt
                    best = ev
        if not best:
            return ""
        title = best.get("summary", best.get("title", ""))
        diff = best_start - now
        total_min = int(diff.total_seconds() / 60)
        if total_min < 60:
            prefix = "In {}min".format(total_min)
        elif total_min < 1440:
            h = total_min // 60
            m = total_min % 60
            prefix = "In {}h{}".format(h, " {}m".format(m) if m else "")
        else:
            day_names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            prefix = day_names[best_start.weekday()]
        return "{}  \u00b7  {}".format(prefix, title)
    return _cached("event", fetch)


HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Photo Frame</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { background: #000; overflow: hidden; width: 100vw; height: 100vh; }
  #photo {
    width: 100vw; height: 100vh;
    object-fit: contain;
    opacity: 0;
    transition: opacity 1.5s ease;
  }
  #photo.visible { opacity: 1; }
  .overlay {
    position: fixed;
    color: #fff; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    text-align: right; z-index: 10;
    text-shadow: 0 2px 8px rgba(0,0,0,0.8);
    background: rgba(0,0,0,0.35);
    padding: 16px 24px;
    border-radius: 14px;
  }
  .overlay .clock { font-size: 36px; font-weight: 300; }
  .overlay .date { font-size: 16px; opacity: 0.8; margin-top: 2px; }
  .overlay .title { font-size: 14px; opacity: 0.6; margin-top: 6px; }
  .overlay .weather { margin-top: 8px; font-size: 14px; opacity: 0.85; }
  .overlay .weather .temp { font-size: 20px; font-weight: 400; }
  .overlay .forecast { margin-top: 6px; font-size: 12px; opacity: 0.7; }
  .overlay .forecast span { margin-left: 10px; }
</style>
</head>
<body>
<img id="photo" alt="">
<div class="overlay" id="overlay">
  <div class="clock" id="clock"></div>
  <div class="date" id="date"></div>
  TITLE_PLACEHOLDER
  <div class="weather" id="weather" style="display:none"></div>
  <div class="forecast" id="forecast" style="display:none"></div>
</div>
<script>
  var REFRESH = REFRESH_PLACEHOLDER;
  var photo = document.getElementById('photo');
  var overlay = document.getElementById('overlay');
  var BLANK = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

  // Parse URL params
  function getParam(name) {
    var m = location.search.match(new RegExp('[?&]' + name + '=([^&]*)'));
    return m ? decodeURIComponent(m[1]) : null;
  }
  var HA_URL = getParam('ha_url') || '';
  var HA_TOKEN = getParam('token') || '';
  var WEATHER_ENTITY = getParam('weather') || 'weather.forecast_home';

  // ── Photo loading ──────────────────────────────────────────
  function loadPhoto() {
    photo.classList.remove('visible');
    setTimeout(function() {
      photo.onload = function() { photo.classList.add('visible'); };
      photo.onerror = function() { setTimeout(loadPhoto, 5000); };
      photo.src = '/random?t=' + Date.now();
    }, 1600);
  }

  // ── Clock ──────────────────────────────────────────────────
  function updateClock() {
    var now = new Date();
    document.getElementById('clock').textContent =
      now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    document.getElementById('date').textContent =
      now.toLocaleDateString([], { weekday: 'long', month: 'long', day: 'numeric' });
  }

  // ── Anti-burn-in bounce (1px/sec drift) ────────────────────
  var bx = 40, by = 40, bdx = 1, bdy = 0.7;
  setInterval(function() {
    var ow = overlay.offsetWidth || 200;
    var oh = overlay.offsetHeight || 150;
    var maxX = window.innerWidth - ow - 20;
    var maxY = window.innerHeight - oh - 20;
    bx += bdx; by += bdy;
    if (bx <= 20 || bx >= maxX) bdx = -bdx;
    if (by <= 20 || by >= maxY) bdy = -bdy;
    bx = Math.max(20, Math.min(bx, maxX));
    by = Math.max(20, Math.min(by, maxY));
    overlay.style.left = bx + 'px';
    overlay.style.top = by + 'px';
  }, 1000);

  // ── Weather (optional, requires HA) ────────────────────────
  function fetchWeather() {
    if (!HA_URL || !HA_TOKEN) return;
    var headers = { 'Authorization': 'Bearer ' + HA_TOKEN, 'Content-Type': 'application/json' };

    // Current weather
    fetch(HA_URL + '/api/states/' + WEATHER_ENTITY, { headers: headers })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var a = data.attributes || {};
        var weatherEl = document.getElementById('weather');
        weatherEl.innerHTML = '<span class="temp">' + Math.round(a.temperature || 0) + '&deg;</span> ' + (data.state || '');
        weatherEl.style.display = 'block';
      })
      .catch(function() {});

    // Forecast
    fetch(HA_URL + '/api/services/weather/get_forecasts', {
      method: 'POST',
      headers: headers,
      body: JSON.stringify({ type: 'daily', entity_id: WEATHER_ENTITY })
    })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        var forecasts = (data && data[WEATHER_ENTITY] && data[WEATHER_ENTITY].forecast) || [];
        if (forecasts.length === 0) return;
        var days = forecasts.slice(0, 3);
        var html = '';
        var dayNames = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
        for (var i = 0; i < days.length; i++) {
          var d = new Date(days[i].datetime);
          var hi = Math.round(days[i].temperature || 0);
          var lo = Math.round(days[i].templow || 0);
          html += '<span>' + dayNames[d.getDay()] + ' ' + hi + '/' + lo + '&deg;</span>';
        }
        var forecastEl = document.getElementById('forecast');
        forecastEl.innerHTML = html;
        forecastEl.style.display = 'block';
      })
      .catch(function() {});
  }

  // ── Init ───────────────────────────────────────────────────
  loadPhoto();
  setInterval(loadPhoto, REFRESH * 1000);
  updateClock();
  setInterval(updateClock, 30000);
  fetchWeather();
  setInterval(fetchWeather, 300000); // refresh weather every 5 min
</script>
</body>
</html>"""


class PhotoHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # Suppress access logs

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/")

        if path == "" or path == "/index.html":
            self.serve_html()
        elif path == "/random":
            self.serve_random(parsed)
        elif path.startswith("/frigate") and FRIGATE_URL:
            self.proxy_frigate(parsed)
        elif path.startswith("/ha/"):
            self.serve_ha(path)
        elif path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_error(404)

    def serve_ha(self, path):
        """Serve pre-formatted HA data as plain text."""
        handlers = {
            "/ha/weather": ha_weather,
            "/ha/forecast": ha_forecast,
            "/ha/thermostat": ha_thermostat,
            "/ha/event": ha_next_event,
        }
        fn = handlers.get(path)
        if not fn:
            self.send_error(404)
            return
        if not HA_URL or not HA_TOKEN:
            self.send_error(503, "HA_URL/HA_TOKEN not configured")
            return
        text = fn()
        data = text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def proxy_frigate(self, parsed):
        """Proxy requests to Frigate API. /frigate/foo → FRIGATE_URL/foo"""
        # Strip the /frigate prefix and forward the rest
        downstream = parsed.path[len("/frigate"):]
        if not downstream:
            downstream = "/"
        url = FRIGATE_URL + downstream
        if parsed.query:
            url += "?" + parsed.query
        try:
            req = Request(url)
            resp = urlopen(req, timeout=10)
            data = resp.read()
            ct = resp.headers.get("Content-Type", "application/octet-stream")
            self.send_response(resp.status)
            self.send_header("Content-Type", ct)
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_error(502, "Frigate proxy error: {}".format(e))

    def serve_html(self):
        title_div = '<div class="title">{}</div>'.format(TITLE) if TITLE else ""
        html = HTML_TEMPLATE.replace("REFRESH_PLACEHOLDER", str(REFRESH))
        html = html.replace("TITLE_PLACEHOLDER", title_div)
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        self.wfile.write(html.encode())

    def serve_random(self, parsed):
        photos = get_photos()
        if not photos:
            self.send_error(503, "No photos found in {}".format(PHOTO_DIR))
            return

        path = random.choice(photos)
        params = parse_qs(parsed.query)

        # Optional resize
        if "w" in params or "h" in params:
            max_w = int(params.get("w", [1280])[0])
            max_h = int(params.get("h", [800])[0])
            data, ct = resize_image(path, max_w, max_h)
            if data:
                self.send_response(200)
                self.send_header("Content-Type", ct)
                self.send_header("Cache-Control", "no-cache, no-store")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                return

        # Serve original file
        ct = mimetypes.guess_type(path)[0] or "application/octet-stream"
        try:
            with open(path, "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", ct)
            self.send_header("Cache-Control", "no-cache, no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except OSError:
            self.send_error(500, "Failed to read file")


if __name__ == "__main__":
    photos = get_photos()
    print(f"photoframe-server: {len(photos)} photos in {PHOTO_DIR}, port {PORT}, refresh {REFRESH}s")
    if not photos:
        print(f"WARNING: no images found in {PHOTO_DIR}", file=sys.stderr)

    class ThreadingHTTPServer(ThreadingMixIn, HTTPServer):
        daemon_threads = True

    server = ThreadingHTTPServer(("0.0.0.0", PORT), PhotoHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()
