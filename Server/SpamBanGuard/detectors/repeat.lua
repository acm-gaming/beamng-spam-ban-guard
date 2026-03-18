local RepeatDetector = {}

function RepeatDetector.newState()
    return {
        entries = {},
        messageCount = 0,
    }
end

---@param value unknown
---@return string
local function normalizeMessage(value)
    local message = tostring(value or "")
    message = message:lower():gsub("%s+", " ")
    return (message:match("^%s*(.-)%s*$") or "")
end

local function evictStale(entries, cutoff)
    for normalized, entry in pairs(entries) do
        if entry.lastTs < cutoff then
            entries[normalized] = nil
        end
    end
end

---@param state table
---@param message unknown
---@param timeNow integer
---@param config table
---@param shouldCount boolean
---@return table
function RepeatDetector.observe(state, message, timeNow, config, shouldCount)
    state.messageCount = state.messageCount + 1
    if state.messageCount % config.gcIntervalMessages == 0 then
        evictStale(state.entries, timeNow - config.staleTtlSeconds)
    end

    if not shouldCount then
        return {
            count = 0,
            normalized = nil,
            moderate = false,
            severe = false,
        }
    end

    local normalized = normalizeMessage(message)
    if normalized == "" then
        return {
            count = 0,
            normalized = nil,
            moderate = false,
            severe = false,
        }
    end

    local entry = state.entries[normalized]
    if not entry or (timeNow - entry.lastTs) > config.windowSeconds then
        entry = {
            count = 0,
            lastTs = timeNow,
        }
        state.entries[normalized] = entry
    end

    entry.count = entry.count + 1
    entry.lastTs = timeNow

    return {
        count = entry.count,
        normalized = normalized,
        moderate = entry.count >= config.moderateThreshold,
        severe = entry.count >= config.severeThreshold,
    }
end

return RepeatDetector
