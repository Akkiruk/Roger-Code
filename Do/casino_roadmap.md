# Casino Roadmap

Last updated: 2026-11-01

## What Is Shipped

Every wagering game was rebuilt on one engine, `Shared/lib/casino/`. Read the header of `table.lua` first; `Games/HiLo` is the reference game.

| Game | Package | Return with good play | How it is proved |
| --- | --- | --- | --- |
| Blackjack | `blackjack` | 98.65% | Basic-strategy simulation |
| Baccarat | `baccarat` | Banker 98.94%, Player 98.77%, Tie 85.64% | Exact enumeration |
| Video Poker | `videopoker` | 98.373% | Exact, optimal hold on every deal |
| 3 Card Poker | `three-card-poker` | Ante 96.63%, Pair Plus 92.72% | Exact enumeration |
| Ultimate Texas Hold'em | `ultimate-holdem` | 97.57%, Trips 96.50% | Simulation, 150M hands |
| Hi-Lo | `hilo` | 96% at every stopping point | Pricing rule plus simulation |
| Crazy Eights | `crazyeights` | At most 97.4% found | Simulation against the best plan found |
| Slots | `slots` | 95.02% before the jackpot | Exact |
| Roulette | `roulette` | 97.30% | Exact |
| Horse Racing | `horse-racing` | 95.18% to 96.00% on every bet | Exact over all finishing orders |
| Five-card draw | `pokertable` | Players against each other, no rake | Conservation and side-pot tests |
| Casino Hub | `casino-hub` | Leaderboards, measured returns, shared jackpot | Scenario suite |
| Casino cabinet | `casino` | All 10 single-player games on one computer, one at a time, from a menu | Emulator walk-through |
| Big Table | `big-table` | 8 games on one dealer and up to 8 seats. Hold'em, Omaha, Stud and Five-Card Draw are players against each other, no rake. Blackjack, Roulette, Baccarat and Craps are against the house, each with a return its test holds to | Each game's `Tests/group_<id>_test.lua`, and `group.mjs` on real rednet across real seats, with a crash at each step of a move |
| Duel | `duel` | Heads-Up Hold'em, Gin Rummy, Liar's Dice and Battleship for stakes, 1v1 on two walls of one computer, no rake | Each game's `Tests/group_<id>_test.lua`, and `group.mjs` |

The cabinet bundles the game folders through `manifest-bundle` in `Games/Casino/startup.lua`. A game starts by reboot, and its `casino_*` files are stored as `cabinet_<game>_casino_*`, so each game keeps its own books. A round left open returns to its game on boot.

Big Table and Duel run on their own engine, `Shared/lib/casino/group/`. `Do/group_tables_design.md` says how and why. Games are listed in each cabinet's `games/registry.lua`, and `Games/BigTable/games/README.md` is what a game provides.

The monitor is always a 6x6 wall at text scale 0.5.

## Around The Table

A table has at most 4 peripherals and 2 monitors: player detector, speaker, wireless modem, chat box, plus the 6x6 wall and one smaller monitor. All of it is optional, and a table with none of it plays the same.

| Feature | Where | Needs |
| --- | --- | --- |
| Whispers: a queued outbox, spaced for the box's cooldown, retried, oldest dropped past a limit | `chat.lua` | Chat box |
| Owed notes: a player who has left is told what the book holds, once per amount, and told when it moves | `session.lua` | Chat box |
| Session summary: "12 rounds, +340, best win 900" on the wall and in a whisper. Survives a reboot | `session.lua` | Nothing. The whisper needs a chat box |
| Poker hands whispered when dealt and after the draw. PEEK stays, because a whisper can fail and PEEK is how cards are thrown | `pokertable_app.lua` | Chat box |
| Scoreboard: leaders, the jackpot if a hub is heard, NOW PLAYING. On the hub too | `board.lua` | A monitor smaller than the wall |
| Live attract screens: a real round through the rules and view, on every table and PokerTable's empty lobby | `demo.lua`, `game.demo` | Nothing |
| Win lamps on a big win or a jackpot, and the hub's own lamp on a jackpot. Sides are set in one place | `lamps.lua` | Nothing. A redstone integrator is used if present |
| Baccarat road: finished coups in `keep.road` | `baccarat_rules.lua`, `baccarat_view.lua` | Nothing |
| Hub page for Arcade results, heard on `arcade.v1`. Display only | `casino_hub_rules.lua`, `casino_hub_view.lua` | A modem on the hub |
| Practice: PRACTICE on the idle screen, 1,000 pretend chips, the same rules and screens, marked on every frame. No approval. It is the choice on offer when the economy is offline. An idle seat gives way in 10 seconds once someone else has touched the table | `door.lua`, `pretend.lua`, `Table:pretendSeat` | Nothing |
| Hub tournaments: the owner touches the hub wall, picks a game and 15, 30 or 60 minutes, and every table of that game offers TOURNAMENT. A live board, final standings, top three whispered, past winners kept | `tournament.lua`, `casino_hub_contest.lua`, `casino_hub_contest_view.lua` | A modem on the hub and tables. The whisper needs a chat box |
| HINT button: Blackjack's basic strategy and Video Poker's best hold, lit for 6 seconds. `hint = false` on a game table turns it off | `table.lua`, `rules.hint`, `videopoker_hint.lua` | Nothing |
| Badges: common ones plus `game.badges`, per table, with a line on the result and a whisper once the result is on the wall | `badges.lua` | Nothing. The whisper needs a chat box |
| Floor badge, beat the house at every game: the hub works it out from the rounds it hears and names champions in its state. Poker Table has no house and does not count | `casino_hub_rules.lua`, `badges.lua` | A modem on the hub |
| Player card, from the bet screen: record, win-loss bar, last 12 rounds, badges. The favourite game comes from the hub | `playercard.lua` | Nothing |
| The seated player's run of wins at the top of the scoreboard, updated when a result is shown | `board.lua` | A monitor smaller than the wall |

## Rules That Must Hold

- Stakes are never taken up front. This is the owner's decision: nobody gives up tokens and then waits to get them back.
- A round's net moves once, before the final reveal plays. What cannot move is kept as owed and settled when that player next sits down.
- A reboot resumes the round. Nothing is voided.
- Every transfer goes through `books.lua`: the result is booked, the transfer is written down, it happens, and it is crossed off in one write to the owed book. A crash at any step is answered from the audit log, then the server's ledger once the player has touched the table. If neither can ever tell, a payment counts as not made and a charge as taken, so the host carries the doubt and the player never does.
- In a shoe game a live shoe's seed is never shown or logged. FAIR shows the shoe's hash, and its seed once the shoe is finished. A new shoe game sets `shoe = true` on its game table and `keep.shuffled` when it reshuffles.
- The hash is on the table before any card, in the play scene and on PokerTable. FAIR must only promise what is true.
- The owner's touch locks a table's terminal, on tables, PokerTable and the hub. A table stays playable, and asks on its idle screen until it is locked. `isTerminalLocked` only reads.
- The network is not trusted and not signed. Anything a table or the hub hears is checked for shape and size, nothing more.
- Big Table's network is unsigned and unencrypted on purpose. The owner chose this on 2026-11-01: griefers are not a worry, so easy to use beats secure. A private view can be overheard by someone who goes looking, and that is accepted. No codes, keys or setup screens are to be added.
- A jackpot claim the hub has not answered pays the seed at once and stays open until it answers, and then the player is booked the rest.
- vhcctweaks stays on 2.2.35. Money only moves within 30 seconds of the player's last touch. Pressing a button is a touch, so a slow decision settles at once.
- With a player detector (`presence.lua`, range 12) someone at the table gets 5 minutes, and someone gone for 5 seconds has the round finished and settled at once. After 25 seconds with no touch they are asked to tap, which keeps the money able to move. With no detector the round finishes after 60 seconds. What could not move is owed until that player next touches the table.
- Measured returns on the hub divide by everything wagered, raises, doubles and splits included. A game's `rules.risk` gives that at the end of a round. Three Card Poker and Hold'em state their hub targets on that basis, which is why they differ from the per-Ante figures above.
- Paytables are total return on the bet, in every game.
- `Tests/run.lua` runs in the publish workflow. A game outside its target return stops the deploy.
- Anti-cheat stays light: make abuse awkward, don't build around it.
- Detector, chat box and integrator calls wait a tick and swallow events, so they only run in a worker coroutine, never in the main loop.
- Chat is only ever whispered to a named player, never public, and nothing a table sends to chat may reveal another player's cards.
- A demo never touches `keep`, the journal, the wallet, the stats or the hub. It gets its own random source and a keep of its own for each round, so a live shoe cannot notice it.
- HINT is advice and nothing else: it is not an action in the rules, never reaches the journal, reads only what the player can see, and follows what the table is really offering, so a double the balance cannot cover is not advised. `rules.hint` is optional for any game. Blackjack shares `rules.basic` with its return test, and returns 98.55% of the opening bet, 98.64% of all wagered, over 200M rounds. Video Poker's table was fitted to this paytable and is on the best hold for 99.98% of all 2,598,960 deals, loses 0.00002 of a bet at worst, and returns 98.373%. `hint-oracle.mjs` proves both, and a changed paytable needs its `fit` run again.
- A lamp fires when the result is shown, not when the money moves: that is before the reveal, and a lamp would give the result away. The Baccarat road waits for the same reason, because `keep` has the result before the cards have played.
- A pretend seat cannot reach tokens. `table.lua` has no direct `require` of the wallet, books, journal, stats, session, net or lamps: they sit behind `door.lua`, which sends every call to `pretend.lua` while a pretend seat sits, and refuses anything with no stand-in. The seat has its own keep and shoe and nothing on disk, so a reboot just ends practice and a live round is never touched.
- A tournament moves no tokens, ever. One entry per player per contest: one stack at one table, played across as many visits as they like. `casino_tournament.dat` keeps each stack and what an open round has staked, so a reboot costs that stake and never gives a fresh stack. The hub takes a score from that table only, only if it is further on than the last, and never after a final one. A forged score can fake a leaderboard line, which is accepted. Nothing waits on the hub: if it goes, seats play on to the end they last heard and nobody new can enter.
- A badge comes after the money and never touches it. An error in badges is caught and logged, and a round always finishes. A badge is granted once: the round's tag lands in the same write as the grant.

## Testing

- `Tests/`: rules, payouts and returns, pure Lua.
- `craftos-agent/tools/casinotest/`: every game played on the emulator; `money.mjs` proves the money rules, `crash.mjs` takes the computer down at each step of a settle, `floor.mjs` covers the peripherals around a table, `badges.mjs` covers badges and the card, `practice.mjs` and `tournament.mjs` cover pretend seats, `hint.mjs` the HINT button, `hint-oracle.mjs` its advice, and `mutants.mjs`, `pretend-mutants.mjs` and `hint-mutants.mjs` prove those tests can fail. `group.mjs` runs the group engine on real rednet, `group-all.mjs` runs its cases a few at a time, `group-<game>.mjs` and `group-play.mjs` play the real games, and `group-mutants.mjs` proves `group.mjs` can fail.
- `craftos-agent/tools/mcbridge/rc-casino.mjs`: every game with real tokens on a real server.

## Later

- PhoneOS still has its old blackjack and slots. They are deprecated and were left alone.
- Texas Hold'em on PokerTable, once five-card draw has proved itself on a live server.
