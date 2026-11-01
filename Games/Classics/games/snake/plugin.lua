-- games/snake/plugin.lua
-- Snake as an Arcade classic. Tap a side of the head, or use the arrows, and the snake turns that way.

local base = require("lib.arcade.base")
local rules = require("games.snake.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 3, 2

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.panel)
  local function cell(x, y, color)
    ui.fill(L.x0 + (x - 1) * CELL_W, L.y0 + (y - 1) * CELL_H, CELL_W, CELL_H, color)
  end
  cell(s.food[1], s.food[2], C.red)
  for i, part in ipairs(s.snake) do
    cell(part[1], part[2], i == 1 and C.hi or C.ok)
  end
end

--- The whole wall steers: tap the side you want.
function view.actionAt(L, _, px, py)
  return base.splitAction(L, px, py)
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "eat" then app.audio.play("capture") end
    if ev.type == "level" then app.audio.later("select", 120) end
    if ev.type == "crash" then app.audio.play("error") end
  end
end

return base.fill({
  id = "snake", title = "Snake", blurb = "Eat, grow, don't crash", color = "ok", accent = 0x35D07F,
  action = true, split = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Steer the snake to the red food. Each one makes it longer.",
    "",
    "Tap the side of the wall you want to go: the top goes up, the bottom down, the left side left and the right side right. The wall is split corner to corner, so you never have to look away.",
    "",
    "Hitting a wall or yourself ends the game. Every five foods the snake speeds up and food is worth more.",
  },
})
