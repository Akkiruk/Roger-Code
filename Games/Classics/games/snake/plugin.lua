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

function view.controls(L)
  return base.dpad(L)
end

--- A tap on the board turns the snake toward it.
function view.actionAt(L, s, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  local head = s.snake[1]
  local dx = (px - L.x0) / CELL_W + 1 - head[1]
  local dy = (py - L.y0) / CELL_H + 1 - head[2]
  -- the way the snake is going stays open: a tap picks one of the two sides
  if s.dir == "left" or s.dir == "right" then return { kind = "turn", dir = dy < 0 and "up" or "down" } end
  if math.abs(dx) >= 0 then return { kind = "turn", dir = dx < 0 and "left" or "right" } end
  return nil
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
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Steer the snake to the red food. Each one makes it longer.",
    "",
    "Use the arrows, or tap the board: a tap above or below the head turns up or down, and a tap to either side turns that way.",
    "",
    "Hitting a wall or yourself ends the game. Every five foods the snake speeds up and food is worth more.",
  },
})
