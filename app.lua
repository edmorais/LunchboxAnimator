-- ===========================================================================
--  LUNCHBOX - App
--  State, frame operations, playback, export, input, and the drawing of the
--  room: the monitor on its stand, the filmstrip deck and the control deck,
--  in VideoLab's style.
--
--  Everything is drawn in logical units. The layout module turns the window
--  size into rectangles; app.resize applies them to the widgets, so drawing
--  and hit-testing always agree.
-- ===========================================================================
local theme   = require("theme")
local widgets = require("widgets")
local source  = require("source")
local storage = require("storage")
local layout  = require("layout")
local Take    = require("take")

local lg, C = love.graphics, theme.C
local app = {}

local FPS_OPTS = { 8, 12, 15, 24 }
local PK_DEV_ROWS, PK_MODE_ROWS = layout.PK_DEV_ROWS, layout.PK_MODE_ROWS
local PK_DEV_RH, PK_MODE_RH = layout.PK_DEV_RH, layout.PK_MODE_RH

-- ----------------------------------------------------------------- state --
local S = {
    mode = "live",                       -- live | review | play
    flipHold = false,
    shutter = 0,
    lastAuto = 0,
    playFrom = 0, playTo = 0, playDir = 1, playAccum = 0,
    imgX = 0, imgY = 0, imgW = 0, imgH = 0,
    exp = { active = false, idx = 0, total = 0, dir = "", label = "", fallback = false },
    helpOpen = false,
    confirmMsg = nil, confirmBody = nil, confirmId = nil,
    toastMsg = "", toastUntil = 0, status = "",
    devices = {}, curDev = -1, curMode = 1,
    pickerOpen = false, pickerScanned = false, pendingScan = false, scanAt = 0,
    adjustOpen = false, adjust = { rows = {}, drag = nil },
    pickSel = 1, pickMode = 1, pickTop = 0, modeTop = 0,   -- pickSel 1 = test pattern
    dragging = nil,
    frameNum = 0,
    mx = -1, my = -1,                    -- mouse, logical units
    cursor = nil,
}
app.S = S

local take, W = nil, {}
local L = nil                            -- current layout
local winW, winH = theme.REF_W, theme.REF_H
local aspectNow = theme.CAM_W / theme.CAM_H
local diffShader
local staticCv, glassCv                  -- baked layers, rebuilt on relayout

local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
local inside = layout.inside

-- ------------------------------------------------------------- accessors --
local function fps()       return FPS_OPTS[W.segFps.sel] end
local function exposures() return W.segExp.sel end
local function onionMode() return W.segOnion.sel - 1 end   -- 0 off, 1, 3, diff
app.fps = fps

local function toast(m)
    S.toastMsg = m
    S.status = m
    S.toastUntil = love.timer.getTime() + 2.4
end
app.toast = toast

local function sourceName()
    if source.isSim() or S.curDev < 1 or S.curDev > #S.devices then return "TEST CARD" end
    return string.upper(S.devices[S.curDev].name)
end
app.sourceName = sourceName

local function flipping() return S.flipHold or (W.btnFlip and W.btnFlip.down) end

-- ======================================================================= --
--  LOAD + LAYOUT                                                          --
-- ======================================================================= --
function app.load()
    lg.setDefaultFilter("linear", "linear")
    lg.setLineStyle("smooth")
    theme.initShaders()
    theme.loadFonts()
    take = Take.new()
    app.take = take

    -- LÖVE has no DIFFERENCE blend mode, but it has shaders, so the onion
    -- skin's difference view is done on the GPU.
    diffShader = lg.newShader [[
        extern Image other;
        extern float otherFlip;
        vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
            vec2 o = vec2(mix(tc.x, 1.0 - tc.x, otherFlip), tc.y);
            vec4 a = Texel(tex, tc);
            vec4 b = Texel(other, o);
            return vec4(abs(a.rgb - b.rgb), color.a);
        }
    ]]

    source.load()
    app.buildUI()
    take.number = storage.nextTakeNumber()      -- never overwrite an earlier session
    S.lastAuto = love.timer.getTime()
    app.resize(lg.getDimensions())
    toast("TEST CARD - PRESS SOURCE TO PICK A CAMERA")
end

function app.buildUI()
    local list, deckGroup = {}, {}
    local function add(w, inDeck)
        w.emit = app.action
        list[#list + 1] = w
        if inDeck then deckGroup[#deckGroup + 1] = w end
        return w
    end
    local B, T, Sg, F = widgets.Btn.new, widgets.Toggle.new, widgets.Segmented.new, widgets.Fader.new

    -- RECORD
    W.btnCapture = add(B("CAPTURE", "CAPTURE", { dark = true, ink = C.RED, subInk = C.INK_DIM,
                                                     glyph = "rec", sub = "SPACE", size = 16 }), true)
    W.btnDelete  = add(B("DELETE", "DELETE", { dark = true, glyph = "trash" }), true)
    W.btnUndo    = add(B("UNDO", "UNDO", { dark = true, glyph = "undo" }), true)
    -- TRANSPORT
    W.btnStepB    = add(B("STEPB", "", { dark = true, glyph = "prev", lbl = "BACK", repeats = true }), true)
    W.btnFlip     = add(B("", "", { dark = true, glyph = "flip", lbl = "FLIP" }), true)  -- hold to compare
    W.btnStepF    = add(B("STEPF", "", { dark = true, glyph = "next", lbl = "FWD", repeats = true }), true)
    W.btnPlay     = add(B("PLAY", "", { dark = true, glyph = "play", lbl = "PLAY" }), true)
    W.btnPlayLast = add(B("PLAYLAST", "", { dark = true, glyph = "last", lbl = "LAST" }), true)
    W.btnStop     = add(B("STOP", "", { dark = true, glyph = "stop", lbl = "STOP" }), true)
    W.tglLoop     = add(T("LOOP", "LOOP", false), true)
    W.tglPing     = add(T("PING", "PING-PONG", false), true)
    W.tglAutoLive = add(T("AUTOLIVE", "AUTO LIVE", true), true)
    -- TIMING
    W.segFps = add(Sg("FPS", "FRAME RATE", { "8", "12", "15", "24" }, 2, { capStyle = "lbl" }), true)
    W.segExp = add(Sg("EXP", "EXPOSURE", { "1", "2", "3" }, 1,
                      { capStyle = "lbl", subs = { "ONES", "TWOS", "THREES" } }), true)
    W.sldShort    = add(F("SHORT", "PLAY LAST", 4, 48, 12, true, " FR"), true)
    W.tglLapse    = add(T("LAPSE", "LAPSE", false), true)
    W.sldInterval = add(F("INTERVAL", "TIME-LAPSE INTERVAL", 0.5, 15, 3, false, " S"), true)
    -- ONION SKIN
    W.segOnion = add(Sg("ONION", nil, { "OFF", "1", "3", "DIFF" }, 2), true)
    W.sldMix   = add(F("MIX", "MIX", 0, 100, 45, true, "%"), true)
    -- SYSTEM
    W.jog = add(widgets.Jog.new("JOG"), true)
    W.jog.onStep = function(d) app.step(d) end
    W.btnNew    = add(B("NEWTAKE", "NEW TAKE", { glyph = "new" }), true)
    W.btnExport = add(B("EXPORT", "EXPORT", { glyph = "export" }), true)
    W.btnCam    = add(B("CAMERA", "SOURCE", {}), true)
    W.btnAdjust = add(B("ADJUST", "ADJUST", {}), true)
    W.btnHelp   = add(B("HELP", "?", { size = 16 }), true)
    -- monitor foot, like VideoLab's 4:3 / 16:9 pair
    W.tglMirror = add(T("MIRROR", "MIRROR", false, { dark = true, size = 11 }))
    W.tglGuides = add(T("GUIDES", "GUIDES", false, { dark = true, size = 11 }))
    W.tglOsd    = add(T("OSD", "OSD", true, { dark = true, size = 11 }))
    -- filmstrip
    W.strip = add(widgets.Strip.new("STRIP"))
    W.strip.take = take
    W.strip.onScrub = function(i) app.setPlayhead(i) end

    app.widgets, app.deckGroup = list, deckGroup
    app.W = W
end

--- Window size changed (or first load): work out the scale, re-rasterise
--- fonts if it moved, and lay everything out again.
function app.resize(w, h)
    winW, winH = w, h
    local s, LW, LH = layout.scaleFor(w, h, theme.REF_W, theme.REF_H)
    if s ~= theme.scale or not L then theme.setScale(s) end
    app.LW, app.LH = LW, LH
    app.relayout()
end

function app.relayout()
    L = layout.compute(app.LW, app.LH, aspectNow)
    app.L = L
    local function put(w, r) w:setRect(r.x, r.y, r.w, r.h) end
    put(W.btnCapture, L.capture); put(W.btnDelete, L.delete); put(W.btnUndo, L.undo)
    local tr = { W.btnStepB, W.btnFlip, W.btnStepF, W.btnPlay, W.btnPlayLast, W.btnStop }
    for i, b in ipairs(tr) do put(b, L.trans[i]) end
    put(W.tglLoop, L.loop); put(W.tglPing, L.ping); put(W.tglAutoLive, L.autolive)
    put(W.segFps, L.fps); put(W.segExp, L.exp); put(W.sldShort, L.short)
    put(W.tglLapse, L.lapse); put(W.sldInterval, L.interval)
    put(W.segOnion, L.onion); put(W.sldMix, L.mix)
    put(W.jog, L.jog)
    put(W.btnNew, L.newtake); put(W.btnExport, L.export)
    put(W.btnCam, L.source); put(W.btnAdjust, L.adjust); put(W.btnHelp, L.help)
    put(W.tglMirror, L.mirror); put(W.tglGuides, L.guides); put(W.tglOsd, L.osd)
    put(W.strip, L.strip)
    W.strip:follow()
    app.bake()
end

--- The monitor follows the camera's shape, as VideoLab's does.
local function trackAspect()
    local w, h = source.width(), source.height()
    if w and h and w > 1 and h > 1 then
        local a = w / h
        if math.abs(a - aspectNow) > 0.005 then
            aspectNow = a
            app.relayout()
        end
    end
end

function app.toLogical(x, y)
    return x / theme.scale, y / theme.scale
end

-- ======================================================================= --
--  FRAME OPERATIONS                                                       --
-- ======================================================================= --
function app.doCapture()
    local n = exposures()
    if take:size() + n > theme.MAX_FRAMES then
        toast("BUFFER FULL - EXPORT OR START A NEW TAKE")
        return
    end
    local data = source.grab(W.tglMirror.on)      -- capture what you see
    if not data then toast("NO SOURCE") return end
    take:add(data, n)
    take.playhead = take:size() - 1
    S.mode = "live"
    S.shutter = 1
    W.strip:follow()
    toast(n > 1 and ("CAPTURED x" .. n) or "CAPTURED")
end

function app.doDelete()
    if take:isEmpty() then toast("NOTHING TO DELETE") return end
    local i = clamp(take.playhead, 0, take:size() - 1)
    take:removeAt(i)
    take.playhead = math.min(i, take:size() - 1)
    if take:isEmpty() then take.playhead = -1 S.mode = "live" end
    W.strip:follow()
    toast("DELETED FRAME " .. (i + 1))
end

function app.doUndo()
    if not take:canUndo() then toast("NOTHING TO UNDO") return end
    take:restore()
    W.strip:follow()
    toast("RESTORED")
end

function app.step(d)
    if take:isEmpty() then return end
    S.mode = "review"
    take.playhead = clamp(take.playhead + d, 0, take:size() - 1)
    W.strip:follow()
end

function app.setPlayhead(i)
    if take:isEmpty() then return end
    take.playhead = clamp(i, 0, take:size() - 1)
    S.mode = "review"
    W.strip:follow()
end

function app.goLive()
    S.mode = "live"
    take.playhead = take:size() - 1
    W.strip:follow()
end

function app.newTake()
    take:clear()
    -- advance, but also skip past anything already exported on disk
    take.number = math.max(take.number + 1, storage.nextTakeNumber())
    S.mode = "live"
    W.strip:follow()
    toast("TAKE " .. theme.nf(take.number, 3) .. " - EMPTY")
end

-- ---------------------------------------------------------------- playback --
function app.startPlay(from, to)
    if take:isEmpty() then toast("NOTHING TO PLAY") return end
    S.playFrom = clamp(from, 0, take:size() - 1)
    S.playTo   = clamp(to, 0, take:size() - 1)
    take.playhead = S.playFrom
    S.playDir, S.playAccum = 1, 0
    S.mode = "play"
end

function app.stopPlay()
    if S.mode ~= "play" then return end
    S.mode = W.tglAutoLive.on and "live" or "review"
    if S.mode == "live" then take.playhead = take:size() - 1 end
    W.strip:follow()
end

function app.togglePlay()
    if S.mode == "play" then app.stopPlay() else app.startPlay(0, take:size() - 1) end
end

function app.playLast()
    local n = math.floor(W.sldShort.val)
    app.startPlay(math.max(0, take:size() - n), take:size() - 1)
end

--- Time based, so 12 fps stays 12 fps whatever the window is doing.
local function updatePlayback(dt)
    if S.mode ~= "play" or take:isEmpty() then return end
    S.playAccum = S.playAccum + dt
    local spf = 1 / fps()
    while S.playAccum >= spf do
        S.playAccum = S.playAccum - spf
        take.playhead = take.playhead + S.playDir
        if take.playhead > S.playTo then
            if W.tglPing.on then
                S.playDir = -1
                take.playhead = math.max(S.playFrom, S.playTo - 1)
            elseif W.tglLoop.on then
                take.playhead = S.playFrom
            else
                take.playhead = S.playTo
                app.stopPlay()
                break
            end
        elseif take.playhead < S.playFrom then
            if W.tglLoop.on or W.tglPing.on then
                S.playDir = 1
                take.playhead = S.playFrom
            else
                take.playhead = S.playFrom
                app.stopPlay()
                break
            end
        end
    end
    W.strip:follow()
end

local function updateTimelapse(now)
    if not W.tglLapse.on or S.mode ~= "live" then S.lastAuto = now return end
    if now - S.lastAuto >= W.sldInterval.val then
        S.lastAuto = now
        app.doCapture()
    end
end

-- --------------------------------------------------------------- exporting --
function app.beginExport()
    if take:isEmpty() then toast("NOTHING TO EXPORT") return end
    if S.exp.active then toast("EXPORT ALREADY RUNNING") return end

    local root, fallback = storage.chooseTakesRoot()
    local dir = storage.join(root, "take_" .. theme.nf(take.number, 3))
    if not storage.ensureDir(dir) then
        toast("CANNOT WRITE TO " .. dir)
        return
    end
    S.exp.dir      = dir
    S.exp.label    = "take_" .. theme.nf(take.number, 3)
    S.exp.fallback = fallback
    S.exp.idx, S.exp.total, S.exp.active = 0, take:size(), true
    toast("EXPORTING " .. S.exp.total .. " FRAMES")
end

--- A couple of PNGs per update so the deck never freezes mid-export.
local function tickExport()
    if not S.exp.active then return end
    for _ = 1, theme.SAVES_PER_FRAME do
        if not S.exp.active then break end
        local d = take:data(S.exp.idx)
        if d then
            -- encode in memory, then write outside love.filesystem's sandbox
            local fd = d:encode("png")
            local ok, err = storage.writeFile(
                storage.join(S.exp.dir, "frame_" .. theme.nf(S.exp.idx + 1, 4) .. ".png"),
                fd:getString())
            if not ok then
                S.exp.active = false
                toast("EXPORT FAILED: " .. tostring(err))
                return
            end
        end
        S.exp.idx = S.exp.idx + 1
        if S.exp.idx >= S.exp.total then
            local notes = table.concat({
                "LunchBox take " .. theme.nf(take.number, 3),
                "frames: " .. S.exp.total,
                "rate:   " .. fps() .. " fps",
                "length: " .. theme.nfd(S.exp.total / fps(), 2) .. " s",
                "",
                "assemble with:",
                "ffmpeg -framerate " .. fps() .. " -i frame_%04d.png -c:v libx264 "
                    .. "-pix_fmt yuv420p take_" .. theme.nf(take.number, 3) .. ".mp4",
            }, "\n")
            storage.writeFile(storage.join(S.exp.dir, "take.txt"), notes)
            S.exp.active = false
            toast(S.exp.fallback and "EXPORTED TO SAVE FOLDER - APP FOLDER IS READ-ONLY"
                  or ("EXPORTED " .. string.upper(S.exp.label)))
        end
    end
end

--- Click the cassette: open the takes folder in the system file browser.
function app.openTakesFolder()
    local root = storage.chooseTakesRoot()
    local url = "file:///" .. root:gsub("\\", "/"):gsub("^/", "")
    local ok = pcall(love.system.openURL, url)
    toast(ok and "OPENING TAKES FOLDER" or "COULD NOT OPEN THE TAKES FOLDER")
end

-- ======================================================================= --
--  UPDATE                                                                 --
-- ======================================================================= --
local CURSORS = {}
local function setCursor(kind)
    if S.cursor == kind then return end
    S.cursor = kind
    if not love.mouse.getSystemCursor then return end
    if kind == "arrow" then pcall(love.mouse.setCursor) return end
    if CURSORS[kind] == nil then
        local ok, c = pcall(love.mouse.getSystemCursor, kind)
        CURSORS[kind] = ok and c or false
    end
    if CURSORS[kind] then pcall(love.mouse.setCursor, CURSORS[kind]) end
end

function app.update(dt)
    S.frameNum = S.frameNum + 1
    local now = love.timer.getTime()

    source.update()
    if source.stalled() then
        source.useTestPattern()
        S.curDev = -1
        toast("NO SIGNAL - BACK ON THE TEST CARD")
    end
    trackAspect()

    updateTimelapse(now)
    updatePlayback(dt)
    tickExport()
    S.shutter = math.max(0, S.shutter - dt / 0.22)

    local modal = S.pickerOpen or S.helpOpen or S.confirmMsg
    for _, wd in ipairs(app.deckGroup) do wd.visible = not S.adjustOpen end

    S.mx, S.my = app.toLogical(love.mouse.getPosition())
    local cursor = "arrow"
    for _, wd in ipairs(app.widgets) do
        wd:tick(dt)
        if modal then wd.hot = false else wd:hover(S.mx, S.my) end
        if wd.hot then cursor = wd:cursor() end
    end
    if not modal and cursor == "arrow" then
        if inside(L.screen, S.mx, S.my) then cursor = "crosshair"
        elseif inside(L.cassette, S.mx, S.my) and not S.adjustOpen then cursor = "hand" end
    end
    if S.dragging or S.adjust.drag then cursor = S.cursor end
    setCursor(cursor)

    if S.pendingScan and S.frameNum >= S.scanAt then
        S.pendingScan = false
        app.doScan()
    end
end

-- ======================================================================= --
--  MONITOR                                                                --
-- ======================================================================= --
local function fitInto(iw, ih, r)
    local a = iw / ih
    local w, h = r.w, r.w / a
    if h > r.h then h = r.h; w = r.h * a end
    S.imgW, S.imgH = w, h
    S.imgX, S.imgY = r.x + (r.w - w) * 0.5, r.y + (r.h - h) * 0.5
end

local function drawGuides()
    lg.setLineWidth(1)
    theme.col(C.WHITE, .22)
    for i = 1, 2 do
        lg.line(S.imgX + S.imgW * i / 3, S.imgY, S.imgX + S.imgW * i / 3, S.imgY + S.imgH)
        lg.line(S.imgX, S.imgY + S.imgH * i / 3, S.imgX + S.imgW, S.imgY + S.imgH * i / 3)
    end
    theme.col(C.WHITE, .32)
    lg.rectangle("line", S.imgX + S.imgW * .05, S.imgY + S.imgH * .05, S.imgW * .9, S.imgH * .9)
    local cx, cy = S.imgX + S.imgW * .5, S.imgY + S.imgH * .5
    lg.line(cx - 12, cy, cx + 12, cy)
    lg.line(cx, cy - 12, cx, cy + 12)
end

local function drawOnion()
    local m    = onionMode()
    local mix  = W.sldMix.val / 100
    local base = clamp(take.playhead, 0, take:size() - 1)

    if m == 3 then                                    -- difference, via shader
        local ghost = take:ghost(1, base)
        local liveD = source.drawable()
        if not ghost or not liveD then return end
        local gw, gh = ghost:getDimensions()
        local lw, lh = liveD:getDimensions()
        if gw ~= lw or gh ~= lh then                  -- mixed-resolution take
            theme.drawFit(ghost, S.imgX, S.imgY, S.imgW, S.imgH, false, mix)
            return
        end
        lg.setShader(diffShader)
        diffShader:send("other", ghost)
        diffShader:send("otherFlip", W.tglMirror.on and 1 or 0)
        theme.drawFit(liveD, S.imgX, S.imgY, S.imgW, S.imgH, W.tglMirror.on, mix)
        lg.setShader()
        return
    end

    local layers = (m == 1) and 1 or 3
    for i = 1, layers do
        local idx = base - (i - 1)
        if idx < 0 then break end
        local g = take:ghost(i, idx)
        if g then
            -- stored frames are already mirrored, so ghosts line up as drawn
            theme.drawFit(g, S.imgX, S.imgY, S.imgW, S.imgH, false, mix * (1 - (i - 1) * 0.3))
        end
    end
end

--- The on-screen display, VideoLab's VT323 overlay: what mode we are in and
--- what is set, top left; where we are, top right; messages, bottom left.
local function drawOsd(live)
    local r = L.screen
    local size = clamp(math.floor(r.h * 0.05), 14, 26)
    local lh = size * 0.95 + 1
    local px, py = r.x + r.w * 0.04, r.y + r.h * 0.032

    local title, acc
    if S.mode == "play" then title, acc = "PLAY " .. fps() .. " FPS", C.MODE.play
    elseif flipping() and not take:isEmpty() then title, acc = "LAST FRAME", C.MODE.review
    elseif S.mode == "review" then title, acc = "REVIEW", C.MODE.review
    else title, acc = "LIVE", C.MODE.live end
    local soft = theme.mix(acc, C.WHITE, .45)

    local y = py
    theme.osdLine(size, title, px, y, acc); y = y + lh
    theme.osdLine(size, "TAKE " .. theme.nf(take.number, 3), px, y, soft); y = y + lh
    if exposures() > 1 then
        theme.osdLine(size, "ON " .. ({ "ONES", "TWOS", "THREES" })[exposures()], px, y, soft); y = y + lh
    end
    if live and onionMode() > 0 and not take:isEmpty() then
        theme.osdLine(size, "ONION " .. W.segOnion.opts[W.segOnion.sel] .. " " ..
                      math.floor(W.sldMix.val) .. "%", px, y, soft); y = y + lh
    end
    if W.tglLapse.on and S.mode == "live" then
        local left = math.max(0, W.sldInterval.val - (love.timer.getTime() - S.lastAuto))
        theme.osdLine(size, "LAPSE " .. theme.nfd(left, 1) .. "S", px, y, C.A_INTERLACE); y = y + lh
    end

    local rx = r.x + r.w - r.w * 0.04
    local n = take:isEmpty() and 0 or take.playhead + 1
    theme.osdLine(size, string.format("F%04d/%04d", n, take:size()), rx, py, C.INK, "r")
    theme.osdLine(size, theme.timecode(math.max(0, n - 1), fps()), rx, py + lh, C.INK, "r")

    local by = r.y + r.h - r.h * 0.032 - lh
    local now = love.timer.getTime()
    if now < S.toastUntil and S.toastMsg ~= "" then
        local a = clamp((S.toastUntil - now) / 0.4, 0, 1)
        theme.osdLine(size, S.toastMsg, px, by, C.WHITE, "l", a)
    else
        local line = (source.isSim() and "TEST " or "CAM ") .. sourceName() .. "  " ..
                     source.width() .. "X" .. source.height()
        if W.tglMirror.on then line = line .. "  MIRROR" end
        theme.osdLine(size, theme.trunc("osd", size, line, r.w * 0.8), px, by, C.INK, "l", .85)
    end
end

--- The parts of the monitor that never change: stand, housing, bezel and
--- the printed badge. Drawn into the static layer.
local function drawMonitorStatic()
    local st = L.stand
    local mesh = lg.newMesh({
        { st.x + st.w * .08, st.y, 0, 0, .110, .118, .125, 1 },
        { st.x + st.w * .92, st.y, 0, 0, .110, .118, .125, 1 },
        { st.x + st.w, st.y + st.h, 0, 0, .165, .173, .184, 1 },
        { st.x, st.y + st.h, 0, 0, .165, .173, .184, 1 },
    }, "fan", "static")
    lg.setColor(1, 1, 1, 1)
    lg.draw(mesh)
    mesh:release()

    theme.box(L.monitor.x, L.monitor.y, L.monitor.w, L.monitor.h, theme.S.monitor)
    theme.box(L.bezel.x, L.bezel.y, L.bezel.w, L.bezel.h, theme.S.bezel)
    local r = L.screen
    theme.box(r.x, r.y, r.w, r.h, theme.S.screen)

    local f = L.foot
    local cy = f.y + f.h * 0.5
    theme.col(C.INK)
    local ww = theme.text("mark", 19, "LunchBox", f.x + 6, cy, "l", "c", .01)
    local modelX = f.x + 6 + ww + 10
    local room = L.mirror.x - 14 - modelX
    local model = "VM-2026  PREVIEW MONITOR"
    if theme.textWidth("label", 10, model, .16) > room then model = "VM-2026" end
    if theme.textWidth("label", 10, model, .16) <= room then
        theme.col(C.INK_DIM)
        theme.text("label", 10, model, modelX, cy, "l", "c", .16)
    end
    local lx = L.lamps.x
    theme.col(C.INK_DIM)
    local tw = theme.text("label", 9, "TALLY", lx + 12, cy, "l", "c", .14)
    theme.text("label", 9, "POWER", lx + 12 + tw + 30, cy, "l", "c", .14)
    app.lampX = { lx + 4, lx + 12 + tw + 22 }
end

local function drawMonitor()
    local r = L.screen
    local live = (S.mode == "live" and not flipping())
    local d
    if not live then
        d = take:image(take.playhead)
        if not d then live = true end
    end
    if live then d = source.drawable() end

    theme.clip(r.x, r.y, r.w, r.h)
    if d then
        local iw, ih = d:getDimensions()
        if iw >= 2 and ih >= 2 then
            fitInto(iw, ih, r)
            theme.drawFit(d, S.imgX, S.imgY, S.imgW, S.imgH, live and W.tglMirror.on, 1)
            if live and onionMode() > 0 and not take:isEmpty() then drawOnion() end
            if W.tglGuides.on then drawGuides() end
        end
    end
    theme.clip()
    lg.setColor(1, 1, 1, 1)
    lg.setBlendMode("alpha", "premultiplied")
    lg.draw(glassCv, r.x, r.y)                      -- highlight + vignette, baked
    lg.setBlendMode("alpha")
    if W.tglOsd.on then drawOsd(live) end
    if S.shutter > 0 then
        theme.col(C.WHITE, .82 * S.shutter)
        lg.rectangle("fill", r.x, r.y, r.w, r.h, 6, 6)
    end

    local cy = L.foot.y + L.foot.h * 0.5
    theme.lamp(app.lampX[1], cy, (S.mode == "live") or S.shutter > 0, C.RED)
    theme.lamp(app.lampX[2], cy, true, C.GREEN)
end

-- ======================================================================= --
--  FILMSTRIP DECK                                                         --
-- ======================================================================= --
local function drawFilmDeck()
    local p = L.filmPanel
    local secs = take:size() / fps()
    local right = take:size() .. (take:size() == 1 and " FRAME" or " FRAMES") ..
                  "  " .. theme.nfd(secs, 2) .. " S @ " .. fps()
    theme.panelHead(p.x + 14, p.y + 11, p.w - 28, "TAKE", theme.nf(take.number, 3), C.ACC, right)
end

-- ======================================================================= --
--  CONTROL DECK                                                           --
-- ======================================================================= --
local CHIPS = { C.A_RES, C.A_FPS, C.A_ASPECT, C.A_INTERLACE, C.A_SAMPLING, C.A_DEPTH }

local function drawBrand()
    local b = L.brand
    local cy = b.y + 12
    theme.col(C.INK)
    local ww = theme.text("mark", 24, "LunchBox", b.x, cy, "l", "c", .01)
    for i, c in ipairs(CHIPS) do
        theme.col(c)
        lg.rectangle("fill", b.x + ww + 12 + (i - 1) * 9, cy - 6, 7, 12, 1, 1)
    end
    theme.col(C.INK_DIM)
    theme.text("label", 10.5, "LBX-2026", b.x + b.w, cy - 9, "r", "t", .16)
    theme.text("label", 9, "STOP-MOTION DECK", b.x + b.w, cy + 3, "r", "t", .16)
end

local function drawCassette()
    local r = L.cassette
    local hot = inside(r, S.mx, S.my) and not (S.pickerOpen or S.helpOpen or S.confirmMsg)
    theme.box(r.x, r.y, r.w, r.h, hot and theme.S.cassetteHot or theme.S.cassette)
    local sx, sy, sw = r.x + 12, r.y + 9, r.w - 24
    theme.box(sx, sy, sw, 8, theme.S.slot)
    if hot then
        theme.col(C.VFD, .35)
        lg.setLineWidth(1)
        lg.rectangle("line", sx - .5, sy - .5, sw + 1, 9, 4, 4)
    end
    -- the slot doubles as a gauge: tape used, or export progress
    local f, col
    if S.exp.active then
        f, col = S.exp.idx / math.max(1, S.exp.total), C.GREEN
    else
        f = take:size() / theme.MAX_FRAMES
        col = f > .9 and C.RED or C.VFD
    end
    if f > 0 then
        theme.col(col, .75)
        lg.rectangle("fill", sx + 2, sy + 3, math.max(2, (sw - 4) * f), 2, 1, 1)
    end
    theme.col(C.INK_DIM)
    theme.text("label", 9.5, "TAKE " .. theme.nf(take.number, 3), sx, r.y + 26, "l", "t", .16)
    local right = S.exp.active and ("WRITING " .. S.exp.idx .. "/" .. S.exp.total)
                  or (hot and "OPEN TAKES FOLDER" or (take:size() .. " / " .. theme.MAX_FRAMES .. " FR"))
    theme.text("label", 9.5, right, sx + sw, r.y + 26, "r", "t", .16)
end

local function drawVfd()
    local r = L.vfd
    local x = r.x + 14
    -- annunciators
    local ann = {
        { "LIVE", S.mode == "live" }, { "REVIEW", S.mode == "review" },
        { "PLAY", S.mode == "play" }, { "CAM", not source.isSim() },
        { "LOOP", W.tglLoop.on or W.tglPing.on }, { "LAPSE", W.tglLapse.on },
        { "SAVE", S.exp.active },
    }
    for _, a in ipairs(ann) do
        x = x + theme.vfdText(10.5, a[1], x, r.y + 11, "l", "t", a[2], .08) + 9
    end
    -- frame counter
    local n = take:isEmpty() and 0 or take.playhead + 1
    local bx = r.x + 14
    local bw = theme.vfdText(34, theme.nf(n, 4), bx, r.y + 30, "l", "t", true, .04)
    theme.vfdText(14, "/" .. theme.nf(take:size(), 4), bx + bw + 6, r.y + 30 + 34 * .7, "l", "b", true, .06)
    -- timecode, right
    local tc = theme.timecode(math.max(0, n - 1), fps())
    theme.vfdText(15, tc, r.x + r.w - 14, r.y + 30 + 34 * .7, "r", "b", true, .04)
    theme.vfdText(9, "TC " .. fps() .. "F", r.x + r.w - 14, r.y + 30, "r", "t", true, .1)
    -- status line: last message, else the setup in one line
    local st = S.status
    if love.timer.getTime() > S.toastUntil + 4 or st == "" then
        st = "TAKE " .. theme.nf(take.number, 3) .. "  " .. fps() .. " FPS  ON " ..
             ({ "ONES", "TWOS", "THREES" })[exposures()] .. "  " .. sourceName()
    end
    theme.vfdText(12, theme.trunc("vfd", 12, st, r.w - 28, .06), r.x + 14, r.y + r.h - 17, "l", "t", true, .06)
end

local function drawDeckLabels()
    theme.gt("RECORD", L.gtRecord.x, L.gtRecord.y, L.gtRecord.w)
    theme.gt("TRANSPORT", L.gtTrans.x, L.gtTrans.y, L.gtTrans.w)
    theme.gt("TIMING", L.gtTiming.x, L.gtTiming.y, L.gtTiming.w)
    theme.gt("ONION SKIN", L.gtOnion.x, L.gtOnion.y, L.gtOnion.w)
    theme.gt("SYSTEM", L.gtSystem.x, L.gtSystem.y, L.gtSystem.w)
    theme.lbl("JOG", L.jog.x + L.jog.w * .5, L.jog.y + L.jog.h + 6)
end

-- ======================================================================= --
--  CAMERA ADJUST                                                          --
--  Takes over the lower deck the way a hardware menu page would, so the
--  monitor keeps running live while you tune exposure and gain.
-- ======================================================================= --
function app.openAdjust()
    if not source.hasControls() then
        toast(string.upper(source.controlsStatus()))
        return
    end
    S.adjust.rows = {}
    for i, p in ipairs(source.PROPS) do
        local v, a = source.getProp(p.id)
        -- writing the current value back is a no-op that reveals whether the
        -- camera supports the property at all
        local ok = source.setProp(p.id, v, a)
        S.adjust.rows[i] = { id = p.id, name = p.name, value = v, auto = a,
                             ok = ok, initV = v, initA = a }
    end
    S.adjustOpen = true
    S.pickerOpen = false
end

function app.adjustRevert()
    for _, r in ipairs(S.adjust.rows) do
        if r.ok then
            r.value, r.auto = r.initV, r.initA
            source.setProp(r.id, r.value, r.auto)
        end
    end
    toast("CAMERA SETTINGS REVERTED")
end

local function adjustSet(i, mx)
    local r = S.adjust.rows[i]
    local g = layout.adjust(L.adjustArea).rows[i]
    if not r or not r.ok or not g then return end
    r.value = clamp((mx - (g.fader.x + 7)) / (g.fader.w - 14), 0, 1)
    r.auto = false
    source.setProp(r.id, r.value, false)
end

local function drawAdjust()
    local q = layout.adjust(L.adjustArea)
    theme.panelHead(q.head.x, q.head.y, q.head.w, "CAMERA", "ADJUST", C.ACC,
                    theme.trunc("label", 9.5, sourceName(), 150, .14))
    for i, r in ipairs(S.adjust.rows) do
        local g = q.rows[i]
        if g then
            theme.col(r.ok and C.INK or C.INK_FAINT)
            theme.text("label", 10, r.name, g.label.x, g.label.y, "l", "t", .14)
            theme.col(r.ok and (r.auto and C.VFD or C.INK_DIM) or C.INK_FAINT)
            theme.text("label", 10, (not r.ok) and "N/A" or (r.auto and "AUTO"
                       or (math.floor(r.value * 100 + .5) .. "%")),
                       g.auto.x - 10, g.label.y, "r", "t", .14)
            if r.ok then
                theme.key(g.auto.x, g.auto.y, g.auto.w, g.auto.h, {
                    on = r.auto, led = true, ledCol = C.VFD, label = "AUTO", size = 10,
                    hot = inside(g.auto, S.mx, S.my) })
                theme.fader(g.fader.x, g.fader.y + 8, g.fader.w, r.value,
                            inside(g.fader, S.mx, S.my), S.adjust.drag == i)
            else
                theme.box(g.fader.x, g.fader.y + 8, g.fader.w, 8, theme.S.slot, .5)
            end
        end
    end
    theme.key(q.revert.x, q.revert.y, q.revert.w, q.revert.h,
              { dark = true, label = "REVERT", hot = inside(q.revert, S.mx, S.my) })
    theme.key(q.close.x, q.close.y, q.close.w, q.close.h,
              { label = "CLOSE  (A)", hot = inside(q.close, S.mx, S.my) })
end

local function adjustClick(mx, my)
    local q = layout.adjust(L.adjustArea)
    if inside(q.revert, mx, my) then app.adjustRevert() return true end
    if inside(q.close, mx, my) then S.adjustOpen = false return true end
    for i, r in ipairs(S.adjust.rows) do
        local g = q.rows[i]
        if g and r.ok then
            if inside(g.auto, mx, my) then
                r.auto = not r.auto
                source.setProp(r.id, r.value, r.auto)
                return true
            end
            if inside(g.fader, mx, my) then
                S.adjust.drag = i
                adjustSet(i, mx)
                return true
            end
        end
    end
    return inside(L.adjustArea, mx, my)
end

-- ======================================================================= --
--  DIALOGS                                                                --
-- ======================================================================= --
local function dim()
    theme.col(C.BLACK, .62)
    lg.rectangle("fill", 0, 0, app.LW, app.LH)
end

--- VideoLab's help-panel header: topic in the accent, a close cross, and a
--- VT323 headline.
local function dialogHead(P, topic, headline, acc)
    theme.box(P.x, P.y, P.w, P.h, theme.S.help)
    theme.col(acc or C.ACC)
    theme.text("osd", 22, topic, P.x + 22, P.y + 22, "l", "t")
    local hot = inside({ x = P.x + P.w - 44, y = P.y + 10, w = 34, h = 34 }, S.mx, S.my)
    theme.col(hot and C.INK or C.INK_DIM)
    theme.text("osd", 28, "x", P.x + P.w - 26, P.y + 26, "c", "c")
    if headline then
        theme.col(C.WHITE)
        theme.text("osd", 30, headline, P.x + 22, P.y + 48, "l", "t")
    end
end

-- -------------------------------------------------------------------- help --
local HELP_ROWS = {
    { { "SPACE" }, "Capture a frame" },
    { { "1", "2", "3" }, "Shoot on ones, twos or threes" },
    { { "BKSP" }, "Delete the frame at the playhead" },
    { { "Z" }, "Undo the last delete" },
    { { "TAB" }, "Hold to flip between live and last frame" },
    { { "<", ">" }, "Step one frame" },
    { { "HOME", "END" }, "First or last frame" },
    { { "P" }, "Play the whole take, or stop" },
    { { "L" }, "Play the last few frames" },
    { { "R" }, "Loop playback" },
    { { "O" }, "Onion skin: off, 1, 3, difference" },
    { { "+", "-" }, "Onion mix" },
    { { "F" }, "Frame rate" },
    { { "M" }, "Mirror the camera" },
    { { "G" }, "Framing guides" },
    { { "T" }, "Time-lapse capture" },
    { { "C" }, "Choose the source" },
    { { "A" }, "Camera exposure and gain" },
    { { "E" }, "Export a PNG sequence" },
    { { "N" }, "Start a new take" },
}

local function drawHelp()
    dim()
    local P = L.helpBox
    dialogHead(P, "LUNCHBOX", "KEYS AND CONTROLS")
    local colW = (P.w - 44 - 24) / 2
    local half = math.ceil(#HELP_ROWS / 2)
    for i, row in ipairs(HELP_ROWS) do
        local col = (i <= half) and 0 or 1
        local k = (col == 0) and i or (i - half)
        local x = P.x + 22 + col * (colW + 24)
        local cy = P.y + 104 + (k - 1) * 30
        theme.col(C.WHITE, .07)
        lg.rectangle("fill", x, cy + 14, colW, 1)
        local kx = x
        for _, cap in ipairs(row[1]) do kx = kx + theme.kbd(cap, kx, cy) + 4 end
        theme.col(theme.hex"d9dcdf")
        theme.text("body", 14, row[2], x + 96, cy, "l", "c")
    end
    local fy = P.y + P.h - 62
    local root, fallback = storage.chooseTakesRoot()
    theme.col(C.INK_DIM)
    theme.text("body", 13, (fallback and "Takes (app folder is read-only): " or "Takes are saved in: "),
               P.x + 22, fy, "l", "t")
    theme.col(C.INK)
    theme.text("body", 13, theme.trunc("body", 13, root, P.w - 22 - 150 - 22 - 150), P.x + 22 + 150, fy, "l", "t")
    theme.col(C.INK_DIM)
    theme.text("body", 13, "Camera:", P.x + 22, fy + 20, "l", "t")
    theme.col(source.hasCamera() and C.VFD or C.A_RES)
    theme.text("body", 13, theme.trunc("body", 13, source.cameraStatus(), P.w - 22 - 150 - 22 - 150),
               P.x + 22 + 150, fy + 20, "l", "t")
    local cb = { x = P.x + P.w - 22 - 120, y = P.y + P.h - 22 - 34, w = 120, h = 34 }
    theme.hbtn(cb.x, cb.y, cb.w, cb.h, "CLOSE", "acc", inside(cb, S.mx, S.my))
end

-- ----------------------------------------------------------------- confirm --
function app.askConfirm(id, msg, body) S.confirmId, S.confirmMsg, S.confirmBody = id, msg, body end

local function drawConfirm()
    dim()
    local P = L.confirm
    dialogHead(P, "NEW TAKE", S.confirmMsg)
    if S.confirmBody then
        theme.col(theme.hex"d9dcdf")
        theme.text("body", 14, S.confirmBody, P.x + 22, P.y + 92, "l", "t")
    end
    local q = layout.confirm(P)
    theme.hbtn(q.cancel.x, q.cancel.y, q.cancel.w, q.cancel.h, "CANCEL  (N)", nil, inside(q.cancel, S.mx, S.my))
    theme.hbtn(q.yes.x, q.yes.y, q.yes.w, q.yes.h, "DISCARD  (Y)", "red", inside(q.yes, S.mx, S.my))
end

function app.confirmYes()
    local id = S.confirmId
    S.confirmMsg, S.confirmId, S.confirmBody = nil, nil, nil
    if id == "NEWTAKE" then app.newTake() end
end

local function confirmClick(mx, my)
    local P = L.confirm
    local q = layout.confirm(P)
    if inside(q.yes, mx, my) then app.confirmYes()
    elseif inside(q.cancel, mx, my) or not inside(P, mx, my)
        or inside({ x = P.x + P.w - 44, y = P.y + 10, w = 34, h = 34 }, mx, my) then
        S.confirmMsg = nil
    end
end

-- ======================================================================= --
--  SOURCE PICKER                                                          --
-- ======================================================================= --
function app.requestScan()
    S.pendingScan = true
    S.scanAt = S.frameNum + 2          -- let the dialog paint before we block
end

function app.doScan()
    source.tryLoadCamera(true)          -- retry the DLL: it may have just been added
    S.devices = source.scan()
    S.pickerScanned = true
    app.syncPicker()
    if not source.hasCamera() then
        toast("NO CAMERA SUPPORT - " .. string.upper(source.cameraStatus()))
    else
        toast(#S.devices == 0 and "NO CAMERAS DETECTED"
              or (#S.devices .. (#S.devices == 1 and " CAMERA FOUND" or " CAMERAS FOUND")))
    end
end

local function modeCount()
    if S.pickSel <= 1 or S.pickSel - 1 > #S.devices then return 0 end
    return #S.devices[S.pickSel - 1].formats
end

local function followMode()
    local n = modeCount()
    S.modeTop = clamp(math.min(S.modeTop, S.pickMode - 1),
                      math.max(0, S.pickMode - PK_MODE_ROWS),
                      math.max(0, n - PK_MODE_ROWS))
end

function app.syncPicker()
    S.pickSel = (S.curDev < 1) and 1 or (S.curDev + 1)
    S.pickMode = S.curMode
    local total = #S.devices + 1
    S.pickTop = clamp(S.pickSel - PK_DEV_ROWS, 0, math.max(0, total - PK_DEV_ROWS))
    S.modeTop = 0
    followMode()
end

function app.pickDevice(i)
    local total = #S.devices + 1
    local prev = S.pickSel
    S.pickSel = clamp(i, 1, total)
    if S.pickSel ~= prev then
        S.pickMode = (S.pickSel > 1) and (S.devices[S.pickSel - 1].best or 1) or 1
        S.modeTop = 0
    end
    S.pickTop = clamp(S.pickTop, math.max(0, S.pickSel - PK_DEV_ROWS),
                      math.max(0, total - PK_DEV_ROWS))
    S.pickTop = math.min(S.pickTop, S.pickSel - 1)
    followMode()
end

function app.openPicker()
    S.pickerOpen = true
    app.syncPicker()
    if not S.pickerScanned then app.requestScan() end
end

function app.applyPicker()
    S.pickerOpen = false
    if S.pickSel == 1 then
        source.useTestPattern()
        S.curDev = -1
        toast("SOURCE: TEST CARD")
        return
    end
    local d = S.devices[S.pickSel - 1]
    if source.open(d, S.pickMode) then
        S.curDev, S.curMode = S.pickSel - 1, S.pickMode
        -- report what actually opened, not what was requested
        toast("SOURCE: " .. string.upper(d.name) .. "  " .. source.width() .. "X" .. source.height())
    else
        S.curDev = -1
        toast("COULD NOT OPEN THAT CAMERA - BACK ON THE TEST CARD")
    end
end

local function drawPicker()
    dim()
    local P = L.picker
    local q = layout.picker(P)
    dialogHead(P, "SOURCE", "SELECT A CAMERA")
    theme.col(C.INK_DIM)
    theme.text("body", 13.5, "Pick a camera and a capture format, or stay on the built-in test card.",
               P.x + 22, P.y + 80, "l", "t")

    local function listBox(r, title)
        theme.box(r.x, r.y, r.w, r.h, theme.S.panel)
        theme.col(C.INK_DIM)
        theme.text("key", 11, title, r.x, r.y - 14, "l", "t", .2)
    end
    listBox(q.devList, "DEVICE")
    listBox(q.modeList, "FORMAT")
    theme.col(C.ACC)
    theme.text("label", 9.5, "NOW: " .. sourceName(), q.modeList.x + q.modeList.w, q.modeList.y - 14,
               "r", "t", .14)

    if S.pendingScan then
        theme.col(C.INK_DIM)
        theme.text("osd", 24, "SCANNING FOR CAMERAS...", P.x + P.w * .5, q.devList.y + 110, "c", "c")
    else
        -- devices
        local total = #S.devices + 1
        local dl = q.devList
        for row = 0, PK_DEV_ROWS - 1 do
            local i = S.pickTop + row + 1
            if i > total then break end
            local rr = { x = dl.x + 4, y = dl.y + 4 + row * PK_DEV_RH, w = dl.w - 8, h = PK_DEV_RH - 3 }
            local sel = (i == S.pickSel)
            if sel then theme.box(rr.x, rr.y, rr.w, rr.h, theme.S.rowSel)
            elseif inside(rr, S.mx, S.my) then theme.box(rr.x, rr.y, rr.w, rr.h, theme.S.rowHot) end
            local current = (i == 1) and (S.curDev < 1) or (S.curDev == i - 1)
            theme.led(rr.x + 14, rr.y + rr.h * .5, 2.6, current, C.GREEN)
            local nm = (i == 1) and "Built-in test card" or S.devices[i - 1].name
            theme.col(sel and C.WHITE or C.INK)
            theme.text(sel and "bodyS" or "body", 14, theme.trunc("body", 14, nm, rr.w - 110),
                       rr.x + 28, rr.y + rr.h * .5, "l", "c")
            if i > 1 then
                local mc = #S.devices[i - 1].formats
                theme.col(C.INK_DIM)
                theme.text("label", 9, mc .. (mc == 1 and " FORMAT" or " FORMATS"),
                           rr.x + rr.w - 10, rr.y + rr.h * .5, "r", "c", .14)
            end
        end
        theme.scrollHint(dl.x + dl.w - 6, dl.y + 4, dl.h - 8, total, PK_DEV_ROWS, S.pickTop)

        if S.pickerScanned and #S.devices == 0 then
            local ny = dl.y + 4 + PK_DEV_RH + 14
            theme.col(C.INK)
            theme.text("bodyM", 13.5, "No cameras available.", dl.x + 16, ny, "l", "t")
            theme.col(C.INK_DIM)
            theme.text("body", 12.5, theme.trunc("body", 12.5, source.cameraStatus() .. ".", dl.w - 32),
                       dl.x + 16, ny + 22, "l", "t")
            theme.text("body", 12.5, "See the README for escapi.dll, then press Rescan.",
                       dl.x + 16, ny + 40, "l", "t")
        end

        -- formats
        local ml = q.modeList
        local mc = modeCount()
        if S.pickSel == 1 then
            theme.col(C.INK_DIM)
            local lines = { "Generated inside LunchBox at " .. theme.CAM_W .. " x " .. theme.CAM_H .. ".",
                            "Colour bars and a moving disc, so you can",
                            "rehearse timing, try onion skin and export",
                            "a dummy take with no camera attached." }
            for k, s in ipairs(lines) do
                theme.text("body", 13, s, ml.x + 16, ml.y + 16 + (k - 1) * 20, "l", "t")
            end
        elseif mc > 0 then
            local d = S.devices[S.pickSel - 1]
            for row = 0, PK_MODE_ROWS - 1 do
                local i = S.modeTop + row + 1
                if i > mc then break end
                local rr = { x = ml.x + 4, y = ml.y + 4 + row * PK_MODE_RH, w = ml.w - 8, h = PK_MODE_RH - 3 }
                local sel = (i == S.pickMode)
                if sel then theme.box(rr.x, rr.y, rr.w, rr.h, theme.S.rowSel)
                elseif inside(rr, S.mx, S.my) then theme.box(rr.x, rr.y, rr.w, rr.h, theme.S.rowHot) end
                local f = d.formats[i]
                theme.col(sel and C.VFD or C.INK)
                theme.text("vfd", 13, string.format("%4d x %-4d", f.w, f.h), rr.x + 14, rr.y + rr.h * .5, "l", "c")
                theme.col(C.INK_DIM)
                theme.text("label", 9, d.requested and "REQUEST" or (math.floor(f.fps + .5) .. " FPS"),
                           rr.x + 120, rr.y + rr.h * .5, "l", "c", .14)
                if i == d.best then
                    theme.col(C.ACC)
                    theme.text("label", 9, "SUGGESTED", rr.x + rr.w - 10, rr.y + rr.h * .5, "r", "c", .14)
                end
            end
            theme.scrollHint(ml.x + ml.w - 6, ml.y + 4, ml.h - 8, mc, PK_MODE_ROWS, S.modeTop)
            if d.requested then
                theme.col(C.INK_DIM)
                theme.text("body", 12, "escapi does not report formats: these are requests,",
                           ml.x, ml.y + ml.h + 10, "l", "t")
                theme.text("body", 12, "and the driver scales to the nearest it supports.",
                           ml.x, ml.y + ml.h + 26, "l", "t")
            end
        end
        if not take:isEmpty() then
            theme.col(C.A_RES)
            theme.text("body", 12, "Take " .. theme.nf(take.number, 3) .. " holds " .. take:size() ..
                       (take:size() == 1 and " frame" or " frames") ..
                       ": switching format mid-take mixes resolutions.",
                       q.devList.x, q.devList.y + q.devList.h + 10, "l", "t")
        end
    end

    local can = source.hasControls()
    theme.hbtn(q.rescan.x, q.rescan.y, q.rescan.w, q.rescan.h, "RESCAN", nil, inside(q.rescan, S.mx, S.my))
    theme.hbtn(q.adjust.x, q.adjust.y, q.adjust.w, q.adjust.h, "ADJUST", nil,
               can and inside(q.adjust, S.mx, S.my), not can)
    theme.hbtn(q.cancel.x, q.cancel.y, q.cancel.w, q.cancel.h, "CANCEL", nil, inside(q.cancel, S.mx, S.my))
    theme.hbtn(q.use.x, q.use.y, q.use.w, q.use.h, "USE SOURCE", "acc", inside(q.use, S.mx, S.my), S.pendingScan)
end

local function pickerClick(mx, my)
    local P = L.picker
    local q = layout.picker(P)
    if not inside(P, mx, my) or inside(q.close, mx, my) then S.pickerOpen = false return end
    if inside(q.rescan, mx, my) then app.requestScan() return end
    if inside(q.adjust, mx, my) then app.openAdjust() return end
    if inside(q.cancel, mx, my) then S.pickerOpen = false return end
    if inside(q.use, mx, my) then if not S.pendingScan then app.applyPicker() end return end
    if S.pendingScan then return end
    local dl, ml = q.devList, q.modeList
    if inside(dl, mx, my) then
        local row = math.floor((my - dl.y - 4) / PK_DEV_RH)
        if row >= 0 and row < PK_DEV_ROWS and S.pickTop + row + 1 <= #S.devices + 1 then
            app.pickDevice(S.pickTop + row + 1)
        end
    elseif inside(ml, mx, my) then
        local row = math.floor((my - ml.y - 4) / PK_MODE_RH)
        if row >= 0 and row < PK_MODE_ROWS and S.modeTop + row + 1 <= modeCount() then
            S.pickMode = S.modeTop + row + 1
        end
    end
end

local function pickerKey(key)
    if key == "up" then app.pickDevice(S.pickSel - 1)
    elseif key == "down" then app.pickDevice(S.pickSel + 1)
    elseif key == "left" then S.pickMode = math.max(1, S.pickMode - 1) followMode()
    elseif key == "right" then S.pickMode = math.min(math.max(1, modeCount()), S.pickMode + 1) followMode()
    elseif key == "return" or key == "kpenter" then app.applyPicker()
    elseif key == "r" then app.requestScan()
    elseif key == "a" then app.openAdjust()
    elseif key == "t" then app.pickDevice(1) end
end

local function pickerWheel(d)
    local q = layout.picker(L.picker)
    local total = #S.devices + 1
    if S.mx < q.modeList.x - 10 then
        S.pickTop = clamp(S.pickTop + d, 0, math.max(0, total - PK_DEV_ROWS))
    else
        S.modeTop = clamp(S.modeTop + d, 0, math.max(0, modeCount() - PK_MODE_ROWS))
    end
end

-- ======================================================================= --
--  DRAW                                                                   --
-- ======================================================================= --
--- Everything that only changes when the window does - the room, the three
--- housings, the VFD window, the printed badges - is drawn once into a
--- canvas at device resolution. Each frame then costs one quad for all of
--- it, and the shader only runs for keys and other small moving parts.
function app.bake()
    local dpi = theme.dpi
    if staticCv then staticCv:release() end
    if glassCv then glassCv:release() end
    staticCv = lg.newCanvas(math.ceil(app.LW), math.ceil(app.LH), { dpiscale = dpi })
    glassCv  = lg.newCanvas(math.max(1, L.screen.w), math.max(1, L.screen.h), { dpiscale = dpi })

    lg.push("all")
    lg.origin()
    lg.setCanvas(staticCv)
    lg.clear(C.ROOM[1], C.ROOM[2], C.ROOM[3], 1)
    theme.box(0, 0, app.LW, app.LH, theme.S.room)
    local fd = L.film
    theme.box(fd.x, fd.y, fd.w, fd.h, theme.S.deck)
    theme.box(L.filmPanel.x, L.filmPanel.y, L.filmPanel.w, L.filmPanel.h, theme.S.panel)
    drawMonitorStatic()
    local d = L.deck
    theme.box(d.x, d.y, d.w, d.h, theme.S.deck)
    drawBrand()
    theme.box(L.vfd.x, L.vfd.y, L.vfd.w, L.vfd.h, theme.S.vfd)

    lg.setCanvas(glassCv)
    lg.clear(0, 0, 0, 0)
    theme.box(0, 0, L.screen.w, L.screen.h, theme.S.glassHi)
    theme.box(0, 0, L.screen.w, L.screen.h, theme.S.glassVig)
    lg.setCanvas()
    lg.pop()
end

function app.draw()
    lg.setColor(1, 1, 1, 1)
    lg.setBlendMode("alpha", "premultiplied")      -- canvases hold premultiplied colour
    lg.draw(staticCv, 0, 0)
    lg.setBlendMode("alpha")

    drawFilmDeck()
    drawMonitor()
    drawCassette()
    drawVfd()
    if S.adjustOpen then drawAdjust() else drawDeckLabels() end

    for _, wd in ipairs(app.widgets) do wd:draw() end

    if S.helpOpen then drawHelp() end
    if S.pickerOpen then drawPicker() end
    if S.confirmMsg then drawConfirm() end
end

-- ======================================================================= --
--  INPUT                                                                  --
-- ======================================================================= --
function app.mousepressed(x, y, button)
    if button ~= 1 then return end
    local mx, my = app.toLogical(x, y)
    S.mx, S.my = mx, my
    if S.confirmMsg then confirmClick(mx, my) return end
    if S.pickerOpen then pickerClick(mx, my) return end
    if S.helpOpen then S.helpOpen = false return end
    if S.adjustOpen and adjustClick(mx, my) then return end

    for _, wd in ipairs(app.widgets) do
        if wd.visible and wd:press(mx, my) then S.dragging = wd return end
    end
    if inside(L.cassette, mx, my) then app.openTakesFolder() return end
    if inside(L.screen, mx, my) then
        if S.mode == "live" then app.doCapture() else app.goLive() end
    end
end

function app.mousemoved(x, y)
    local mx, my = app.toLogical(x, y)
    S.mx, S.my = mx, my
    if S.adjust.drag then adjustSet(S.adjust.drag, mx) return end
    if S.dragging then S.dragging:drag(mx, my) end
end

function app.mousereleased()
    for _, wd in ipairs(app.widgets) do wd:release() end
    S.dragging = nil
    S.adjust.drag = nil
end

function app.wheelmoved(dx, dy)
    local d = -dy                                   -- wheel down = forward
    if S.pickerOpen then pickerWheel(d) return end
    if S.helpOpen or S.confirmMsg then return end
    local mx, my = S.mx, S.my
    if inside(L.film, mx, my) then W.strip:wheel(d)
    elseif inside(L.monitor, mx, my) then app.step(d > 0 and 1 or -1)
    else
        for _, f in ipairs({ W.sldShort, W.sldInterval, W.sldMix }) do
            if f.visible and f:hit(mx, my) then
                f:nudge(-dy * (f.integer and 1 or 0.5))
                return
            end
        end
    end
end

function app.keypressed(key)
    if key == "escape" then                          -- never quits
        if S.helpOpen then S.helpOpen = false
        elseif S.pickerOpen then S.pickerOpen = false
        elseif S.adjustOpen then S.adjustOpen = false
        elseif S.confirmMsg then S.confirmMsg = nil end
        return
    end
    if S.pickerOpen and not S.confirmMsg then pickerKey(key) return end
    if S.confirmMsg then
        if key == "y" or key == "return" then app.confirmYes()
        elseif key == "n" then S.confirmMsg = nil end
        return
    end
    if S.helpOpen then S.helpOpen = false return end

    if key == "space" then app.doCapture()
    elseif key == "tab" then S.flipHold = true
    elseif key == "backspace" or key == "delete" then app.doDelete()
    elseif key == "z" then app.doUndo()
    elseif key == "p" then app.togglePlay()
    elseif key == "l" then app.playLast()
    elseif key == "left" or key == "," then app.step(-1)
    elseif key == "right" or key == "." then app.step(1)
    elseif key == "home" then app.setPlayhead(0)
    elseif key == "end" then app.setPlayhead(take:size() - 1)
    elseif key == "up" or key == "=" or key == "kp+" then W.sldMix:nudge(5)
    elseif key == "down" or key == "-" or key == "kp-" then W.sldMix:nudge(-5)
    elseif key == "o" then W.segOnion:cycle() app.action("ONION")
    elseif key == "1" then W.segExp.sel = 1 app.action("EXP")
    elseif key == "2" then W.segExp.sel = 2 app.action("EXP")
    elseif key == "3" then W.segExp.sel = 3 app.action("EXP")
    elseif key == "f" then W.segFps:cycle() app.action("FPS")
    elseif key == "r" then W.tglLoop.on = not W.tglLoop.on app.action("LOOP")
    elseif key == "m" then W.tglMirror.on = not W.tglMirror.on app.action("MIRROR")
    elseif key == "g" then W.tglGuides.on = not W.tglGuides.on
    elseif key == "t" then W.tglLapse.on = not W.tglLapse.on app.action("LAPSE")
    elseif key == "a" then
        if S.adjustOpen then S.adjustOpen = false else app.openAdjust() end
    elseif key == "c" then app.action("CAMERA")
    elseif key == "e" then app.beginExport()
    elseif key == "n" then app.action("NEWTAKE")
    elseif key == "h" or key == "/" then S.helpOpen = not S.helpOpen end
end

function app.keyreleased(key)
    if key == "tab" then S.flipHold = false end
end

-- ======================================================================= --
--  ACTION DISPATCH                                                        --
-- ======================================================================= --
function app.action(id)
    if id == "CAPTURE" then app.doCapture()
    elseif id == "DELETE" then app.doDelete()
    elseif id == "UNDO" then app.doUndo()
    elseif id == "STEPB" then app.step(-1)
    elseif id == "STEPF" then app.step(1)
    elseif id == "PLAY" then app.togglePlay()
    elseif id == "PLAYLAST" then app.playLast()
    elseif id == "STOP" then
        if S.mode == "play" then app.stopPlay() else app.goLive() end
    elseif id == "FPS" then toast(fps() .. " FPS")
    elseif id == "EXP" then
        toast("SHOOTING ON " .. ({ "ONES", "TWOS", "THREES" })[exposures()])
    elseif id == "ONION" then toast("ONION " .. W.segOnion.opts[W.segOnion.sel])
    elseif id == "MIRROR" then toast(W.tglMirror.on and "MIRROR ON" or "MIRROR OFF")
    elseif id == "GUIDES" then toast(W.tglGuides.on and "GUIDES ON" or "GUIDES OFF")
    elseif id == "OSD" then toast(W.tglOsd.on and "OSD ON" or "OSD OFF")
    elseif id == "LOOP" then toast(W.tglLoop.on and "LOOP ON" or "LOOP OFF")
    elseif id == "PING" then toast(W.tglPing.on and "PING-PONG ON" or "PING-PONG OFF")
    elseif id == "AUTOLIVE" then toast(W.tglAutoLive.on and "AUTO LIVE ON" or "AUTO LIVE OFF")
    elseif id == "LAPSE" then
        S.lastAuto = love.timer.getTime()
        toast(W.tglLapse.on and "TIME-LAPSE ARMED" or "TIME-LAPSE OFF")
    elseif id == "EXPORT" then app.beginExport()
    elseif id == "HELP" then S.helpOpen = not S.helpOpen
    elseif id == "CAMERA" then app.openPicker()
    elseif id == "ADJUST" then
        if S.adjustOpen then S.adjustOpen = false else app.openAdjust() end
    elseif id == "NEWTAKE" then
        if take:isEmpty() then app.newTake()
        else
            app.askConfirm("NEWTAKE", "DISCARD " .. take:size() .. (take:size() == 1 and " FRAME?" or " FRAMES?"),
                "Take " .. theme.nf(take.number + 1, 3) .. " starts empty. Export first to keep them.")
        end
    end
end

return app
