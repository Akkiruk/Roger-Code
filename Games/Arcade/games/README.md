# Writing an Arcade game

A game is a folder under `games/`, plus one line in `registry.lua`. The shell owns the wall: menu, lobby, seats, match flow, journal, timers, walking away, results, stats, settings and the scoreboard. A game brings its rules, its board and, if it wants, a computer player. It never calls `ccvault`: the Arcade is free to play and moves no tokens. The only `ccvault` calls anywhere are in `arcade_hw.lua`, which reads who owns the computer and locks its terminal.

Matches have two seats, red (1) and blue (2).

## The plugin

`games/<id>/plugin.lua` returns `base.fill(M)`. Anything optional gets a default from `base.lua`, so a small game stays small.

Required:

| Field | What it is |
|---|---|
| `id`, `title` | Unique id, and the name shown on the menu |
| `rules` | See below |
| `view.layout(W, H)` | Layout table. `base.grid(W, H, cols, rows)` makes one for a board of square cells, as large as the wall allows |
| `view.drawBoard(L, match, viewer)` | Draw the board inside the layout. It also draws the idle demo, where `match.red` and `match.blue` are nil |
| `view.actionAt(L, match, px, py, viewer)` | The action a touch means, or nil |

Common optional fields:

- `chooseAction(state, level, opts)` and `cpuLevels`, for a computer player. Return an action, or nil. Honour `opts.yield` during long searches. `games/search.lua` is a ready-made search for any game with no hidden pieces.
- `view.onEvents(app, match, events)`, which turns rules events into sound and marks on the board. It must not block, so touches stay live.
- `view.score`, `view.prompt`, `view.finalLine`, `view.howLine`, `view.drawAttract` and `view.demoStep`, to replace the default wording and idle screen. With no `view.score`, the header shows no score. The default idle screen plays a demo game through `drawBoard`.
- `view.onSelect(match, action)` for a two-tap move. If `actionAt` returns `{ kind = "select", ... }`, the shell checks the player may move, then calls this. It never reaches the rules or the journal, so keep what it marks in `match.extras`.
- `settings`, `settingsRows`, `changeSetting`, `matchOptions`, `moveTimer`, for a game's own options. Every game gets a move timer setting without asking.
- `summarize(match)` and `newStore`, for extra records. Every game gets four common badges; `badges` adds more: `id -> { name, text, test = function(m, side, player, won) }`.
- `minSize = { w, h }` greys the game out on a wall too small for it. `sounds = base.SOUNDS` gives a game the usual piece and capture sounds.

`base.lua` also has `cellAt`, `disc` and `boardGrid` for drawing and reading a grid.

## The rules

Rules are pure: no screen, sound, files or clock.

| Function | Contract |
|---|---|
| `new(options)` | A fresh state. `options.first` is the seat to move first |
| `step(state, action, rng)` | Apply an action. Returns `state, events`, or `nil, reason` |
| `checkAction(state, action)` | `true`, or `false, reason` |
| `legalActions(state)` | Every legal action. A missed move timer picks from these |

The state must have `turn` (1 or 2) and `winner` (0 playing, 1, 2, or 3 for a draw). `turn` can stay on the same seat after an action, for an extra turn, a pass, or a jump that carries on: the shell simply asks who is to move next.

`step` must handle `{ kind = "forfeit", seat = n }`, setting `winner` to the other seat and `forfeit` to `n`. Actions are stored in the journal as plain data, so they can hold only strings, numbers, booleans and tables.

Use only `rng` for chance: `rng()` is 0 to 1, and `rng(n)` is 1 to n. The journal holds the seed and every action, so a reboot replays the match exactly.

## Hidden pieces and two walls

A cabinet can have two walls of the same size, back to back with the computer between them. Every screen then shows on both, and either wall can be used. A game can keep things secret by setting `private = true`, usually with `walls = 2`, which hides it from the menu on a one-wall cabinet.

In a private game:

- Each player gets the wall they tapped their name on, and an opponent who did not tap gets the other one. Two named players at one wall are told to move. A touch only counts on the wall of the seat to move.
- `drawBoard`, `drawSides`, `actionAt` and `prompt` get `viewer`, the seat whose wall this is. `viewer` is nil for anyone else: a computer's wall, or a wall the opponent has walked round to, which the shell covers up by itself. With no viewer, draw nothing secret.
- `rules.viewFor(state, seat)` returns what that seat may know. It is all a computer player or a hint is ever given, so a computer cannot cheat. Build it from the fields a seat may see, rather than copying the state and removing things.
- Toasts show on both walls, so keep secrets out of them.
- `view.debug` is written to a file when testing, so leave hidden pieces out of it.

Setting `noHints = true` removes the hint button.

## Help and animation

`help` is a list of lines for the HOW TO PLAY page, which a first-time player sees before their first match. Leave a line `""` for a gap.

For animation, call `base.animate(match, ms, fields)` from `view.onEvents`, and in `drawBoard` read `match.anim` and `base.animT(match)`, which runs from 0 to 1. The shell redraws until it ends. The rules have already moved on by then, so an animation only changes what is drawn, and the next touch simply replaces it. Replays use the same events.

## Classics

A classic is one player, in real time, playing for a high score. Classics are their own package, `Games/Classics`, for a table with one wall, and the shell is shared through `lib/arcade`. Set `action = true` and the game gets its own START screen, high score table and final screen. The shell owns all of that. See `Games/Classics/games/snake` for a complete one.

The screen is a monitor, and a monitor only ever gets separate taps: there's no held button and no joystick. So pick games that work in taps, and keep the speed fair: `tickMs` is how often the game steps, and 100 is as fast as it goes. A tap should set something that stays set, such as a direction, or aim at a spot on the board.

Rules are pure and take chance only from `rng`:

| Function | Contract |
|---|---|
| `new(opts)` | A fresh state. `opts.rng` is the only source of chance |
| `input(state, action)` | A player's action. Takes effect on the next step |
| `tick(state, rng)` | One step of the clock. Returns a list of events |
| `bot(state, rng)` | An action for the idle screen and tests, or nil |

The state must have `score`, `level`, `over`, and `lives` if the game has them. Setting `over` to true ends the run, and setting `won` too makes the final screen say YOU WON!

The view has `layout(W, H)` (`base.actionLayout` makes one), `draw(L, state)`, `controls(L, state)` for buttons as `{ label, x, y, w, h, action }` (leave them out for a game steered by the whole wall: set `split = true` and return `base.splitAction(L, px, py)` from `actionAt`, so a player taps the side they want without looking down), `actionAt(L, state, px, py)` for taps on the board, and `onEvents(app, state, events)` for sound. `help` and `blurb` work as for any game.

A game too long for one sitting sets `saves = true`, and the shell keeps one save for each player and game. It saves every 30 seconds of play and whenever play pauses. Walking away, 10 minutes with no tap, and SAVE & QUIT all save the run and free the wall, so only `over` ends a run: then the save is deleted and the score posted. The ready screen offers the tapper CONTINUE and NEW GAME, with a line from `view.saveSummary(state)` if there is one, such as "Day 34, Fort Kearney". Everything needed to resume must be in `state` as plain data, because it comes back from a file: no functions, metatables or the rng, which continues by itself. Two fields sharing a table come back as two tables, so compare by value; fractions keep 14 digits; and a new version of a game has to cope with states saved by the last one. `input` may end the game itself: a long game's `tick` may be rare. `ONLY=<id>,saves` in `tools/arcadetest` checks a game resumes exactly.

A long game that tells a story also sets `story = true`. It gets the whole wall, with no score header and no high score table on the ready screen, and it doesn't have to end: a story that continues in a later update keeps `over` false, so its saves carry on. `rules.new` is told `opts.player`, the name of whoever started the run.

## Versus

A Versus game is two players in real time, one wall each, for the Versus cabinet (`Games/Versus`): two equal 6x6 walls back to back with the computer between them. Each player sees only their own wall. The shell owns picking, joining, the 3-2-1, the clock, the header with both names and the score, QUIT, walking away, the final board, the wins table and REMATCH. A one-wall cabinet plays the computer.

A plugin sets `versus = true`, `tickMs` (100 or more), `title`, `blurb`, `help`, `rules` and `view`, and returns `base.fill(M)`.

| Rules | Contract |
|---|---|
| `new({ rng })` | A fresh state: plain data, and `rng` is the only source of chance |
| `input(state, player, action)` | Player 1 or 2's action. Takes effect on the next step |
| `tick(state, rng)` | One step of the clock. Returns a list of events |
| `bot(state, rng, player, level)` | An action for that player, or nil. Plays the computer and the idle demo. `level` is one of `cpuLevels`, or nil if the game has none |

The state must have `over`, `winner` (1, 2, or 0 for a draw) and `score = { p1, p2 }`, the round or match score the header shows. A game plays its own match inside the state, such as first to five, and sets `over` when it's decided.

| View | Contract |
|---|---|
| `layout(W, H)` | `base.actionLayout` makes one |
| `draw(L, state, player)` | Drawn once per wall from that player's side, so a game can be mirrored |
| `actionAt(L, state, px, py, player)` | Turns a tap on that player's wall into an action, or nil |
| `onEvents(app, state, events)` | Sound. Must not block |

`split = true` and `splitMiddle = "BOMB"` show the corner-to-corner hint for the first four seconds, as for classics, and `base.splitAction`, `base.inMiddle` and `base.drawMiddle` work the same. QUIT sits in the bottom right corner, and a tap there doesn't reach `actionAt`. To offer a difficulty, set `cpuLevels = { "easy", "hard" }`: the ready screen shows them under PLAY THE COMPUTER.

Wins and losses are kept per game in `arcade_versus_<id>.dat`. A match against the computer isn't counted, and neither is a draw. A forfeit, by QUIT twice or by being away for 20 seconds, counts as a loss.

## Proving a game

`tools/arcadetest` in craftos-agent has what a new game needs: an oracle written from the published rules without reading the Lua (`oracles/`), with `rules.snapshot` and `rules.key` for `games.mjs` to compare every position, and `mutants.mjs` to show that comparison can fail.
