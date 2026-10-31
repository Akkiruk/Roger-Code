-- games/missile/plugin.lua
-- Missile Command as an Arcade classic. There are no buttons: the whole board is for aiming, and a tap fires at that spot.

local base = require("lib.arcade.base")
local rules = require("games.missile.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local WIDTH, HEIGHT, GROUND, ASPECT = rules.WIDTH, rules.HEIGHT, rules.GROUND, rules.ASPECT

local view = {}

--- The board takes the wall. TOUCH TO PLAY has no room under it, so on the idle screen it goes at the top of the sky.
function view.layout(W, H)
  local L = base.actionLayout(W, H, WIDTH, HEIGHT)
  L.statusY = L.y0 + 2
  return L
end

local function trailColor(level)
  local list = { C.red, C.warn, C.accent, C.soft }
  return list[(level - 1) % #list + 1]
end

local function drawCity(L, site)
  local x, y = L.x0 + site.x, L.y0 + GROUND
  if site.alive then
    ui.fill(x - 4, y - 3, 3, 3, C.blue)
    ui.fill(x - 1, y - 5, 3, 5, C.info)
    ui.fill(x + 2, y - 2, 3, 2, C.blue)
    ui.fill(x, y - 4, 1, 1, C.text)
  else
    ui.fill(x - 3, y - 1, 7, 1, C.redTint)
  end
end

--- The rockets a base has left, as pips on the ground beneath it.
local function drawRockets(L, site)
  local x, y = L.x0 + site.x - 4, L.y0 + GROUND + 1
  for i = 1, site.rockets do
    local row = floor((i - 1) / 5)
    ui.fill(x + (i - 1 - row * 5) * 2, y + row * 2, 1, 1, C.text)
  end
end

local function drawBase(L, site)
  local x, y = L.x0 + site.x, L.y0 + GROUND
  if site.alive then
    local color = site.rockets > 0 and C.hi or C.line
    ui.fill(x - 4, y - 2, 9, 2, color)
    ui.fill(x - 2, y - 3, 5, 1, color)
    ui.fill(x, y - 4, 1, 1, color)
  else
    ui.fill(x - 4, y - 1, 9, 1, C.redTint)
  end
  drawRockets(L, site)
end

local function drawGround(L, s)
  ui.fill(0, L.y0 + GROUND, L.W, L.H - L.y0 - GROUND, C.hiTint)
  for _, site in ipairs(s.sites) do
    if site.city then drawCity(L, site) else drawBase(L, site) end
  end
  if s.spare > 0 then
    ui.small("NEW CITY x" .. s.spare, 2, L.y0 + GROUND + 2, C.ok, C.hiTint)
  end
end

local function drawMissiles(L, s)
  local color = trailColor(s.level)
  for _, m in ipairs(s.missiles) do
    ui.line(L.x0 + floor(m.fromX), L.y0 + floor(m.fromY), L.x0 + floor(m.x), L.y0 + floor(m.y), color)
    ui.fill(L.x0 + floor(m.x), L.y0 + floor(m.y), 1, 1, C.text)
  end
end

local function drawBombers(L, s)
  for _, b in ipairs(s.bombers) do
    local x, y = L.x0 + floor(b.x), L.y0 + floor(b.y)
    ui.fill(x - 3, y, 7, 1, C.accent)
    ui.fill(x - 1, y - 1, 3, 1, C.text)
  end
end

local function drawShots(L, s)
  for _, shot in ipairs(s.shots) do
    local x, y = L.x0 + floor(shot.x), L.y0 + floor(shot.y)
    local toX, toY = L.x0 + floor(shot.toX), L.y0 + floor(shot.toY)
    ui.line(L.x0 + shot.fromX, L.y0 + shot.fromY, x, y, C.info)
    ui.fill(x, y, 1, 1, C.text)
    -- a cross where it will burst, so a tap can be seen to have landed
    ui.fill(toX - 2, toY, 5, 1, C.hi)
    ui.fill(toX, toY - 1, 1, 3, C.hi)
  end
end

local function drawBlasts(L, s)
  local flash = { C.text, C.hi, C.warn, C.red }
  for _, b in ipairs(s.blasts) do
    local ry = floor(b.r + 0.5)
    if ry > 0 then
      local rx = floor(b.r * ASPECT + 0.5)
      local color = b.harmless and C.warn or flash[b.age % #flash + 1]
      ui.ellipse(L.x0 + floor(b.x) - rx, L.y0 + floor(b.y) - ry, rx * 2 + 1, ry * 2 + 1, color)
    end
  end
end

local function drawBanner(L, s)
  local b = s.banner
  if not b then return end
  local cx, y = L.x0 + floor(WIDTH / 2), L.y0 + 24
  if b.first then
    ui.text("WAVE 1", cx, y, C.hi, "center")
    ui.small("Tap the sky to fire", cx, y + 8, C.text, C.bg, "center")
    return
  end
  ui.text("WAVE " .. s.level .. " CLEAR", cx, y, C.hi, "center")
  ui.small(string.format("Cities %d  Rockets %d  x%d", b.cities, b.rockets, b.mult), cx, y + 8, C.text, C.bg, "center")
  ui.small("BONUS " .. b.bonus, cx, y + 10, C.ok, C.bg, "center")
  if b.rebuilt > 0 then ui.small("CITY REBUILT", cx, y + 12, C.ok, C.bg, "center") end
end

function view.draw(L, s)
  drawGround(L, s)
  drawMissiles(L, s)
  drawBombers(L, s)
  drawShots(L, s)
  drawBlasts(L, s)
  drawBanner(L, s)
end

--- Anywhere under the header aims there. The rules keep the spot in the sky.
function view.actionAt(L, _, px, py)
  if py < L.y0 then return nil end
  return { kind = "fire", x = px - L.x0, y = py - L.y0 }
end

--- A busy step can hold many of one thing: one sound of each is plenty.
function view.onEvents(app, _, events)
  local heard = {}
  local function once(name, ...)
    if not heard[name] then
      heard[name] = true
      app.audio.play(name, ...)
    end
  end
  for _, ev in ipairs(events) do
    if ev.type == "fire" then once("placeBlue") end
    if ev.type == "kill" then
      if ev.bomber then once("captureBlue") elseif ev.chain > 1 then once("captureRed") else once("capture") end
    end
    if ev.type == "city" or ev.type == "base" then once("error") end
    if ev.type == "empty" then once("error", 0.5) end
    if ev.type == "wave" then once("select") end
    if ev.type == "bonus" then app.audio.later("select", 120) end
  end
end

return base.fill({
  id = "missile", title = "Missile Command", short = "Missile Cmd", blurb = "Tap the sky, save the cities", color = "warn",
  accent = 0xFFD257, action = true, livesName = "CITIES", tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Missiles are falling on your six cities. Tap anywhere on the board and the nearest base fires a rocket at that spot.",
    "",
    "It bursts into a blast that grows and then shrinks. Anything caught in it is destroyed, and goes up in a blast of its own.",
    "",
    "Aim ahead of a missile, not at it: the rocket takes a moment. Each base has ten rockets a wave, shown under it.",
    "",
    "A wave pays for each city and rocket left. Every 10,000 points rebuilds a city. Lose them all and the game is over.",
  },
})
