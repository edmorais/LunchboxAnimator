-- ===========================================================================
--  LUNCHBOX - Storage
--  love.filesystem can only write inside the save directory (%APPDATA% on
--  Windows), so exports go out through plain Lua io instead: ImageData is
--  encoded to a FileData and the bytes are written to an absolute path next
--  to the application.
--
--  Directories are created with the OS call rather than os.execute, which
--  would flash a console window on Windows.
--
--  If the app folder is not writable - installed under Program Files, run
--  from a read-only drive - this falls back to the save directory and says so
--  rather than silently losing the take.
-- ===========================================================================
local storage = {}

local SEP = package.config:sub(1, 1)
local ffiOK, ffi = pcall(require, "ffi")

-- ------------------------------------------------------------------ mkdir --
local mkdir
if ffiOK and ffi then
    if love.system.getOS() == "Windows" then
        pcall(function()
            ffi.cdef [[ int CreateDirectoryA(const char *path, void *sec); ]]
            local k32 = ffi.load("kernel32")
            mkdir = function(p) k32.CreateDirectoryA(p, nil) end
        end)
    else
        pcall(function()
            ffi.cdef [[ int mkdir(const char *path, unsigned int mode); ]]
            mkdir = function(p) ffi.C.mkdir(p, 493) end       -- 0755
        end)
    end
end

-- ------------------------------------------------------------------ paths --
local function dirOf(p)
    if not p or p == "" then return nil end
    local low = p:lower()
    if low:sub(-4) == ".exe" or low:sub(-5) == ".love" then
        return p:match("^(.*)[/\\][^/\\]*$")
    end
    return p
end

--- The folder the application itself lives in: the game folder when run
--- unfused, or the folder holding the .exe / .love otherwise.
function storage.appDir()
    local fs = love.filesystem
    local d = fs.getSource and dirOf(fs.getSource())
    if not d or d == "" then d = fs.getWorkingDirectory and fs.getWorkingDirectory() end
    return d
end

function storage.join(a, b) return (a:gsub("[/\\]+$", "")) .. SEP .. b end

--- Create a directory and every parent above it.
function storage.ensureDir(path)
    local prefix = (path:sub(1, 1) == "/") and "/" or ""
    local cur, first = prefix, true
    for part in path:gmatch("[^/\\]+") do
        cur = first and (prefix .. part) or (cur .. SEP .. part)
        first = false
        if mkdir then
            mkdir(cur)
        else
            os.execute('mkdir "' .. cur .. '" 2>' ..
                       (love.system.getOS() == "Windows" and "nul" or "/dev/null"))
        end
    end
    return storage.writable(path)
end

--- Only a real write proves the folder is usable; UAC and read-only media are
--- both silent until you actually try.
function storage.writable(dir)
    local probe = storage.join(dir, ".lunchbox-write-test")
    local f = io.open(probe, "wb")
    if not f then return false end
    f:write("x")
    f:close()
    os.remove(probe)
    return true
end

function storage.writeFile(path, bytes)
    local f, err = io.open(path, "wb")
    if not f then return false, tostring(err) end
    f:write(bytes)
    f:close()
    return true
end

--- Both places a take could already exist, so a fresh launch never reuses a
--- number that an earlier session wrote.
function storage.takesRoots()
    local list = {}
    local app = storage.appDir()
    if app then list[#list + 1] = storage.join(app, "takes") end
    if love.filesystem.getSaveDirectory then
        list[#list + 1] = storage.join(love.filesystem.getSaveDirectory(), "takes")
    end
    return list
end

local function takeExists(root, n)
    local dir = storage.join(root, string.format("take_%03d", n))
    local f = io.open(storage.join(dir, "take.txt"), "r")
    if f then f:close() return true end
    f = io.open(storage.join(dir, "frame_0001.png"), "rb")   -- interrupted export
    if f then f:close() return true end
    return false
end

--- Highest take already on disk. Takes are written in sequence, so stop after
--- a long run of misses rather than probing all 999 slots on every launch.
function storage.highestTakeNumber()
    local hi = 0
    for _, root in ipairs(storage.takesRoots()) do
        local miss = 0
        for n = 1, 999 do
            if takeExists(root, n) then
                hi = math.max(hi, n)
                miss = 0
            else
                miss = miss + 1
                if miss >= 50 then break end
            end
        end
    end
    return hi
end

function storage.nextTakeNumber()
    return math.min(999, storage.highestTakeNumber() + 1)
end

--- Where takes should go: beside the application, or the save folder if that
--- is not writable. Returns path, usedFallback.
function storage.chooseTakesRoot()
    local app = storage.appDir()
    if app then
        local root = storage.join(app, "takes")
        if storage.ensureDir(root) then return root, false end
    end
    love.filesystem.createDirectory("takes")          -- makes the save tree
    return storage.join(love.filesystem.getSaveDirectory(), "takes"), true
end

return storage
