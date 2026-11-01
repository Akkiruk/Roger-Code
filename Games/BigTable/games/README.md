# Writing a group game

This is the whole contract for a game on **Big Table** or **Duel**. `Shared/lib/casino/group/` is the engine. It owns the seats, the buttons, the clock, the money and FAIR. A game owns its rules and two pictures, and never touches a wallet, a monitor, a modem or the clock.

`Tests/group_plugins/highcard.lua` (players) and `onebet.lua` (house) are complete working games of about 150 lines. Start by reading one.

## Where it goes

```
Games/BigTable/games/<id>/plugin.lua     returns the table below
Games/BigTable/games/<id>/<anything>.lua required as games.<id>.<anything>
Games/BigTable/games/registry.lua        already lists draw holdem omaha stud blackjack roulette baccarat craps
Games/Duel/games/<id>/plugin.lua         the same, listed for holdem gin liarsdice battleship
Tests/group_<id>_test.lua                picked up by Tests/run.lua
```

A registry loads each plugin in `pcall` and skips one that is missing or broken, so the cabinet runs while games are being written. Look in `casino.log` for `did not load`.

Use `require("lib.casino.deck")`, `poker`, `ui`, `theme` and the rest freely. `pokertable_rules` is on both cabinets through `manifest-bundle`, for its `pots`, `award` and five-card rules. Both cabinets have a `games.holdem`, so two plugins can only share rules through a file both can reach, such as `Shared/lib/casino/group/rules/<name>.lua` required as `lib.casino.group.rules.<name>`.

The plugin file must not run anything at load but `require`s and tables. No `goto`, Lua 5.1 only.

## The plugin

```lua
return {
  id = "holdem", title = "TEXAS HOLD'EM",     -- id matches the folder. title is on tiles and the top bar
  kind = "players",                           -- "players": nets sum to zero, less any odd chips in state.kept. "house": each seat against the host
  minSeats = 2, maxSeats = 8,                 -- 8 at most. Two for Duel
  felt = "green",                             -- green blue burgundy purple teal ember
  tagline = "Fixed limit",                    -- optional, one short line under the title
  help = function() return lines end,         -- strings, or { text, "gold" } for a heading. "" is a gap. No secrets
  event = function(ev) return seconds, sound end,  -- optional. sound is a name from lib/casino/audio.lua, or nil
  rules = rules, tableView = tableView, seatView = seatView,

  -- "players" games
  ante = 5,          -- the least a stack must hold to be dealt in. Default 1
  minBuy = 100, maxStack = 5000,              -- the buy-in panel. Defaults shown
  chips = { 100, 250, 500, 1000, 2500 },      -- optional. Tiles on the buy-in panel

  -- match games on Duel. With stakes set there is no buy-in: the first to sit names one and the second takes it or leaves it
  stakes = { 25, 50, 100, 250, 500 },
  stakeCover = 1,    -- a player must hold stake * this to sit. Gin at a stake per point wants more. Default 1

  -- "house" games
  minBet = 10, maxBet = 2000,                 -- per seat, for the whole of their bet
  spots = { { id = "player", label = "PLAYER", sub = "1:1", color = "accent" }, ... },
                     -- optional: places to bet. A chip selects, then a tap on a spot puts it there. Up to 12 fit

  turnMs = 45000,    -- optional. How long a seat has before auto. Default 45 seconds
  shoe = false,      -- optional, as table.lua: cards last across rounds in keep.shoe. rules.new sets keep.shuffled when it
                     -- starts a new shoe. The engine then shows only the shoe's hash until that shoe is finished
}
```

## Rules

Rules are pure: no screen, no sound, no money, no `os.*`, no `math.random`. The state holds plain numbers, strings, booleans and tables with no functions and no metatables, because it goes in a journal at every step and a reboot resumes it. All randomness comes from the `rng` given (`rng:below(n)`). `seat` is a seat number, 1 to 8, not a list position: seats can be empty, so `entries` can be seats 2, 3 and 7.

| Function | Contract |
| --- | --- |
| `new(entries, button, rng, keep)` | Returns `state, events`. `entries` is a list by seat order of `{ seat, name, stack }` for players, plus `stake` with `plugin.stakes`, or `{ seat, name, bet, bets }` for house. `bets` is `{ [spotId] = tokens }` and only there with `plugin.spots`. `bet` is always the total. `button` is a position in `entries`. `keep` is this game's own table across rounds. |
| `waitingOn(state)` | A list of the seats that may act now. More than one for simultaneous play. An empty list with the round not over means the computer moves next (below). |
| `actions(state, seat)` | Buttons for that seat: a list of `{ id, label, color, textColor, sub, value, cost, small }`. Up to 5 are big, up to 10 are small. `color` and `textColor` are names from `lib/casino/theme.lua`: `win red gold blue orange accent panel2 ink text`. `cost` is tokens this press adds to what the seat has at risk: the engine greys the button out if their balance cannot cover it, and tracks what they have spent. |
| `act(state, seat, id, value, rng)` | Applies it and returns events, a list. **A non-empty list means it happened; empty or nil means it did not.** Illegal input must do nothing and change nothing. `id` can be a button id or a region id. Check `seat` is really allowed: the engine only checks they are in `waitingOn`. `seat` is nil for the computer's own move. |
| `auto(state, seat)` | Returns `id, value`: the safe default when a seat's clock runs out: check, fold, stand, no bet. It must be legal and make progress. With `seat` nil it is the computer's own move. |
| `viewFor(state, seat)` | What this seat may know, **built field by field, never by copying state**. `seat = nil` is the public view, for the dealer's wall and anyone watching. |
| `done(state)` | True when the round is over. |
| `nets(state)` | `seat -> tokens`, whole numbers. For `players` they sum to `-(state.kept or 0)`: split-pot odd chips go to the owner through `lib/casino/group/rounding.lua`. A loser never loses more than their stack. |
| `result(state, seat)` | `{ kind, title, detail }` for that seat. `kind` is `win`, `lose` or `push`. `seat = nil` is the table's line, shown on the dealer's wall. |
| `maxWin(entry)` | House games: the most this entry can win, net, whatever happens, doubles and splits included. The host must cover the sum of these before a round starts, and bets are cut to fit. |
| `risk(state, seat)` | Optional: all that seat really staked. For the stats and the hub's measured return. Without it the engine uses the bet plus each `cost`, or the size of the net. |
| `present(state, seat)` | Optional: true if this seat, its clock just run out, has still played, so it is not counted as away. For a game where the clock closing is normal, such as bets left down in Roulette. |
| `finish(state, keep)` | Optional: runs once at the end of a round, for what lasts, such as a road or what is left of a shoe. |

**Nobody deals.** A round starts by itself once enough seats are ready, and a seat that does not act is handled by `auto`. When the game has work of its own, such as a house drawing, a wheel spinning or a roll with no shooter, make `waitingOn` return `{}`. A second later the engine calls `auto(state, nil)` and passes what it returns to `act(state, nil, id, value, rng)`. A seat's press may just as well do it all inside `act`.

**A round can be over as it is dealt.** If `done` is true straight after `new`, it settles and shows like any other.

**Money.** `nets` is the only thing the engine reads. Stakes are never taken up front. A game does not know whether a player paid, and must not care: a table runs on what the dealer declares. Stacks are what was declared. A player who owes from an earlier hand plays on what their balance covers after it, and the engine works that out before `new`.

## Secrets

Each seat is only ever sent that seat's view, but everything else goes everywhere:

- `viewFor(state, seat)` is what stops one player seeing another's cards. Build it field by field. A folded player's cards stay hidden. At the end show only what the rules turn over.
- `viewFor(state, nil)` must hold nothing a player could not see across the table.
- **Events go to every seat and the dealer's wall**, and on a shared network they can be overheard. An event never carries a hidden card: `{ type = "deal", seat = 3 }`, not the card. The seat's view has the card.
- `result(state, nil)`, `help()` and every label are public.
- A live shoe's order and seed never leave the rules. Do not log.

`viewFor` also decides the final reveal. When `done` is true it can show what the showdown turns over: the engine holds that view back until the money has moved, then plays the events of the last move.

## Pictures

Views are pure functions of the view table, because a seat has only what it was sent. They may not read `state` or call `rules`.

```lua
seatView.draw(c, view, anim, info)    -- the player's own screen
seatView.regions(view)                -- optional: tappable parts, { { id, value, x, y, w, h } }. Only live on their turn
tableView.draw(c, view, anim, info)   -- the dealer's wall. Big Table only
```

- `c` is a `lib/casino/canvas.lua` canvas: `c:rect c:text c:textCenter c:big c:bigCenter c:panel c:frame`, and `lib/casino/ui.lua` draws cards with `ui.card(c, x, y, card, small)`. Cells are 2 wide by 3 tall. `c` is cleared to the felt before you draw. Everything you draw is run under `pcall`, and a mistake shows as a line on the screen and not a crash.
- `view` is what `viewFor` returned. `anim` is `{ ev, t }` while an event plays, `t` going from 0 to 1, otherwise nil. Draw the state after the event, and use `anim` to hold something back or move it.
- `info` on a seat is `{ seat, name }`. On the wall it is `{ waiting = { [seat] = true }, seats = { { number, name, line, color, acting } } }`.
- A region is passed to `rules.act(state, seat, id, value)` like a button. A throw toggle or a target square is a region, and it round-trips through the dealer, so keep the marks in the state: that way a reboot keeps them too.
- Colours come from `theme.C`: `C.gold`, `C.ink`, `C.text`, `C.mute`, `C.win`, `C.red`, `C.felt`, `C.feltDark`, `C.panel`, and so on.

### Sizes

| Screen | Size | Yours |
| --- | --- | --- |
| Big Table seat, a 4x4 wall | **78 x 52** always. A bigger wall centres the same 78x52, and a real 4x4 is 79 wide by the mod's own sums, so never count on the last column | `seatui.area(c)`: x 1, y 10, w 78, h 30 |
| Big Table dealer wall, 6x6 | 121 x 81 | `seatui.tableArea(c)`: x 1, y 10, w 121, h 63 |
| Duel wall, 6x6 | 121 x 81, the whole wall | `seatui.area(c)`: x 1, y 10, w 121, h 59 |

`local seatui = require("lib.casino.group.seatui")`, then `local x, y, w, h = seatui.area(c)`. The engine draws the top bar above that, the turn clock, buttons and hash below it, and a short note on the last row of your area. When a round ends it covers the bottom 10 rows of your area on a seat, and the bottom 15 on a 6x6 wall, with the result, so keep the cards above that. A seat's card rows: `ui.CARD_W, ui.CARD_H` are 17 by 16, `ui.SMALL_W, ui.SMALL_H` 13 by 12. Five small cards fit across 78 with `ui.fan(cx, 5, ui.SMALL_W, 76)`. The dealer's wall has a row of seats along the bottom (name, stack, whose turn) that the engine draws.

Big Table draws the public view on the dealer's wall and the private view on the seat, so the seat need not repeat the board if it has no room. A seat's `viewFor` should still say what the player must decide on: their cards, what it costs to call.

## Duel

The same game with a different table:

- There is no dealer's wall, so `tableView` is never drawn and a Duel plugin can leave it out. `seatView` has both players' public picture to itself, on 121x81.
- A player gets the wall they tapped. Seat 1 is the first wall by name, seat 2 the other.
- Touches only count from the seat that is in `waitingOn`, on that seat's own wall.
- **A wall with no viewer shows nothing secret.** After a reboot, or once anyone else touches a player's wall, or after 5 minutes with no touch, that wall gets `viewFor(state, nil)` and a note saying to tap, and buttons do nothing. So `seatView.draw` has to draw the public view as well as the private one. `view` has no private fields then, so check for them.
- Stakes: set `plugin.stakes` for a match game. `entries[i].stake` is the stake and `entries[i].stack` is what the player's balance covers, up to `maxStack`. `nets` must stay within `stack`, so Gin at a stake per point caps at the smaller stack.
- `minSeats = 2, maxSeats = 2`, `kind = "players"`.

## How to test

Pure tests, in `Tests/group_<id>_test.lua`:

```lua
local kit = require("group_kit")
local testing = require("testing")
local plugin = kit.plugin("BigTable", "holdem")       -- loads it the way the cabinet does

testing.test("holdem keeps the contract", function()
  kit.fuzz(plugin, { rounds = 500, seats = { 2, 5, 8 }, stack = 500, absent = 15 })
end)
```

`kit.fuzz` plays random legal rounds and fails if a state stops being plain, a view changes the state or is not repeatable, an unknown action does anything, `auto` does nothing, a round does not end, nets do not sum to zero, a net is not whole, a loser loses past their stack, a house win passes `maxWin`, or a result is malformed. Options: `rounds`, `seats`, `stack`, `bet`, `bets`, `stake`, `absent` (percent of turns left to `auto`), `pick(state, seat, actions, rng)` to steer play, and `check(state, entries)` run at every step. `kit.shows(view, value)` says whether a value appears anywhere in a view, which is how a test proves a card stays hidden:

```lua
check = function(state, entries)
  for _, entry in ipairs(entries) do
    local view = plugin.rules.viewFor(state, entry.seat)
    for _, other in ipairs(state.players) do
      if other.seat ~= entry.seat and not state.showdown then
        for _, card in ipairs(other.hole) do testing.truthy(not kit.shows(view.hole, card)) end
      end
    end
  end
end
```

House games must also prove their return. A paytable is total return on the bet, and `Tests/run.lua` stops the deploy if a game is outside its target. Run them with:

```
cd C:/Users/rboon/source/repos/_ext/rc-multi
ROGER_DIR=C:/Users/rboon/source/repos/_ext/rc-multi node C:/Users/rboon/source/repos/craftos-agent/tools/casinotest/unit.mjs group_<id>
```

On the emulator, with real seats and real rednet, a whole game played at random with its tokens counted across every computer:

```
ROGER_DIR=C:/Users/rboon/source/repos/_ext/rc-multi node C:/Users/rboon/source/repos/craftos-agent/tools/casinotest/group-play.mjs BigTable holdem
ROGER_DIR=C:/Users/rboon/source/repos/_ext/rc-multi node C:/Users/rboon/source/repos/craftos-agent/tools/casinotest/group-play.mjs Duel gin
```

It sits three players, or two on Duel, plays a few rounds by pressing whatever is offered, and checks that the tokens add up. `SHOTS=dir` saves the dealer's wall and each seat as PNGs after every round, so look at them: a 78x52 screen is small. Each computer of a run is its own engine, so run a few at a time, not dozens.

`tools/casinotest/group.mjs` proves the engine itself and needs no change for a new game.
