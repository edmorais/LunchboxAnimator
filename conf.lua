-- LUNCHBOX - stop-motion capture station (LÖVE 11.x)
function love.conf(t)
    t.identity           = "lunchbox"     -- save dir: %APPDATA%\LOVE\lunchbox
    t.version            = "11.5"
    t.console            = false          -- set true on Windows to see print()

    t.window.title       = "LunchBox - stop-motion capture station"
    t.window.width       = 1280
    t.window.height      = 820
    t.window.resizable   = true           -- the layout reflows; text stays sharp
    t.window.minwidth    = 1000
    t.window.minheight   = 680
    t.window.vsync       = 1
    t.window.msaa        = 0              -- edges are antialiased in the shader

    -- nothing here makes sound; switching these off keeps the console quiet
    t.modules.audio      = false
    t.modules.sound      = false
    t.modules.physics    = false
    t.modules.joystick   = false
    t.modules.touch      = false
end
