local CONFIG = {
    -- Messages allowed inside WINDOW_SECONDS before a player is considered spamming.
    MAX_MESSAGES_IN_WINDOW = 6,
    WINDOW_SECONDS = 10,

    -- Same (normalized) message repeated this many times inside REPEAT_WINDOW_SECONDS triggers a ban.
    MAX_REPEAT_COUNT = 3,
    REPEAT_WINDOW_SECONDS = 20,

    -- File where persistent banned identifiers are stored (one key per line).
    BAN_FILE = "banned_ids.txt",

    -- Message shown when a player is blocked/kicked for spam.
    BAN_REASON = "Banned: chat spam detected",
}

local state = {
    -- key -> true
    banned = {},
    -- player_id -> { timestamps = { ... }, repeats = { [normalized_msg] = { ... } } }
    chat = {}
}

local function now()
    return os.time()
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalize_message(msg)
    return tostring(msg or ""):lower():gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
end

local function get_plugin_dir()
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

local _ban_file_path

local function ban_file_path()
    if _ban_file_path then return _ban_file_path end
    local dir = get_plugin_dir()
    if FS and FS.ConcatPaths then
        _ban_file_path = FS.ConcatPaths(dir, CONFIG.BAN_FILE)
    else
        _ban_file_path = dir .. "/" .. CONFIG.BAN_FILE
    end
    return _ban_file_path
end

local function load_bans()
    local path = ban_file_path()
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

local function save_bans()
    local path = ban_file_path()
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

local function append_ban(key)
    local path = ban_file_path()
    local file, err = io.open(path, "a")
    if not file then
        print("[SpamBanGuard] Failed to append ban: " .. tostring(err))
        return false
    end
    file:write(key, "\n")
    file:close()
    return true
end

local function key_from_identifiers(identifiers)
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

local function is_banned_identifiers(identifiers)
    local key = key_from_identifiers(identifiers)
    if not key then
        return false
    end
    return state.banned[key] == true
end

local function add_ban_for_player(player_id)
    local identifiers = MP.GetPlayerIdentifiers(player_id)
    local key = key_from_identifiers(identifiers)
    if not key then
        print("[SpamBanGuard] Could not resolve identifiers for player_id=" .. tostring(player_id))
        return false
    end

    state.banned[key] = true
    if append_ban(key) then
        print("[SpamBanGuard] Added ban: " .. key)
    end
    return true
end

local function prune_old_timestamps(timestamps, cutoff)
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

local function ensure_player_chat_state(player_id)
    if not state.chat[player_id] then
        state.chat[player_id] = {
            timestamps = {},
            repeats = {}
        }
    end
    return state.chat[player_id]
end

local function handle_spam_ban(player_id, player_name, trigger)
    local banned = add_ban_for_player(player_id)
    if banned then
        local notice = string.format("[SpamBanGuard] %s was banned for spam (%s)", tostring(player_name), tostring(trigger))
        print(notice)
        MP.SendChatMessage(-1, notice)
    end

    MP.DropPlayer(player_id, CONFIG.BAN_REASON)
    return 1
end

function on_chat_message(player_id, player_name, message)
    local t = now()
    local pstate = ensure_player_chat_state(player_id)

    pstate.timestamps[#pstate.timestamps + 1] = t
    prune_old_timestamps(pstate.timestamps, t - CONFIG.WINDOW_SECONDS)

    if #pstate.timestamps >= CONFIG.MAX_MESSAGES_IN_WINDOW then
        return handle_spam_ban(player_id, player_name, "rate")
    end

    local normalized = normalize_message(message)
    local repeat_times = pstate.repeats[normalized] or {}
    repeat_times[#repeat_times + 1] = t
    prune_old_timestamps(repeat_times, t - CONFIG.REPEAT_WINDOW_SECONDS)

    if #repeat_times == 0 then
        pstate.repeats[normalized] = nil
    else
        pstate.repeats[normalized] = repeat_times
        if #repeat_times >= CONFIG.MAX_REPEAT_COUNT then
            return handle_spam_ban(player_id, player_name, "repeated message")
        end
    end

    return 0
end

function on_player_auth(player_name, player_role, is_guest, identifiers)
    if is_banned_identifiers(identifiers) then
        print("[SpamBanGuard] Blocked banned player during auth: " .. tostring(player_name))
        return CONFIG.BAN_REASON
    end
    return 0
end

function on_player_disconnect(player_id)
    state.chat[player_id] = nil
end

function on_init()
    load_bans()
    print("[SpamBanGuard] Ready")
end

MP.RegisterEvent("onInit", "on_init")
MP.RegisterEvent("onPlayerAuth", "on_player_auth")
MP.RegisterEvent("onChatMessage", "on_chat_message")
MP.RegisterEvent("onPlayerDisconnect", "on_player_disconnect")
