-- ===========================================================================
--  LUNCHBOX - Stop-Motion Capture Station (LÖVE 11.x)
--
--  A frame grabber / line tester in the spirit of the Animation Toolworks
--  LunchBox: live video assist, one-button capture, instant playback, onion
--  skin, jog wheel and a filmstrip, dressed in VideoLab's DVCAM style.
--
--  Boots on the built-in test card. Press SOURCE (C) to pick a camera.
--  See README.md for webcam support on Windows (escapi.dll).
-- ===========================================================================
local app   = require("app")
local theme = require("theme")

function love.load()
    app.load()
end

function love.resize(w, h)
    app.resize(w, h)
end

function love.update(dt)
    app.update(dt)
end

function love.draw()
    -- everything is laid out in logical units and scaled to the window
    love.graphics.push()
    love.graphics.scale(theme.scale)
    app.draw()
    love.graphics.pop()
end

function love.mousepressed(x, y, button)  app.mousepressed(x, y, button) end
function love.mousemoved(x, y)            app.mousemoved(x, y) end
function love.mousereleased(x, y, button) app.mousereleased(x, y, button) end
function love.wheelmoved(dx, dy)          app.wheelmoved(dx, dy) end
function love.keypressed(key)             app.keypressed(key) end
function love.keyreleased(key)            app.keyreleased(key) end
