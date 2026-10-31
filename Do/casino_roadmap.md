# Casino Roadmap

Last updated: 2026-10-31

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

The monitor is always a 6x6 wall at text scale 0.5.

## Rules That Must Hold

- Stakes are never taken up front. This is the owner's decision: nobody gives up tokens and then waits to get them back.
- A round's net moves once, before the final reveal plays. What cannot move is kept as owed and settled when that player next sits down.
- A reboot resumes the round. Nothing is voided.
- vhcctweaks stays on 2.2.35. Money only moves within 30 seconds of the player's last touch. Pressing a button is a touch, so a slow decision settles at once.
- With a player detector (`presence.lua`, range 12) someone at the table gets 5 minutes, and someone gone for 5 seconds has the round finished and settled at once. With no detector the round finishes after 60 seconds. What could not move is owed until that player next touches the table.
- Paytables are total return on the bet, in every game.
- `Tests/run.lua` runs in the publish workflow. A game outside its target return stops the deploy.
- Anti-cheat stays light: make abuse awkward, don't build around it.

## Testing

- `Tests/`: rules, payouts and returns, pure Lua.
- `craftos-agent/tools/casinotest/`: every game played on the emulator; `money.mjs` proves the money rules.
- `craftos-agent/tools/mcbridge/rc-casino.mjs`: every game with real tokens on a real server.

## Later

- PhoneOS still has its old blackjack and slots. They are deprecated and were left alone.
- Texas Hold'em on PokerTable, once five-card draw has proved itself on a live server.
