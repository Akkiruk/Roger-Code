# Copilot Instructions — Roger-Code Project Context

This file covers project-specific context for the Roger-Code repo only. Lua/ComputerCraft coding rules are in the minecraft workspace's `copilot-instructions.md` (loaded automatically in this multi-root workspace). Emulator and CraftOS-PC API details are in the `.instructions.md` files in this repo's `.github/instructions/` folder (loaded automatically for `Games/**` files).

## Repository Info

- GitHub: `https://github.com/Akkiruk/Roger-Code` (branch: main)
- Language: Lua 5.1 for ComputerCraft (CC: Tweaked)

## Project Structure

- `Games/<Name>/` — Casino games (Blackjack, Slots, Roulette, Baccarat, TaskMaster)
- `Games/lib/` — Shared CC libraries used across games
- `Games/emulator/` — CraftOS-PC mock framework and stubs
- `Games/installer.lua` — Universal installer (handles any program, not just casino games)
- `scripts/build-deploy-index.ps1` — Generated deploy-index builder
- `deploy-index/latest.json` — Published deployment catalog branch output
- `Utilities/` — Standalone utility scripts
- `Do/` — API reference docs

## File Storage Rules

- ALL scripts, configs, and test files live in this repo — never directly in the minecraft save folders.
- Games in `Games/<Name>/`, standalone utilities in `Utilities/`.
- Shared CC libraries in `Games/lib/`.

## Workflow Preference

- Prefer an aggressive autonomous workflow by default.
- If a task has an obvious next step that follows naturally from the user's request, take that step automatically and carry it through to completion.
- Pause only when the next step would be destructive, would conflict with existing work, or would force a non-obvious product decision that the user should make explicitly.

## Installer & Deployment Index

- `scripts/build-deploy-index.ps1` generates `latest.json` and `programs/*.json` package specs.
- Deployment metadata is published to the `deploy-index` branch and consumed by the installer/updater.
- Generated JSON must be UTF-8 with NO BOM (`[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`).
- Config files (`*_config.lua`, `*_settings.lua`) are preserved on updates.
- Any new subfolder with `.lua` files under `Games/` or `Utilities/` is auto-discovered by the deploy-index builder.

## Adding a New Program

1. Create folder under `Games/` or `Utilities/`
2. Add `.lua` files and entrypoint metadata comments as needed
3. Run "Build Deploy Index" locally if you want to inspect generated package output
4. Commit the source files
5. Push — GitHub Actions publishes deploy metadata automatically

## Deployment

Programs deploy via installer from generated deploy-index metadata.
The installer/updater discover packages from:
`https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/latest.json`

Payload files download from commit-pinned raw URLs under:
`https://raw.githubusercontent.com/Akkiruk/Roger-Code/<commit>/...`
