# Roger-Code Instructions

## Scope

- This repo is the source of truth for the user's ComputerCraft and Lua programs.
- Primary branch: `main`
- Runtime target: `%APPDATA%\PrismLauncher\instances\mcparadisepack\minecraft\`

## Source Of Truth

- Keep canonical ComputerCraft source, configs, tests, and shared libraries here.
- Do not treat the PrismLauncher runtime instance as canonical source unless the user explicitly asks for an instance-local hotfix.
- Main layout:
  - `Games/<Name>/` for games and larger programs
  - `Games/lib/` for shared libraries
  - `Utilities/` for standalone tools
  - `Do/` for project docs

## Manifest And Deployment

- The primary deployment flow is the generated deploy index published from `scripts/build-deploy-index.ps1`.
- On every push to `main`, GitHub Actions publishes the current deploy metadata to the `deploy-index` branch.
- `Games/manifest.json` and the old manifest generator have been retired from the deployment flow.
- Use `scripts/sync-roger-code.ps1 -Game <Name>` only when the user explicitly asks for a local PrismLauncher deployment.
- `scripts/deploy-to-world.ps1` is the manual deploy entry point for live ComputerCraft saves; do not run it by default.
- The legacy `.vscode/deploy-to-emulator.ps1` path now forwards into the live PrismLauncher deploy flow for compatibility.
- Generated package versions are auto-bumped by the deploy-index builder when package hashes change.
- Installer and updater metadata come from `https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/...`, while payload files are downloaded from commit-pinned raw URLs under `main`.

## Runtime

- Prefer the real PrismLauncher world runtime under `saves/*/computercraft/computer/`.
- Use `scripts/deploy-to-world.ps1 -ListTargets` to see which computers currently have installed programs.
- Pass `-ComputerId` when you want to force deployment to a specific computer folder.

## Lua And ComputerCraft Rules

- Target Lua 5.1 and CC:Tweaked-compatible APIs.
- Never use `goto` or labels.
- Declare variables and functions before first reference; use forward declarations when needed.
- Prefer `local` over globals.
- Never pass possibly nil function references directly to `pcall` or similar wrappers.
- Use `os.epoch("local")` for real timestamps and elapsed time.
- Log operational errors to files instead of relying on screen output alone.

## Git Workflow Preference

- Default behavior after changes: commit and push directly to `main` without waiting for user review.
- Never create a feature branch or PR-only flow for routine repo changes unless the user explicitly asks for one.
- After any completed repo change, finish the loop in the same turn by pushing the full change set unless the user explicitly says not to push yet.
- Do not stop to ask for verification or review before pushing to `main` unless a failed git operation forces recovery work.
- Do not auto-deploy changes into the local PrismLauncher save. Push to GitHub and let the user's installer/update flow pull the new version unless the user explicitly asks for a local deploy.
- Skip tests, linting, emulator runs, and other verification by default. Only run verification when the user explicitly asks for it or when it is required to recover from a failed git operation.
- Use `scripts/push-all.ps1` for the default fast path unless the task needs a custom flow.
- Do not fake success or use destructive history rewrites. If a push fails, report it plainly.
