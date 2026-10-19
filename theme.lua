-- ===========================================================================
--  LUNCHBOX - Theme
--  The VideoLab design system, translated to LÖVE.
--
--  Every colour, radius and shadow here comes from the VideoLab web
--  recreation's stylesheet. Boxes are drawn by one signed-distance shader
--  that understands what a CSS box can do - a four-stop vertical gradient,
--  per-corner radii, a border, inset highlights and shadows, and outer drop
--  shadows - so each VideoLab rule becomes a style table rather than an
--  approximation. No textures, no images.
--
--  Everything is drawn in a logical coordinate space and scaled to the
--  window. Fonts are rasterised at the device scale (LÖVE's dpiscale), so
--  text stays crisp at any window size.
-- ===========================================================================
local theme = {}

local lg = love.graphics
local utf8 = require("utf8")

-- ------------------------------------------------------------ constants --
theme.REF_W, theme.REF_H = 1100, 820     -- logical space never gets smaller

theme.CAM_W, theme.CAM_H, theme.CAM_FPS = 640, 480, 30
theme.MAX_FRAMES      = 300      -- RAM guard, ~1.2 MB per 640x480 frame
theme.THUMB_H         = 58       -- logical; stored at 2x so they stay sharp
theme.SAVES_PER_FRAME = 2        -- PNGs written per update while exporting
theme.JOG_STEP        = 0.22     -- radians of wheel travel per frame step

-- --------------------------------------------------------------- palette --
local function hex(h, a)
    return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255,
             tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end
theme.hex = hex

local C = {
    -- room + housings
    ROOM = hex"0d0e0f",  ROOM_HI = hex"24272a",
    BODY = hex"2e3134",  BODY_HI = hex"3f4347", BODY_LO = hex"202224",
    RECESS = hex"17191a",
    -- printed ink + keys
    INK = hex"eceef0",   INK_DIM = hex"9aa0a6", INK_FAINT = hex"5d6267",
    KEY_HI = hex"e7e9eb", KEY = hex"c6c9cd",    KEY_LO = hex"a9adb2",
    KEY_INK = hex"1d1f22",
    -- lights
    VFD = hex"74f5e2",   VFD_OFF = hex("74f5e2", 0.13), VFD_BG = hex"041210",
    RED = hex"ff3b2f",   GREEN = hex"45f06c",
    -- VideoLab's lab accents; LunchBox takes the resolution orange as its own
    A_RES = hex"ff9f43", A_FPS = hex"ff5d73", A_ASPECT = hex"3fe0f0",
    A_INTERLACE = hex"ffe14a", A_SAMPLING = hex"ff52e5", A_DEPTH = hex"58ff74",
    WHITE = { 1, 1, 1, 1 }, BLACK = { 0, 0, 0, 1 },
}
C.ACC = C.A_RES
C.MODE = { live = C.RED, review = C.A_RES, play = C.GREEN }
theme.C = C

function theme.col(c, a)
    lg.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
end

function theme.mix(a, b, t)
    return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
             a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t }
end

-- ------------------------------------------------------------- scaling --
theme.scale = 1      -- logical -> window units
theme.dpi   = 1      -- logical -> device pixels (scale * OS DPI)

-- ------------------------------------------------------------------ type --
-- VideoLab's four families. All SIL OFL; licences sit beside the files.
local FAMILY = {
    label = "fonts/BarlowCondensed-SemiBold.ttf",    -- 600: legends, .lbl, .gt
    key   = "fonts/BarlowCondensed-Bold.ttf",        -- 700: key caps
    mark  = "fonts/BarlowCondensed-BoldItalic.ttf",  -- italic 700: wordmark
    cond  = "fonts/BarlowCondensed-Medium.ttf",      -- 500
    body  = "fonts/Barlow-Regular.ttf",              -- help text
    bodyM = "fonts/Barlow-Medium.ttf",
    bodyS = "fonts/Barlow-SemiBold.ttf",
    vfd   = "fonts/ShareTechMono-Regular.ttf",       -- the VFD
    osd   = "fonts/VT323-Regular.ttf",               -- on-screen display, titles
}

local fontCache, metrics = {}, {}
local textCache, textCacheN = {}, 0

local function loadFace(fam, size, dpi)
    local file = FAMILY[fam]
    local ok, f = pcall(lg.newFont, file, size, "normal", dpi)
    if ok then return f end
    return lg.newFont(size, "normal", dpi)          -- missing file: built-in face
end

--- Cap-height metrics, measured once per family by rendering an "H". This
--- is what lets labels sit optically centred in keys and slots, whatever the
--- face - LÖVE only reports ascent and line height.
local function measure(fam)
    if metrics[fam] then return metrics[fam] end
    local f = loadFace(fam, 100, 1)
    local cv = lg.newCanvas(200, 200)
    lg.push("all")
    lg.origin()
    lg.setCanvas(cv)
    lg.clear(0, 0, 0, 0)
    lg.setShader()
    lg.setColor(1, 1, 1, 1)
    lg.setFont(f)
    lg.print("H", 20, 20)
    lg.setCanvas()
    lg.pop()
    local id = cv:newImageData()
    local top, bot = nil, nil
    for y = 0, 199 do
        for x = 0, 199, 2 do
            local _, _, _, a = id:getPixel(x, y)
            if a > 0.5 then
                top = top or y
                bot = y
                break
            end
        end
    end
    cv:release()
    local m = { top = ((top or 30) - 20) / 100, cap = (((bot or 90) - (top or 30)) + 1) / 100 }
    metrics[fam] = m
    return m
end

function theme.loadFonts()
    for fam in pairs(FAMILY) do measure(fam) end
end

--- Change the device scale. Fonts are re-rasterised lazily at the new size.
function theme.setScale(s)
    theme.scale = s
    theme.dpi = s * (lg.getDPIScale and lg.getDPIScale() or 1)
    fontCache, textCache, textCacheN = {}, {}, 0
end

function theme.font(fam, size)
    local key = fam .. ":" .. size
    local f = fontCache[key]
    if not f then
        f = loadFace(fam, size, theme.dpi)
        fontCache[key] = f
    end
    return f
end

--- Text with CSS-style letter-spacing (em) and optical vertical alignment.
---   ha: "l" | "c" | "r"
---   va: "t" (cap top) | "c" (cap middle) | "b" (baseline)
--- Each distinct tracked label is baked once into a batched Text object.
local function batch(f, s, tr)
    local key = tostring(f) .. "\0" .. s .. "\0" .. tr
    local e = textCache[key]
    if e then return e end
    if textCacheN > 600 then textCache, textCacheN = {}, 0 end
    local t, dx = lg.newText(f), 0
    for _, cp in utf8.codes(s) do
        local ch = utf8.char(cp)
        t:add(ch, dx, 0)
        dx = dx + f:getWidth(ch) + tr
    end
    e = { t = t, w = math.max(0, dx - tr) }
    textCache[key] = e
    textCacheN = textCacheN + 1
    return e
end

function theme.textWidth(fam, size, s, em)
    s = tostring(s)
    local f = theme.font(fam, size)
    if not em or em == 0 then return f:getWidth(s) end
    return batch(f, s, em * size).w
end

function theme.text(fam, size, s, x, y, ha, va, em)
    s = tostring(s)
    if s == "" then return 0 end
    local f = theme.font(fam, size)
    local m = metrics[fam] or measure(fam)
    local w, draw
    if em and em ~= 0 then
        local e = batch(f, s, em * size)
        w, draw = e.w, e.t
    else
        w = f:getWidth(s)
    end
    local dx = x
    if ha == "c" then dx = x - w * 0.5 elseif ha == "r" then dx = x - w end
    local dy
    if va == "c" then dy = y - (m.top + m.cap * 0.5) * size
    elseif va == "b" then dy = y - (m.top + m.cap) * size
    else dy = y - m.top * size end
    -- snap to device pixels so glyphs land on the raster grid
    local px = 1 / theme.dpi
    dx = math.floor(dx / px + 0.5) * px
    dy = math.floor(dy / px + 0.5) * px
    if draw then
        lg.draw(draw, dx, dy)
    else
        lg.setFont(f)
        lg.print(s, dx, dy)
    end
    return w
end

function theme.trunc(fam, size, s, maxW, em)
    if theme.textWidth(fam, size, s, em) <= maxW then return s end
    while #s > 3 and theme.textWidth(fam, size, s .. "...", em) > maxW do
        s = s:sub(1, #s - 1)
    end
    return s .. "..."
end

-- ============================================================= box shader --
local BOX_SRC = [[
extern vec2  u_size;     // quad size, logical px
extern vec4  u_rect;     // box inside the quad: x, y, w, h
extern vec4  u_rad;      // corner radii: tl, tr, br, bl
extern vec4  u_c0;
extern vec4  u_c1;
extern vec4  u_c2;
extern vec4  u_c3;
extern vec2  u_stops;    // where c1 and c2 sit (c0 at 0, c3 at 1)
extern vec4  u_bcol;     // border colour
extern float u_bw;       // border width
extern vec4  u_ic[3];    // inset layer colours
extern vec3  u_ig[3];    // inset layer: offsetY, blur, spread
extern float u_mode;     // 0 box, 1 outer shadow, 2 radial fill
extern vec2  u_sh;       // outer shadow: blur, spread
extern vec4  u_radial;   // radial centre (uv) and radii (uv)
extern float u_px;       // one device pixel, in logical px

float sdBox(vec2 p, vec2 b, vec4 r) {
    float rr = (p.x > 0.0) ? ((p.y > 0.0) ? r.z : r.y) : ((p.y > 0.0) ? r.w : r.x);
    rr = min(rr, min(b.x, b.y));
    vec2 q = abs(p) - b + rr;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - rr;
}

vec4 over(vec4 base, vec4 top) {
    float a = top.a + base.a * (1.0 - top.a);
    vec3 c = (top.rgb * top.a + base.rgb * base.a * (1.0 - top.a)) / max(a, 1e-5);
    return vec4(c, a);
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 p  = tc * u_size;
    vec2 hb = u_rect.zw * 0.5;
    vec2 c  = u_rect.xy + hb;

    if (u_mode > 0.5 && u_mode < 1.5) {
        // CSS blur radius ~ 2 sigma; a smoothstep across +-blur/2 reads the same
        float b = max(u_sh.x * 0.5, u_px);
        float d = sdBox(p - c, max(hb + u_sh.y, vec2(0.5)), max(u_rad + u_sh.y, vec4(0.0)));
        float a = 1.0 - smoothstep(-b, b, d);
        return vec4(u_c0.rgb, u_c0.a * a) * color;
    }

    float d = sdBox(p - c, hb, u_rad);
    float cover = 1.0 - smoothstep(-u_px * 0.5, u_px * 0.5, d);
    if (cover <= 0.0) discard;

    vec4 col;
    if (u_mode > 1.5) {
        float t = length((tc - u_radial.xy) / u_radial.zw);
        col = mix(u_c0, u_c1, smoothstep(u_stops.x, u_stops.y, t));
    } else {
        float t = clamp((p.y - u_rect.y) / max(u_rect.w, 1e-4), 0.0, 1.0);
        if (t < u_stops.x)      col = mix(u_c0, u_c1, t / max(u_stops.x, 1e-4));
        else if (t < u_stops.y) col = mix(u_c1, u_c2, (t - u_stops.x) / max(u_stops.y - u_stops.x, 1e-4));
        else                    col = mix(u_c2, u_c3, (t - u_stops.y) / max(1.0 - u_stops.y, 1e-4));
    }

    // inset box-shadows: the part of the box outside a shifted copy of itself
    for (int i = 0; i < 3; i++) {
        if (u_ic[i].a > 0.0) {
            float ds = sdBox(p - c - vec2(0.0, u_ig[i].x), hb - u_ig[i].z, u_rad);
            float b  = max(u_ig[i].y * 0.5, u_px * 0.5);
            float a  = smoothstep(-b, b, ds) * u_ic[i].a;
            col = over(col, vec4(u_ic[i].rgb, a));
        }
    }

    if (u_bw > 0.0) {
        float bin = smoothstep(-u_bw - u_px * 0.5, -u_bw + u_px * 0.5, d);
        col = over(col, vec4(u_bcol.rgb, u_bcol.a * bin));
    }

    col.a *= cover;
    return col * color;
}
]]

local boxShader, quad
local last = {}
local NONE4 = { 0, 0, 0, 0 }
local ZERO3 = { 0, 0, 0 }

local function send(name, v)
    if last[name] == v then return end          -- styles are static tables
    last[name] = v
    boxShader:send(name, v)
end

local function sendN(name, a, b, c, d)
    local l = last[name]
    if type(l) == "table" and l[1] == a and l[2] == b and l[3] == c and l[4] == d then return end
    last[name] = { a, b, c, d }
    if d ~= nil then boxShader:send(name, { a, b, c, d })
    elseif c ~= nil then boxShader:send(name, { a, b, c })
    elseif b ~= nil then boxShader:send(name, { a, b })
    else boxShader:send(name, a) end
end

function theme.initShaders()
    local ok, sh = pcall(lg.newShader, BOX_SRC)
    if ok then boxShader = sh else
        print("LunchBox: box shader unavailable, using flat fallback - " .. tostring(sh))
    end
    quad = lg.newMesh({ { 0, 0, 0, 0 }, { 1, 0, 1, 0 }, { 1, 1, 1, 1 }, { 0, 1, 0, 1 } }, "fan", "static")
    last = {}
end

function theme.hasShader() return boxShader ~= nil end

local function radii(r)
    if type(r) == "table" then return r end
    r = r or 0
    return { r, r, r, r }
end

--- Prepare a style table once: fills defaults and pre-builds the arrays the
--- shader wants, so drawing does no allocation.
---   c = { top } | { top, bottom } | { c0, c1, c2, c3 } with stops for c1, c2
function theme.style(st)
    st.rad = radii(st.r)
    local c = st.c or { C.BLACK }
    if #c == 1 then
        st.c0, st.c1, st.c2, st.c3, st.stops = c[1], c[1], c[1], c[1], { 1, 1 }
    elseif #c == 2 then
        st.c0, st.c1, st.c2, st.c3 = c[1], c[2], c[2], c[2]
        st.stops = st.stops or { 1, 1 }
    else
        st.c0, st.c1, st.c2, st.c3 = c[1], c[2], c[3], c[4] or c[3]
        st.stops = st.stops or { 0.5, 0.5 }
    end
    st.bcol = st.border and st.border[1] or NONE4
    st.bw   = st.border and st.border[2] or 0
    local ic, ig = {}, {}
    for i = 1, 3 do
        local L = st.insets and st.insets[i]
        if L then ic[i] = L[1]; ig[i] = { L[2], L[3] or 0, L[4] or 0 }
        else ic[i] = NONE4; ig[i] = ZERO3 end
    end
    st.ic, st.ig = ic, ig
    st.shadows = st.shadows or {}
    st.mode = st.radial and 2 or 0
    return st
end

local function flatFallback(x, y, w, h, st)
    local r = st.rad[1]
    theme.col(st.c1)
    lg.rectangle("fill", x, y, w, h, r, r)
    if st.bw > 0 then
        theme.col(st.bcol)
        lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, r, r)
    end
end

--- Draw a box in a style. `alpha` fades the whole thing (disabled keys).
function theme.box(x, y, w, h, st, alpha)
    if w <= 0 or h <= 0 then return end
    local r0, g0, b0, a0 = lg.getColor()
    lg.setColor(1, 1, 1, alpha or 1)
    if not boxShader then
        flatFallback(x, y, w, h, st)
        lg.setColor(r0, g0, b0, a0)
        return
    end
    local prev = lg.getShader()
    lg.setShader(boxShader)
    sendN("u_px", 1 / theme.dpi)
    send("u_rad", st.rad)

    for _, s in ipairs(st.shadows) do
        local dx, dy, blur, spread, col = s[1], s[2], s[3], s[4], s[5]
        local e = blur + math.max(0, spread) + 2
        sendN("u_mode", 1)
        sendN("u_size", w + 2 * e, h + 2 * e)
        sendN("u_rect", e, e, w, h)
        sendN("u_sh", blur, spread)
        send("u_c0", col)
        lg.draw(quad, x + dx - e, y + dy - e, 0, w + 2 * e, h + 2 * e)
    end

    sendN("u_mode", st.mode)
    sendN("u_size", w, h)
    sendN("u_rect", 0, 0, w, h)
    send("u_c0", st.c0); send("u_c1", st.c1); send("u_c2", st.c2); send("u_c3", st.c3)
    send("u_stops", st.stops)
    send("u_bcol", st.bcol); sendN("u_bw", st.bw)
    if last.u_ic ~= st.ic then
        last.u_ic = st.ic
        boxShader:send("u_ic", st.ic[1], st.ic[2], st.ic[3])
        boxShader:send("u_ig", st.ig[1], st.ig[2], st.ig[3])
    end
    if st.radial then send("u_radial", st.radial) end
    lg.draw(quad, x, y, 0, w, h)

    lg.setShader(prev)
    lg.setColor(r0, g0, b0, a0)
end

-- ================================================================ styles --
-- Each table below is one VideoLab CSS rule. Shadows are
-- { dx, dy, blur, spread, colour }; insets are { colour, offsetY, blur }.
local B = hex"000000"
local function k(a) return { 0, 0, 0, a } end
local function wv(a) return { 1, 1, 1, a } end

local KEY_SHADOWS  = { { 0, 2, 0, 0, hex"0e0f10" }, { 0, 4, 7, 0, k(.45) } }
local DARK_SHADOWS = { { 0, 2, 0, 0, hex"0a0b0c" }, { 0, 4, 7, 0, k(.45) } }

theme.S = {
    -- .key
    key = theme.style {
        r = 4, c = { C.KEY_HI, C.KEY, C.KEY, C.KEY_LO }, stops = { .48, .48 },
        border = { hex"0c0d0e", 1 },
        insets = { { wv(.9), 1, 0 }, { k(.16), -2, 0 } },
        shadows = KEY_SHADOWS },
    -- .key[aria-pressed=true]
    keyOn = theme.style {
        r = 4, c = { hex"f2f3f4", hex"d6d9dc", hex"d6d9dc", hex"babec2" }, stops = { .48, .48 },
        border = { hex"0c0d0e", 1 },
        insets = { { wv(.9), 1, 0 }, { k(.16), -2, 0 } },
        shadows = KEY_SHADOWS },
    -- .key:active
    keyDown = theme.style {
        r = 4, c = { C.KEY_HI, C.KEY, C.KEY, C.KEY_LO }, stops = { .48, .48 },
        border = { hex"0c0d0e", 1 },
        insets = { { k(.35), 1, 3 } },
        shadows = { { 0, 1, 2, 0, k(.5) } } },
    -- .key.dark
    dark = theme.style {
        r = 4, c = { hex"55595d", hex"404346", hex"404346", hex"333639" }, stops = { .5, .5 },
        border = { hex"0a0b0c", 1 },
        insets = { { wv(.2), 1, 0 }, { k(.3), -2, 0 } },
        shadows = DARK_SHADOWS },
    darkOn = theme.style {
        r = 4, c = { hex"62666a", hex"4a4d51", hex"4a4d51", hex"3b3e41" }, stops = { .5, .5 },
        border = { hex"0a0b0c", 1 },
        insets = { { wv(.2), 1, 0 }, { k(.3), -2, 0 } },
        shadows = DARK_SHADOWS },
    darkDown = theme.style {
        r = 4, c = { hex"55595d", hex"404346", hex"404346", hex"333639" }, stops = { .5, .5 },
        border = { hex"0a0b0c", 1 },
        insets = { { k(.6), 1, 3 } },
        shadows = {} },
    -- .deck
    deck = theme.style {
        r = 10, c = { C.BODY_HI, C.BODY, C.BODY, C.BODY_LO }, stops = { .10, .75 },
        insets = { { wv(.16), 1, 0 }, { k(.45), -2, 0 } },
        shadows = { { 0, 24, 50, -18, k(.85) } } },
    -- .monitor
    monitor = theme.style {
        r = { 16, 16, 6, 6 },
        c = { hex"44484c", hex"35383b", hex"2c2f32", hex"26282a" }, stops = { .08, .70 },
        insets = { { wv(.14), 1, 0 }, { k(.5), -1, 0 } },
        shadows = { { 0, 30, 60, -20, k(.8) } } },
    -- .bezel
    bezel = theme.style {
        r = 12, c = { hex"121314", hex"1b1d1f" },
        insets = { { k(.9), 3, 10 }, { wv(.06), -1, 0 } },
        shadows = { { 0, 1, 0, 0, wv(.08) } } },
    screen = theme.style { r = 6, c = { B } },
    -- .glass: a soft highlight and a vignette, both radial
    glassHi = theme.style {
        r = 6, c = { wv(.07), wv(0) }, radial = { .2, 0, 1.2, .9 }, stops = { 0, .45 } },
    glassVig = theme.style {
        r = 6, c = { k(0), k(.45) }, radial = { .5, .5, .7, .7 }, stops = { .62, 1.0 } },
    -- .vfd
    vfd = theme.style {
        r = 6, c = { hex"0a1f1c", C.VFD_BG, C.VFD_BG, C.VFD_BG }, stops = { .7, .7 },
        border = { B, 1 },
        insets = { { k(.9), 2, 8 } },
        shadows = { { 0, 1, 0, 0, wv(.08) } } },
    -- .panel (recessed lab panel)
    panel = theme.style {
        r = 7, c = { C.RECESS, hex"1c1e20" },
        border = { hex"0c0d0e", 1 },
        insets = { { k(.65), 2, 6 } },
        shadows = { { 0, 1, 0, 0, wv(.07) } } },
    -- .cassette
    cassette = theme.style {
        r = 6, c = { hex"232527", hex"1a1c1e" },
        border = { hex"0f1011", 1 },
        insets = { { wv(.07), 1, 0 } },
        shadows = { { 0, 1, 0, 0, wv(.05) } } },
    cassetteHot = theme.style {
        r = 6, c = { hex"27292b", hex"1d1f21" },
        border = { hex"0f1011", 1 },
        insets = { { wv(.09), 1, 0 } },
        shadows = { { 0, 1, 0, 0, wv(.05) } } },
    -- .cassette .slot
    slot = theme.style {
        r = 4, c = { hex"050505", hex"141516" },
        insets = { { k(.9), 2, 3 } },
        shadows = { { 0, 1, 0, 0, wv(.07) } } },
    -- .help-panel
    help = theme.style {
        r = 8, c = { { 6 / 255, 7 / 255, 8 / 255, .94 } },
        border = { wv(.12), 1 },
        shadows = { { 0, 20, 60, 0, k(.7) } } },
    -- .hbtn and .hbtn.primary
    hbtn    = theme.style { r = 4, c = { wv(0) }, border = { wv(.25), 1 } },
    hbtnHot = theme.style { r = 4, c = { wv(.06) }, border = { wv(.4), 1 } },
    hbtnAcc = theme.style { r = 4, c = { C.ACC } },
    hbtnRed = theme.style { r = 4, c = { C.RED } },
    -- kbd chips
    kbd = theme.style { r = 3, c = { hex"e2e4e6", hex"b8bcc0" }, shadows = { { 0, 1, 0, 0, hex"0b0c0d" } } },
    -- the room
    room = theme.style { r = 0, c = { C.ROOM_HI, hex("24272a", 0) }, radial = { .5, 0, .9, .6 }, stops = { 0, .7 } },
    -- list rows inside dialogs
    rowSel = theme.style { r = 4, c = { wv(.07) }, border = { theme.mix(C.ACC, { 0, 0, 0, 0 }, .45), 1 } },
    rowHot = theme.style { r = 4, c = { wv(.035) } },
}

-- ============================================================ primitives --
--- A 5px LED, as set into the corner of a VideoLab key.
function theme.led(x, y, r, on, col)
    if on then
        theme.col(col, .28)
        lg.circle("fill", x, y, r * 2.2, 18)
        theme.col(col)
    else
        theme.col(hex"4c4442")
    end
    lg.circle("fill", x, y, r, 14)
    if not on then
        theme.col(B, .45)
        lg.arc("fill", "open", x, y, r, math.pi, math.pi * 2, 10)
    end
end

--- .lamp: the monitor's TALLY and POWER lights.
function theme.lamp(x, y, on, col)
    if on then
        theme.col(col, .3)
        lg.circle("fill", x, y, 8, 18)
        theme.col(col, .55)
        lg.circle("fill", x, y, 5.2, 16)
        theme.col(col)
    else
        theme.col(hex"2a1f1e")
    end
    lg.circle("fill", x, y, 3.5, 14)
end

--- .lbl - the caption printed under a key.
function theme.lbl(s, cx, y, col)
    theme.col(col or C.INK_DIM)
    return theme.text("label", 9, s, cx, y, "c", "t", .14)
end

--- .gt - a group title with VideoLab's bracket rules either side.
function theme.gt(s, x, y, w)
    local tw = theme.textWidth("label", 9.5, s, .18)
    local cx = x + w * 0.5
    local midY = y + 1.5
    theme.col(C.INK_DIM)
    theme.text("label", 9.5, s, cx, y, "c", "t", .18)
    local gap = 7
    local l1, l2 = x, cx - tw * 0.5 - gap
    local r1, r2 = cx + tw * 0.5 + gap, x + w
    theme.col(C.INK_FAINT)
    if l2 - l1 >= 8 then
        lg.rectangle("fill", l1, midY, l2 - l1, 1)
        lg.rectangle("fill", l1, midY, 1, 5)
    end
    if r2 - r1 >= 8 then
        lg.rectangle("fill", r1, midY, r2 - r1, 1)
        lg.rectangle("fill", r2 - 1, midY, 1, 5)
    end
end

--- .panel-head - "LAB  NAME ---------" with the name in the accent colour.
function theme.panelHead(x, y, w, lead, name, acc, right)
    theme.col(C.INK_DIM)
    local lw = theme.text("key", 11, lead, x, y, "l", "t", .2)
    acc = acc or C.ACC
    theme.col(acc, .3)
    theme.text("key", 11, name, x + lw + 10, y - 0.5, "l", "t", .2)
    theme.col(acc)
    local nw = theme.text("key", 11, name, x + lw + 10, y, "l", "t", .2)
    local rx = x + lw + 10 + nw + 10
    local rw = w - (rx - x)
    if right then
        local tw = theme.textWidth("label", 9.5, right, .14)
        theme.col(C.INK_DIM)
        theme.text("label", 9.5, right, x + w, y + 0.5, "r", "t", .14)
        rw = rw - tw - 12
    end
    local steps = 24                                -- rule fading to the right
    for i = 0, steps - 1 do
        theme.col(C.INK_FAINT, 1 - i / steps)
        lg.rectangle("fill", rx + rw * i / steps, y + 3.5, rw / steps + 0.5, 1)
    end
end

--- VFD text with the phosphor glow VideoLab gets from text-shadow.
function theme.vfdText(size, s, x, y, ha, va, on, em)
    if on == false then
        theme.col(C.VFD_OFF)
        return theme.text("vfd", size, s, x, y, ha, va, em)
    end
    local g = math.max(0.8, size * 0.06)
    theme.col(C.VFD, .11)
    for i = 0, 7 do
        local a = i * math.pi / 4
        theme.text("vfd", size, s, x + math.cos(a) * g, y + math.sin(a) * g, ha, va, em)
    end
    theme.col(C.VFD)
    return theme.text("vfd", size, s, x, y, ha, va, em)
end

--- An OSD line: VT323 on a black backing, with the 2px drop shadow.
function theme.osdLine(size, s, x, y, col, ha, alpha)
    alpha = alpha or 1
    local w = theme.textWidth("osd", size, s)
    local pad = size * 0.3
    local h = size * 0.95
    local bx = (ha == "r") and (x - w - pad * 2) or x
    theme.col(B, .58 * alpha)
    lg.rectangle("fill", bx, y, w + pad * 2, h)
    local tx = bx + pad
    theme.col(B, .85 * alpha)
    theme.text("osd", size, s, tx + 2, y + h * 0.5 + 2, "l", "c")
    theme.col(col, alpha)
    theme.text("osd", size, s, tx, y + h * 0.5, "l", "c")
    return w + pad * 2, h
end

--- kbd chip, as used in VideoLab's help panel. Returns its width.
function theme.kbd(s, x, cy)
    local w = theme.textWidth("label", 11, s, .06) + 12
    theme.box(x, cy - 9, w, 18, theme.S.kbd)
    theme.col(C.KEY_INK)
    theme.text("label", 11, s, x + w * 0.5, cy, "c", "c", .06)
    return w
end

--- .hbtn: a flat outline button; kind = nil | "acc" | "red".
function theme.hbtn(x, y, w, h, s, kind, hot, disabled)
    local st = (kind == "acc" and theme.S.hbtnAcc) or (kind == "red" and theme.S.hbtnRed)
        or (hot and theme.S.hbtnHot) or theme.S.hbtn
    local a = disabled and .3 or ((kind and hot) and .88 or 1)
    theme.box(x, y, w, h, st, a)
    theme.col(kind and hex"0b0c0d" or C.INK, disabled and .3 or 1)
    theme.text("label", 13, s, x + w * 0.5, y + h * 0.5, "c", "c", .1)
end

--- A VideoLab key. o = { dark, on, down, hot, led, ledCol, ink, label, sub,
--- glyph, size, disabled }.
function theme.key(x, y, w, h, o)
    local st
    if o.dark then
        st = o.down and theme.S.darkDown or (o.on and theme.S.darkOn or theme.S.dark)
    else
        st = o.down and theme.S.keyDown or (o.on and theme.S.keyOn or theme.S.key)
    end
    local dy = o.down and 2 or 0
    local alpha = o.disabled and .45 or 1
    theme.box(x, y + dy, w, h, st, alpha)
    if o.hot and not o.down and not o.disabled then
        theme.col(C.WHITE, o.dark and .05 or .16)
        lg.rectangle("fill", x + 1.5, y + 1.5, w - 3, h - 3, 3, 3)
    end
    y = y + dy

    if o.led then
        local small = h < 30
        theme.led(x + (small and 6 or 7.5), y + (small and 5.5 or 7), small and 2 or 2.5,
                  o.on, o.ledCol or C.ACC)
    end

    local ink = o.ink or (o.dark and C.INK or C.KEY_INK)
    local size = o.size or (h < 30 and 11 or 12)
    local cx = x + w * 0.5
    local cy = y + h * 0.5
    if o.sub then cy = cy - size * 0.34 end

    theme.col(ink, alpha)
    if o.glyph and (not o.label or o.label == "") then
        theme.glyph(o.glyph, cx, cy, math.min(h, w) * 0.24, ink, alpha)
    elseif o.glyph then
        local gs = size * 0.6
        local tw = theme.textWidth("key", size, o.label, .07)
        local total = tw + gs * 2 + 6
        local gx = cx - total * 0.5 + gs
        theme.glyph(o.glyph, gx, cy, gs, ink, alpha)
        theme.col(ink, alpha)
        theme.text("key", size, o.label, gx + gs + 6, cy, "l", "c", .07)
    elseif o.label then
        theme.text("key", size, o.label, cx, cy, "c", "c", .07)
    end
    if o.sub then
        theme.col(o.subInk or ink, (o.subInk and 1 or .62) * alpha)
        theme.text("label", 8.5, o.sub, cx, cy + size * 0.5 + 5, "c", "c", .1)
    end
end

--- A fader: the cassette slot with a key-grey thumb riding in it.
function theme.fader(x, y, w, t, hot, down)
    theme.box(x, y, w, 8, theme.S.slot)
    local kx = x + 7 + (w - 14) * t
    theme.col(C.ACC, (hot or down) and .9 or .7)
    lg.rectangle("fill", x + 3, y + 3, math.max(0, kx - x - 3), 2, 1, 1)
    local tw, th = 14, 20
    local ty = y + 4 - th * 0.5 + (down and 1 or 0)
    theme.box(kx - tw * 0.5, ty, tw, th,
              down and theme.S.keyDown or (hot and theme.S.keyOn or theme.S.key))
    theme.col(C.KEY_INK, .5)
    lg.rectangle("fill", kx - 0.5, ty + 4, 1, th - 8)
    return kx
end

--- A thin scroll indicator for the dialog lists.
function theme.scrollHint(x, y, h, total, visible, top)
    if total <= visible then return end
    theme.col(C.WHITE, .08)
    lg.rectangle("fill", x, y, 3, h, 1.5, 1.5)
    local th = math.max(18, h * visible / total)
    local ty = y + (h - th) * (top / math.max(1, total - visible))
    theme.col(C.ACC, .7)
    lg.rectangle("fill", x, ty, 3, th, 1.5, 1.5)
end

-- ----------------------------------------------------------------- icons --
-- Drawn on a 16-unit grid like VideoLab's inline SVGs; s is the half-size.
function theme.glyph(g, cx, cy, s, c, alpha)
    if not g then return end
    theme.col(c, alpha)
    if g == "rec" then
        lg.circle("fill", cx, cy, s * 0.8, 24)
    elseif g == "play" then
        lg.polygon("fill", cx - s * 0.55, cy - s * 0.75, cx - s * 0.55, cy + s * 0.75, cx + s * 0.8, cy)
    elseif g == "stop" then
        lg.rectangle("fill", cx - s * 0.62, cy - s * 0.62, s * 1.24, s * 1.24, 1, 1)
    elseif g == "prev" then
        lg.polygon("fill", cx + s * 0.65, cy - s * 0.72, cx + s * 0.65, cy + s * 0.72, cx - s * 0.45, cy)
        lg.rectangle("fill", cx - s * 0.8, cy - s * 0.72, s * 0.28, s * 1.44)
    elseif g == "next" then
        lg.polygon("fill", cx - s * 0.65, cy - s * 0.72, cx - s * 0.65, cy + s * 0.72, cx + s * 0.45, cy)
        lg.rectangle("fill", cx + s * 0.52, cy - s * 0.72, s * 0.28, s * 1.44)
    elseif g == "last" then
        lg.polygon("fill", cx - s * 0.95, cy - s * 0.72, cx - s * 0.95, cy + s * 0.72, cx - s * 0.05, cy)
        lg.polygon("fill", cx - s * 0.05, cy - s * 0.72, cx - s * 0.05, cy + s * 0.72, cx + s * 0.85, cy)
    elseif g == "trash" then
        lg.rectangle("fill", cx - s * 0.52, cy - s * 0.35, s * 1.04, s * 1.1, 1, 1)
        lg.rectangle("fill", cx - s * 0.75, cy - s * 0.62, s * 1.5, s * 0.2)
        lg.rectangle("fill", cx - s * 0.22, cy - s * 0.86, s * 0.44, s * 0.26)
    elseif g == "undo" then
        lg.setLineWidth(math.max(1, s * 0.26))
        lg.arc("line", "open", cx + s * 0.1, cy + s * 0.12, s * 0.62, math.rad(170), math.rad(400), 20)
        lg.setLineWidth(1)
        lg.polygon("fill", cx - s * 0.85, cy - s * 0.5, cx - s * 0.15, cy - s * 0.3, cx - s * 0.75, cy + s * 0.25)
    elseif g == "flip" then
        theme.col(c, .45 * (alpha or 1))
        lg.rectangle("fill", cx - s * 0.85, cy - s * 0.62, s * 1.1, s * 0.95, 1, 1)
        theme.col(c, alpha)
        lg.rectangle("fill", cx - s * 0.25, cy - s * 0.3, s * 1.1, s * 0.95, 1, 1)
    elseif g == "cam" then
        lg.rectangle("fill", cx - s * 0.9, cy - s * 0.45, s * 1.8, s * 1.15, 2, 2)
        lg.rectangle("fill", cx - s * 0.32, cy - s * 0.78, s * 0.64, s * 0.36, 1, 1)
        theme.col(hex"c6c9cd", alpha)
        lg.circle("fill", cx, cy + s * 0.12, s * 0.36, 16)
        theme.col(c, alpha)
        lg.circle("fill", cx, cy + s * 0.12, s * 0.2, 12)
    elseif g == "export" then
        lg.rectangle("fill", cx - s * 0.15, cy - s * 0.85, s * 0.3, s * 0.85)
        lg.polygon("fill", cx - s * 0.5, cy - s * 0.05, cx + s * 0.5, cy - s * 0.05, cx, cy + s * 0.5)
        lg.rectangle("fill", cx - s * 0.85, cy + s * 0.62, s * 1.7, s * 0.22)
    elseif g == "new" then
        lg.setLineWidth(math.max(1, s * 0.18))
        lg.rectangle("line", cx - s * 0.75, cy - s * 0.6, s * 1.5, s * 1.2, 1, 1)
        lg.line(cx - s * 0.3, cy, cx + s * 0.3, cy)
        lg.line(cx, cy - s * 0.3, cx, cy + s * 0.3)
        lg.setLineWidth(1)
    elseif g == "dial" then
        lg.setLineWidth(math.max(1, s * 0.18))
        lg.circle("line", cx, cy, s * 0.7, 20)
        lg.setLineWidth(1)
        lg.circle("fill", cx, cy, s * 0.22, 12)
        lg.rectangle("fill", cx - s * 0.06, cy - s * 0.95, s * 0.12, s * 0.4)
    end
end

-- ----------------------------------------------------------------- utils --
function theme.nf(v, digits)
    local s = tostring(math.floor(math.abs(v)))
    while #s < digits do s = "0" .. s end
    return (v < 0 and "-" or "") .. s
end

function theme.nfd(v, decimals) return string.format("%." .. decimals .. "f", v) end

--- HH:MM:SS:FF for a frame index at a frame rate.
function theme.timecode(frame, fps)
    frame = math.max(0, math.floor(frame))
    local ff = frame % fps
    local secs = math.floor(frame / fps)
    return string.format("%02d:%02d:%02d:%02d",
        math.floor(secs / 3600), math.floor(secs / 60) % 60, secs % 60, ff)
end

--- Clip to a logical rect. setScissor works in window units, so convert.
function theme.clip(x, y, w, h)
    if not x then lg.setScissor() return end
    local s = theme.scale
    lg.setScissor(math.floor(x * s), math.floor(y * s), math.ceil(w * s), math.ceil(h * s))
end

--- Draw a Drawable into a rect, optionally mirrored, at a given alpha.
function theme.drawFit(d, x, y, w, h, mirror, alpha)
    if not d then return end
    local iw, ih = d:getDimensions()
    if iw < 2 or ih < 2 then return end
    lg.setColor(1, 1, 1, alpha or 1)
    local sx, sy = w / iw, h / ih
    if mirror then lg.draw(d, x + w, y, 0, -sx, sy) else lg.draw(d, x, y, 0, sx, sy) end
    lg.setColor(1, 1, 1, 1)
end

return theme
