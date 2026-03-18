local BanStore = {}
BanStore.__index = BanStore

---@param value string
---@return string
local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@param base string
---@param child string
---@return string
local function defaultJoinPath(base, child)
    if FS and FS.ConcatPaths then
        return FS.ConcatPaths(base, child)
    end
    return base .. "/" .. child
end

---@param path string
---@return boolean
local function fileExists(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end
    file:close()
    return true
end

---@param value string
---@return string
local function escapeJson(value)
    local out = tostring(value or "")
    out = out:gsub("\\", "\\\\")
    out = out:gsub('"', '\\"')
    out = out:gsub("\n", "\\n")
    out = out:gsub("\r", "\\r")
    out = out:gsub("\t", "\\t")
    return out
end

---@param value string
---@return string
local function unescapeJson(value)
    local input = tostring(value or "")
    local chars = {}
    local i = 1

    while i <= #input do
        local ch = input:sub(i, i)
        if ch ~= "\\" then
            chars[#chars + 1] = ch
            i = i + 1
        else
            local esc = input:sub(i + 1, i + 1)
            if esc == "n" then
                chars[#chars + 1] = "\n"
            elseif esc == "r" then
                chars[#chars + 1] = "\r"
            elseif esc == "t" then
                chars[#chars + 1] = "\t"
            elseif esc == '"' then
                chars[#chars + 1] = '"'
            elseif esc == "\\" then
                chars[#chars + 1] = "\\"
            elseif esc == "" then
                chars[#chars + 1] = "\\"
                i = i + 1
                break
            else
                chars[#chars + 1] = esc
            end
            i = i + 2
        end
    end

    return table.concat(chars)
end

---@param value string
---@return string
local function escapePattern(value)
    return (value:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

---@param line string
---@param field string
---@return string|nil
local function extractJsonStringField(line, field)
    local pattern = '"' .. escapePattern(field) .. '"%s*:%s*"'
    local _, valueStart = line:find(pattern)
    if not valueStart then
        return nil
    end

    local i = valueStart + 1
    local chars = {}

    while i <= #line do
        local ch = line:sub(i, i)
        if ch == '"' then
            return unescapeJson(table.concat(chars))
        end

        if ch == "\\" then
            local nextChar = line:sub(i + 1, i + 1)
            if nextChar == "" then
                return nil
            end
            chars[#chars + 1] = "\\"
            chars[#chars + 1] = nextChar
            i = i + 2
        else
            chars[#chars + 1] = ch
            i = i + 1
        end
    end

    return nil
end

---@param line string
---@param field string
---@return integer|nil
local function extractJsonNumberField(line, field)
    local pattern = '"' .. escapePattern(field) .. '"%s*:%s*(-?%d+)'
    local raw = line:match(pattern)
    if not raw then
        return nil
    end
    return tonumber(raw)
end

---@param record table
---@return string
local function encodeRecord(record)
    return string.format(
        '{"key":"%s","reason":"%s","trigger":"%s","timestamp":%d}',
        escapeJson(record.key),
        escapeJson(record.reason),
        escapeJson(record.trigger),
        record.timestamp
    )
end

---@param line string
---@return table|nil
local function decodeRecord(line)
    local key = extractJsonStringField(line, "key")
    if not key or key == "" then
        return nil
    end

    local reason = extractJsonStringField(line, "reason") or ""
    local trigger = extractJsonStringField(line, "trigger") or ""
    local timestamp = extractJsonNumberField(line, "timestamp")
    if not timestamp then
        return nil
    end

    return {
        key = key,
        reason = reason,
        trigger = trigger,
        timestamp = timestamp,
    }
end

---@param map table<string, table>
---@return integer
local function countEntries(map)
    local total = 0
    for _ in pairs(map) do
        total = total + 1
    end
    return total
end

---@param options table
---@return table
function BanStore.new(options)
    local nowFn = options.now or os.time
    local pluginDir = options.pluginDir or "."
    local joinPath = options.joinPath or defaultJoinPath

    local self = setmetatable({
        now = nowFn,
        defaultReason = options.defaultReason or "Banned: chat spam detected",
        storePath = joinPath(pluginDir, options.fileName or "bans.ndjson"),
        legacyPath = joinPath(pluginDir, options.legacyFileName or "banned_ids.txt"),
        recordsByKey = {},
    }, BanStore)

    return self
end

---@param message string
function BanStore:log(message)
    print("[SpamBanGuard] " .. message)
end

---@return boolean
function BanStore:saveAll()
    local file, err = io.open(self.storePath, "w")
    if not file then
        self:log("Failed to save ban store: " .. tostring(err))
        return false
    end

    local keys = {}
    for key in pairs(self.recordsByKey) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    for _, key in ipairs(keys) do
        file:write(encodeRecord(self.recordsByKey[key]), "\n")
    end

    file:close()
    return true
end

---@param record table
---@return boolean
function BanStore:appendRecord(record)
    local file, err = io.open(self.storePath, "a")
    if not file then
        self:log("Failed to append ban record: " .. tostring(err))
        return false
    end

    file:write(encodeRecord(record), "\n")
    file:close()
    return true
end

function BanStore:migrateLegacyIfNeeded()
    if fileExists(self.storePath) or not fileExists(self.legacyPath) then
        return false
    end

    local file, err = io.open(self.legacyPath, "r")
    if not file then
        self:log("Failed to read legacy ban file: " .. tostring(err))
        return false
    end

    local imported = 0
    local importTs = self.now()
    for line in file:lines() do
        local key = trim(line)
        if key ~= "" and not self.recordsByKey[key] then
            self.recordsByKey[key] = {
                key = key,
                reason = self.defaultReason,
                trigger = "legacy-import",
                timestamp = importTs,
            }
            imported = imported + 1
        end
    end

    file:close()

    if imported == 0 then
        return false
    end

    if self:saveAll() then
        self:log("Migrated " .. tostring(imported) .. " legacy banned identifier(s)")
        return true
    end

    return false
end

---@return integer, boolean
function BanStore:load()
    self:migrateLegacyIfNeeded()

    local file = io.open(self.storePath, "r")
    if not file then
        self:log("No ban store found at " .. self.storePath .. " (will create on first ban)")
        return 0, false
    end

    local loaded = 0
    for line in file:lines() do
        local trimmed = trim(line)
        if trimmed ~= "" then
            local record = decodeRecord(trimmed)
            if record then
                if not self.recordsByKey[record.key] then
                    loaded = loaded + 1
                end
                self.recordsByKey[record.key] = record
            else
                self:log("Skipping malformed ban record line")
            end
        end
    end

    file:close()
    return loaded, true
end

---@param key string|nil
---@return boolean
function BanStore:isBanned(key)
    if not key or key == "" then
        return false
    end
    return self.recordsByKey[key] ~= nil
end

---@param record table
---@return boolean, boolean, boolean
function BanStore:add(record)
    if type(record) ~= "table" or type(record.key) ~= "string" or record.key == "" then
        return false, false, false
    end

    if self.recordsByKey[record.key] then
        return true, false, true
    end

    self.recordsByKey[record.key] = {
        key = record.key,
        reason = record.reason or self.defaultReason,
        trigger = record.trigger or "spam",
        timestamp = record.timestamp or self.now(),
    }

    if self:appendRecord(self.recordsByKey[record.key]) then
        return true, true, true
    end

    if self:saveAll() then
        return true, true, true
    end

    return true, true, false
end

---@return integer
function BanStore:count()
    return countEntries(self.recordsByKey)
end

return BanStore
