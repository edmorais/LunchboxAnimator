-- ===========================================================================
--  LUNCHBOX - Take
--  The captured frames, their thumbnails and one level of undo.
--
--  Frames are held as ImageData (system RAM). Only thumbnails plus four
--  reusable textures ever sit on the GPU: one review slot and three onion
--  slots, refreshed with Image:replacePixels when the playhead moves. A 300
--  frame take is therefore ~350 MB of RAM and a few MB of VRAM rather than
--  300 full textures.
-- ===========================================================================
local theme = require("theme")
local lg = love.graphics

local Take = {}
Take.__index = Take

function Take.new()
    local self = setmetatable({}, Take)
    self.frames  = {}          -- ImageData, shared between duplicate exposures
    self.thumbs  = {}          -- Image
    self.playhead = -1         -- 0-based to match the rest of the port
    self.number   = 1
    self.thumbW   = 80
    self.undoFrame, self.undoThumb, self.undoIndex = nil, nil, -1
    self.reviewImg, self.reviewIdx = nil, -2
    self.ghostImg, self.ghostIdx = { nil, nil, nil }, { -2, -2, -2 }
    return self
end

function Take:size()    return #self.frames end
function Take:isEmpty() return #self.frames == 0 end

function Take:recalcThumbW()
    local m = 0
    for _, t in ipairs(self.thumbs) do m = math.max(m, t:getWidth() * 0.5) end
    self.thumbW = (m < 2) and 80 or m
end

function Take:invalidate()
    self.reviewIdx = -2
    self.ghostIdx = { -2, -2, -2 }
end

--- Stores one ImageData and one thumbnail, referenced `copies` times, so
--- shooting on twos or threes costs no extra memory but still exports as
--- separate files.
function Take:add(data, copies)
    if not data then return 0 end
    local w, h = data:getWidth(), data:getHeight()
    -- stored at twice the drawn height so they stay sharp in a big window
    local th = theme.THUMB_H * 2
    local tw = math.max(2, math.floor(w * th / h + 0.5))

    -- LÖVE cannot resize ImageData, so scale through a canvas.
    local full = lg.newImage(data)
    local cv   = lg.newCanvas(tw, th)
    lg.push("all")
    lg.origin()
    lg.setShader()
    lg.setCanvas(cv)
    lg.clear(0, 0, 0, 1)
    lg.setColor(1, 1, 1, 1)
    lg.draw(full, 0, 0, 0, tw / w, th / h)
    lg.setCanvas()
    lg.pop()
    local thumb = lg.newImage(cv:newImageData())
    thumb:setFilter("linear", "linear")
    full:release()
    cv:release()

    for _ = 1, copies do
        self.frames[#self.frames + 1] = data
        self.thumbs[#self.thumbs + 1] = thumb
    end
    self:recalcThumbW()
    self:invalidate()
    return copies
end

function Take:removeAt(i)                     -- i is 0-based
    if i < 0 or i >= self:size() then return end
    self.undoFrame = self.frames[i + 1]
    self.undoThumb = self.thumbs[i + 1]
    self.undoIndex = i
    table.remove(self.frames, i + 1)
    table.remove(self.thumbs, i + 1)
    self:recalcThumbW()
    self:invalidate()
end

function Take:canUndo() return self.undoFrame ~= nil end

function Take:restore()
    if not self.undoFrame then return false end
    local i = math.max(0, math.min(self:size(), self.undoIndex))
    table.insert(self.frames, i + 1, self.undoFrame)
    table.insert(self.thumbs, i + 1, self.undoThumb)
    self.undoFrame, self.undoThumb = nil, nil
    self:recalcThumbW()
    self:invalidate()
    self.playhead = i
    return true
end

function Take:clear()
    self.frames, self.thumbs = {}, {}
    self.undoFrame, self.undoThumb, self.undoIndex = nil, nil, -1
    self.playhead = -1
    self.thumbW = 80
    self:invalidate()
end

function Take:data(i)
    if i < 0 or i >= self:size() then return nil end
    return self.frames[i + 1]
end

function Take:thumb(i)
    if i < 0 or i >= self:size() then return nil end
    return self.thumbs[i + 1]
end

local function refresh(img, idx, data, wantIdx)
    if not img or img:getWidth() ~= data:getWidth()
                or img:getHeight() ~= data:getHeight() then
        if img then img:release() end
        return lg.newImage(data), wantIdx
    end
    if idx ~= wantIdx then img:replacePixels(data) end
    return img, wantIdx
end

--- The frame under the playhead, uploaded on demand into one texture.
function Take:image(i)
    local d = self:data(i)
    if not d then return nil end
    if self.reviewIdx ~= i or not self.reviewImg then
        self.reviewImg, self.reviewIdx = refresh(self.reviewImg, self.reviewIdx, d, i)
    end
    return self.reviewImg
end

--- One texture per onion layer, refreshed only when that layer's frame changes.
function Take:ghost(slot, i)
    local d = self:data(i)
    if not d or slot < 1 or slot > 3 then return nil end
    if self.ghostIdx[slot] ~= i or not self.ghostImg[slot] then
        local img, idx = refresh(self.ghostImg[slot], self.ghostIdx[slot], d, i)
        self.ghostImg[slot], self.ghostIdx[slot] = img, idx
    end
    return self.ghostImg[slot]
end

return Take
