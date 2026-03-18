local PLUGIN_DIR = "Server/SpamBanGuard"

math.randomseed(os.time())

local Engine = assert(loadfile(PLUGIN_DIR .. "/core/engine.lua"))()
local BaseConfig = assert(loadfile(PLUGIN_DIR .. "/config.lua"))()
local BanStore = assert(loadfile(PLUGIN_DIR .. "/persistence/ban_store.lua"))()

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

---@param target table
---@param source table
local function mergeInto(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            mergeInto(target[k], v)
        else
            target[k] = deepCopy(v)
        end
    end
end

---@param path string
---@param content string
local function writeFile(path, content)
    local file = assert(io.open(path, "w"))
    file:write(content)
    file:close()
end

---@param path string
---@return string[]
local function readLines(path)
    local file = io.open(path, "r")
    if not file then
        return {}
    end

    local lines = {}
    for line in file:lines() do
        lines[#lines + 1] = line
    end
    file:close()
    return lines
end

---@param prefix string
---@param ext string
---@return string
local function tempFileName(prefix, ext)
    return string.format("%s%d_%d%s", prefix, os.time(), math.random(100000, 999999), ext)
end

---@param condition boolean
---@param message string
local function assertTrue(condition, message)
    if not condition then
        error(message, 0)
    end
end

---@param actual any
---@param expected any
---@param message string
local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(message .. " (expected=" .. tostring(expected) .. ", actual=" .. tostring(actual) .. ")", 0)
    end
end

---@param options table|nil
---@return table
local function newHarness(options)
    options = options or {}

    local config = deepCopy(BaseConfig)
    config.logging.level = "error"

    local storeFile = options.storeFile or tempFileName("tmp_test_bans_", ".ndjson")
    local legacyFile = options.legacyFile or tempFileName("tmp_test_legacy_", ".txt")
    config.persistence.banStoreFile = storeFile
    config.persistence.legacyBanFile = legacyFile

    if options.configOverride then
        mergeInto(config, options.configOverride)
    end

    local identifiersByPlayer = options.identifiersByPlayer or {}
    local dropped = {}
    local chats = {}
    local timeNow = options.startTime or 1000

    local fakeMP = {
        GetPlayerIdentifiers = function(playerId)
            return identifiersByPlayer[playerId]
        end,
        SendChatMessage = function(target, message)
            chats[#chats + 1] = { target = target, message = message }
        end,
        DropPlayer = function(playerId, reason)
            dropped[#dropped + 1] = { playerId = playerId, reason = reason }
        end,
    }

    local function testLoadModule(pluginDir, relativePath)
        local path = pluginDir .. "/" .. relativePath
        local chunk, err = loadfile(path)
        if not chunk then
            error("failed to load module at " .. path .. ": " .. tostring(err))
        end
        return chunk()
    end

    local engine = Engine.new({
        config = config,
        pluginDir = PLUGIN_DIR,
        mp = fakeMP,
        now = function()
            return timeNow
        end,
        loadModule = testLoadModule,
    })

    local storePath = PLUGIN_DIR .. "/" .. storeFile
    local legacyPath = PLUGIN_DIR .. "/" .. legacyFile

    return {
        engine = engine,
        config = config,
        dropped = dropped,
        chats = chats,
        storePath = storePath,
        legacyPath = legacyPath,
        advance = function(seconds)
            timeNow = timeNow + (seconds or 1)
        end,
        cleanup = function()
            os.remove(storePath)
            os.remove(legacyPath)
        end,
    }
end

---@param options table|nil
---@param fn fun(h: table)
local function withHarness(options, fn)
    local h = newHarness(options)
    local ok, err = pcall(fn, h)
    h.cleanup()
    if not ok then
        error(err, 0)
    end
end

local tests = {}

---@param name string
---@param fn fun()
local function test(name, fn)
    tests[#tests + 1] = { name = name, run = fn }
end

test("strict countdown is exempt from bans", function()
    withHarness({
        identifiersByPlayer = {
            [1] = { beammp = "countdown-user" },
        },
    }, function(h)
        h.engine:onInit()
        for i = 10, 1, -1 do
            local rc = h.engine:onChatMessage(1, "countdown-user", tostring(i))
            assertEqual(rc, 0, "countdown message should not be blocked")
            h.advance(1)
        end
        assertEqual(#h.dropped, 0, "countdown player should not be dropped")
    end)
end)

test("repeated spam message triggers ban and auth block", function()
    withHarness({
        identifiersByPlayer = {
            [2] = { beammp = "repeat-spammer" },
        },
    }, function(h)
        h.engine:onInit()

        local rc = 0
        for _ = 1, 3 do
            rc = h.engine:onChatMessage(2, "repeat-spammer", "buy now")
            h.advance(1)
        end

        assertEqual(rc, 1, "repeat spam should trigger ban")
        assertEqual(#h.dropped, 1, "repeat spammer should be dropped once")

        local authResult = h.engine:onPlayerAuth("repeat-spammer", { beammp = "repeat-spammer" })
        assertTrue(type(authResult) == "string", "banned user should be blocked at auth")
    end)
end)

test("non-numeric countdown-like messages are not exempt", function()
    withHarness({
        identifiersByPlayer = {
            [3] = { beammp = "punctuated-user" },
        },
    }, function(h)
        h.engine:onInit()

        local banned = false
        for i = 12, 1, -1 do
            local rc = h.engine:onChatMessage(3, "punctuated-user", tostring(i) .. "...")
            if rc == 1 then
                banned = true
                break
            end
            h.advance(1)
        end

        assertTrue(banned, "punctuated numeric burst should not be exempt")
    end)
end)

test("moderate signal co-occurrence triggers ban", function()
    withHarness({
        identifiersByPlayer = {
            [4] = { beammp = "co-user" },
        },
        configOverride = {
            rate = {
                windowSeconds = 10,
                moderateThreshold = 4,
                severeThreshold = 99,
            },
            repeatSpam = {
                windowSeconds = 10,
                moderateThreshold = 2,
                severeThreshold = 99,
            },
            countdown = {
                suspiciousModerateThreshold = 99,
                suspiciousSevereThreshold = 999,
            },
            policy = {
                cooccurrenceWindowSeconds = 10,
            },
        },
    }, function(h)
        h.engine:onInit()

        local rc = 0
        rc = h.engine:onChatMessage(4, "co-user", "hey")
        assertEqual(rc, 0, "first message should pass")
        h.advance(1)

        rc = h.engine:onChatMessage(4, "co-user", "hey")
        assertEqual(rc, 0, "repeat moderate alone should not ban")
        h.advance(1)

        rc = h.engine:onChatMessage(4, "co-user", "alpha")
        assertEqual(rc, 0, "third message should pass")
        h.advance(1)

        rc = h.engine:onChatMessage(4, "co-user", "beta")
        assertEqual(rc, 1, "rate+repeat moderate co-occurrence should ban")
    end)
end)

test("disconnect clears player state", function()
    withHarness({
        identifiersByPlayer = {
            [5] = { beammp = "disconnect-user" },
        },
    }, function(h)
        h.engine:onInit()

        assertEqual(h.engine:onChatMessage(5, "disconnect-user", "same"), 0, "first repeat should pass")
        h.advance(1)
        assertEqual(h.engine:onChatMessage(5, "disconnect-user", "same"), 0, "second repeat should pass")
        h.engine:onPlayerDisconnect(5)
        h.advance(1)
        assertEqual(h.engine:onChatMessage(5, "disconnect-user", "same"), 0, "state should reset after disconnect")
        assertEqual(#h.dropped, 0, "disconnect test should not drop player")
    end)
end)

test("legacy banned_ids import migrates and blocks auth", function()
    withHarness({}, function(h)
        writeFile(h.legacyPath, "beammp:legacy-user\nip:1.2.3.4\n\n")
        h.engine:onInit()

        local lines = readLines(h.storePath)
        assertTrue(#lines >= 2, "legacy import should create NDJSON records")

        local authResult = h.engine:onPlayerAuth("legacy-user", { beammp = "legacy-user" })
        assertTrue(type(authResult) == "string", "imported legacy ban should block auth")
    end)
end)

test("malformed store lines are ignored while valid lines load", function()
    withHarness({}, function(h)
        writeFile(h.storePath, "not-json\n{\"key\":\"beammp:ok-user\",\"reason\":\"x\",\"trigger\":\"manual\",\"timestamp\":1234}\n")
        h.engine:onInit()

        local authBlocked = h.engine:onPlayerAuth("ok-user", { beammp = "ok-user" })
        assertTrue(type(authBlocked) == "string", "valid record should be loaded")

        local authAllowed = h.engine:onPlayerAuth("not-banned", { beammp = "not-banned" })
        assertEqual(authAllowed, 0, "unknown user should pass auth")
    end)
end)

test("numeric burst with interspersed text still triggers ban", function()
    withHarness({
        identifiersByPlayer = {
            [6] = { beammp = "evasion-user" },
        },
        configOverride = {
            countdown = {
                maxStepGapSeconds = 3,
                minSequenceLength = 2,
                burstWindowSeconds = 10,
                suspiciousModerateThreshold = 6,
                suspiciousSevereThreshold = 10,
            },
            rate = {
                windowSeconds = 10,
                moderateThreshold = 99,
                severeThreshold = 99,
            },
            repeatSpam = {
                windowSeconds = 10,
                moderateThreshold = 99,
                severeThreshold = 99,
            },
        },
    }, function(h)
        h.engine:onInit()

        -- Send numbers with text interspersed to try evading burst counter.
        for i = 1, 5 do
            h.engine:onChatMessage(6, "evasion-user", tostring(i * 10))
            h.advance(1)
        end
        h.engine:onChatMessage(6, "evasion-user", "text break")
        h.advance(1)

        local banned = false
        for i = 6, 12 do
            local rc = h.engine:onChatMessage(6, "evasion-user", tostring(i * 10))
            if rc == 1 then
                banned = true
                break
            end
            h.advance(1)
        end

        assertTrue(banned, "numeric burst should accumulate across text breaks")
    end)
end)

test("ban store deduplicates repeated key adds", function()
    local storeFile = tempFileName("tmp_store_dedupe_", ".ndjson")
    local legacyFile = tempFileName("tmp_store_dedupe_legacy_", ".txt")
    local storePath = PLUGIN_DIR .. "/" .. storeFile
    local legacyPath = PLUGIN_DIR .. "/" .. legacyFile

    local store = BanStore.new({
        now = function()
            return 1700000000
        end,
        pluginDir = PLUGIN_DIR,
        fileName = storeFile,
        legacyFileName = legacyFile,
        defaultReason = "test",
    })

    local ok, isNew, persisted = store:add({
        key = "beammp:dup-user",
        reason = "test",
        trigger = "manual",
        timestamp = 1700000000,
    })
    assertTrue(ok and isNew and persisted, "first add should persist")

    local ok2, isNew2, persisted2 = store:add({
        key = "beammp:dup-user",
        reason = "test",
        trigger = "manual",
        timestamp = 1700000001,
    })
    assertTrue(ok2 and not isNew2 and persisted2, "second add should be deduplicated")

    local lines = readLines(storePath)
    assertEqual(#lines, 1, "deduplicated key should be written once")

    os.remove(storePath)
    os.remove(legacyPath)
end)

local passed = 0
local failed = {}

for _, case in ipairs(tests) do
    io.write("[test] " .. case.name .. " ... ")
    local ok, err = pcall(case.run)
    if ok then
        passed = passed + 1
        io.write("ok\n")
    else
        failed[#failed + 1] = { name = case.name, err = tostring(err) }
        io.write("FAIL\n")
    end
end

print(string.format("Summary: %d passed, %d failed", passed, #failed))
if #failed > 0 then
    for _, failure in ipairs(failed) do
        print("- " .. failure.name .. ": " .. failure.err)
    end
    os.exit(1)
end
