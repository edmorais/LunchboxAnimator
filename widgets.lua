-- ===========================================================================
--  LUNCHBOX - Widgets
--  The deck's controls, drawn as VideoLab parts: grey and dark keys with
--  LEDs, printed captions, faders in recessed slots, a jog wheel and the
--  filmstrip.
--
--  Widgets never reach into the app: they report through an `emit` callback
--  and, where they need data, through narrow functions. They are created
--  once and positioned by the layout with setRect, so the window can be
--  resized freely.
-- ===========================================================================
local theme = require("theme")
local lg, C = love.graphics, theme.C

-- math.atan2 is 5.1-only; keep working if a future LÖVE ships a newer Lua
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local M = {}

local function class(base)
    local c = {}
    c.__index = c
    if base then setmetatable(c, { __index = base }) end
    c.new = function(...)
        local o = setmetatable({}, c)
        if o.init then o:init(...) end
        return o
    end
    return c
end

-- ------------------------------------------------------------------ base --
local Widget = class()
M.Widget = Widget

function Widget:init(id)
    self.id = id
    self.x, self.y, self.w, self.h = 0, 0, 0, 0
    self.enabled, self.hot, self.down, self.visible = true, false, false, true
end

function Widget:setRect(x, y, w, h)
    self.x, self.y, self.w, self.h = x, y, w, h
    return self
end

function Widget:hit(mx, my)
    return self.visible and mx >= self.x and mx < self.x + self.w
       and my >= self.y and my < self.y + self.h
end

function Widget:hover(mx, my) self.hot = self.enabled and self:hit(mx, my) end
function Widget:tick(dt) end
function Widget:draw() end
function Widget:press(mx, my) return false end
function Widget:drag(mx, my) end
function Widget:release() self.down = false end
function Widget:wheel(d) end
function Widget:cursor() return "hand" end

function Widget:fire()
    if self.emit and self.id and self.id ~= "" then self.emit(self.id) end
end

-- ----------------------------------------------------------------- key ---
--- A push key. o = { dark, ink, glyph, sub, lbl, repeats, size, ledCol }
local Btn = class(Widget)
M.Btn = Btn

function Btn:init(id, label, o)
    Widget.init(self, id)
    o = o or {}
    self.label = label or ""
    self.dark, self.ink, self.glyph, self.sub = o.dark, o.ink, o.glyph, o.sub
    self.subInk = o.subInk
    self.lbl, self.repeats, self.size = o.lbl, o.repeats, o.size
    self.held = false                 -- true while a hold-to-act key is down
    self.heldSince, self.lastRepeat = 0, 0
end

function Btn:press(mx, my)
    if not self.enabled or not self:hit(mx, my) then return false end
    self.down = true
    self.heldSince = love.timer.getTime()
    self.lastRepeat = self.heldSince
    self:fire()
    return true
end

function Btn:tick()
    if not (self.down and self.repeats) then return end
    local now = love.timer.getTime()
    if now - self.heldSince > 0.38 and now - self.lastRepeat > 0.07 then
        self.lastRepeat = now
        self:fire()
    end
end

function Btn:draw()
    if not self.visible then return end
    theme.key(self.x, self.y, self.w, self.h, {
        dark = self.dark, down = self.down or self.held, hot = self.hot,
        ink = self.ink, label = self.label, glyph = self.glyph, sub = self.sub,
        subInk = self.subInk, size = self.size, disabled = not self.enabled })
    if self.lbl then theme.lbl(self.lbl, self.x + self.w * 0.5, self.y + self.h + 6) end
end

-- ---------------------------------------------------------- latching key --
--- A key with an LED that latches on and off.
local Toggle = class(Widget)
M.Toggle = Toggle

function Toggle:init(id, label, on, o)
    Widget.init(self, id)
    o = o or {}
    self.label, self.on = label, on
    self.dark, self.ledCol, self.lbl, self.size = o.dark, o.ledCol, o.lbl, o.size
end

function Toggle:press(mx, my)
    if not self.enabled or not self:hit(mx, my) then return false end
    self.on = not self.on
    self.down = true
    self:fire()
    return true
end

function Toggle:draw()
    if not self.visible then return end
    theme.key(self.x, self.y, self.w, self.h, {
        dark = self.dark, on = self.on, down = self.down, hot = self.hot,
        led = true, ledCol = self.ledCol, label = self.label, size = self.size,
        disabled = not self.enabled })
    if self.lbl then theme.lbl(self.lbl, self.x + self.w * 0.5, self.y + self.h + 6) end
end

-- ------------------------------------------------------- key selector ----
--- A row of keys of which exactly one is pressed, LED lit - the way
--- VideoLab's lab panels choose a value. The rect covers the keys; the
--- caption is printed underneath, as a bracketed group title or a .lbl.
local Segmented = class(Widget)
M.Segmented = Segmented

function Segmented:init(id, caption, opts, sel, o)
    Widget.init(self, id)
    o = o or {}
    self.caption, self.opts, self.sel = caption, opts, sel
    self.subs, self.capStyle, self.gap = o.subs, o.capStyle or "gt", o.gap or 6
    self.pressIdx, self.hotIdx = nil, nil
end

function Segmented:cycle() self.sel = (self.sel % #self.opts) + 1 end

function Segmented:keyRect(i)
    local n, g = #self.opts, self.gap
    local kw = (self.w - g * (n - 1)) / n
    return self.x + (i - 1) * (kw + g), self.y, kw, self.h
end

function Segmented:indexAt(mx, my)
    if not self:hit(mx, my) then return nil end
    for i = 1, #self.opts do
        local kx, _, kw = self:keyRect(i)
        if mx >= kx - self.gap * 0.5 and mx < kx + kw + self.gap * 0.5 then return i end
    end
end

function Segmented:hover(mx, my)
    Widget.hover(self, mx, my)
    self.hotIdx = self.hot and self:indexAt(mx, my) or nil
end

function Segmented:press(mx, my)
    if not self.enabled then return false end
    local i = self:indexAt(mx, my)
    if not i then return false end
    self.sel, self.pressIdx, self.down = i, i, true
    self:fire()
    return true
end

function Segmented:release() self.down, self.pressIdx = false, nil end

function Segmented:draw()
    if not self.visible then return end
    for i, opt in ipairs(self.opts) do
        local kx, ky, kw, kh = self:keyRect(i)
        theme.key(kx, ky, kw, kh, {
            on = (i == self.sel), down = (i == self.pressIdx), hot = (i == self.hotIdx),
            led = true, label = opt, sub = self.subs and self.subs[i],
            disabled = not self.enabled })
    end
    if self.caption then
        if self.capStyle == "lbl" then
            theme.lbl(self.caption, self.x + self.w * 0.5, self.y + self.h + 6)
        else
            theme.gt(self.caption, self.x, self.y + self.h + 7, self.w)
        end
    end
end

-- ----------------------------------------------------------------- fader --
--- Caption and value printed above a recessed slot with a key-grey thumb.
local Fader = class(Widget)
M.Fader = Fader

function Fader:init(id, caption, lo, hi, v, integer, unit)
    Widget.init(self, id)
    self.caption, self.lo, self.hi, self.val = caption, lo, hi, v
    self.integer, self.unit = integer, unit or ""
end

function Fader:slotY() return self.y + self.h - 10 end

function Fader:setFrom(mx)
    local t = math.max(0, math.min(1, (mx - (self.x + 7)) / (self.w - 14)))
    self.val = self.lo + t * (self.hi - self.lo)
    if self.integer then self.val = math.floor(self.val + 0.5) end
end

function Fader:nudge(d)
    self.val = math.max(self.lo, math.min(self.hi, self.val + d))
    if self.integer then self.val = math.floor(self.val + 0.5) end
end

function Fader:press(mx, my)
    if not self.enabled or not self:hit(mx, my) then return false end
    self.down = true
    self:setFrom(mx)
    self:fire()
    return true
end

function Fader:drag(mx, my) if self.down then self:setFrom(mx) end end

function Fader:valueText()
    return (self.integer and tostring(math.floor(self.val)) or theme.nfd(self.val, 1)) .. self.unit
end

function Fader:draw()
    if not self.visible then return end
    theme.col(C.INK_DIM)
    theme.text("label", 9, self.caption, self.x, self.y, "l", "t", .14)
    theme.col((self.hot or self.down) and C.INK or C.INK_DIM)
    theme.text("label", 9, self:valueText(), self.x + self.w, self.y, "r", "t", .14)
    theme.fader(self.x, self:slotY(), self.w,
                (self.val - self.lo) / (self.hi - self.lo), self.hot, self.down)
end

-- ------------------------------------------------------------- jog wheel --
local Jog = class(Widget)
M.Jog = Jog

function Jog:init(id)
    Widget.init(self, id)
    self.ang, self.lastA, self.accum = 0, 0, 0
end

function Jog:setRect(x, y, w, h)
    Widget.setRect(self, x, y, w, h)
    self.rad = math.min(w, h) * 0.5
    self.ccx, self.ccy = x + w * 0.5, y + h * 0.5
    return self
end

function Jog:hit(mx, my)
    if not self.visible then return false end
    local dx, dy = mx - self.ccx, my - self.ccy
    return dx * dx + dy * dy <= self.rad * self.rad
end

function Jog:press(mx, my)
    if not self.enabled or not self:hit(mx, my) then return false end
    self.down = true
    self.lastA = atan2(my - self.ccy, mx - self.ccx)
    return true
end

function Jog:drag(mx, my)
    if not self.down then return end
    local a = atan2(my - self.ccy, mx - self.ccx)
    local d = a - self.lastA
    while d > math.pi do d = d - 2 * math.pi end
    while d < -math.pi do d = d + 2 * math.pi end
    self.lastA = a
    self.ang = self.ang + d
    self.accum = self.accum + d
    while math.abs(self.accum) >= theme.JOG_STEP do    -- detented
        local dir = self.accum > 0 and 1 or -1
        if self.onStep then self.onStep(dir) end
        self.accum = self.accum - dir * theme.JOG_STEP
    end
end

function Jog:cursor() return "sizeall" end

local jogRing, jogKnob, jogDimple
function Jog:draw()
    if not self.visible then return end
    jogRing = jogRing or theme.style { r = 999, c = { theme.hex"050505", theme.hex"161718" },
        insets = { { { 0, 0, 0, .9 }, 2, 4 } }, shadows = { { 0, 1, 0, 0, { 1, 1, 1, .07 } } } }
    jogKnob = jogKnob or theme.style { r = 999,
        c = { theme.hex"5b5f63", theme.hex"404346", theme.hex"404346", theme.hex"2e3134" }, stops = { .5, .5 },
        border = { theme.hex"0a0b0c", 1 },
        insets = { { { 1, 1, 1, .22 }, 1, 0 }, { { 0, 0, 0, .35 }, -2, 0 } },
        shadows = { { 0, 3, 0, 0, theme.hex"0a0b0c" }, { 0, 6, 10, 0, { 0, 0, 0, .5 } } } }
    jogDimple = jogDimple or theme.style { r = 999, c = { theme.hex"25282a", theme.hex"3a3d40" },
        insets = { { { 0, 0, 0, .8 }, 1, 3 } } }

    local cx, cy, r = self.ccx, self.ccy, self.rad
    theme.box(cx - r, cy - r, r * 2, r * 2, jogRing)
    local kr = r - 5
    theme.box(cx - kr, cy - kr + (self.down and 1 or 0), kr * 2, kr * 2, jogKnob)
    local ky = cy + (self.down and 1 or 0)

    theme.col(C.BLACK, .35)                             -- grip ribs
    lg.setLineWidth(1.4)
    for i = 0, 35 do
        local a = self.ang + i * math.pi * 2 / 36
        lg.line(cx + math.cos(a) * kr * 0.84, ky + math.sin(a) * kr * 0.84,
                cx + math.cos(a) * kr * 0.97, ky + math.sin(a) * kr * 0.97)
    end
    lg.setLineWidth(1)

    local dr = kr * 0.2
    local dx, dy = cx + math.cos(self.ang) * kr * 0.55, ky + math.sin(self.ang) * kr * 0.55
    theme.box(dx - dr, dy - dr, dr * 2, dr * 2, jogDimple)
    theme.led(dx, dy, 2.2, self.down or self.hot, C.ACC)
end

-- ------------------------------------------------------------- filmstrip --
local Strip = class(Widget)
M.Strip = Strip

function Strip:init(id)
    Widget.init(self, id)
    self.scroll, self.target = 0, 0
end

function Strip:cellW()
    return (self.take and self.take.thumbW or 80) + 8
end

function Strip:maxScroll()
    if not self.take then return 0 end
    return math.max(0, self.take:size() * self:cellW() - self.w + 8)
end

function Strip:follow()
    if not self.take or self.take:isEmpty() then self.target = 0 return end
    local cw = self:cellW()
    self.target = math.max(0, math.min(self:maxScroll(),
        self.take.playhead * cw - self.w * 0.5 + cw * 0.5))
end

function Strip:indexAt(mx)
    return math.floor((mx - self.x - 4 + self.scroll) / self:cellW())
end

function Strip:press(mx, my)
    if not self.enabled or not self:hit(mx, my) or not self.take then return false end
    self.down = true
    local i = self:indexAt(mx)
    if i >= 0 and i < self.take:size() and self.onScrub then self.onScrub(i) end
    return true
end

function Strip:drag(mx, my)
    if not self.down or not self.take then return end
    local i = self:indexAt(mx)
    if i >= 0 and i < self.take:size() and self.onScrub then self.onScrub(i) end
end

function Strip:wheel(d)
    self.target = math.max(0, math.min(self:maxScroll(), self.target + d * 48))
end

function Strip:tick(dt)
    self.scroll = self.scroll + (self.target - self.scroll) * math.min(1, 17 * (dt or 0.016))
end

function Strip:draw()
    if not self.visible then return end
    local x, y, w, h = self.x, self.y, self.w, self.h
    local cw = self:cellW()

    -- perforations along both edges, scrolling with the film
    local off = -((self.scroll * 0.5) % 16)
    theme.col(C.BLACK, .7)
    for pass = 0, 1 do
        local py = (pass == 0) and y + 1 or y + h - 6
        local px = x + off
        while px < x + w do
            if px + 8 > x and px < x + w - 2 then
                lg.rectangle("fill", math.max(x, px + 3), py, 7, 5, 1, 1)
            end
            px = px + 16
        end
    end

    if not self.take or self.take:isEmpty() then
        theme.col(C.INK_FAINT)
        theme.text("label", 11, "NO FRAMES YET", x + w * 0.5, y + h * 0.5 - 7, "c", "c", .18)
        theme.col(C.INK_FAINT, .8)
        theme.text("body", 12, "Press CAPTURE or Space to grab the first one.",
                   x + w * 0.5, y + h * 0.5 + 10, "c", "c")
        return
    end

    theme.clip(x, y, w, h)
    local th0 = theme.THUMB_H
    local ty  = y + math.floor((h - th0) * 0.5)
    local first = math.max(0, math.floor(self.scroll / cw) - 1)
    local last  = math.min(self.take:size() - 1, math.floor((self.scroll + w) / cw) + 1)
    for i = first, last do
        local img = self.take:thumb(i)
        if img then
            local tw  = img:getWidth() * 0.5
            local tx  = x + 4 + i * cw - self.scroll + (self.take.thumbW - tw) * 0.5
            local cur = (i == self.take.playhead)
            theme.col(C.BLACK)
            lg.rectangle("fill", tx - 1, ty - 1, tw + 2, th0 + 2, 2, 2)
            lg.setColor(1, 1, 1, 1)
            lg.draw(img, tx, ty, 0, 0.5, 0.5)
            if cur then
                theme.col(C.ACC, .25)
                lg.setLineWidth(5)
                lg.rectangle("line", tx - 2.5, ty - 2.5, tw + 5, th0 + 5, 3, 3)
                theme.col(C.ACC)
                lg.setLineWidth(2)
                lg.rectangle("line", tx - 1.5, ty - 1.5, tw + 3, th0 + 3, 2, 2)
                lg.setLineWidth(1)
            end
            -- frame number, OSD-style, in the thumbnail's corner
            local num = tostring(i + 1)
            local nw = theme.textWidth("osd", 15, num) + 6
            theme.col(C.BLACK, .62)
            lg.rectangle("fill", tx, ty + th0 - 13, nw, 13)
            theme.col(cur and C.ACC or C.INK)
            theme.text("osd", 15, num, tx + 3, ty + th0 - 6.5, "l", "c")
        end
    end
    theme.clip()
end

return M
