-- games/tron/plugin.lua
-- Light cycles as a Versus game. Both walls show the same arena from the same side, with no mirroring: the only difference
-- is the colours, so your own trail is blue on your wall and orange on theirs. The whole wall steers.

local base = require("lib.arcade.base")
local rules = require("games.tron.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 3, 2
local GRID_EVERY = 3        -- cells between the lines of the floor
local GO_TICKS = 8          -- how long GO! stays up

-- A trail is a band of the player's colour with a hot line down the middle of it.
local MINE = { band = C.blue, core = C.info, tint = C.blueTint }
local THEIRS = { band = C.warn, core = C.hi, tint = C.redTint }
local BURST = { C.text, C.hi, C.warn, C.red }

local function cellX(L, x) return L.x0 + (x - 1) * CELL_W end
local function cellY(L, y) return L.y0 + (y - 1) * CELL_H end

--- The look a cycle has on this wall. With no player, as on the idle screen, the first cycle is the blue one.
local function looks(player, viewer)
  return player == (viewer or 1) and MINE or THEIRS
end

local function drawFloor(L)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  for x = GRID_EVERY, COLS - 1, GRID_EVERY do ui.fill(cellX(L, x + 1) - 1, L.y0, 1, L.bh, C.panel) end
  for y = GRID_EVERY, ROWS - 1, GRID_EVERY do ui.fill(L.x0, cellY(L, y + 1) - 1, L.bw, 1, C.panel) end
  ui.frame(L.x0 - 1, L.y0 - 1, L.bw + 2, L.bh + 2, C.line)
end

--- One straight run of a trail, from cell a to cell b.
local function drawRun(L, a, b, look)
  local x0, y0 = cellX(L, math.min(a[1], b[1])), cellY(L, math.min(a[2], b[2]))
  local w = (math.abs(a[1] - b[1]) + 1) * CELL_W
  local h = (math.abs(a[2] - b[2]) + 1) * CELL_H
  ui.fill(x0, y0, w, h, look.band)
  if a[2] == b[2] then
    ui.fill(x0, y0, w, 1, look.core)
  else
    ui.fill(x0 + 1, y0, 1, h, look.core)
  end
end

--- A trail is mostly long straight runs, so it draws as those and not cell by cell, which keeps a full arena cheap.
local function drawTrail(L, trail, look)
  local from = 1
  while from <= #trail do
    local to = from
    local a = trail[from]
    while trail[to + 1] and (trail[to + 1][1] == a[1] or trail[to + 1][2] == a[2]) do to = to + 1 end
    drawRun(L, a, trail[to], look)
    from = math.max(to, from + 1)
    if to == #trail then break end
  end
end

--- The head, a white block, so the eye can find it in a tangle.
local function drawHead(L, c)
  ui.fill(cellX(L, c.x), cellY(L, c.y), CELL_W, CELL_H, C.text)
end

--- Sparks flying out of the crash in eight directions, cooling as they go.
local function drawBurst(L, s, burst, look)
  local age = rules.CRASH_TICKS - s.wait
  local x, y = cellX(L, burst.x) + 1, cellY(L, burst.y)
  local color = BURST[math.min(#BURST, floor(age / 3) + 1)]
  local reach = 2 + age
  for dx = -1, 1 do
    for dy = -1, 1 do
      local px = x + dx * reach * 3
      local py = y + dy * reach * 2
      if (dx ~= 0 or dy ~= 0) and px >= L.x0 and px + 2 <= L.x0 + L.bw and py >= L.y0 and py + 1 <= L.y0 + L.bh then
        ui.fill(px, py, 2, 1, age % 2 == 0 and color or look.core)
      end
    end
  end
  if age < 6 then ui.fill(x - 3, y - 1, 8, 4, color) end
end

--- A word on a dark strip, in the big font, across the middle of the arena.
local function banner(L, text, color, sub)
  local cx, cy = L.x0 + floor(L.bw / 2), L.y0 + floor(L.bh / 2)
  local w = math.max(ui.textWidth(text), sub and #sub or 0) + 6
  local h = ui.fontHeight() + (sub and 5 or 3)
  ui.fill(cx - floor(w / 2), cy - floor(h / 2), w, h, C.bg)
  ui.text(text, cx, cy - floor(h / 2) + 1, color, "center")
  if sub then ui.small(sub, cx, cy + floor(h / 2) - 2, C.line, C.bg, "center") end
end

--- Marks your cycle before the off, so you know which one is yours.
local function drawTags(L, s, viewer)
  for p, c in ipairs(s.cycles) do
    local mine = p == (viewer or 1)
    local x = cellX(L, c.x) + 1
    ui.small(mine and "YOU" or "THEM", x, cellY(L, c.y) - 3, looks(p, viewer).band, C.bg, "center")
  end
end

--- The header has the score. The first round has no count of its own, as the shell's 3-2-1 stands over it, at ticks 0.
local function drawNotes(L, s, viewer)
  if s.phase == "count" then
    drawTags(L, s, viewer)
    banner(L, tostring(math.ceil(s.wait / rules.TICKS_PER_NUMBER)), C.hi, "ROUND " .. s.round)
  elseif s.phase == "run" and s.ticks < GO_TICKS then
    drawTags(L, s, viewer)
    if s.ticks > 0 then banner(L, "GO!", C.ok) end
  elseif s.phase == "crash" then
    local me = viewer or 1
    if s.roundWinner == 0 then
      banner(L, "DRAW", C.hi, "PLAY IT AGAIN")
    elseif s.roundWinner == me then
      banner(L, "ROUND WON", C.info)
    else
      banner(L, "CRASHED", C.warn)
    end
  end
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

function view.draw(L, s, player)
  drawFloor(L)
  for p, c in ipairs(s.cycles) do drawTrail(L, c.trail, looks(p, player)) end
  for _, c in ipairs(s.cycles) do drawHead(L, c) end
  -- the burst has played out by the end of the match, and the final board stays up, so it must leave no sparks behind
  if s.over then return end
  for _, burst in ipairs(s.bursts) do drawBurst(L, s, burst, looks(burst.player, player)) end
  drawNotes(L, s, player)
end

--- The whole wall steers: tap the side you want.
function view.actionAt(L, _, px, py)
  return base.splitAction(L, px, py)
end

--- No buttons: the wall is the control.
function view.controls()
  return {}
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "count" then app.audio.play("tap") end
    if ev.type == "go" then app.audio.play("select", 1, 1.5) end
    if ev.type == "turn" then app.audio.play("placeBlue", 0.25, 1.3) end
    if ev.type == "crash" then app.audio.play("captureBlue", 1, 0.5) end
    if ev.type == "round" then
      if ev.winner == 0 then app.audio.later("back", 160) else app.audio.later("capture", 160, 1, 1.2) end
    end
  end
end

return base.fill({
  id = "tron", title = "Light Cycles", blurb = "Box them in before they box you", color = "info",
  versus = true, split = true, tickMs = 100, minSize = { w = 118, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Two light cycles, each leaving a solid wall behind it. Crash into any wall, yours or theirs, or the edge of the arena, and the other player wins the round. Crash on the same step and the round is played again. First to five rounds wins.",
    "",
    "Tap the side of your wall you want to go: the top goes up, the bottom down, the left side left and the right side right. The wall is split corner to corner, so you never have to look away. You can't turn straight back on yourself, but two quick taps make a hairpin.",
    "",
    "Your own trail is always blue and theirs is orange, on both walls. Every round starts slowly and keeps getting faster, so cut them off early and leave yourself room.",
  },
})
