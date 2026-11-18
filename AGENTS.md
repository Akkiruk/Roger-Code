# Roger-Code Instructions

## Scope

- This repo is the source of truth for the user's ComputerCraft and Lua programs.
- Primary branch: `main`
- Deployment target: dedicated-server ComputerCraft computers via the GitHub installer/update flow.

## Source Of Truth

- Keep canonical ComputerCraft source, configs, tests, and shared libraries here.
- Never rely on local singleplayer saves, PrismLauncher world files, or direct runtime log inspection for this repo.
- Main layout:
  - `Games/<Name>/` for actual game packages
  - `Apps/<Name>/` for non-game multi-file installable programs
  - `Shared/lib/` for shared libraries
  - `System/` for installer and universal runtime bootstrap files
  - `Utilities/` for standalone tools
  - `Do/` for project docs

## Manifest And Deployment

- The primary deployment flow is the generated deploy index published from `scripts/build-deploy-index.ps1`.
- On every push to `main`, GitHub Actions publishes the current deploy metadata to the `deploy-index` branch.
- `Games/manifest.json` and the old manifest generator have been retired from the deployment flow.
- Folder-based installable packages must mark their entrypoint file with `-- manifest-entrypoint: true`; the deploy-index builder no longer guesses a main file.
- Top-level standalone `Utilities/*.lua` files remain auto-discovered as single-file install targets without needing the marker.
- Local world deployment scripts are deprecated stubs and must not be used.
- Generated package versions are auto-bumped by the deploy-index builder when package hashes change.
- Installer and updater metadata come from `https://raw.githubusercontent.com/Akkiruk/Roger-Code/deploy-index/...`, while payload files are downloaded from commit-pinned raw URLs under `main`.

## Runtime

- Assume runtime computers live on the dedicated server and are not directly accessible from this workspace.
- Validate changes through source inspection, package metadata, and the published installer/update flow unless the user explicitly supplies external runtime evidence.

## Casino

- Every wagering game is a plugin on `Shared/lib/casino/table.lua`: pure rules, a view, a game table. Read that file's header first; `Games/HiLo` is the reference.
- Rules never touch ccvault, the screen or sound, and hold plain numbers, so they test without a monitor and survive a reboot.
- Stakes are deliberately not taken up front: nobody gives up tokens before a round ends. A round's net moves once, before the final reveal, and anything that cannot move is kept in `journal` as owed. Every transfer goes through `books.lua`, so a crash at any step can be answered. A live shoe's seed is never shown or logged (`shoe = true` on the game table), the hash is on the table before any card, and the owner's touch locks a table's terminal. Network messages are checked for shape and size only: no signing.
- Paytables are total return on the bet. A new paytable needs a return check in `Tests/`.
- Tables are built for one fixed 6x6 monitor wall at text scale 0.5, about 121x81 cells, each cell 2 wide by 3 tall.
- A table has at most 4 peripherals and 2 monitors, all optional: player detector, speaker, wireless modem, chat box, plus the wall and one smaller monitor, which is a display-only scoreboard (`board.lua`). A table with none of these must play exactly as it does with them.
- Detector, chat box and integrator calls wait a tick and swallow events, so they only run in a worker coroutine (`presence.lua`, `chat.lua`, `lamps.lua`), never in the main loop.
- Chat is only ever whispered to a named player, and nothing sent to chat may reveal another player's cards. `session.lua` holds what a player is told as they go, and reads the owed book without changing it.
- Idle screens play a real round through `demo.lua`. A demo must never touch `keep`, the journal, the wallet, the stats or the hub. A game steers its demo with `game.demo`; `view.attract` is the fallback.
- Practice and hub tournaments are one thing: a pretend seat, with chips and no tokens. `table.lua` reaches money only through `door.lua`, and with a pretend seat sitting every door leads to the stand-ins in `pretend.lua`. A new module that holds money or player records goes behind a door, never a direct `require` in `table.lua`; a new door call needs a stand-in, or `Tests/practice_test.lua` fails. Tournaments never move tokens, and `tournament.lua` is their only file on a table.

## Gear Shop

- `Apps/GearShop` on `Shared/lib/gearshop`: the owner's walk-in gear shop. One shop computer runs everything; every other computer is a node that only lends its chests, monitors and detectors through its ender modem (vhcctweaks 2.2.36 links). Only CC:Tweaked, Advanced Peripherals and vhcctweaks: no Mekanism.
- `rules.lua` is the maths and holds every limit's default (prices, what is bought, credit, the owner's floor); it touches no peripheral and `Tests/gearshop_test.lua` runs it and the vault index (`stock.lua`) against pretend chests.
- `shop.lua` is the only code that changes anything, and it only runs in the worker coroutine (`app.lua`): inventory, detector and money calls lose events while they wait. The screen coroutine draws and turns events into jobs, and never makes such a call.
- The chests are the truth about items. Each display chest's phase (`filling`, `open`, `sweeping`) is written before items move, so a reboot at any step can be finished; read the header of `shop.lua` before changing a step. Tokens go through the casino's `journal.lua` and `books.lua`, never straight to `ccvault`.
- Display chests are never left stocked: filled while their shopper is checked in, emptied after. Payment is the tab, paid by one tap on PAY; the spending allowance is never used. Store credit is spent first and never paid out. Selling to the shop pays store credit only while the `sellForTokens` limit is off (the default); a sale begun for tokens and anything still owed from one are paid as before. With it on, sellers pick tokens or credit, and the owner's floor only stops those token payouts.
- A display chest or the kiosk needs no player detector of its own: setup records its place through any detector (the door's), and a piece taken from it goes on the tab of the shopper it is locked to. A detector of its own, if it has one, is still used to tell who took a piece.
- A display chest's monitor lists no gear (the shopper opens the chest): it shows the type and level, the price, the shopper's tab and store credit, the page, and the buttons. The main target is a 2x1 monitor flush in the floor (36x10 at scale 0.5).
- Wings: setup (G) can put a display chest in a wing from the `categories` limit (Weapons, Armour, Magic, Oddities). It then only shows and offers its wing's types; check-in fills the nearest chest of every wing first, then the nearest of the rest (`rules.spread`). A chest with no wing shows every type.
- Refused gear at the sell point goes to the returns chest (setup U) at once, moved like every other item (`state.moving` written before), with a record of who stood at the sell point; DONATE gives it to the junk chest (setup J), never to stock. With no returns chest it stays in the sell chest as before; with no junk chest there is no DONATE.
- A player lookup can fail at any moment (offline, or on another server of the network): it returns nil and a reason, never throws, and what could not be done waits.
- The whole shop is tested in the emulator from craftos-agent: `node tools/geartest/all.mjs` (visits, selling, unloads and other servers, a crash at every money and item step, setup at the terminal, 15,000 pieces). Money or item code is not done until `crash.mjs` passes.

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
- Do not attempt direct local deployment or runtime log inspection. Push to GitHub and let the server-side installer/update flow pull the new version.
- Casino rules and payouts must pass `Tests/run.lua` before pushing. GitHub runs no tests: publishing only builds the deploy index, so test before you push.
- Use `scripts/push-all.ps1` for the default fast path unless the task needs a custom flow.
- Do not fake success or use destructive history rewrites. If a push fails, report it plainly.
