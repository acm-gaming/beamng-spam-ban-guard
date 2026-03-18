local RateDetector = {}

function RateDetector.newState()
    return {
        times = {},
        head = 1,
    }
end

local function compact(state)
    if state.head <= 1 then
        return
    end

    local newTimes = {}
    local write = 1
    for i = state.head, #state.times do
        newTimes[write] = state.times[i]
        write = write + 1
    end

    state.times = newTimes
    state.head = 1
end

---@param state table
---@param timeNow integer
---@param config table
---@param shouldCount boolean
---@return table
function RateDetector.observe(state, timeNow, config, shouldCount)
    if shouldCount then
        state.times[#state.times + 1] = timeNow
    end

    local cutoff = timeNow - config.windowSeconds
    while state.head <= #state.times and state.times[state.head] < cutoff do
        state.head = state.head + 1
    end

    if state.head > 64 and state.head * 2 > #state.times then
        compact(state)
    end

    local count = #state.times - state.head + 1
    if count < 0 then
        count = 0
    end

    return {
        count = count,
        moderate = count >= config.moderateThreshold,
        severe = count >= config.severeThreshold,
    }
end

return RateDetector
