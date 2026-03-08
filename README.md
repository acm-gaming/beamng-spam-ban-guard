# SpamBanGuard (BeamMP Server Plugin)

Auto-detects chat spam, bans the player, and saves their identifier so they stay blocked after server restart.

## What it does

- Watches `onChatMessage` for:
  - Message rate spam (too many messages in short time)
  - Repeated message spam (same message repeated)
- Bans offender by persistent identifier (prefers BeamMP ID, falls back to IP)
- Saves bans to `banned_ids.txt`
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

Edit `CONFIG` at the top of `main.lua`:

- `MAX_MESSAGES_IN_WINDOW` + `WINDOW_SECONDS`
- `MAX_REPEAT_COUNT` + `REPEAT_WINDOW_SECONDS`
- `BAN_REASON`

## Persistent ban file

`banned_ids.txt` is created in the plugin folder on first ban.

Format is one key per line:

- `beammp:1234567`
- `ip:1.2.3.4`
