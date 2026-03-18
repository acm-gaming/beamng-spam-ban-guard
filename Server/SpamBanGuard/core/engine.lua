local Engine = {}
Engine.__index = Engine

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

---@param map table<string, integer>
---@param cutoff integer
---@return string[]
local function activeSignals(map, cutoff)
    local names = {}
    for name, timeValue in pairs(map) do
        if timeValue >= cutoff then
            names[#names + 1] = name
        else
            map[name] = nil
        end
    end
    table.sort(names)
    return names
end

---@param options table
---@return table
function Engine.new(options)
    local config = options.config
    local pluginDir = options.pluginDir
    local mp = options.mp or MP
    local now = options.now or os.time
    local loadModule = options.loadModule

    local self = setmetatable({
        config = config,
        pluginDir = pluginDir,
        mp = mp,
        now = now,
        players = {},
    }, Engine)

    self.levelOrder = {
        error = 1,
        info = 2,
        debug = 3,
    }

    self.logLevel = (config.logging and config.logging.level) or "info"

    self.RateDetector = loadModule(pluginDir, "detectors/rate.lua")
    self.RepeatDetector = loadModule(pluginDir, "detectors/repeat.lua")
    self.CountdownDetector = loadModule(pluginDir, "detectors/countdown.lua")
    local BanStore = loadModule(pluginDir, "persistence/ban_store.lua")

    self.banStore = BanStore.new({
        now = now,
        pluginDir = pluginDir,
        fileName = config.persistence.banStoreFile,
        legacyFileName = config.persistence.legacyBanFile,
        defaultReason = config.banReason,
    })

    return self
end

---@param level string
---@param message string
function Engine:log(level, message)
    local wanted = self.levelOrder[level] or self.levelOrder.info
    local current = self.levelOrder[self.logLevel] or self.levelOrder.info
    if wanted <= current then
        print("[SpamBanGuard] " .. message)
    end
end

---@param playerId integer
---@return table
function Engine:ensurePlayerState(playerId)
    local state = self.players[playerId]
    if state then
        return state
    end

    state = {
        rate = self.RateDetector.newState(),
        repeatSpam = self.RepeatDetector.newState(),
        countdown = self.CountdownDetector.newState(),
        signalTimes = {},
    }
    self.players[playerId] = state
    return state
end

---@param signalTimes table<string, integer>
---@param timeNow integer
---@param rate table
---@param repeatSpam table
---@param countdown table
---@return string|nil
function Engine:evaluateSignals(signalTimes, timeNow, rate, repeatSpam, countdown)
    local severe = {}
    if rate.severe then
        severe[#severe + 1] = "rate"
    end
    if repeatSpam.severe then
        severe[#severe + 1] = "repeat"
    end
    if countdown.severe then
        severe[#severe + 1] = "numeric"
    end
    if #severe > 0 then
        table.sort(severe)
        return "severe:" .. table.concat(severe, "+")
    end

    if rate.moderate then
        signalTimes.rate = timeNow
    end
    if repeatSpam.moderate then
        signalTimes.repeatSpam = timeNow
    end
    if countdown.moderate then
        signalTimes.numeric = timeNow
    end

    local cutoff = timeNow - self.config.policy.cooccurrenceWindowSeconds
    local active = activeSignals(signalTimes, cutoff)
    if #active >= 2 then
        return "cooccurrence:" .. table.concat(active, "+")
    end

    return nil
end

---@param playerId integer
---@param playerName string
---@param trigger string
---@param timeNow integer
---@return integer
function Engine:handleSpamBan(playerId, playerName, trigger, timeNow)
    local key = keyFromIdentifiers(self.mp.GetPlayerIdentifiers(playerId))
    if key then
        local ok, isNew, persisted = self.banStore:add({
            key = key,
            reason = self.config.banReason,
            trigger = trigger,
            timestamp = timeNow,
        })

        if not ok then
            self:log("error", "Failed to add ban key for playerId=" .. tostring(playerId))
        elseif isNew and persisted then
            self:log("info", "Added ban: " .. key)
        elseif isNew and not persisted then
            self:log("error", "Added in-memory ban but failed to persist key: " .. key)
        end
    else
        self:log("error", "Could not resolve identifiers for playerId=" .. tostring(playerId))
    end

    local notice = string.format("[SpamBanGuard] %s was banned for spam (%s)", tostring(playerName), tostring(trigger))
    self:log("info", notice:gsub("^%[SpamBanGuard%]%s*", ""))
    self.mp.SendChatMessage(-1, notice)
    self.mp.DropPlayer(playerId, self.config.banReason)
    self.players[playerId] = nil
    return 1
end

---@param playerId integer
---@param playerName string
---@param message unknown
---@return integer
function Engine:onChatMessage(playerId, playerName, message)
    local timeNow = self.now()
    local playerState = self:ensurePlayerState(playerId)

    local countdown = self.CountdownDetector.observe(
        playerState.countdown,
        message,
        timeNow,
        self.config.countdown
    )

    -- Exempt valid strict countdown steps from rate/repeat spam counters.
    local countTowardSpam = not countdown.exempt

    local rate = self.RateDetector.observe(
        playerState.rate,
        timeNow,
        self.config.rate,
        countTowardSpam
    )

    local repeatSpam = self.RepeatDetector.observe(
        playerState.repeatSpam,
        message,
        timeNow,
        self.config.repeatSpam,
        countTowardSpam
    )

    local trigger = self:evaluateSignals(playerState.signalTimes, timeNow, rate, repeatSpam, countdown)
    if trigger then
        return self:handleSpamBan(playerId, playerName, trigger, timeNow)
    end

    return 0
end

---@param playerName string
---@param identifiers table|nil
---@return integer|string
function Engine:onPlayerAuth(playerName, identifiers)
    local key = keyFromIdentifiers(identifiers)
    if key and self.banStore:isBanned(key) then
        self:log("info", "Blocked banned player during auth: " .. tostring(playerName))
        return self.config.banReason
    end
    return 0
end

---@param playerId integer
function Engine:onPlayerDisconnect(playerId)
    self.players[playerId] = nil
end

function Engine:onInit()
    local loaded = self.banStore:load()
    self:log("info", "Ready (" .. tostring(self.banStore:count()) .. " banned identifier(s), loaded=" .. tostring(loaded) .. ")")
end

return Engine
