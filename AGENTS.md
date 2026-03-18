# AGENTS.md

## Purpose

This repository contains a BeamMP server plugin that detects chat spam, bans offenders, and persists ban state across restarts.

## Current Module Layout

- `Server/SpamBanGuard/main.lua`: BeamMP event adapter (`onInit`, `onPlayerAuth`, `onChatMessage`, `onPlayerDisconnect`)
- `Server/SpamBanGuard/config.lua`: default values + JSON loader + deep-merge logic
- `Server/SpamBanGuard/config.json`: runtime overrides (optional, loaded if present)
- `Server/SpamBanGuard/config.json.example`: default config example to copy/customize
- `Server/SpamBanGuard/core/engine.lua`: orchestration and ban decision policy
- `Server/SpamBanGuard/detectors/rate.lua`: rolling rate detector
- `Server/SpamBanGuard/detectors/repeat.lua`: normalized repeated-message detector
- `Server/SpamBanGuard/detectors/countdown.lua`: strict numeric countdown exemption + numeric burst signal
- `Server/SpamBanGuard/persistence/ban_store.lua`: NDJSON ban store + legacy migration from `banned_ids.txt`
- `Server/SpamBanGuard/tests/run.lua`: local Lua test runner

## Behavioral Requirements

- Strict numeric descending countdowns (`10`, `9`, `8`, ...) within the configured step gap must be exempt from rate/repeat spam counting.
- Non-numeric countdown-like messages (for example `10...`) are not exempt.
- Existing ban-key priority remains: `beammp` identifier first, then `ip` fallback.
- If `config.json` is missing, log and use defaults.
- If `config.json` is partial, merge missing options from defaults.

## Testing Requirements

- Run local tests before committing:
  - `lua Server/SpamBanGuard/tests/run.lua`
- Keep Lua files syntax-valid:
  - `find Server/SpamBanGuard -type f -name '*.lua' | xargs -n1 luac -p`
- CI workflow: `.github/workflows/test.yml` runs syntax checks and test suite on push/PR.

## Commit Policy (Required)

Use **Conventional Commits** for all commits in this repo.

Accepted examples:

- `feat(spam-guard): add countdown exemption tests`
- `fix(engine): avoid false positive cooccurrence ban`
- `refactor(detectors): split repeat logic into module`
- `test(ci): add Lua workflow for plugin tests`
- `docs(readme): update ban store format docs`

If a change does not fit `feat`/`fix`, use appropriate conventional types such as `refactor`, `test`, `docs`, `chore`, or `ci`.
