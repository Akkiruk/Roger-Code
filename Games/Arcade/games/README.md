# Writing an Arcade game

A game is a folder under `games/`, plus one line in `registry.lua`. The shell owns the wall: menu, lobby, seats, match flow, journal, timers, walking away, results, stats, settings and the scoreboard. A game brings its rules, its board and, if it wants, a computer player. It never calls `ccvault`: the Arcade is free to play and moves no tokens.

Matches have two seats, red (1) and blue (2).

## The plugin

`games/<id>/plugin.lua` returns `base.fill(M)`. Anything optional gets a default from `base.lua`, so a small game stays small.

Required:

| Field | What it is |
|---|---|
| `id`, `title` | Unique id, and the name shown on the menu |
| `rules` | See below |
| `view.layout(W, H)` | Layout table. `base.layout(W, H, boardW, boardH)` makes one |
| `view.drawBoard(L, match)` | Draw the board inside the layout |
| `view.actionAt(L, match, px, py)` | The action a touch means, or nil |

Common optional fields:

- `chooseAction(state, level, opts)` and `cpuLevels`, for a computer player. Return an action, or nil. Honour `opts.yield` during long searches.
- `view.onEvents(app, match, events)`, which turns rules events into sound and marks on the board. It must not block, so touches stay live.
- `view.score`, `view.prompt`, `view.finalLine`, `view.howLine`, `view.drawAttract` and `view.demoStep`, to replace the default wording and idle screen.
- `settings`, `settingsRows`, `changeSetting`, `matchOptions`, `moveTimer`, for a game's own options.
- `summarize(match)` and `newStore`, for extra records. `achievements` and `award` add badges.
- `minSize = { w, h }` greys the game out on a wall too small for it.

## The rules

Rules are pure: no screen, sound, files or clock.

| Function | Contract |
|---|---|
| `new(options)` | A fresh state. `options.first` is the seat to move first |
| `step(state, action, rng)` | Apply an action. Returns `state, events`, or `nil, reason` |
| `checkAction(state, action)` | `true`, or `false, reason` |
| `legalActions(state)` | Every legal action. A missed move timer picks from these |

The state must have `turn` (1 or 2) and `winner` (0 playing, 1, 2, or 3 for a draw).

`step` must handle `{ kind = "forfeit", seat = n }`, setting `winner` to the other seat and `forfeit` to `n`. Actions are stored in the journal as plain data, so they can hold only strings, numbers, booleans and tables.

Use only `rng` for chance: `rng()` is 0 to 1, and `rng(n)` is 1 to n. The journal holds the seed and every action, so a reboot replays the match exactly.
