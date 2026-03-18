local CountdownDetector = {}

function CountdownDetector.newState()
    return {
        lastNumber = nil,
        lastTs = nil,
        streakLength = 0,
        burstStart = nil,
        burstCount = 0,
    }
end

---@param value unknown
---@return integer|nil
local function parseStrictNumber(value)
    local trimmed = (tostring(value or ""):match("^%s*(.-)%s*$") or "")
    if trimmed:match("^%d+$") then
        return tonumber(trimmed)
    end
    return nil
end

local function resetStreak(state)
    state.lastNumber = nil
    state.lastTs = nil
    state.streakLength = 0
end

---@param state table
---@param message unknown
---@param timeNow integer
---@param config table
---@return table
function CountdownDetector.observe(state, message, timeNow, config)
    local number = parseStrictNumber(message)
    if number == nil then
        resetStreak(state)
        return {
            number = nil,
            streakLength = 0,
            burstCount = state.burstCount,
            exempt = false,
            moderate = false,
            severe = false,
        }
    end

    local quickStep = state.lastNumber ~= nil
        and state.lastTs ~= nil
        and (timeNow - state.lastTs) <= config.maxStepGapSeconds

    if quickStep and number == (state.lastNumber - 1) then
        state.streakLength = state.streakLength + 1
    else
        state.streakLength = 1
    end

    state.lastNumber = number
    state.lastTs = timeNow

    if state.burstStart == nil or (timeNow - state.burstStart) > config.burstWindowSeconds then
        state.burstStart = timeNow
        state.burstCount = 1
    else
        state.burstCount = state.burstCount + 1
    end

    local exempt = state.streakLength >= config.minSequenceLength

    local moderate = false
    local severe = false
    if not exempt then
        moderate = state.burstCount >= config.suspiciousModerateThreshold
        severe = state.burstCount >= config.suspiciousSevereThreshold
    end

    return {
        number = number,
        streakLength = state.streakLength,
        burstCount = state.burstCount,
        exempt = exempt,
        moderate = moderate,
        severe = severe,
    }
end

return CountdownDetector
