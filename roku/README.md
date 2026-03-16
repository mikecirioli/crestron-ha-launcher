# Roku Screensavers

Two sideloadable Roku screensaver channels that connect to a
[photoframe-server](../photoframe-server/) instance.

## Channels

### photo-screensaver
Displays random photos with crossfade transitions. Equivalent to the
Crestron screensaver — floating clock overlay with rotating data chips
(weather, calendar, thermostat, forecast).

### camera-screensaver
Cycles through camera snapshots via the photoframe-server's
`/camera/<name>` endpoint. Uses thingino's direct ISP snapshot for
near-realtime frames (~230ms). Includes the same floating overlay
and data chip rotation. Camera name shown in the top-left corner.

## Configuration

Edit the constants at the top of each channel's
`components/ScreensaverScene.brs`:

| Constant | Default | Description |
|----------|---------|-------------|
| `SERVER_URL` | `http://192.168.1.245:8099` | photoframe-server base URL |
| `PHOTO_FIT` | `scaleToFit` | `scaleToFit` = contain (black bars), `scaleToZoom` = fill/crop |
| `PHOTO_SEC` / `CYCLE_SEC` | 30 / 10 | Seconds between image changes |
| `DATA_SEC` | 120 | Seconds between data chip rotation |
| `cameras` | *(camera-screensaver only)* | Array of Frigate camera names |
| `dataSources` | `/ha/weather`, etc. | Data endpoints to cycle through |

## Sideloading

1. **Enable Developer Mode** on your Roku: press Home 3x, Up 2x, Right,
   Left, Right, Left, Right. Note the IP and set a password.

2. **Package the channel** — zip the channel folder contents (manifest
   must be at the zip root):
   ```bash
   cd roku/photo-screensaver
   zip -r ../photo-screensaver.zip .
   ```

3. **Upload** — open `http://<roku-ip>` in a browser, log in with the
   dev password, and upload the zip via the Installer page.

4. The screensaver appears in **Settings > Theme > Screensavers**.

## Placeholder Images

Each channel needs `images/icon.png` (336x210 HD) and
`images/splash.jpg` (1920x1080). For sideloading these can be any
valid image of the right size — they're only shown in the Roku UI,
not during the screensaver itself.

## Camera Snapshots

The camera screensaver uses photoframe-server's `/camera/<name>`
endpoint, which fetches frames directly from thingino cameras'
`/image.jpg` ISP endpoint (~230ms per frame, full 1920x1080).

A background polling thread starts on first request and auto-stops
after 30 seconds of inactivity to conserve resources. Camera
discovery uses `/camera/list` (populated from go2rtc stream names
plus any hardcoded cameras in server.py).

Camera configs are currently hardcoded in `server.py`'s `_CAMERAS`
dict. Future: accept a `CAMERAS` JSON env var for easy multi-camera
setup without code changes.
