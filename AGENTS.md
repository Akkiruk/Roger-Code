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
- Stakes are deliberately not taken up front: nobody gives up tokens before a round ends. A round's net moves once, after the final reveal has played (never before it: the balance and the bank's "[CCVault] +N tokens" chat line would give the result away), with the result journaled before the reveal starts, and anything that cannot move is kept in `journal` as owed. Every transfer goes through `books.lua`, so a crash at any step can be answered. A live shoe's seed is never shown or logged (`shoe = true` on the game table), the hash is on the table before any card, and the owner's touch locks a table's terminal. Network messages are checked for shape and size only: no signing.
- House limits are owner settings: the reserve (default 500 tokens of the host's balance, never risked) and the per-round share (default 25% of what is above the reserve, the most one round's biggest win may take). `Shared/lib/casino/limits.lua` holds the defaults and the values on offer; the owner changes them on the Casino Hub wall (touch it, HOUSE LIMITS), and the hub's state carries them to every table and group table of that host. Read them through `limits.room`/`limits.maxBet` with the host's name, never a number of your own.
- Every bet screen (single tables, group seats, buy-ins and stakes) says what the player may bet: "You can bet up to X", X the smaller of their balance and the table limit (`limits.allowed`; the house's cover and any cap of the game's), read again every few seconds and "Checking your balance..." until it is read. Chips over X are greyed, MAX is exactly X, and at X a line says why ("your balance" / "table limit"). A greyed button with a `why` still answers a tap with that note (`ui.button` adds a `refused` region; group seats show it themselves). Roulette checks each spot against the house's cover as it goes down, since a spot that pays more can take less.
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
- Display chests are never left stocked: filled while their shopper holds them, emptied after. A piece is paid for as it is taken: after a take goes on the tab, `autoPay` pays the tab through the same steps as PAY (tab to payment to the owed book to a transfer). vhcctweaks 2.2.37 (e7c880a) lets a computer charge a player who approved it with no fresh touch; older builds also want a touch within `interactionStaleSeconds`, so there it often cannot. A charge the server takes nothing of is undone back onto the tab, as it was (`pay-undone`: the lines back on the tab and the tokens written down as a refund in one save, booked once as `gs-ref-<id>`). Whatever is owed is collected first on the player's next tap of any shop screen (`collectOnTap`, posted before the tap's own job; PAY does it itself) and when they are checked out. Pieces paid for this visit are kept in `state.paid`; one put back (at a station, the kiosk or the sell chest) is refunded, store credit to credit and tokens host to player (no touch needed), through `state.refunds`. Store credit also goes against tokens already owed. PAY stays on every station's screen (and on the door, if there is one: the door is optional); the spending allowance is never used. Store credit is spent first and never paid out. Selling to the shop pays store credit only while the `sellForTokens` limit is off (the default); a sale begun for tokens and anything still owed from one are paid as before. With it on, sellers pick tokens or credit, and the owner's floor only stops those token payouts.
- Prices: a piece costs `pricePerLevel` (1) tokens per level of the gear, never under `minPrice` (1), whatever its rarity, so one station holds pieces at different prices: its screen shows the range of what is in the chest ("40-49 each"), each piece is charged its own price (fixed when it goes on display), and a piece put back takes its own line off the tab. A seller gets `creditPerPiece` (1) store credit for each accepted piece, or `tokensPerPiece` (1) tokens with `sellForTokens` on.
- A display chest or the kiosk needs no player detector of its own: setup records its place through any detector (the door's), and a piece taken from it goes on the tab of the shopper it is locked to. A detector of its own, if it has one, is still used to tell who took a piece.
- A display chest's monitor lists no gear (the shopper opens the chest): it shows the type and level, the price, the shopper's tab and store credit, the page, and the buttons. The main target is a 2x1 monitor flush in the floor (36x10 at scale 0.5).
- One display station per gear type: setup (A, then G to change it) gives each station one gear type (`gearType` in the setup, e.g. `the_vault:sword`; its wing is set from the type, for the label), or a family of types: `idol` (`the_vault:idol`) is every `the_vault:idol_*`, matched like a wing's names (`rules.ofType`). There is no separate check-in: a tap on a free station (or the kiosk) checks the player in (with the one-time APPROVE in chat, as before), and the station fills with its type at their level bracket (the nearest bracket with stock); LV -/+ steps to the next bracket that has some, NEXT PAGE pages, DONE gives it back. It is also given back on check-out, when its shopper walks `stationLeaveDistance` away from it (two looks running), or after `stationIdleMinutes` with no tap or take there. A shopper holds at most `stationsPerShopper` (3) at once: tapping one more frees the one they used longest ago. Anyone else tapping a held station sees "In use by <name>" and a rough "free in" hint. The station screen is titled with its type even when free ("SWORDS - tap to browse") and has no TYPE picker.
- A station's place is recorded by the owner standing on its chest (setup A, first step), through any detector; that step takes Enter at the terminal or a tap on any shop monitor, so it can be done before the station's monitor is up (S skips the monitor step; M sets it later).
- Wings: G can instead put a station in a wing from the `categories` limit (Weapons, Armour, Magic, Oddities); such a station, or one with neither, keeps the TYPE picker and offers its wing's types (every type with no wing).
- The how-it-works screen (setup H, a tap on its monitor; `info` in the setup, absent in older setups) is help: a home screen of topics as big buttons, each topic a page (NEXT and BACK when it runs long, HOME always) and a page of questions whose answers open on a tap; back home after a minute untouched. Its pages turn in the screen coroutine (`ui.infoTouch`); a tap there is still a shop tap and collects what the tapper owes. Every number on it comes from the limits and the setup (`ui.infoTopics`, `ui.infoFaq`). Made for a 4x4 monitor at text scale 1 (39x26); one narrower than 36 columns at scale 1 (a 3x3) uses 0.5.
- A monitor the shop can reach with no job shows "Not set up yet" (`ui.idle`). A node blanks its own monitors when it starts and then announces itself; the shop then draws that node's monitors again in full, so neither the installer's update screen nor a stale picture lingers.
- The sell screen on a monitor of 20 rows or more (the owner's 2x2 in the floor, 36x24) has headed sections: what to do, what is bought one rule a line (`rules.buysLines`), the pieces in the chest or the last batch one a line (green bought, red refused and why), the seller's store credit, and big buttons. A 2x1 keeps the compact layout.
- The returns, junk and intake steps (U, J, I) also watch the unassigned Sophisticated storage (otherwise all vault), a few at a time, so a netherite barrel can be shown by dropping an item in it. Any container with a job is never vault (`isVaultChest` checks the roles first). If the one picked held vault stock, setup says to empty it before W.
- W with someone checked in says so; a second W checks everyone out (stations emptied into the vault, tabs kept), then writes. A shop with no door has no CHECK OUT, and the owner is often checked in himself.
- The search kiosk shows inputs only; what a search brings goes into its pickup chest, best first, and the shopper looks through it there (no lists on the screen, no free text). ADVANCED SEARCH: type, a level range, rarity, legendary only, a least Gear Score, stat filters (each a least value, stepped by about a tenth of the best in stock, `rules.statStep`), and what "best" means (Gear Score, level or one of the stats: `rules.rank`). The stats offered are those on pieces in stock (`Stock:stats`, from `piece.stats`: modifier `attribute` ids, without `the_vault:`, and numeric values), grouped Offense, Defense, Utility by words in their names (`rules.statGroup`). IMPROVEMENTS (Phase 1 of the design in the lobby build folder, no build logic): `getPlayerEquipment` (read at most once a minute per shopper) gives the Gear Score worn per slot; pieces in stock that beat it by `improveMargin`, from `improveBelow` levels under the shopper up to `improveAbove` over, identified and not broken, come usable-now first by gain, then the ones over their level (`rules.improvements`). The slot picker shows how many each slot has; a slot (or ANY SLOT) brings them, as a search by keys in that order. `rules.piece` keeps `slot`, `gs` (only when the scorer counts it), `greed`, `broken` and `stats` (vhcctweaks 2.2.37 details).
- IMPROVEMENTS by build (Phase 2): `lib/gearshop/builds.lua` holds the design's ten presets (weights 0-3, REF per attribute, caps, `require`d types per slot, `keep` core stats, ability patterns, trinkets); the owner's own weights are the limit `buildWeights`, edited on page 4 with B. `lib/gearshop/improve.lua` is pure: `infer` (worn stats as a cosine against each build, Temper lean, what they hold, abilities on gear and, from vhcctweaks 2.2.37, learned skills and the one on their key, trinkets; under 0.35 confidence it says "pick your build" and uses balanced), `fit` (fit points; a capped stat counts only up to the player's own cap from `getPlayerStats`, else the build's), `upgrade` (type allowed, the keep rule: never lose more than 10% of a core stat, the worth-it threshold), and `search` (same level window as Phase 1, identified, unbroken, greed tier the player can wear; looter judges only boots and magnets). `Shop:readPlayer` reads everything once a minute and marks the read `limited` when the server lacks the 2.2.37 reads (the kiosk then says "Build guess limited until the server updates"). A player's own pick ("gs" is Best rolled, the Phase 1 rule) is kept in `state.builds` between visits; CHANGE BUILD on the kiosk sets it, "Let the shop guess" clears it.
- The kiosk frees itself like a station (`stationIdleMinutes`, `stationLeaveDistance`). A note after APPROVE (a payment or payout that went through) shows on the screen the player last tapped.
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
