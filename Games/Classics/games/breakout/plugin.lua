-- games/breakout/plugin.lua
-- Breakout as an Arcade classic. A tap anywhere on the wall sets where the paddle slides to: there are no buttons.

local base = require("lib.arcade.base")
local rules = require("games.breakout.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 3, 2
local WALL_W = 2
-- top row first. The shell paints C.hi in the game's accent, so the accent stays yellow to keep this a rainbow.
local ROW_COLORS = { C.red, C.warn, C.hi, C.ok, C.info, C.blue }

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

local function drawWalls(L)
  ui.fill(L.x0 - WALL_W, L.y0, WALL_W, L.bh, C.line)
  ui.fill(L.x0 + L.bw, L.y0, WALL_W, L.bh, C.line)
  ui.fill(L.x0 - WALL_W, L.y0, L.bw + 2 * WALL_W, rules.CEILING * CELL_H, C.line)
end

local function drawBricks(L, s)
  local w, h = rules.BRICK_W * CELL_W, rules.BRICK_H * CELL_H
  for r, row in ipairs(s.bricks) do
    local y = L.y0 + (rules.TOP + (r - 1) * rules.BRICK_H) * CELL_H
    for c, live in ipairs(row) do
      -- the gap is on each brick's right, except the last, which runs up to the side wall
      local gap = c < rules.BRICK_COLS and 1 or 0
      if live then ui.fill(L.x0 + (c - 1) * w, y, w - gap, h - 1, ROW_COLORS[r]) end
    end
  end
end

local function drawPaddle(L, s)
  local half = rules.reach(s)
  local x = L.x0 + math.floor((s.paddle - half) * CELL_W + 0.5)
  local y = L.y0 + rules.PADDLE_Y * CELL_H
  ui.fill(x, y, 2 * half * CELL_W, rules.PADDLE_H * CELL_H, C.text)
  -- a mark under the spot the paddle is heading for, since a tap can land anywhere
  if math.abs(s.goal - s.paddle) >= 1 then
    ui.fill(L.x0 + math.floor(s.goal * CELL_W) - 1, y + rules.PADDLE_H * CELL_H + 1, 3, 1, C.hi)
  end
end

local function drawBall(L, s)
  local b = s.ball
  if s.over or b.y >= ROWS - rules.BALL_R then return end
  local x = L.x0 + math.floor((b.x - rules.BALL_R) * CELL_W + 0.5)
  local y = L.y0 + math.floor((b.y - rules.BALL_R) * CELL_H + 0.5)
  ui.fill(x, y, CELL_W, CELL_H, C.text)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawWalls(L)
  drawBricks(L, s)
  drawPaddle(L, s)
  drawBall(L, s)
end

--- A tap anywhere aims the paddle at that spot across the board. How high up it lands makes no difference.
function view.actionAt(L, _, px)
  return { kind = "aim", x = (px + 0.5 - L.x0) / CELL_W }
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "brick" then
      app.audio.play(ev.row <= 2 and "captureRed" or (ev.row <= 4 and "capture" or "captureBlue"))
    end
    if ev.type == "paddle" then app.audio.play("placeRed") end
    if ev.type == "wall" then app.audio.play("placeBlue") end
    if ev.type == "shrink" then app.audio.later("select", 80) end
    if ev.type == "level" then app.audio.later("select", 120) end
    if ev.type == "lost" or ev.type == "over" then app.audio.play("error") end
  end
end

return base.fill({
  id = "breakout", title = "Breakout", blurb = "Keep the ball up, knock the wall down", color = "warn", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Bounce the ball off the paddle to knock out the bricks. The higher the row, the more a brick is worth.",
    "",
    "Tap anywhere on the wall, at any height. The paddle slides to that spot across the board and stays there, and a yellow mark shows where it's heading. There's nothing to hold.",
    "",
    "Where the ball hits the paddle sets its angle: near the middle goes up steeply, near the ends goes out wide.",
    "",
    "The ball speeds up with every brick. Once it reaches the top wall the paddle shrinks. Clear the wall for a new one, faster, with a full paddle.",
    "",
    "You have three balls.",
  },
})
