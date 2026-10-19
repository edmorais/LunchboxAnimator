-- ===========================================================================
--  LUNCHBOX - Source
--  The live image: either the built-in test pattern or a webcam.
--
--  LÖVE has no camera API at all (love.video only plays Theora files), so the
--  webcam path goes through LuaJIT's FFI to escapi.dll - a small DirectShow
--  capture library. Drop escapi.dll (x64) next to the executable and cameras
--  appear in SOURCE SELECT; without it the station stays on the test pattern
--  and says so plainly. Nothing else in the app depends on the DLL.
--
--  escapi: https://github.com/jarikomppa/escapi
-- ===========================================================================
local theme = require("theme")
local lg = love.graphics

local source = {}

-- Some capture drivers hand back bottom-up buffers. If the live image is
-- upside down, flip this.
local FLIP_V = false

-- ------------------------------------------------------------------- FFI --
-- escapi.dll is looked for in several places, on demand, so RESCAN can pick
-- one up without restarting. Every failure is kept and reported verbatim:
-- "not found", "wrong architecture" and "loaded but no exports" are very
-- different problems and the picker says which one you have.
local ffi, lib
local cdefDone   = false
local loadedFrom = nil
local dllVersion = nil
local lastError  = nil
local searched   = {}

local haveFFI = pcall(function() ffi = require("ffi") end)
haveFFI = haveFFI and ffi ~= nil

local SEP = package.config:sub(1, 1)

local function ensureCdef()
    if cdefDone or not haveFFI then return cdefDone end
    local ok = pcall(function()
        -- These are escapi.dll's real exports. setupESCAPI() is deliberately
        -- absent: it is not exported by the DLL at all -- it lives in
        -- escapi.cpp on the client side and does LoadLibrary +
        -- GetProcAddress itself. Coming in through the FFI we skip that
        -- helper, so bindLib() below does its job instead.
        ffi.cdef [[
            struct SimpleCapParams { int *mTargetBuf; int mWidth; int mHeight; };
            int  ESCAPIDLLVersion(void);
            void initCOM(void);
            int  countCaptureDevices(void);
            void getCaptureDeviceName(unsigned int deviceno, char *namebuffer, int bufferlength);
            int  initCapture(unsigned int deviceno, struct SimpleCapParams *aParams);
            void deinitCapture(unsigned int deviceno);
            void doCapture(unsigned int deviceno);
            int  isCaptureDone(unsigned int deviceno);
            float getCapturePropertyValue(unsigned int deviceno, int prop);
            int   getCapturePropertyAuto(unsigned int deviceno, int prop);
            int   setCaptureProperty(unsigned int deviceno, int prop, float value, int autoval);
        ]]
    end)
    cdefDone = ok
    return ok
end

--- Strip a trailing file name so a fused .exe path becomes its folder.
local function dirOf(p)
    if not p or p == "" then return nil end
    local low = p:lower()
    if low:sub(-4) == ".exe" or low:sub(-5) == ".love" then
        return p:match("^(.*)[/\\][^/\\]*$")
    end
    return p
end

--- Every place worth looking, most specific first. The bare name comes last:
--- it uses the OS search path, whose "application directory" is wherever
--- love.exe lives, which is *not* the game folder when running unfused.
local function candidates()
    local list, seen = {}, {}
    local function push(dir)
        if not dir or dir == "" then return end
        dir = dir:gsub("[/\\]+$", "")
        local full = dir .. SEP .. "escapi.dll"
        if not seen[full] then
            seen[full] = true
            list[#list + 1] = full
        end
    end
    local fs = love.filesystem
    if fs.getSource then push(dirOf(fs.getSource())) end                -- game folder / fused exe
    if fs.getSourceBaseDirectory then push(fs.getSourceBaseDirectory()) end
    if fs.getWorkingDirectory then push(fs.getWorkingDirectory()) end
    if fs.getSaveDirectory then push(fs.getSaveDirectory()) end
    list[#list + 1] = "escapi"                                          -- OS search path
    return list
end

--- What escapi.cpp's setupESCAPI() does for a C client: check the version,
--- resolve the entry points, initialise COM. A device count of zero is a
--- perfectly good result here - it means the DLL works and no camera is
--- plugged in, which is not a load failure.
-- escapi property ids (escapi.h). Values are normalised 0..1 floats.
source.PROPS = {
    { id = 15, name = "EXPOSURE" },
    { id = 10, name = "GAIN" },
    { id = 1,  name = "BRIGHTNESS" },
    { id = 2,  name = "CONTRAST" },
    { id = 4,  name = "SATURATION" },
    { id = 8,  name = "WHITE BALANCE" },
    { id = 6,  name = "GAMMA" },
    { id = 5,  name = "SHARPNESS" },
    { id = 17, name = "FOCUS" },
    { id = 14, name = "ZOOM" },
}

local propsOK = false

local REQUIRED = {
    "countCaptureDevices", "initCapture", "deinitCapture",
    "doCapture", "isCaptureDone", "getCaptureDeviceName",
}

local function bindLib(loaded)
    local ver
    pcall(function() ver = loaded.ESCAPIDLLVersion() end)
    if ver and ver < 0x200 then
        return nil, string.format("escapi.dll is too old (0x%x, needs 0x200+)", ver)
    end
    for _, name in ipairs(REQUIRED) do
        if not pcall(function() return loaded[name] end) then
            return nil, "escapi.dll has no " .. name .. "() - wrong or too old DLL"
        end
    end
    pcall(function() loaded.initCOM() end)     -- absent on very old builds

    -- Property control is optional: older DLLs simply do not export it.
    propsOK = pcall(function()
        return loaded.getCapturePropertyValue, loaded.getCapturePropertyAuto,
               loaded.setCaptureProperty
    end)
    return ver or 0
end

local function classify(err)
    err = tostring(err or "")
    local low = err:lower()
    if low:find("not a valid win32") or low:find("bad exe") or low:find("%%1 is not") then
        return "wrong architecture - use the 64-bit escapi.dll"
    end
    if low:find("cannot resolve symbol") or low:find("undefined symbol") then
        return "loaded, but has no setupESCAPI export - wrong DLL?"
    end
    if low:find("procedure") then
        return "loaded, but a dependency is missing (VC++ runtime?)"
    end
    return err:gsub("^.-:%s*", "")
end

--- Try to bind escapi. Safe to call repeatedly; RESCAN does exactly that.
function source.tryLoadCamera(force)
    if lib and not force then return true end
    if not haveFFI then
        lastError = "this build has no LuaJIT FFI"
        return false
    end
    if not ensureCdef() then
        lastError = "could not declare the escapi interface"
        return false
    end

    lib, loadedFrom, lastError = nil, nil, nil
    searched = candidates()
    local firstErr

    for _, path in ipairs(searched) do
        local ok, loaded = pcall(ffi.load, path)
        if ok then
            -- Loading is not enough: the entry points have to resolve, or we
            -- would report a camera that cannot capture.
            local ver, err = bindLib(loaded)
            if not ver then
                firstErr = firstErr or err
            else
                lib, loadedFrom, dllVersion = loaded, path, ver
                lastError = nil
                return true
            end
        else
            firstErr = firstErr or classify(loaded)
        end
    end
    lastError = firstErr or "escapi.dll not found"
    return false
end

source.tryLoadCamera()

function source.hasCamera() return lib ~= nil end

-- ----------------------------------------------------------------- state --
local st = {
    sim       = true,
    devIndex  = -1,
    w         = theme.CAM_W,
    h         = theme.CAM_H,
    newFrame  = false,
    gotFrame  = false,
    startTime = 0,
    canvas    = nil,     -- test pattern target
    camImage  = nil,     -- webcam frame as a texture
    camData   = nil,     -- webcam frame as ImageData
    buf       = nil,     -- escapi target buffer
    params    = nil,
    grabCv    = nil,     -- scratch canvas used by grab()
}

--- True when a live camera can actually be adjusted.
function source.hasControls()
    return lib ~= nil and propsOK and st.devIndex >= 0
end

function source.controlsStatus()
    if st.sim or st.devIndex < 0 then return "the test pattern has no controls" end
    if not propsOK then return "this escapi.dll has no property controls" end
    return "ready"
end

--- Returns value (0..1) and whether the driver is in auto for this property.
function source.getProp(id)
    if not source.hasControls() then return 0.5, false end
    local v, a = 0.5, false
    pcall(function() v = lib.getCapturePropertyValue(st.devIndex, id) end)
    pcall(function() a = lib.getCapturePropertyAuto(st.devIndex, id) ~= 0 end)
    if v ~= v then v = 0.5 end                       -- guard against NaN
    return math.max(0, math.min(1, v)), a
end

--- Returns false when the camera does not support the property, which is how
--- unsupported rows get greyed out in the UI.
function source.setProp(id, value, auto)
    if not source.hasControls() then return false end
    local ok, r = pcall(function()
        return lib.setCaptureProperty(st.devIndex, id,
                                      math.max(0, math.min(1, value)), auto and 1 or 0)
    end)
    return ok and r ~= 0
end

function source.cameraStatus()
    if lib then
        local v = (dllVersion and dllVersion > 0)
            and string.format(" v%d.%d", math.floor(dllVersion / 256), dllVersion % 256)
            or ""
        return "escapi" .. v .. " ready (" .. tostring(loadedFrom) .. ")"
    end
    return tostring(lastError or "escapi.dll not found")
end

--- Where we looked, for the help overlay - the fastest way for someone to see
--- which folder the DLL actually needs to be in.
function source.searchPaths() return searched end

function source.load()
    st.canvas = lg.newCanvas(theme.CAM_W, theme.CAM_H)
    st.startTime = love.timer.getTime()
    source.useTestPattern()
end

function source.isSim()   return st.sim end
function source.width()   return st.w end
function source.height()  return st.h end
function source.frameNew() return st.newFrame end

function source.stalled()
    return (not st.sim) and (not st.gotFrame)
       and (love.timer.getTime() - st.startTime) > 6
end

function source.close()
    if lib and st.devIndex >= 0 then
        pcall(function() lib.deinitCapture(st.devIndex) end)
    end
    st.devIndex = -1
    st.newFrame = false
end

function source.useTestPattern()
    source.close()
    st.sim = true
    st.gotFrame = false
    st.w, st.h = theme.CAM_W, theme.CAM_H
end

-- ------------------------------------------------------------ enumeration --
--- escapi reports no capture formats, so - exactly as on the openFrameworks
--- Windows build - offer a ladder of sizes to request. escapi scales whatever
--- the device gives to the size asked for.
function source.fillRequestFormats(dev)
    local ladder = { { 320, 240 }, { 640, 480 }, { 800, 600 },
                     { 1024, 768 }, { 1280, 720 }, { 1920, 1080 } }
    dev.formats = {}
    for _, r in ipairs(ladder) do
        dev.formats[#dev.formats + 1] = {
            w = r[1], h = r[2], fps = theme.CAM_FPS,
            label = r[1] .. " x " .. r[2] .. "   REQUEST",
        }
        if r[1] == theme.CAM_W and r[2] == theme.CAM_H then dev.best = #dev.formats end
    end
    dev.best = dev.best or 1
    dev.requested = true
    return dev
end

function source.scan()
    local out = {}
    if not lib then return out end
    local ok, n = pcall(function() return lib.countCaptureDevices() end)
    if not ok or not n then return out end
    for i = 0, n - 1 do
        local name = "Camera " .. i
        pcall(function()
            local buf = ffi.new("char[?]", 256)
            lib.getCaptureDeviceName(i, buf, 256)
            local s = ffi.string(buf)
            if s and #s > 0 then name = s end
        end)
        out[#out + 1] = source.fillRequestFormats({ id = i, name = name, best = 1 })
    end
    return out
end

-- ---------------------------------------------------------------- opening --
function source.open(dev, formatIdx)
    if not lib then return false end
    source.close()
    local f = dev.formats[math.max(1, math.min(#dev.formats, formatIdx or 1))]

    local ok = pcall(function()
        st.buf = ffi.new("int[?]", f.w * f.h)
        st.params = ffi.new("struct SimpleCapParams")
        st.params.mTargetBuf = st.buf
        st.params.mWidth  = f.w
        st.params.mHeight = f.h
        if lib.initCapture(dev.id, st.params) == 0 then error("initCapture failed") end
        lib.doCapture(dev.id)
    end)
    if not ok then
        st.buf, st.params = nil, nil
        source.useTestPattern()
        return false
    end

    st.devIndex = dev.id
    st.w, st.h  = f.w, f.h
    st.sim      = false
    st.gotFrame = false
    st.newFrame = false
    st.startTime = love.timer.getTime()
    st.camData  = love.image.newImageData(f.w, f.h, "rgba8")
    st.camImage = lg.newImage(st.camData)
    st.grabCv   = nil
    return true
end

-- ---------------------------------------------------------------- update --
--- A broadcast test card, drawn live: 75% colour bars, the reverse-blue
--- strip, a PLUGE row and a disc on a slow orbit, so onion skin, DIFF and
--- playback all have motion to show without a camera.
local BARS = {
    { .75, .75, .75 }, { .75, .75, 0 }, { 0, .75, .75 }, { 0, .75, 0 },
    { .75, 0, .75 },   { .75, 0, 0 },   { 0, 0, .75 },
}
local REV = { { 0, 0, .75 }, { .07, .07, .07 }, { .75, 0, .75 }, { .07, .07, .07 },
              { 0, .75, .75 }, { .07, .07, .07 }, { .75, .75, .75 } }

local function renderSim()
    local t = love.timer.getTime()
    local w, h = theme.CAM_W, theme.CAM_H
    lg.push("all")
    lg.origin()
    lg.setShader()
    lg.setCanvas(st.canvas)
    lg.clear(.07, .07, .07, 1)

    local bw = w / 7
    local barH = math.floor(h * 0.62)
    for i, c in ipairs(BARS) do
        lg.setColor(c)
        lg.rectangle("fill", math.floor((i - 1) * bw), 0, math.ceil(bw), barH)
    end
    local revH = math.floor(h * 0.08)
    for i, c in ipairs(REV) do
        lg.setColor(c)
        lg.rectangle("fill", math.floor((i - 1) * bw), barH, math.ceil(bw), revH)
    end
    -- PLUGE: -I, white, +Q, black, then three near-black steps
    local py = barH + revH
    local pw = w / 6
    local pl = { { 0, .13, .30 }, { 1, 1, 1 }, { .2, 0, .42 }, { .07, .07, .07 } }
    for i, c in ipairs(pl) do
        lg.setColor(c)
        lg.rectangle("fill", math.floor((i - 1) * pw), py, math.ceil(pw), h - py)
    end
    for i, v in ipairs({ .03, .07, .11 }) do
        lg.setColor(v, v, v)
        lg.rectangle("fill", math.floor(4 * pw + (i - 1) * pw * 2 / 3), py, math.ceil(pw * 2 / 3), h - py)
    end

    -- identification box, VideoLab style: black plate, VT323
    local bx, by, bwid, bh = w * 0.5 - 150, barH * 0.5 - 20, 300, 40
    lg.setColor(0, 0, 0, .85)
    lg.rectangle("fill", bx, by, bwid, bh)
    lg.setColor(1, 1, 1, .2)
    lg.rectangle("line", bx + .5, by + .5, bwid - 1, bh - 1)
    local secs = math.floor(t)
    lg.setColor(1, 1, 1)
    theme.text("osd", 26, "LUNCHBOX TEST", bx + 12, by + bh * 0.5, "l", "c")
    lg.setColor(theme.C.VFD)
    theme.text("osd", 26, string.format("%02d:%02d:%02d", math.floor(secs / 60) % 60, secs % 60,
               math.floor(t * 30) % 30), bx + bwid - 12, by + bh * 0.5, "r", "c")

    -- the moving element
    local cx = w * 0.5 + math.cos(t * 0.9) * w * 0.30
    local cy = barH * 0.5 + math.sin(t * 1.4) * barH * 0.28
    lg.setColor(0, 0, 0, .35)
    lg.circle("fill", cx + 3, cy + 4, 38, 48)
    lg.setColor(1, 1, 1)
    lg.circle("fill", cx, cy, 38, 48)
    lg.setColor(.07, .07, .07)
    lg.setLineWidth(3)
    lg.line(cx - 38, cy, cx + 38, cy)
    lg.line(cx, cy - 38, cx, cy + 38)
    lg.circle("line", cx, cy, 20, 32)
    lg.setLineWidth(1)

    lg.setCanvas()
    lg.pop()
end

--- BGRA (escapi) -> RGBA (LÖVE), straight through the ImageData's own memory.
local function convertFrame()
    local ptr = st.camData:getFFIPointer()
    if not ptr then return false end
    local dst = ffi.cast("uint8_t*", ptr)
    local src = ffi.cast("uint8_t*", st.buf)
    local w, h = st.w, st.h
    for row = 0, h - 1 do
        local srow = FLIP_V and (h - 1 - row) or row
        local d = row * w * 4
        local s = srow * w * 4
        for x = 0, w - 1 do
            dst[d + 0] = src[s + 2]      -- R <- B
            dst[d + 1] = src[s + 1]      -- G
            dst[d + 2] = src[s + 0]      -- B <- R
            dst[d + 3] = 255
            d, s = d + 4, s + 4
        end
    end
    return true
end

function source.update()
    st.newFrame = false
    if st.sim then
        renderSim()
        st.newFrame = true
        return
    end
    if not lib or st.devIndex < 0 then return end
    local ok, done = pcall(function() return lib.isCaptureDone(st.devIndex) end)
    if ok and done == 1 then
        if convertFrame() then
            st.camImage:replacePixels(st.camData)
            st.gotFrame = true
            st.newFrame = true
        end
        pcall(function() lib.doCapture(st.devIndex) end)
    end
end

function source.drawable()
    if st.sim then return st.canvas end
    return st.camImage
end

--- A CPU copy of the current image, mirrored on the GPU when asked. Returns
--- ImageData, which is what Take stores and what the exporter encodes.
function source.grab(mirror)
    local d = source.drawable()
    if not d then return nil end
    local w, h = d:getDimensions()
    if not st.grabCv or st.grabCv:getWidth() ~= w or st.grabCv:getHeight() ~= h then
        st.grabCv = lg.newCanvas(w, h)
    end
    lg.push("all")
    lg.origin()
    lg.setShader()
    lg.setCanvas(st.grabCv)
    lg.clear(0, 0, 0, 1)
    lg.setColor(1, 1, 1, 1)
    if mirror then lg.draw(d, w, 0, 0, -1, 1) else lg.draw(d, 0, 0) end
    lg.setCanvas()
    lg.pop()
    return st.grabCv:newImageData()
end

return source
