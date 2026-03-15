# Roku Screensavers

Two sideloadable Roku screensaver channels that connect to a
[photoframe-server](../photoframe-server/) instance.

## Channels

### photo-screensaver
Displays random photos with crossfade transitions. Equivalent to the
Crestron screensaver — floating clock overlay with rotating data chips
(weather, calendar, thermostat, forecast).

### camera-screensaver
Cycles through Frigate camera snapshots via the photoframe-server's
`/frigate/api/<camera>/latest.jpg` proxy. Includes the same floating
overlay and data chip rotation. Camera name shown in the top-left corner.

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

## go2rtc (Future)

The camera screensaver currently uses Frigate's detection stream
snapshots (`/api/<cam>/latest.jpg`), which are lower resolution.
A future update will optionally use go2rtc for full-resolution
camera snapshots.
