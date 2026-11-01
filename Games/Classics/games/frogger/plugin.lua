-- games/frogger/plugin.lua
-- Frogger as an Arcade classic. Every tap is one hop: on an arrow, or on the board, which hops toward the tap.

local base = require("lib.arcade.base")
local rules = require("games.frogger.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local COLS, ROWS, TILE = rules.COLS, rules.ROWS, rules.TILE
local ROW_H = 5               -- a tile is 6 x 5, a little taller than square, to fill the wall
local CAR_COLORS = { [8] = C.text, [9] = C.red, [10] = C.info, [11] = C.warn, [12] = C.accent }
local BLURB = "Hop the road, ride the river"

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * TILE, ROWS * ROW_H)
end

local function rowY(L, row)
  return L.y0 + (row - 1) * ROW_H
end

local function drawLandscape(L)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.panel)
  ui.fill(L.x0, rowY(L, rules.HOME_ROW), L.bw, ROW_H, C.ok)
  ui.fill(L.x0, rowY(L, rules.HOME_ROW + 1), L.bw, (rules.MEDIAN_ROW - 2) * ROW_H, C.blueTint)
  ui.fill(L.x0, rowY(L, rules.MEDIAN_ROW), L.bw, ROW_H, C.tie)
  ui.fill(L.x0, rowY(L, rules.START_ROW), L.bw, ROW_H, C.tie)
  for row = rules.MEDIAN_ROW + 1, rules.START_ROW - 2 do
    for x = 2, L.bw - 3, TILE do ui.fill(L.x0 + x, rowY(L, row) + ROW_H - 1, 2, 1, C.tie) end
  end
end

local function drawFrog(x, y, facing, color)
  ui.fill(x + 1, y, TILE - 2, ROW_H, color)
  ui.fill(x, y + 1, TILE, ROW_H - 2, color)
  if facing == "left" or facing == "right" then
    local side = facing == "left" and x or x + TILE - 1
    ui.fill(side, y + 1, 1, 1, C.text)
    ui.fill(side, y + 2, 1, 1, C.text)
  else
    local top = facing == "up" and y or y + ROW_H - 1
    ui.fill(x + 1, top, 1, 1, C.text)
    ui.fill(x + TILE - 2, top, 1, 1, C.text)
  end
end

local function drawBays(L, s)
  for i = 1, rules.BAY_COUNT do
    local x = L.x0 + rules.bayLeft(i)
    ui.fill(x, L.y0, rules.BAY_W, ROW_H, C.blueTint)
    if s.bays[i] then drawFrog(x + (rules.BAY_W - TILE) / 2, L.y0, "up", C.soft) end
  end
end

local function drawCar(x, y, len, dir, color)
  ui.fill(x, y + 1, len, 2, color)
  ui.fill(x + 1, y, len - 2, ROW_H, color)
  local front = dir > 0 and x + len - 3 or x + 2
  ui.fill(front, y, 1, ROW_H, C.bg)
end

local function drawLog(x, y, len)
  ui.fill(x, y, len, ROW_H - 1, C.warn)
  ui.fill(x + 2, y + 1, len - 4, 1, C.redTint)
end

--- A group of turtles, one a tile wide. They shrink and pale as they sink, and leave only ripples while under.
local function drawTurtles(x, y, len, stage)
  for at = x, x + len - TILE, TILE do
    if stage == "under" then
      ui.fill(at + 2, y + 1, 2, 1, C.blue)
    elseif stage == "up" then
      base.disc(at, y, TILE - 1, ROW_H, C.red)
      ui.fill(at + 2, y + 1, 1, 2, C.redTint)
    else
      base.disc(at + 1, y + 1, TILE - 2, ROW_H - 2, stage == "sinking" and C.text or C.redTint)
    end
  end
end

local function drawLanes(L, s)
  for row = rules.HOME_ROW, rules.START_ROW do
    local lane = s.lanes[row]
    for _, item in ipairs(lane and lane.items or {}) do
      local x, y = L.x0 + rules.itemLeft(lane, item), rowY(L, row)
      if lane.kind == "car" then
        drawCar(x, y, item.len, lane.dir, CAR_COLORS[row])
      elseif lane.kind == "log" then
        drawLog(x, y, item.len)
      else
        drawTurtles(x, y, item.len, rules.diveStage(item, s.beats))
      end
    end
  end
end

--- What's left of a lost frog.
local function drawSplat(L, splat)
  local x, y = L.x0 + splat.x, rowY(L, splat.row)
  local color = splat.why == "water" and C.text or C.red
  ui.fill(x + 1, y, 1, 1, color)
  ui.fill(x + 4, y, 1, 1, color)
  ui.fill(x + 2, y + 1, 2, 2, color)
  ui.fill(x + 1, y + 3, 1, 1, color)
  ui.fill(x + 4, y + 3, 1, 1, color)
end

local function drawTime(L, s)
  local left = math.ceil(L.bw * math.max(0, s.time) / rules.FROG_TICKS)
  ui.fill(L.x0, L.y0 + L.bh, left, 1, s.time * 3 < rules.FROG_TICKS and C.warn or C.ok)
end

function view.draw(L, s)
  drawLandscape(L)
  drawBays(L, s)
  drawLanes(L, s)
  if s.dead > 0 and s.splat then
    drawSplat(L, s.splat)
  elseif s.dead == 0 then
    drawFrog(L.x0 + s.frog.x, rowY(L, s.frog.row), s.frog.facing, C.ok)
  end
  -- whatever hangs over the side of the board is covered up
  ui.fill(0, L.y0, L.x0, L.bh, C.bg)
  ui.fill(L.x0 + L.bw, L.y0, L.W - L.x0 - L.bw, L.bh, C.bg)
  drawTime(L, s)
end

--- The whole wall steers: tap the side you want to hop.
function view.actionAt(L, _, px, py)
  return base.splitAction(L, px, py)
end

--- The idle screen. The title's tails hang into the line under it, so that line goes at the foot of the wall instead.
function view.drawAttract(W, H, demo)
  local L = view.layout(W, H)
  ui.text("Frogger", math.floor(W / 2), 0, C.ok, "center", W - 2)
  if demo.match then view.draw(L, demo.match.state) end
  ui.small(BLURB, math.floor(W / 2), H - 5, C.line, C.bg, "center", W - 2)
  return L.statusY + 2
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "hop" then app.audio.play("placeRed") end
    if ev.type == "home" then app.audio.play("capture") end
    if ev.type == "level" then app.audio.later("select", 120) end
    if ev.type == "die" then app.audio.play("error") end
  end
end

return base.fill({
  id = "frogger", title = "Frogger", blurb = BLURB, color = "ok", accent = 0x35D07F,
  action = true, split = true, tickMs = 100, minSize = { w = 100, h = 74 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Get a frog home to each of the five bays at the top.",
    "",
    "Every tap is one hop. Tap the side of the wall you want to go: the top hops up, the bottom down, the left side left and the right side right. The wall is split corner to corner, so you never have to look away.",
    "",
    "Cross the road without being hit, then ride the logs and turtles over the river. The water is deadly. So is riding off the edge, or a turtle that dives under you: they sink slowly and turn pale first.",
    "",
    "The bar under the board is your time for this frog. You have three lives, and each forward hop and each frog home scores. Fill all five bays and the next level runs faster.",
  },
})
