# Group Tables: Big Table and Duel

Two new casino cabinets on one new engine, `Shared/lib/casino/group/`. Decided by the owner on 2026-11-01:

- **Big Table** (`Games/BigTable`, package `big-table`, category Games): 8 games for several players, each at their own screen.
- **Duel** (`Games/Duel`, package `duel`, category Games): 1v1 games for stakes on the Arcade's two-wall design, like Battleship: two equal 6x6 walls back to back with the computer between.
- Poker Table's five-card draw is one of Big Table's 8. It has left the Casino cabinet. `Games/PokerTable` stays as its own package and does not change.

The Arcade stays free. Nothing here goes in `Games/Arcade` or adds tokens to `Shared/lib/arcade`.

## The games

| Cabinet | Game | Kind | Seats |
| --- | --- | --- | --- |
| Big Table | Five-Card Draw, using `pokertable_rules` | players | 2-6 |
| Big Table | Texas Hold'em, fixed limit | players | 2-8 |
| Big Table | Omaha, fixed limit | players | 2-8 |
| Big Table | Seven Card Stud, fixed limit | players | 2-8 |
| Big Table | Blackjack, shared dealer hand | house | 1-8 |
| Big Table | Roulette, shared wheel | house | 1-8 |
| Big Table | Baccarat, shared coup | house | 1-8 |
| Big Table | Craps, shared dice | house | 1-8 |
| Duel | Heads-Up Hold'em | players | 2 |
| Duel | Gin Rummy, stake per point | players | 2 |
| Duel | Liar's Dice, stake per match | players | 2 |
| Duel | Battleship, stake per match | players | 2 |

## Big Table hardware

- One **dealer**: advanced computer, 6x6 wall at scale 0.5 (121x81), any modem. The wall shows what everyone may see: pot, community cards, wheel, dice, seats, whose turn.
- Up to 8 **seats**: each an advanced computer, a 4x4 wall at scale 0.5 (78x52 cells), and an ender modem. Each shows that player's private cards and their buttons. A bigger seat wall centres the same 78x52 layout.
- All computers are placed by the same owner.
- The same package goes on every computer.

## Setting up is automatic

The owner decided on 2026-11-01: griefers are not a worry, so easy to use beats secure. No codes, no keys, no encryption, no keypad, no setup screens. Anti-cheat stays light, the same as the rest of the casino.

- Install the package on every computer and it works. The wall decides the role: a 6x6 wall makes a dealer, a smaller one makes a seat. No touch is needed.
- A seat finds its dealer by itself: it broadcasts on protocol `casino.group.v1` until a dealer with the same `ccvault.getHostName` answers, and joins it. If one owner has several dealers in range of the network, the seat shows them as tiles for one tap, and remembers the choice in `group_link.dat`. The dealer gives seats numbers in the order they arrive.
- Messages are plain rednet, addressed to one computer, with a `seq` from `os.epoch("utc")` so stale or repeated ones are dropped. Shape and size are checked like `net.lua` does, so junk cannot crash a table. Nothing is signed or sealed, so a private view can be overheard by someone who goes looking, and the owner accepts that.
- Nothing secret goes in a toast, on the dealer wall or in a log. In a `players` game each seat is sent only that seat's view.

## Nobody has to be the dealer

The owner said on 2026-11-01 that no game may need a person dealing or running it. "Dealer" only ever means the computer.

- A round starts by itself: once enough seats are ready, a short countdown runs and the computer shuffles, deals, spins, rolls, draws for the house and pays. Nobody presses start, and more players can sit during the countdown.
- A player who does not act is handled by `auto` when their turn timer runs out, so one person cannot stall the table.
- In Craps the shooter taps ROLL, and the computer rolls for them when the timer runs out. The computer rolls with nobody seated as shooter.
- The owner does not need to be online or at the table. Nothing in a round waits for them, and their touch is only ever an option, never a requirement.

## Money

The owner's flow, on 2026-11-01: when a game resolves, money goes from the losers to the computer's owner, and from the owner out to the winners. That is the `players` order below. The owner is the go-between and keeps only the rounding: when a split pot cannot divide evenly, the odd chips go to the owner, not to a player. That is the only cut in a `players` game, and there is no rake. The lead adds this after the review fixes, so nobody else changes it yet.

The rules in `casino_roadmap.md` hold, all of them: stakes never up front, one settle before the final reveal, a reboot resumes, every transfer through `books.lua`, chips declared not taken, `transfer` needs a touch within 30 seconds on that computer. vhcctweaks stays on 2.2.35.

ccvault sessions are per player per computer, so **only the seat's computer can move that player's tokens**. The dealer owns the truth; the seat is the hands.

- The dealer's owed book (`journal`) holds every result. A hand's nets are booked there once, under a tag, before anything moves.
- A move is an order `{ tag, name, amount }` to that player's seat. Tags are unique per attempt. The seat handles it exactly once: it writes `open[tag]`, calls `journal.book` then `books.move`, takes any part that did not move back off its own book so only the dealer's book carries a debt, writes `done[tag] = moved`, and answers `{ tag, moved }`. A repeated tag gets the stored answer. After a reboot the seat resolves `open` with `books.resolve` before answering anything.
- The dealer comes off its book only on that answer. An order with no answer is sent again under the same tag.
- `players` games use `pokertable_rules.settle`'s order, across the network: collect from every loser first, pay winners only from what was collected, never below even. A loser's failure never costs the host.
- `house` games settle each seat against the host on its own. Before a round the dealer checks `wallet.hostBalance()` covers the sum of every seat's `maxWin`, and shrinks or refuses bets that do not fit.
- The dealer reads balances itself with `wallet.balance`, which needs no touch.
- Any touch on a seat tells the dealer; if the book holds something for that name, the dealer sends a fresh order.
- A seated player with a debt plays on what their balance covers after it. Someone who has left must clear it before sitting again. One book for the whole table, not per game.
- In Duel both walls are on one computer, so the same flow runs with a local station and no network.

## The engine

`Shared/lib/casino/group/`:

| File | Job |
| --- | --- |
| `link.lua` | Finding the dealer, seq, heartbeats, resend |
| `station.lua` | One interface over a remote seat (through `link`) and a local wall (Duel): `show(view)`, input as `(seat, who, buttonId, value)` |
| `dealer.lua` | Runs a table: lobby, game choice, seats, the hand loop, timers, journal, FAIR, settling, results |
| `seat.lua` | The seat computer. Thin: draws what it is sent, reports touches, carries out moves |
| `seatui.lua` | Layout helpers for a seat screen of any size |

A dealer reboot resumes the hand from its journal while seats show WAITING FOR THE DEALER. A seat that goes quiet is auto-acted after the turn limit and loses the seat after 2 hands, as Poker Table does.

The game on Big Table is picked from 8 tiles on the dealer wall while no hand is running. Picking needs no seated player; a change while players are seated happens between hands and needs every seated player to agree on their screens. An idle wall runs a demo or a tile menu.

### A game plugin

`Games/<Cabinet>/games/<id>/plugin.lua`, listed in that cabinet's `games/registry.lua`, returns:

```lua
{ id, title, kind = "players"|"house", minSeats, maxSeats, felt, help = function() return lines end,
  rules = ..., tableView = ..., seatView = ... }
```

Rules are pure, serializable and use only the `rng` given. `seat` is a seat number:

| Function | Contract |
| --- | --- |
| `new(entries, button, rng, keep)` | `entries` is a list of `{ seat, name, stack or bet }`. Returns state, events |
| `waitingOn(state)` | List of seats that may act now. More than one for simultaneous betting |
| `actions(state, seat)` | Buttons: `{ id, label, color, sub, value, cost }` |
| `act(state, seat, id, value, rng)` | Applies it, returns events. Illegal input does nothing |
| `auto(state, seat)` | The safe default for a missing player: check, fold, stand, no bet |
| `viewFor(state, seat)` | What this seat may know, built field by field. `seat = nil` is the table's public view |
| `done(state)`, `nets(state)` | `nets` is seat -> tokens. For `players` they sum to zero |
| `result(state, seat)` | `{ kind, title, detail }` for that seat |
| `maxWin(entry)` | House games: the most this bet can win |

Views are pure functions of a serialized view: `tableView.draw(c, view, anim)` on the dealer, `seatView.draw(c, view, anim)` on the seat, `seatView.regions(view)` for tappable cards. `event(ev)` gives duration and sound. The engine, not the game, owns buttons, timers, money and FAIR.

## Tests

- Pure tests go in `Tests/group_<id>_test.lua` and are picked up by `Tests/run.lua`, so a game outside its return target stops the deploy.
- `craftos-agent/tools/casinotest/group.mjs` runs a dealer and real seats with `SessionManager.createNetwork`, ender modems and real rednet. Each emulated computer has its own world and ledger, so the harness must keep balances in step or prove conservation across the ledgers. Log that in `docs/conformance/emulator-vs-real-deviations.md`.
- Crash tests take the dealer and a seat down at each step of a move. Each step of `settle` must be exactly once.
- Junk and repeated messages must not crash a table or move tokens twice.
