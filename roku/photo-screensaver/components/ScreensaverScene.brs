' Copyright (c) 2026 Mike Cirioli. Licensed under CC BY-NC-SA 4.0.
' https://creativecommons.org/licenses/by-nc-sa/4.0/
'
' ============================================================
' 3 Bad Dogs Screensaver for Roku
' ============================================================
' Two modes (selectable via screensaver settings):
'   "photo"  — random photos with crossfade from photoframe-server
'   "camera" — live camera snapshots (near-realtime via thingino)
'
' Both modes share the floating clock overlay with rotating
' data chips (weather, calendar, thermostat, forecast).
'
' Configuration: edit the constants below.
' ============================================================

sub init()
    ' ── Configuration ──────────────────────────────────────────
    m.SERVER_URL  = "http://192.168.1.245:8099"
    m.PHOTO_W     = 1920
    m.PHOTO_H     = 1080
    m.PHOTO_SEC   = 30       ' seconds between photo changes
    m.CAMERA_SEC  = 1        ' seconds between camera snapshot refreshes
    m.DATA_SEC    = 120      ' seconds between data chip rotation
    m.PHOTO_FIT   = "scaleToFit"

    m.CYCLE_SEC   = 5        ' seconds per camera when cycling
    m.cameraName  = "gatetown"  ' fallback default
    m.BLACKLIST   = ["driveway"]

    ' Data sources — each cycle shows the next one
    m.dataSources = [
        "/ha/weather",
        "/ha/event",
        "/ha/thermostat",
        "/ha/forecast"
    ]
    ' ── End configuration ──────────────────────────────────────

    ' Read saved settings from registry
    sec = CreateObject("roRegistrySection", "settings")
    m.mode = sec.Read("mode")
    if m.mode <> "camera" then m.mode = "photo"

    ' Camera selection: specific camera name or "cycle"
    savedCamera = sec.Read("camera")
    if savedCamera <> "" then m.cameraName = savedCamera
    m.cycleMode = (m.cameraName = "cycle")
    m.cameraList = []
    m.cameraIndex = 0
    m.cycleCounter = 0

    ' Photo state
    m.front = "a"
    m.photoA = m.top.findNode("photoA")
    m.photoB = m.top.findNode("photoB")
    m.photoA.loadDisplayMode = m.PHOTO_FIT
    m.photoB.loadDisplayMode = m.PHOTO_FIT

    ' Overlay refs
    m.overlay   = m.top.findNode("overlay")
    m.overlayBg = m.top.findNode("overlayBg")
    m.clock     = m.top.findNode("clock")
    m.dateLabel = m.top.findNode("dateLabel")
    m.dataChip  = m.top.findNode("dataChip")

    ' Crossfade animation refs
    m.fadeInA  = m.top.findNode("fadeInA")
    m.fadeOutA = m.top.findNode("fadeOutA")
    m.fadeInB  = m.top.findNode("fadeInB")
    m.fadeOutB = m.top.findNode("fadeOutB")

    ' Bounce state (anti-burn-in)
    m.bx = 100.0 : m.by = 100.0
    m.bdx = 1.0  : m.bdy = 0.7
    m.overlayW = 420 : m.overlayH = 160

    ' Data chip rotation state
    m.dataIndex = 0

    ' Observe photo load status for crossfade trigger
    m.photoA.observeField("loadStatus", "onPhotoLoadA")
    m.photoB.observeField("loadStatus", "onPhotoLoadB")

    ' Set up photo/camera timer based on mode
    m.photoTimer = m.top.findNode("photoTimer")
    if m.mode = "camera"
        m.photoTimer.duration = m.CAMERA_SEC
    else
        m.photoTimer.duration = m.PHOTO_SEC
    end if
    m.photoTimer.observeField("fire", "onPhotoTimer")
    m.photoTimer.control = "start"

    m.clockTimer = m.top.findNode("clockTimer")
    m.clockTimer.observeField("fire", "onClockTimer")
    m.clockTimer.control = "start"

    m.dataTimer = m.top.findNode("dataTimer")
    m.dataTimer.duration = m.DATA_SEC
    m.dataTimer.observeField("fire", "onDataTimer")
    m.dataTimer.control = "start"

    m.bounceTimer = m.top.findNode("bounceTimer")
    m.bounceTimer.observeField("fire", "onBounce")
    m.bounceTimer.control = "start"

    ' Camera mode: both posters opaque, Z-order handles visibility
    ' photoB (on top) is the primary display, photoA is the backdrop
    if m.mode = "camera"
        m.photoA.opacity = 1.0
        m.photoB.opacity = 1.0
        ' If cycle mode, fetch camera list before first image
        if m.cycleMode
            fetchCameraList()
        end if
    end if

    ' Initial render
    updateClock()
    loadNextImage()
    fetchNextData()
end sub

' ── Image loading (photo or camera) ──────────────────────

sub loadNextImage()
    ts = CreateObject("roDateTime")
    if m.mode = "camera"
        ' Don't load until we have a real camera name
        if m.cycleMode and m.cameraList.count() = 0 then return

        ' Camera mode: always load into photoB (on top in Z-order).
        ' While loading, photoA shows through with previous frame = no flicker.
        ' When ready, photoB covers photoA seamlessly.
        url = m.SERVER_URL + "/camera/" + m.cameraName + "?t=" + ts.asSeconds().toStr()
        m.photoB.uri = url
    else
        ' Photo mode: load into back buffer for crossfade
        url = m.SERVER_URL + "/random?w=" + m.PHOTO_W.toStr() + "&h=" + m.PHOTO_H.toStr() + "&t=" + ts.asSeconds().toStr()
        if m.front = "a"
            m.photoB.uri = url
        else
            m.photoA.uri = url
        end if
    end if
end sub

sub onPhotoLoadA(event as object)
    if event.getData() = "ready"
        if m.mode = "camera" then return
        m.fadeInA.control = "start"
        m.fadeOutB.control = "start"
        m.front = "a"
    end if
end sub

sub onPhotoLoadB(event as object)
    if event.getData() = "ready"
        if m.mode = "camera"
            ' Sync photoA (behind) to current frame so it's the backdrop for next load
            m.photoA.uri = m.photoB.uri
            return
        end if
        m.fadeInB.control = "start"
        m.fadeOutA.control = "start"
        m.front = "b"
    end if
end sub

sub onPhotoTimer()
    ' In cycle mode, advance camera every CYCLE_SEC seconds
    if m.cycleMode and m.cameraList.count() > 0
        m.cycleCounter = m.cycleCounter + 1
        cycleTicks = m.CYCLE_SEC / m.CAMERA_SEC
        if cycleTicks < 1 then cycleTicks = 1
        if m.cycleCounter >= cycleTicks
            m.cycleCounter = 0
            m.cameraIndex = (m.cameraIndex + 1) mod m.cameraList.count()
            m.cameraName = m.cameraList[m.cameraIndex]
        end if
    end if
    loadNextImage()
end sub

' ── Camera list for cycle mode ───────────────────────────

sub fetchCameraList()
    ts = CreateObject("roDateTime")
    url = m.SERVER_URL + "/camera/list?t=" + ts.asSeconds().toStr()
    task = CreateObject("roSGNode", "HttpTask")
    task.observeField("response", "onCameraListResponse")
    task.request = { url: url }
    task.control = "run"
    m.cameraListTask = task
end sub

sub onCameraListResponse(event as object)
    text = event.getData()
    if text = invalid or text = "" then return

    json = ParseJSON(text)
    if json = invalid or type(json) <> "roArray" or json.count() = 0 then return

    ' Filter blacklisted cameras
    filtered = []
    for each name in json
        skip = false
        for each bl in m.BLACKLIST
            if LCase(name) = LCase(bl) then skip = true
        end for
        if not skip then filtered.push(name)
    end for

    if filtered.count() = 0 then return

    m.cameraList = filtered
    m.cameraIndex = 0
    m.cameraName = m.cameraList[0]
    m.cycleCounter = 0

    ' Now start loading images
    loadNextImage()
end sub

' ── Clock overlay ──────────────────────────────────────────

sub updateClock()
    dt = CreateObject("roDateTime")
    dt.toLocalTime()

    hours = dt.getHours()
    ampm = "AM"
    if hours >= 12 then ampm = "PM"
    if hours > 12 then hours = hours - 12
    if hours = 0 then hours = 12
    mins = dt.getMinutes()
    minStr = mins.toStr()
    if mins < 10 then minStr = "0" + minStr
    m.clock.text = hours.toStr() + ":" + minStr + " " + ampm

    days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    dow = dt.getDayOfWeek()
    mon = dt.getMonth() - 1
    day = dt.getDayOfMonth()

    dayName = "Sunday"
    if dow >= 0 and dow < days.count() then dayName = days[dow]
    monName = "January"
    if mon >= 0 and mon < months.count() then monName = months[mon]

    m.dateLabel.text = dayName + ", " + monName + " " + day.toStr()
end sub

sub onClockTimer()
    updateClock()
end sub

' ── Rotating data chips ────────────────────────────────────

sub fetchNextData()
    if m.dataSources.count() = 0 then return

    path = m.dataSources[m.dataIndex]
    m.dataIndex = (m.dataIndex + 1) mod m.dataSources.count()

    ts = CreateObject("roDateTime")
    url = m.SERVER_URL + path + "?t=" + ts.asSeconds().toStr()

    task = CreateObject("roSGNode", "HttpTask")
    task.observeField("response", "onDataResponse")
    task.request = { url: url }
    task.control = "run"
    m.dataTask = task
end sub

sub onDataResponse(event as object)
    text = event.getData()
    if text <> invalid and text <> ""
        m.dataChip.text = text
    end if
    resizeOverlay()
end sub

sub onDataTimer()
    fetchNextData()
end sub

' ── Overlay sizing ─────────────────────────────────────────

sub resizeOverlay()
    content = m.top.findNode("overlayContent")
    rect = content.boundingRect()
    w = rect.width + 48
    h = rect.height + 32
    if w < 200 then w = 200
    if h < 100 then h = 100
    m.overlayBg.width = w
    m.overlayBg.height = h
    m.overlayW = w
    m.overlayH = h
end sub

' ── Anti-burn-in bounce ────────────────────────────────────

sub onBounce()
    maxX = 1920 - m.overlayW - 20
    maxY = 1080 - m.overlayH - 20

    m.bx = m.bx + m.bdx
    m.by = m.by + m.bdy

    if m.bx <= 20 or m.bx >= maxX then m.bdx = -m.bdx
    if m.by <= 20 or m.by >= maxY then m.bdy = -m.bdy

    if m.bx < 20 then m.bx = 20
    if m.bx > maxX then m.bx = maxX
    if m.by < 20 then m.by = 20
    if m.by > maxY then m.by = maxY

    m.overlay.translation = [m.bx, m.by]
end sub
