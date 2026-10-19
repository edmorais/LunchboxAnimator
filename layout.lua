-- ===========================================================================
--  LUNCHBOX - Layout
--  Pure geometry: given the logical window size and the picture's aspect
--  ratio, where everything goes. No drawing and no LÖVE calls, so the same
--  numbers drive rendering and hit-testing and can be checked on their own.
--
--  The room holds three objects, as in VideoLab: a monitor that hugs the
--  picture's aspect ratio and sits on a stand, the filmstrip deck under it,
--  and the control deck down the right-hand side.
-- ===========================================================================
local layout = {}

layout.M        = 14      -- room margin
layout.DECK_W   = 352     -- control deck
layout.FILM_H   = 128     -- filmstrip deck
layout.STAND_H  = 14
layout.MON_PAD  = 16      -- monitor housing padding (top and sides)
layout.BEZEL    = 12
layout.FOOT_H   = 44
layout.DECK_PAD = 18
layout.CONTENT_H = 744    -- the control deck's content block

local function R(x, y, w, h) return { x = x, y = y, w = w, h = h } end
layout.R = R

--- Scale and logical size for a window. The logical space is never smaller
--- than REF_W x REF_H, so the deck always fits; a bigger window gives the
--- monitor more room rather than stretching the controls.
function layout.scaleFor(winW, winH, refW, refH)
    local s = math.min(winW / refW, winH / refH)
    s = math.max(0.5, math.min(4, s))
    s = math.floor(s * 50 + 0.5) / 50         -- quantised: fonts re-rasterise less
    return s, winW / s, winH / s
end

function layout.compute(LW, LH, aspect)
    local M = layout.M
    local L = { LW = LW, LH = LH }

    -- control deck -----------------------------------------------------------
    -- the deck is as tall as its controls and sits centred, so a tall window
    -- shows a deck in a room rather than a slab with a void inside it
    local deckH = math.min(LH - 2 * M, layout.CONTENT_H + 2 * layout.DECK_PAD + 12)
    L.deck = R(LW - M - layout.DECK_W, math.floor((LH - deckH) * 0.5), layout.DECK_W, deckH)
    local cx = L.deck.x + layout.DECK_PAD
    local cw = L.deck.w - 2 * layout.DECK_PAD
    local spare = L.deck.h - 2 * layout.DECK_PAD - layout.CONTENT_H
    local y0 = L.deck.y + layout.DECK_PAD + math.max(0, math.floor(spare * 0.5))
    L.content = R(cx, y0, cw, layout.CONTENT_H)

    local function at(dy) return y0 + dy end
    local g6 = 6
    local w2 = (cw - g6) / 2
    local w3 = (cw - 2 * g6) / 3
    local w6 = (cw - 5 * g6) / 6

    L.brand    = R(cx, at(0), cw, 24)
    L.cassette = R(cx, at(34), cw, 40)
    L.vfd      = R(cx, at(84), cw, 80)

    -- RECORD
    L.capture  = R(cx, at(180), cw, 44)
    L.delete   = R(cx, at(232), w2, 30)
    L.undo     = R(cx + w2 + g6, at(232), w2, 30)
    L.gtRecord = R(cx, at(270), cw, 10)

    -- TRANSPORT
    L.trans = {}
    for i = 1, 6 do L.trans[i] = R(cx + (i - 1) * (w6 + g6), at(294), w6, 36) end
    L.loop     = R(cx, at(352), w3, 26)
    L.ping     = R(cx + w3 + g6, at(352), w3, 26)
    L.autolive = R(cx + 2 * (w3 + g6), at(352), w3, 26)
    L.gtTrans  = R(cx, at(386), cw, 10)

    -- TIMING
    local fpsW = 154
    L.fps      = R(cx, at(410), fpsW, 34)
    L.exp      = R(cx + fpsW + 12, at(410), cw - fpsW - 12, 34)
    L.short    = R(cx, at(466), cw, 28)
    L.lapse    = R(cx, at(504), 70, 26)
    L.interval = R(cx + 82, at(502), cw - 82, 28)
    L.gtTiming = R(cx, at(538), cw, 10)

    -- ONION SKIN
    L.onion    = R(cx, at(562), cw, 30)
    L.mix      = R(cx, at(600), cw, 28)
    L.gtOnion  = R(cx, at(636), cw, 10)

    -- SYSTEM
    L.jog      = R(cx + 6, at(660), 56, 56)
    local kx   = cx + 80
    local kw   = cw - 80
    local k2   = (kw - g6) / 2
    local k3   = (kw - 2 * g6) / 3
    L.newtake  = R(kx, at(660), k2, 30)
    L.export   = R(kx + k2 + g6, at(660), k2, 30)
    L.source   = R(kx, at(696), k3, 30)
    L.adjust   = R(kx + k3 + g6, at(696), k3, 30)
    L.help     = R(kx + 2 * (k3 + g6), at(696), k3, 30)
    L.gtSystem = R(cx, at(734), cw, 10)

    -- the adjust page replaces everything under the VFD
    L.adjustArea = R(cx, at(180), cw, layout.CONTENT_H - 180)

    -- left column: filmstrip deck and monitor -------------------------------
    local colX = M
    local colW = L.deck.x - M - colX
    L.col = R(colX, M, colW, LH - 2 * M)

    local P, Bz, F = layout.MON_PAD, layout.BEZEL, layout.FOOT_H
    local FH, SH = layout.FILM_H, layout.STAND_H
    local availW = colW - 2 * P - 2 * Bz
    local availH = (LH - 2 * M) - FH - SH - P - F - 2 * Bz
    aspect = (aspect and aspect > 0.2) and aspect or (4 / 3)
    local sw = availW
    local sh = sw / aspect
    if sh > availH then sh = availH; sw = sh * aspect end
    sw, sh = math.floor(sw), math.floor(sh)
    local hw, hh = sw + 2 * Bz + 2 * P, sh + 2 * Bz + P + F

    -- the monitor sits on its stand on the filmstrip deck; the three move as one
    local stackH = hh + SH - 1 + FH
    local top = M + math.floor(((LH - 2 * M) - stackH) * 0.5)
    L.monitor = R(math.floor(colX + (colW - hw) * 0.5), top, hw, hh)
    local regBot = top + hh
    L.film = R(colX, regBot + SH - 1, colW, FH)
    L.filmPanel = R(L.film.x + 10, L.film.y + 10, L.film.w - 20, L.film.h - 20)
    L.strip = R(L.filmPanel.x + 10, L.filmPanel.y + 28, L.filmPanel.w - 20, L.filmPanel.h - 36)
    L.bezel   = R(L.monitor.x + P, L.monitor.y + P, sw + 2 * Bz, sh + 2 * Bz)
    L.screen  = R(L.bezel.x + Bz, L.bezel.y + Bz, sw, sh)
    L.foot    = R(L.monitor.x + P, L.bezel.y + L.bezel.h, L.monitor.w - 2 * P, F)

    local standW = math.min(L.monitor.w * 0.42, 300)
    L.stand = R(L.monitor.x + (L.monitor.w - standW) * 0.5, regBot - 1, standW, layout.STAND_H)

    -- small dark keys on the monitor foot, as VideoLab's 4:3 / 16:9 pair
    local fy = L.foot.y + (F - 24) * 0.5
    local lampsW = 132
    local kx2 = L.foot.x + L.foot.w - lampsW - 3 * 62 - 2 * 6
    L.mirror  = R(kx2, fy, 62, 24)
    L.guides  = R(kx2 + 68, fy, 62, 24)
    L.osd     = R(kx2 + 136, fy, 62, 24)
    L.lamps   = R(L.foot.x + L.foot.w - lampsW + 14, L.foot.y, lampsW - 14, F)

    -- dialogs ------------------------------------------------------------------
    local function centred(w, h)
        w, h = math.min(w, LW - 32), math.min(h, LH - 32)
        return R(math.floor((LW - w) * 0.5), math.floor((LH - h) * 0.5), w, h)
    end
    L.picker  = centred(780, 510)
    L.helpBox = centred(820, 520)
    L.confirm = centred(470, 196)

    return L
end

--- Picker internals, shared by drawing and hit-testing.
layout.PK_DEV_ROWS, layout.PK_MODE_ROWS = 7, 8
layout.PK_DEV_RH, layout.PK_MODE_RH = 34, 29

function layout.picker(P)
    local q = {}
    q.devList  = R(P.x + 22, P.y + 124, 360, layout.PK_DEV_ROWS * layout.PK_DEV_RH + 8)
    q.modeList = R(P.x + P.w - 22 - 352, P.y + 124, 352, layout.PK_MODE_ROWS * layout.PK_MODE_RH + 8)
    local by = P.y + P.h - 22 - 34
    q.rescan = R(P.x + 22, by, 120, 34)
    q.adjust = R(P.x + 150, by, 120, 34)
    q.cancel = R(P.x + P.w - 22 - 140 - 8 - 150, by, 140, 34)
    q.use    = R(P.x + P.w - 22 - 150, by, 150, 34)
    q.close  = R(P.x + P.w - 44, P.y + 12, 30, 30)
    return q
end

function layout.confirm(P)
    local by = P.y + P.h - 20 - 34
    return {
        cancel = R(P.x + P.w - 20 - 150 - 8 - 130, by, 130, 34),
        yes    = R(P.x + P.w - 20 - 150, by, 150, 34),
    }
end

--- Camera adjust rows inside the deck area.
layout.AJ_ROWS = 10
function layout.adjust(A)
    local q = { rows = {} }
    q.head = R(A.x, A.y, A.w, 14)
    local top, rh = A.y + 26, 44
    for i = 1, layout.AJ_ROWS do
        local y = top + (i - 1) * rh
        q.rows[i] = {
            label = R(A.x, y, A.w - 60, 12),
            auto  = R(A.x + A.w - 52, y - 4, 52, 20),
            fader = R(A.x, y + 14, A.w, 22),
        }
    end
    local by = A.y + A.h - 30
    q.revert = R(A.x, by, (A.w - 6) / 2, 30)
    q.close  = R(A.x + (A.w + 6) / 2, by, (A.w - 6) / 2, 30)
    return q
end

function layout.inside(r, x, y)
    return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

return layout
