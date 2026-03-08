---@class SpamBanGuardConfig
---@field maxMessagesInWindow integer Messages allowed inside windowSeconds before a player is considered spamming.
---@field windowSeconds integer
---@field maxRepeatCount integer Same normalized message repeated this many times inside repeatWindowSeconds triggers a ban.
---@field repeatWindowSeconds integer
---@field banFile string File where persistent banned identifiers are stored (one key per line).
---@field banReason string Message shown when a player is blocked/kicked for spam.

---@class PlayerChatState
---@field timestamps integer[]
---@field repeats table<string, integer[]>

---@class SpamBanGuardState
---@field banned table<string, boolean> key -> true
---@field chat table<integer, PlayerChatState> playerId -> PlayerChatState

---@type SpamBanGuardConfig
local config = {
    maxMessagesInWindow = 6,
    windowSeconds = 10,
    maxRepeatCount = 3,
    repeatWindowSeconds = 20,
    banFile = "banned_ids.txt",
    banReason = "Banned: chat spam detected",
}

---@type SpamBanGuardState
local state = {
    banned = {},
    chat = {},
}

---@return integer
local function now()
    return os.time()
end

---@param value string
---@return string
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param message unknown
---@return string
local function normalizeMessage(message)
    return tostring(message or ""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

---@return string
local function getPluginDir()
    -- The file lives in the plugin root, so this works from BeamMP server working directory.
    local info = debug.getinfo(1, "S")
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end

    local slash = source:match("^.*()/")
    if slash then
        return source:sub(1, slash - 1)
    end
    return "."
end

---@type string|nil
local banFilePathCache

---@return string
local function getBanFilePath()
    if banFilePathCache then
        return banFilePathCache
    end

    local dir = getPluginDir()
    if FS and FS.ConcatPaths then
        banFilePathCache = FS.ConcatPaths(dir, config.banFile)
    else
        banFilePathCache = dir .. "/" .. config.banFile
    end
    return banFilePathCache
end

local function loadBans()
    local path = getBanFilePath()
    local file = io.open(path, "r")
    if not file then
        print("[SpamBanGuard] No existing ban file found at " .. path .. " (will create on first ban)")
        return
    end

    for line in file:lines() do
        local key = trim(line)
        if key ~= "" then
            state.banned[key] = true
        end
    end

    file:close()
    local count = 0
    for _ in pairs(state.banned) do count = count + 1 end
    print("[SpamBanGuard] Loaded " .. count .. " banned identifier(s)")
end

---@return boolean
local function saveBans()
    local path = getBanFilePath()
    local file, err = io.open(path, "w")
    if not file then
        print("[SpamBanGuard] Failed to save bans: " .. tostring(err))
        return false
    end

    for key in pairs(state.banned) do
        file:write(key, "\n")
    end

    file:close()
    return true
end

---@param key string
---@return boolean
local function appendBan(key)
    local path = getBanFilePath()
    local file, err = io.open(path, "a")
    if not file then
        print("[SpamBanGuard] Failed to append ban: " .. tostring(err))
        return false
    end
    file:write(key, "\n")
    file:close()
    return true
end

---@param identifiers table|nil
---@return string|nil
local function keyFromIdentifiers(identifiers)
    if type(identifiers) ~= "table" then
        return nil
    end

    if identifiers.beammp and identifiers.beammp ~= "" then
        return "beammp:" .. tostring(identifiers.beammp)
    end

    if identifiers.ip and identifiers.ip ~= "" then
        return "ip:" .. tostring(identifiers.ip)
    end

    return nil
end

---@param identifiers table|nil
---@return boolean
local function isBannedIdentifiers(identifiers)
    local key = keyFromIdentifiers(identifiers)
    if not key then
        return false
    end
    return state.banned[key] == true
end

---@param playerId integer
---@return boolean
local function addBanForPlayer(playerId)
    local identifiers = MP.GetPlayerIdentifiers(playerId)
    local key = keyFromIdentifiers(identifiers)
    if not key then
        print("[SpamBanGuard] Could not resolve identifiers for playerId=" .. tostring(playerId))
        return false
    end

    state.banned[key] = true
    if appendBan(key) then
        print("[SpamBanGuard] Added ban: " .. key)
        return true
    end

    -- Fallback: ensure bans still persist if append fails, while keeping behavior deterministic.
    if saveBans() then
        print("[SpamBanGuard] Added ban after full save fallback: " .. key)
        return true
    end
    return false
end

---@param timestamps integer[]
---@param cutoff integer
---@return integer[]
local function pruneOldTimestamps(timestamps, cutoff)
    local write = 0
    for read = 1, #timestamps do
        if timestamps[read] >= cutoff then
            write = write + 1
            timestamps[write] = timestamps[read]
        end
    end
    for i = write + 1, #timestamps do
        timestamps[i] = nil
    end
    return timestamps
end

---@param playerId integer
---@return PlayerChatState
local function ensurePlayerChatState(playerId)
    if not state.chat[playerId] then
        state.chat[playerId] = {
            timestamps = {},
            repeats = {},
        }
    end
    return state.chat[playerId]
end

---@param playerId integer
---@param playerName string
---@param trigger string
---@return integer
local function handleSpamBan(playerId, playerName, trigger)
    local banned = addBanForPlayer(playerId)
    if banned then
        local notice = string.format("[SpamBanGuard] %s was banned for spam (%s)", tostring(playerName), tostring(trigger))
        print(notice)
        MP.SendChatMessage(-1, notice)
    end

    MP.DropPlayer(playerId, config.banReason)
    return 1
end

---@param playerId integer
---@param playerName string
---@param message string
---@return integer
function onChatMessage(playerId, playerName, message)
    local t = now()
    local playerState = ensurePlayerChatState(playerId)

    playerState.timestamps[#playerState.timestamps + 1] = t
    pruneOldTimestamps(playerState.timestamps, t - config.windowSeconds)

    if #playerState.timestamps >= config.maxMessagesInWindow then
        return handleSpamBan(playerId, playerName, "rate")
    end

    local normalizedMessage = normalizeMessage(message)
    local repeatTimes = playerState.repeats[normalizedMessage] or {}
    repeatTimes[#repeatTimes + 1] = t
    pruneOldTimestamps(repeatTimes, t - config.repeatWindowSeconds)

    if #repeatTimes == 0 then
        playerState.repeats[normalizedMessage] = nil
    else
        playerState.repeats[normalizedMessage] = repeatTimes
        if #repeatTimes >= config.maxRepeatCount then
            return handleSpamBan(playerId, playerName, "repeated message")
        end
    end

    return 0
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

    if isBannedIdentifiers(identifiers) then
        print("[SpamBanGuard] Blocked banned player during auth: " .. tostring(playerName))
        return config.banReason
    end
    return 0
end

---@param playerId integer
function onPlayerDisconnect(playerId)
    state.chat[playerId] = nil
end

function onInit()
    loadBans()
    print("[SpamBanGuard] Ready")
end

MP.RegisterEvent("onInit", "onInit")
MP.RegisterEvent("onPlayerAuth", "onPlayerAuth")
MP.RegisterEvent("onChatMessage", "onChatMessage")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
