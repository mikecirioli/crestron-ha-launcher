' ============================================================
' Camera Screensaver for Roku
' ============================================================
' Cycles through Frigate camera snapshots with a floating
' clock overlay and rotating data chips.
'
' Configuration: edit the constants below.
' ============================================================

sub init()
    ' -- Configuration ──────────────────────────────────────────
    ' Only this section needs editing for your setup.
    m.SERVER_URL  = "http://192.168.1.245:8099"
    m.SNAP_H      = 1080       ' snapshot height param
    m.CYCLE_SEC   = 10         ' seconds between camera changes
    m.DATA_SEC    = 120        ' seconds between data chip rotation
    m.PHOTO_FIT   = "scaleToFit"  ' "scaleToFit" = contain, "scaleToZoom" = fill/crop

    ' Camera list — each cycle shows the next one
    ' These are Frigate camera names; snapshots fetched via
    ' photoframe-server's /frigate/api/<name>/latest.jpg proxy
    m.cameras = [
        "frontDoor",
        "backYard",
        "driveway",
        "garage",
        "sideYard",
        "frontPorch",
        "basementStairs"
    ]

    ' Data sources — each cycle shows the next one
    m.dataSources = [
        "/ha/weather",
        "/ha/event",
        "/ha/thermostat",
        "/ha/forecast"
    ]
    ' -- End configuration ──────────────────────────────────────

    ' Camera state
    m.camIndex = 0
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
    m.camLabel  = m.top.findNode("camLabel")
    m.camLabelBg = m.top.findNode("camLabelBg")

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

    ' Set up and start timers
    m.photoTimer = m.top.findNode("photoTimer")
    m.photoTimer.duration = m.CYCLE_SEC
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

    ' Initial render
    updateClock()
    loadNextCamera()
    fetchNextData()
end sub

' -- Camera snapshot loading ───────────────────────────────

sub loadNextCamera()
    if m.cameras.count() = 0 then return

    cam = m.cameras[m.camIndex]
    m.camIndex = (m.camIndex + 1) mod m.cameras.count()

    ' Update camera name label
    m.camLabel.text = cam
    labelRect = m.camLabel.boundingRect()
    m.camLabelBg.width = labelRect.width + 24

    ts = CreateObject("roDateTime")
    url = m.SERVER_URL + "/frigate/api/" + cam + "/latest.jpg?h=" + m.SNAP_H.toStr() + "&t=" + ts.asSeconds().toStr()

    if m.front = "a"
        m.photoB.uri = url
    else
        m.photoA.uri = url
    end if
end sub

sub onPhotoLoadA(event as object)
    if event.getData() = "ready"
        m.fadeInA.control = "start"
        m.fadeOutB.control = "start"
        m.front = "a"
    end if
end sub

sub onPhotoLoadB(event as object)
    if event.getData() = "ready"
        m.fadeInB.control = "start"
        m.fadeOutA.control = "start"
        m.front = "b"
    end if
end sub

sub onPhotoTimer()
    loadNextCamera()
end sub

' -- Clock overlay ─────────────────────────────────────────

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

' -- Rotating data chips ───────────────────────────────────

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
    m.dataTask = task  ' prevent GC
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

' -- Overlay sizing ────────────────────────────────────────

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

' -- Anti-burn-in bounce ───────────────────────────────────

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
