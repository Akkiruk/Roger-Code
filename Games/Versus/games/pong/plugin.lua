-- games/pong/plugin.lua
-- Pong as the 1972 cabinet had it: white on black, a dotted centre line, big square digits. Each player sees their own paddle
-- on the left of their own wall, so player 2's wall is a mirror of player 1's. A tap sets a height: there are no buttons.

local base = require("lib.arcade.base")
local rules = require("games.pong.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS, TOP, BOTTOM = rules.COLS, rules.ROWS, rules.TOP, rules.BOTTOM
local R = rules.BALL_R
local CELL_W, CELL_H = 3, 2       -- a court unit, which looks square on a monitor
local NET_W, NET_DASH, NET_GAP = 2, 2, 2
local DIGIT_DOT_W, DIGIT_DOT_H = 4, 3 -- one dot of a digit, which also looks square
local DIGIT_GAP = 4
local DIGIT_Y = 3                 -- below the top wall
local BLINK_FROM = 10             -- steps before a serve that the ball comes back

-- The digits, three dots wide and five tall, as in the original.
local DIGITS = {
  [0] = { "###", "#.#", "#.#", "#.#", "###" },
  [1] = { "..#", "..#", "..#", "..#", "..#" },
  [2] = { "###", "..#", "###", "#..", "###" },
  [3] = { "###", "..#", "###", "..#", "###" },
  [4] = { "#.#", "#.#", "###", "..#", "..#" },
  [5] = { "###", "#..", "###", "..#", "###" },
  [6] = { "###", "#..", "###", "#.#", "###" },
  [7] = { "###", "..#", "..#", "..#", "..#" },
  [8] = { "###", "#.#", "###", "#.#", "###" },
  [9] = { "###", "#.#", "###", "..#", "..#" },
}
local DIGIT_W = 3 * DIGIT_DOT_W

--- Where a box starting w cells across the court shows on this player's wall. Player 2 sees it from the far end.
local function wallX(L, x, w, player)
  if player == 2 then return L.x0 + L.bw - x - w end
  return L.x0 + x
end

--- Every box is placed from the top left of the court, in units, and rounded to the nearest cell.
local function cellX(x) return floor(x * CELL_W + 0.5) end
local function cellY(L, y) return L.y0 + floor(y * CELL_H + 0.5) end

local function drawDigit(digit, x, y)
  for row, line in ipairs(DIGITS[digit]) do
    for col = 1, #line do
      if line:sub(col, col) == "#" then
        ui.fill(x + (col - 1) * DIGIT_DOT_W, y + (row - 1) * DIGIT_DOT_H, DIGIT_DOT_W, DIGIT_DOT_H, C.text)
      end
    end
  end
end

--- A score, centred on x.
local function drawScore(score, x, y)
  local text = tostring(score)
  local width = #text * DIGIT_W + (#text - 1) * DIGIT_GAP
  for i = 1, #text do
    drawDigit(tonumber(text:sub(i, i)), x - floor(width / 2) + (i - 1) * (DIGIT_W + DIGIT_GAP), y)
  end
end

local function drawNet(L)
  local x = L.x0 + floor((L.bw - NET_W) / 2)
  local y = L.y0 + TOP * CELL_H + NET_GAP
  local last = L.y0 + BOTTOM * CELL_H
  while y + NET_DASH <= last do
    ui.fill(x, y, NET_W, NET_DASH, C.text)
    y = y + NET_DASH + NET_GAP
  end
end

local function drawPaddle(L, paddleY, atX, player)
  local x = wallX(L, atX * CELL_W, rules.PADDLE_W * CELL_W, player)
  ui.fill(x, cellY(L, paddleY - rules.PADDLE_H / 2), rules.PADDLE_W * CELL_W, rules.PADDLE_H * CELL_H, C.text)
end

--- The ball, with a black edge so it still shows crossing a digit or the net. Between points it's gone, as in the original,
-- then it blinks on the centre line for the last moments before the serve. Past the end of the court it's off the screen.
local function drawBall(L, s, player)
  if s.over or s.wait > BLINK_FROM or (s.wait > 0 and s.wait % 4 >= 2) then return end
  local b = s.ball
  local x = wallX(L, cellX(b.x - R), CELL_W, player)
  local y = cellY(L, b.y - R)
  if x <= L.x0 or x + CELL_W >= L.x0 + L.bw then return end
  ui.fill(x - 1, y - 1, CELL_W + 2, CELL_H + 2, C.bg)
  ui.fill(x, y, CELL_W, CELL_H, C.text)
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

function view.draw(L, s, player)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  local mine = player == 2 and 2 or 1
  local digitY = L.y0 + TOP * CELL_H + DIGIT_Y
  local quarter = floor(L.bw / 4)
  drawScore(s.score[mine], L.x0 + quarter, digitY)
  drawScore(s.score[3 - mine], L.x0 + L.bw - quarter, digitY)
  drawNet(L)
  drawBall(L, s, player)
  -- walls and paddles go over the ball, so its black edge can't nick them
  ui.fill(L.x0, L.y0, L.bw, TOP * CELL_H, C.text)
  ui.fill(L.x0, L.y0 + BOTTOM * CELL_H, L.bw, (ROWS - BOTTOM) * CELL_H, C.text)
  drawPaddle(L, s.paddles[1].y, rules.PADDLE_X, player)
  drawPaddle(L, s.paddles[2].y, COLS - rules.PADDLE_X - rules.PADDLE_W, player)
end

--- A tap anywhere on a wall aims that player's paddle at that height. How far across it lands makes no difference, so the
--- mirror needs nothing here: height reads the same from both sides.
function view.actionAt(L, _, _, py)
  return { kind = "aim", y = (py + 0.5 - L.y0) / CELL_H }
end

--- One electronic beep at three pitches, as the original had: the paddle's blip is high, the wall's boop is low, and a point
--- is lower still and held a little longer.
-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  paddle = "bounce", wall = "wall", point = "coin",
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "pong", title = "Pong", blurb = "First to eleven", color = "text",
  versus = true, tickMs = 100, minSize = { w = 120, h = 78 },
  rules = rules, view = view,
  help = {
    "Two paddles, one ball. Miss it and the other player scores. First to eleven wins.",
    "",
    "Your paddle is on the left of your own wall. Tap anywhere on the wall, at any height. The paddle slides to that height and stays there. There's nothing to hold.",
    "",
    "Where the ball hits your paddle sets where it goes: the middle sends it back nearly flat, the top edge sends it steeply up, the bottom edge steeply down. A steep ball is the hard one to reach.",
    "",
    "The ball gets faster with every hit, so a long rally ends one way or the other. It drops back to its starting speed after each point.",
    "",
    "Each serve goes to whoever lost the last point. Watch for the ball blinking on the centre line.",
  },
})
