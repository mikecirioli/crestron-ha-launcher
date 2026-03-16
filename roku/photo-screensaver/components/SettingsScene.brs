' Copyright (c) 2026 Mike Cirioli. Licensed under CC BY-NC-SA 4.0.
' https://creativecommons.org/licenses/by-nc-sa/4.0/

sub init()
    m.SERVER_URL = "http://192.168.1.245:8099"
    m.BLACKLIST = ["driveway", "armory", "critter", "frontPorch"]

    m.modeList = m.top.findNode("modeList")
    m.loading = m.top.findNode("loading")

    ' Load saved settings from registry
    sec = CreateObject("roRegistrySection", "settings")
    m.savedMode = sec.Read("mode")
    if m.savedMode <> "camera" then m.savedMode = "photo"
    m.savedCamera = sec.Read("camera")
    if m.savedCamera = "" then m.savedCamera = "cycle"

    ' Options map: index -> {mode, camera}
    ' 0 = Photo Frame
    ' 1 = Cycle all cameras
    ' 2+ = individual cameras (populated after fetch)
    m.options = []
    m.options.push({ mode: "photo", camera: "" })
    m.options.push({ mode: "camera", camera: "cycle" })

    ' Set initial selection
    if m.savedMode = "photo"
        m.modeList.checkedItem = 0
    else if m.savedCamera = "cycle"
        m.modeList.checkedItem = 1
    else
        ' Will restore after camera list loads
        m.modeList.checkedItem = 1
    end if

    m.modeList.setFocus(true)
    m.modeList.observeField("checkedItem", "onSelectionChanged")

    ' Fetch camera list to add individual camera options
    m.loading.visible = true
    fetchCameraList()
end sub

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
    m.loading.visible = false
    if text = invalid or text = "" then return

    json = ParseJSON(text)
    if json = invalid or type(json) <> "roArray" then return

    ' Get current content and add camera entries
    content = m.modeList.content
    savedIdx = -1

    for each name in json
        ' Skip blacklisted cameras
        skip = false
        for each bl in m.BLACKLIST
            if LCase(name) = LCase(bl) then skip = true
        end for
        if skip then goto nextCam

        item = content.createChild("ContentNode")
        item.title = "Camera — " + name

        opt = { mode: "camera", camera: name }
        m.options.push(opt)

        ' Check if this is the saved selection
        if m.savedMode = "camera" and m.savedCamera = name
            savedIdx = m.options.count() - 1
        end if

        nextCam:
    end for

    ' Restore saved individual camera selection
    if savedIdx >= 0
        m.modeList.checkedItem = savedIdx
    end if
end sub

sub onSelectionChanged()
    idx = m.modeList.checkedItem
    if idx < 0 or idx >= m.options.count() then return

    opt = m.options[idx]
    sec = CreateObject("roRegistrySection", "settings")
    sec.Write("mode", opt.mode)
    sec.Write("camera", opt.camera)
    sec.Flush()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    return false
end function
