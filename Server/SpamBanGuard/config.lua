---@class SpamBanGuardConfig
---@field banReason string
---@field rate table
---@field repeatSpam table
---@field countdown table
---@field policy table
---@field persistence table
---@field logging table

---@type SpamBanGuardConfig
local defaults = {
    banReason = "Banned: chat spam detected",

    rate = {
        windowSeconds = 10,
        moderateThreshold = 6,
        severeThreshold = 10,
    },

    repeatSpam = {
        windowSeconds = 20,
        moderateThreshold = 2,
        severeThreshold = 3,
        staleTtlSeconds = 60,
        gcIntervalMessages = 24,
    },

    countdown = {
        maxStepGapSeconds = 3,
        minSequenceLength = 2,
        burstWindowSeconds = 10,
        suspiciousModerateThreshold = 8,
        suspiciousSevereThreshold = 12,
    },

    policy = {
        cooccurrenceWindowSeconds = 12,
    },

    persistence = {
        banStoreFile = "bans.ndjson",
        legacyBanFile = "banned_ids.txt",
    },

    logging = {
        level = "info",
    },
}

---@param base string
---@param child string
---@return string
local function joinPath(base, child)
    if FS and FS.ConcatPaths then
        return FS.ConcatPaths(base, child)
    end
    return base .. "/" .. child
end

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

---@param value any
---@return any
local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local out = {}
    for k, v in pairs(value) do
        out[k] = deepCopy(v)
    end
    return out
end

---@param defaultValue any
---@param overrideValue any
---@return any
local function mergeWithDefaults(defaultValue, overrideValue)
    if type(defaultValue) ~= "table" then
        if overrideValue == nil then
            return defaultValue
        end
        return overrideValue
    end

    if type(overrideValue) ~= "table" then
        return deepCopy(defaultValue)
    end

    local merged = {}
    for k, v in pairs(defaultValue) do
        merged[k] = mergeWithDefaults(v, overrideValue[k])
    end

    for k, v in pairs(overrideValue) do
        if defaultValue[k] == nil then
            merged[k] = deepCopy(v)
        end
    end

    return merged
end

---@param raw string
---@return table|nil, string|nil
local function decodeJsonWithBuiltIn(raw)
    if type(Util) == "table" and type(Util.JsonDecode) == "function" then
        local ok, decoded = pcall(Util.JsonDecode, raw)
        if ok then
            return decoded, nil
        end
        return nil, tostring(decoded)
    end

    if type(jsonDecode) == "function" then
        local ok, decoded = pcall(jsonDecode, raw)
        if ok then
            return decoded, nil
        end
        return nil, tostring(decoded)
    end

    if type(json) == "table" and type(json.decode) == "function" then
        local ok, decoded = pcall(json.decode, raw)
        if ok then
            return decoded, nil
        end
        return nil, tostring(decoded)
    end

    if type(JSON) == "table" and type(JSON.decode) == "function" then
        local ok, decoded = pcall(JSON.decode, raw)
        if ok then
            return decoded, nil
        end
        return nil, tostring(decoded)
    end

    return nil, "no built-in JSON decoder found (tried Util.JsonDecode, jsonDecode, json.decode, JSON.decode)"
end

---@param path string
---@return table|nil, string|nil
local function readConfigFile(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end

    local contents = file:read("*a")
    file:close()

    local decoded, decodeErr = decodeJsonWithBuiltIn(contents)
    if decodeErr then
        return nil, decodeErr
    end
    if type(decoded) ~= "table" then
        return nil, "root JSON value must be an object"
    end
    return decoded, nil
end

local pluginDir = getPluginDir()
local configPath = joinPath(pluginDir, "config.json")

local userConfig, readErr = readConfigFile(configPath)
if userConfig == nil then
    if type(readErr) == "string" and readErr:match("No such file") then
        print("[SpamBanGuard] config.json not found at " .. configPath .. "; using defaults")
    else
        print("[SpamBanGuard] Failed to load config.json (" .. tostring(readErr) .. "); using defaults")
    end
    return deepCopy(defaults)
end

print("[SpamBanGuard] Loaded config.json from " .. configPath)
return mergeWithDefaults(defaults, userConfig)
