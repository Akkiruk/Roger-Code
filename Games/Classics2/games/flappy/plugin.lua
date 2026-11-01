-- games/flappy/plugin.lua
-- Flappy Bird as an Arcade classic. There are no buttons: a tap anywhere is one flap.

local base = require("lib.arcade.base")
local rules = require("games.flappy.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local WIDTH, HEIGHT, GROUND, PIPE_W = rules.WIDTH, rules.HEIGHT, rules.GROUND, rules.PIPE_W
local LIP_H = 2
local STRIPE_W, STRIPE_GAP = 4, 8   -- the marks that scroll along the ground

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, WIDTH, HEIGHT)
end

--- A rectangle at board position x, cut off at the sides of the board.
local function clipped(L, x, y, w, h, color)
  local left, right = math.max(0, x), math.min(WIDTH, x + w)
  ui.fill(L.x0 + left, L.y0 + y, right - left, h, color)
end

local function drawPipe(L, p)
  local x = floor(p.x + 0.5)
  local top, bottom = floor(p.top + 0.5), floor(p.bottom + 0.5)
  clipped(L, x + 1, 0, PIPE_W - 2, top, C.ok)
  clipped(L, x + 1, bottom, PIPE_W - 2, GROUND - bottom, C.ok)
  clipped(L, x + 2, 0, 2, top, C.soft)
  clipped(L, x + 2, bottom, 2, GROUND - bottom, C.soft)
  clipped(L, x, top - LIP_H, PIPE_W, LIP_H, C.soft)
  clipped(L, x, bottom, PIPE_W, LIP_H, C.soft)
end

local function drawGround(L, s)
  ui.fill(L.x0, L.y0 + GROUND, L.bw, HEIGHT - GROUND, C.redTint)
  ui.fill(L.x0, L.y0 + GROUND, L.bw, 1, C.ok)
  local shift = floor(s.scroll) % STRIPE_GAP
  for x = -shift, WIDTH, STRIPE_GAP do clipped(L, x, GROUND + 1, STRIPE_W, 1, C.warn) end
end

--- Is the wing up? After a flap it is, and it beats in time with the bob while the bird waits for the first tap.
local function wingUp(s)
  if s.started then return s.wing > 0 end
  return floor(s.clock / rules.BOB_BEAT) % 2 == 0
end

local function drawBird(L, s)
  local x, y = L.x0 + rules.BIRD_X, L.y0 + floor(s.y + 0.5)
  ui.fill(x + 1, y, rules.BIRD_W - 2, rules.BIRD_H, C.hi)
  ui.fill(x, y + 1, rules.BIRD_W, rules.BIRD_H - 2, C.hi)
  ui.fill(x + 4, y + 1, 1, 1, C.text)
  ui.fill(x + 5, y + 2, 2, 1, C.warn)
  ui.fill(x + 1, y + (wingUp(s) and 0 or 2), 2, 2, C.text)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.blue)
  for _, p in ipairs(s.pipes) do drawPipe(L, p) end
  drawGround(L, s)
  drawBird(L, s)
  if not s.started then ui.text("TAP TO FLAP", L.x0 + floor(WIDTH / 2), L.y0 + 12, C.text, "center") end
end

--- Any tap is a flap: a finger that lands a little off the board shouldn't cost the run. QUIT is a button, so the shell
-- takes that one first.
function view.actionAt()
  return { kind = "flap" }
end

function view.controls()
  return {}
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "flap" then app.audio.play("placeBlue") end
    if ev.type == "point" then app.audio.play("capture") end
    if ev.type == "crash" then app.audio.play("placeRed", 1, 0.5) end
  end
end

return base.fill({
  id = "flappy", title = "Flappy Bird", short = "Flappy", blurb = "One tap, one flap", color = "ok", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Tap anywhere on the wall and the bird gives one flap up. Between taps it falls. Nothing moves until your first tap.",
    "",
    "Steer through the gaps in the pipes. Every pipe you pass is a point.",
    "",
    "Touching a pipe, the ground or the top of the screen ends the game. You only get one bird.",
    "",
    "Every ten pipes the gaps get a little tighter and closer together.",
  },
})
