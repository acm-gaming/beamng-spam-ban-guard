---@return string
local function getPluginDir()
    local info = debug.getinfo(1, "S")
    local source = (info and info.source) or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    local slash = source:match("^.*()/")
    if slash then
        return source:sub(1, slash - 1)
    end

    return "."
end

---@param base string
---@param child string
---@return string
local function joinPath(base, child)
    if FS and FS.ConcatPaths then
        return FS.ConcatPaths(base, child)
    end
    return base .. "/" .. child
end

---@param pluginDir string
---@param relativePath string
---@return any
local function loadModule(pluginDir, relativePath)
    local path = joinPath(pluginDir, relativePath)
    local chunk, err = loadfile(path)
    if not chunk then
        error("failed to load module at " .. path .. ": " .. tostring(err))
    end
    return chunk()
end

local pluginDir = getPluginDir()
local config = loadModule(pluginDir, "config.lua")
local Engine = loadModule(pluginDir, "core/engine.lua")

local engine = Engine.new({
    config = config,
    pluginDir = pluginDir,
    mp = MP,
    now = os.time,
    loadModule = loadModule,
})

function onInit()
    engine:onInit()
end

---@param playerName string
---@param playerRole string
---@param isGuest boolean
---@param identifiers table|nil
---@return integer|string
function onPlayerAuth(playerName, playerRole, isGuest, identifiers)
    -- Kept for BeamMP callback signature compatibility.
    local _ = playerRole
    _ = isGuest
    return engine:onPlayerAuth(playerName, identifiers)
end

---@param playerId integer
---@param playerName string
---@param message string
---@return integer
function onChatMessage(playerId, playerName, message)
    return engine:onChatMessage(playerId, playerName, message)
end

---@param playerId integer
function onPlayerDisconnect(playerId)
    engine:onPlayerDisconnect(playerId)
end

MP.RegisterEvent("onInit", "onInit")
MP.RegisterEvent("onPlayerAuth", "onPlayerAuth")
MP.RegisterEvent("onChatMessage", "onChatMessage")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
