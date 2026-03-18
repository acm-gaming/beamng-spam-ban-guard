# SpamBanGuard (BeamMP Server Plugin)

[![Test](https://github.com/acm-gaming/beamng-spam-ban-guard/actions/workflows/test.yml/badge.svg)](https://github.com/acm-gaming/beamng-spam-ban-guard/actions/workflows/test.yml)

Auto-detects chat spam, bans the player, and saves their identifier so they stay blocked after server restart.

## What it does

- Watches `onChatMessage` for:
  - Message rate spam (too many messages in short time)
  - Repeated message spam (same message repeated)
  - Numeric burst spam patterns
- Explicitly allows strict numeric descending countdowns (`10`, `9`, `8`, ...) in quick succession
- Bans offender by persistent identifier (prefers BeamMP ID, falls back to IP)
- Saves bans to `bans.ndjson` (with automatic one-time legacy import from `banned_ids.txt`)
- Blocks banned users at `onPlayerAuth` before they join

## Example

```
[08/03/26 05:39:27] [INFO] Identifying new ClientConnection...
[08/03/26 05:39:27] [INFO] Identification success
[08/03/26 05:39:27] [INFO] Client connected
[08/03/26 05:39:27] [INFO] Assigned ID 0 to #######
[08/03/26 05:39:27] [INFO] ####### : Connected
[08/03/26 05:39:28] [LUA] Player stats saved successfully!
[08/03/26 05:39:28] [LUA] Player joined: ####### (ID: :######)
[08/03/26 05:39:42] [CHAT] (0) <#######>  I'm selling ads here. Discord: #########
[08/03/26 05:39:43] [CHAT] (0) <#######>  I'm selling ads here. Discord: #########
[08/03/26 05:39:43] [CHAT] (0) <#######>  I'm selling ads here. Discord: #########
[08/03/26 05:39:43] [LUA] [SpamBanGuard] Added ban: beammp:######
[08/03/26 05:39:43] [LUA] [SpamBanGuard] ####### was banned for spam (repeated message)
[08/03/26 05:39:43] [CHAT] <Server> (to everyone) [SpamBanGuard] ####### was banned for spam (repeated message)
[08/03/26 05:39:43] [INFO] Client kicked: Banned: chat spam detected
[08/03/26 05:39:43] [INFO] ####### Connection Terminated
[08/03/26 05:39:43] [LUA] [STATE] Player 0 state cleared
[08/03/26 05:39:43] [LUA] Player disconnected: ####### (ID: :######)
```

## Install

1. Copy this folder into your BeamMP server:
   - `Resources/`
2. Ensure the Lua file exists at:
   - `Resources/Server/SpamBanGuard/main.lua`
3. Restart server (or hot-reload by editing file)

## Config

Create `Server/SpamBanGuard/config.json` (copy from `Server/SpamBanGuard/config.json.example`).

If `config.json` is missing, the plugin logs that it was not found and uses built-in defaults.

If `config.json` is partial, missing fields are merged from defaults automatically.

- `rate.windowSeconds`, `rate.moderateThreshold`, `rate.severeThreshold`
- `repeatSpam.windowSeconds`, `repeatSpam.moderateThreshold`, `repeatSpam.severeThreshold`
- `countdown.maxStepGapSeconds`, `countdown.minSequenceLength`
- `countdown.burstWindowSeconds`, `countdown.suspicious*Threshold`
- `policy.cooccurrenceWindowSeconds`
- `persistence.banStoreFile`, `persistence.legacyBanFile`
- `banReason`

## Persistent ban file

`bans.ndjson` is created in the plugin folder on first ban.

Each line is a JSON object:

```json
{"key":"beammp:1234567","reason":"Banned: chat spam detected","trigger":"cooccurrence:rate+repeatSpam","timestamp":1762841234}
```

Legacy `banned_ids.txt` is imported automatically if `bans.ndjson` does not exist yet.

## Module layout

- `main.lua`: BeamMP callback adapter and event registration
- `core/engine.lua`: orchestration and ban policy
- `detectors/*.lua`: rate / repeat / countdown detectors
- `persistence/ban_store.lua`: deduplicated NDJSON persistence and legacy import

## Tests

Run local tests:

```bash
lua Server/SpamBanGuard/tests/run.lua
```

CI runs `.github/workflows/test.yml` on every push and pull request.
