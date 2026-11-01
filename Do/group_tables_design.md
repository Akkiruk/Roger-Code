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
- All computers are placed by the same owner. A seat whose `ccvault.getHostName` differs from the dealer's is refused at pairing.
- The same package goes on every computer. On first boot the owner's touch picks DEALER or SEAT, kept in `group_role.dat`.

## Link security

Ender modems are heard everywhere on the server, by anyone with a modem, so the plain-network rule in `casino_roadmap.md` is not enough here: hole cards would be readable, and a forged "pay this player" would drain the host. This is the one place more than light anti-cheat is justified, because it guards the host's tokens. Light otherwise.

- Pairing: the dealer shows a 6-digit table code on its wall and terminal. The owner keys it into each seat on a touch keypad. Key is `sha256(code .. dealerId .. hostName)`. The code never goes over the air. The dealer gives each seat a number in pairing order. Saved in `group_link.dat`.
- Every message on protocol `casino.group.v1` is `{ to, from, seq, nonce, box, mac }`: `box` is the serialized body under the ChaCha20 stream from `lib/casino/rng.lua` keyed from key and nonce; `mac` is HMAC-SHA256 from `rng.sha256` over everything else. Anything with a bad mac, wrong recipient or a seq at or below the last seen is dropped silently. `seq` starts from `os.epoch("utc")` so a reboot never reuses one.
- Nothing secret ever goes in a toast, the dealer wall or a log. In a `house` game secrets are few; in a `players` game each seat is only ever sent that seat's view.
- Accepted weakness: a 6-digit code can be brute-forced offline by someone who captured traffic and writes the tool. Say so in the roadmap.

## Money

The rules in `casino_roadmap.md` hold, all of them: stakes never up front, one settle before the final reveal, a reboot resumes, every transfer through `books.lua`, chips declared not taken, `transfer` needs a touch within 30 seconds on that computer. vhcctweaks stays on 2.2.35.

ccvault sessions are per player per computer, so **only the seat's computer can move that player's tokens**. The dealer owns the truth; the seat is the hands.

- The dealer's owed book (`journal`) holds every result. A hand's nets are booked there once, under a tag, before anything moves.
- A move is an order `{ tag, name, amount }` to that player's seat. Tags are unique per attempt. The seat handles it exactly once: it writes `open[tag]`, calls `journal.book` then `books.move`, takes any part that did not move back off its own book so only the dealer's book carries a debt, writes `done[tag] = moved`, and answers `{ tag, moved }`. A repeated tag gets the stored answer. After a reboot the seat resolves `open` with `books.resolve` before answering anything.
- The dealer comes off its book only on that answer. An order with no answer is sent again under the same tag.
- A seat refuses an order whose amount exceeds what the dealer's own limits allow (`limits.lua`), so a stolen key has a ceiling per order.
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
| `link.lua` | Pairing, sealing, seq, heartbeats, resend |
| `station.lua` | One interface over a remote seat (through `link`) and a local wall (Duel): `show(view)`, input as `(seat, who, buttonId, value)` |
| `dealer.lua` | Runs a table: lobby, game choice, seats, the hand loop, timers, journal, FAIR, settling, results |
| `seat.lua` | The seat computer. Thin: draws what it is sent, reports touches, carries out moves |
| `seatui.lua` | Layout helpers for a seat screen of any size |

A dealer reboot resumes the hand from its journal while seats show WAITING FOR THE DEALER. A seat that goes quiet is auto-acted after the turn limit and loses the seat after 2 hands, as Poker Table does.

The game on Big Table is picked from 8 tiles on the dealer wall while no hand is running. Picking needs no seated player; a change while players are seated happens between hands and needs the owner or every seated player's agreement on their screens. An idle wall runs a demo or a tile menu.

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
- A forged, replayed or tampered message must change nothing.
