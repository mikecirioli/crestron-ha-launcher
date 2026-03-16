# 3 Bad Dogs — Roku Screensaver

A sideloadable Roku screensaver channel with two modes, selectable via the
screensaver settings screen:

- **Photo Frame** — random photos with crossfade transitions from
  [photoframe-server](../photoframe-server/)
- **Camera View** — live camera snapshots from thingino cameras, either a
  single camera or cycling through all available cameras (5s each)

Both modes share a floating clock overlay with rotating data chips
(weather, calendar, thermostat, forecast) for anti-burn-in.

## Configuration

Edit the constants at the top of `components/ScreensaverScene.brs`:

| Constant | Default | Description |
|----------|---------|-------------|
| `SERVER_URL` | `http://192.168.1.245:8099` | photoframe-server base URL |
| `PHOTO_FIT` | `scaleToFit` | `scaleToFit` = contain (black bars), `scaleToZoom` = fill/crop |
| `PHOTO_SEC` | `30` | Seconds between photo changes |
| `CAMERA_SEC` | `1` | Seconds between camera frame refreshes |
| `CYCLE_SEC` | `5` | Seconds per camera when cycling |
| `DATA_SEC` | `120` | Seconds between data chip rotation |
| `BLACKLIST` | `["driveway", ...]` | Camera names to exclude from list/cycle |
| `dataSources` | `/ha/weather`, etc. | Data endpoints to cycle through |

## Settings Screen

The screensaver settings (accessible via Settings > Screensavers > 3 Bad Dogs)
present a single radio button list:

- **Photo Frame** — random photos with crossfade
- **Camera — cycle all cameras (5s each)** — rotates through available cameras
- **Camera — \<name\>** — individual camera options, populated dynamically from
  the server's `/camera/list` endpoint

Selection is persisted in the Roku registry.

## Sideloading

1. **Enable Developer Mode** on your Roku: press Home 3x, Up 2x, Right,
   Left, Right, Left, Right. Note the IP and set a password.

2. **Package the channel** — zip the channel folder contents (manifest
   must be at the zip root):
   ```bash
   cd roku/photo-screensaver
   zip -r /tmp/photo-screensaver.zip .
   ```

3. **Upload** — open `http://<roku-ip>` in a browser, log in with the
   dev password, and upload the zip via the Installer page.

4. The screensaver appears in **Settings > Theme > Screensavers**.

## Camera Snapshots

Camera mode uses photoframe-server's `/camera/<name>` endpoint, which
fetches frames directly from thingino cameras via `/x/ch0.jpg` (~230ms
per frame, full 1920x1080). This is much faster than go2rtc's frame API
(~4s per frame due to H.264 keyframe waiting).

Camera rendering uses a flicker-free double-buffered Z-order technique:
both Poster nodes stay at full opacity, new frames load into the top
layer (photoB), and the bottom layer (photoA) shows the previous frame
as a backdrop during loading.

Camera configs (IP, credentials) are set via the `CAMERAS` env var in
photoframe-server's docker-compose — see the
[photoframe-server README](../photoframe-server/README.md#camera-snapshots-thingino).

## Technical Notes

- Entry point: `RunScreenSaver()` in `source/main.brs` (NOT `Main()` — Roku
  won't list it as a screensaver otherwise)
- Settings entry point: `RunUserInterface()` — shown when user selects the
  screensaver settings option
- **Font gotcha**: `<Font uri="" />` in XML silently crashes init() — omit Font
  nodes entirely or bundle a real TTF file
- Branding: "3 Bad Dogs" — master image at `roku/assets/3-bad-dogs.png`

## License

CC BY-NC-SA 4.0 — see [LICENSE](../LICENSE)
