---@class SpamBanGuardConfig
---@field banReason string
---@field rate table
---@field repeatSpam table
---@field countdown table
---@field policy table
---@field persistence table
---@field logging table

---@type SpamBanGuardConfig
local config = {
    banReason = "Banned: chat spam detected",

    -- Message rate signal.
    rate = {
        windowSeconds = 10,
        moderateThreshold = 6,
        severeThreshold = 10,
    },

    -- Repeated normalized-message signal.
    repeatSpam = {
        windowSeconds = 20,
        moderateThreshold = 2,
        severeThreshold = 3,
        staleTtlSeconds = 60,
        gcIntervalMessages = 24,
    },

    -- Strict numeric countdown exemption and numeric burst signal.
    countdown = {
        maxStepGapSeconds = 3,
        minSequenceLength = 2,
        burstWindowSeconds = 10,
        suspiciousModerateThreshold = 8,
        suspiciousSevereThreshold = 12,
    },

    -- Ban when >=2 moderate signals overlap in this horizon.
    policy = {
        cooccurrenceWindowSeconds = 12,
    },

    persistence = {
        banStoreFile = "bans.ndjson",
        legacyBanFile = "banned_ids.txt",
    },

    logging = {
        level = "info", -- error|info|debug
    },
}

return config
