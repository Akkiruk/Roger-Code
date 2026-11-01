-- games/moag/plugin.lua
-- MOAG as a versus game. Tap the sky to fire at that spot, tap beside your tank to drive. Both players watch one
-- battlefield, but each has their own tank on the left, so player 2's wall is a mirror of player 1's, taps included.
-- The rules work in world units; this file turns them into monitor cells, each 2 units wide and 3 tall. The strip under the
-- field shows the weapon and the reload, and stops short of the shell's QUIT.

local base = require("lib.arcade.base")
local rules = require("games.moag.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local CELL_W, CELL_H, COLS = rules.CELL_W, rules.CELL_H, rules.COLS
local ROWS = rules.HEIGHT / CELL_H
local BEDROCK_ROW = math.floor(rules.BEDROCK / CELL_H)
local SEAT_NAMES = { "RED", "BLUE" }
local NAME_MOST = 10        -- the most letters of a name that show over a tank
local HP_BAR = 8
local LOW_HP = 25
local STRIP_X = 56         -- where the reload starts, clear of the longest weapon name
local WIND_ARROW_MOST = 12  -- the longest the wind arrow gets, in cells
local FLECKS = 110          -- stones in the dirt
local abs, floor, max, min = math.abs, math.floor, math.max, math.min

local SKY = C.blueTint
local DIRT, BARE, GRASS, ROCK, STONE = C.redTint, C.hiTint, C.ok, C.panel, C.tie
local SEAT_COLORS = { C.red, C.blue }
local SHELL_COLORS = { nuke = C.red, dirt = C.warn, tunneller = C.info, big = C.hi }
local CRATE_MARK = { big = "B", cluster = "C", dirt = "D", tunneller = "T", nuke = "N" }

-- A tank, one string for each row. It looks the same from both sides, so only the barrel needs a mirror.
local TANK = { "..ccc..", ".ccccc.", "lklklkl" }

local view = {}

--- The next number of a small fixed sequence.
local function scatter(n)
  return (n * 1103 + 12345) % 32749
end

--- Stones in the dirt, in the same place every time: no chance needed, and they never change.
local function stones()
  local out, n = {}, 11
  for i = 1, FLECKS do
    n = scatter(n)
    local col = n % COLS
    n = scatter(n)
    out[i] = { col = col, row = n % ROWS }
  end
  return out
end
local STONES = stones()

--- Where a box starting at column col, w cells wide, shows on this player's wall.
local function wallX(L, col, w, player)
  if player == 2 then return L.x0 + L.bw - col - w end
  return L.x0 + col
end

local function colOf(x) return floor(x / CELL_W) end
local function rowOf(y) return floor(y / CELL_H) end

--- A world spot's cell on this wall.
local function cellOf(L, x, y, player)
  return wallX(L, colOf(x), 1, player), L.y0 + rowOf(y)
end

--- A bright spot two cells wide, which is about square on the wall.
local function drawSpot(L, x, y, color, player)
  ui.fill(wallX(L, colOf(x), 2, player), L.y0 + rowOf(y), 2, 1, color)
end

-- ---------------------------------------------------------------- the ground

local cache = {}

--- The ground as a list of boxes, for one wall. Columns of one height go in one box. Ground only changes when something
-- lands, so the list is kept until it does and a frame just has to fill it in.
local function groundBoxes(L, s, player)
  local key = player == 2 and 2 or 1
  local kept = cache[key]
  if kept and kept.ground == s.ground and kept.rev == s.rev and kept.L == L then return kept.boxes end
  local boxes, tops = {}, {}
  local c = 1
  while c <= COLS do
    local top = rowOf(s.ground[c])
    local bare = s.bare[c]
    local from = c
    while c < COLS and rowOf(s.ground[c + 1]) == top and s.bare[c + 1] == bare do c = c + 1 end
    local w = c - from + 1
    local x = wallX(L, from - 1, w, player)
    boxes[#boxes + 1] = { x, L.y0 + top, w, ROWS - top, DIRT }
    boxes[#boxes + 1] = { x, L.y0 + top, w, 1, bare and BARE or GRASS }
    for i = from, c do tops[i] = top end
    c = c + 1
  end
  for _, stone in ipairs(STONES) do
    if stone.row > tops[stone.col + 1] + 1 then
      boxes[#boxes + 1] = { wallX(L, stone.col, 2, player), L.y0 + stone.row, 2, 1, STONE }
    end
  end
  boxes[#boxes + 1] = { L.x0, L.y0 + BEDROCK_ROW, L.bw, ROWS - BEDROCK_ROW, ROCK }
  cache[key] = { ground = s.ground, rev = s.rev, L = L, boxes = boxes }
  return boxes
end

view.groundBoxes = groundBoxes

local function drawGround(L, s, player)
  for _, box in ipairs(groundBoxes(L, s, player)) do ui.fill(box[1], box[2], box[3], box[4], box[5]) end
end

--- Dirt on its way down: a piece of a column each.
local function drawSlabs(L, s, player)
  for _, slab in ipairs(s.slabs) do
    local row = rowOf(slab.top)
    ui.fill(wallX(L, slab.c - 1, 1, player), L.y0 + row, 1, max(1, rowOf(slab.top + slab.h) - row), DIRT)
  end
end

-- ---------------------------------------------------------------- what's on it

--- The top row of a tank, or of the dirt lying on it.
local function tankTop(s, t)
  return min(rowOf(t.y) - #TANK, rowOf(rules.restY(s, t.x)) - 1)
end

--- A name and a bar of health over a tank, kept on the wall. On your own, a sliver of reload too.
local function drawLabel(L, s, t, i, player)
  local top = L.y0 + tankTop(s, t) - 4
  local x = wallX(L, colOf(t.x) - floor(HP_BAR / 2), HP_BAR, player)
  x = max(L.x0, min(x, L.x0 + L.bw - HP_BAR))
  local name = tostring((s.names and s.names[i]) or SEAT_NAMES[i]):sub(1, NAME_MOST)
  if t.buried then name = "BURIED" end
  local nameX = max(L.x0, min(x + floor(HP_BAR / 2) - floor(#name / 2), L.x0 + L.bw - #name))
  ui.small(name, nameX, top, SEAT_COLORS[i], SKY, "left")
  ui.fill(x, top + 1, HP_BAR, 1, C.bg)
  ui.fill(x, top + 1, max(t.hp > 0 and 1 or 0, floor(HP_BAR * t.hp / rules.HP + 0.5)), 1, t.hp <= LOW_HP and C.warn or C.ok)
  if i == player and t.reload > 0 then
    ui.fill(x, top + 2, HP_BAR, 1, C.bg)
    ui.fill(x, top + 2, floor(HP_BAR * (1 - t.reload / t.reloadFull)), 1, C.hi)
  end
end

local function drawTank(L, t, i, player)
  if t.hp <= 0 then return end
  local col, row = colOf(t.x) - floor(#TANK[1] / 2), rowOf(t.y) - #TANK
  local x, y = wallX(L, col, #TANK[1], player), L.y0 + row
  local inks = { c = SEAT_COLORS[i], l = C.line, k = C.bg }
  -- the barrel first, so it comes out of the turret
  local fromX, fromY = cellOf(L, t.x, t.y - rules.TURRET_H, player)
  local toX, toY = cellOf(L, t.x + t.ux * rules.BARREL, t.y - rules.TURRET_H + t.uy * rules.BARREL, player)
  ui.line(fromX, fromY, toX, toY, C.text)
  for r, line in ipairs(TANK) do
    for at = 1, #line do
      local ink = inks[line:sub(at, at)]
      if ink then ui.fill(x + at - 1, y + r - 1, 1, 1, ink) end
    end
  end
end

--- Your arc, for a moment after a tap, and only on your own wall: gold when it fired, grey when it was only a sighting.
local function drawArc(L, t, player)
  local aim = t.aim
  if not aim then return end
  local color = aim.fired and C.hi or C.line
  for _, dot in ipairs(aim.dots) do drawSpot(L, dot.x, dot.y, color, player) end
  local x, y = cellOf(L, aim.landX, aim.landY, player)
  ui.fill(x - 2, y, 5, 1, color)
  ui.fill(x, y - 1, 1, 3, color)
end

local function drawShells(L, s, player)
  for _, b in ipairs(s.shells) do
    drawSpot(L, b.x, b.y, SHELL_COLORS[b.kind] or C.text, player)
  end
end

--- A crate on a parachute shows nothing of what's in it. On the ground it has a letter.
local function drawCrate(L, crate, player)
  local x, y = wallX(L, colOf(crate.x) - 2, 5, player), L.y0 + rowOf(crate.y) - 2
  ui.fill(x, y, 5, 2, C.warn)
  if crate.landed then
    ui.small(CRATE_MARK[crate.kind], x + 2, y, C.bg, C.warn, "left")
  else
    ui.fill(x - 1, y - 3, 7, 1, C.text)
    ui.fill(x, y - 2, 1, 2, C.line)
    ui.fill(x + 4, y - 2, 1, 2, C.line)
  end
end

--- A blast starts as big as it will get and burns down to the middle.
local function drawBlasts(L, s, player)
  for _, b in ipairs(s.blasts) do
    local cx, cy = cellOf(L, b.x, b.y, player)
    local w, h = floor(b.r * 2 / CELL_W), floor(b.r * 2 / CELL_H)
    ui.ellipse(cx - floor(w / 2), cy - floor(h / 2), w, h, C.warn)
    w, h = floor(w * 0.6), floor(h * 0.6)
    ui.ellipse(cx - floor(w / 2), cy - floor(h / 2), w, h, b.left > 1 and C.hi or C.red)
  end
end

--- Which way the wind blows on this wall, and how hard: the arrow grows with it.
local function drawWind(L, s, player)
  local cx, y = L.x0 + floor(L.bw / 2), L.y0 + 1
  local wind = player == 2 and -s.wind or s.wind
  local size = floor(abs(wind) / rules.WIND_MOST * WIND_ARROW_MOST + 0.5)
  if size == 0 then
    ui.small("NO WIND", cx, y, C.line, SKY, "center")
    return
  end
  ui.small("WIND", cx, y, C.text, SKY, "center")
  local dir = wind > 0 and 1 or -1
  local tip = cx + dir * (floor(size / 2) + 3)
  local tail = cx - dir * (floor(size / 2) + 3)
  ui.fill(min(tip, tail), y + 3, abs(tip - tail) + 1, 1, C.text)
  ui.fill(tip - dir, y + 2, 1, 3, C.text)
  ui.fill(tip - 2 * dir, y + 1, 1, 5, C.text)
end

--- A box across the sky for the news of the round.
local function banner(L, text, color)
  local cx, y = L.x0 + floor(L.bw / 2), L.y0 + 8
  local w = ui.textWidth(text) + 6
  ui.fill(cx - floor(w / 2), y, w, 9, C.panel)
  ui.frame(cx - floor(w / 2), y, w, 9, color, 1)
  ui.text(text, cx, y + 2, color, "center")
end

local function drawNews(L, s, player)
  if s.over then return end
  if s.hold > 0 then
    banner(L, "ROUND " .. s.round, C.hi)
  elseif s.result then
    local w = s.result.winner
    if w == 0 then
      banner(L, "BOTH GONE", C.hi)
    elseif w == player then
      banner(L, "ROUND WON", SEAT_COLORS[w])
    else
      banner(L, "ROUND LOST", SEAT_COLORS[w])
    end
  elseif s.sudden then
    ui.small("SUDDEN DEATH", L.x0 + floor(L.bw / 2), L.y0 + 5, C.warn, SKY, "center")
  end
end

--- This player's weapon, reload and health, under the field and short of QUIT.
local function drawStrip(L, s, player)
  local t = s.tanks[player == 2 and 2 or 1]
  local y = L.y0 + L.bh + 1
  local w = rules.WEAPONS[t.weapon]
  ui.text(w.name, 2, y, t.weapon == "shell" and C.text or C.hi, "left")
  if t.weapon ~= "shell" then ui.small("x" .. t.ammo, ui.textWidth(w.name) + 4, y + 2, C.text, C.bg, "left") end
  local x, barW = STRIP_X, 24
  local ready = t.reload == 0
  ui.small(t.buried and "DIG OUT" or (ready and "READY" or "LOADING"), x, y, ready and C.ok or C.line, C.bg, "left")
  ui.fill(x, y + 2, barW, 3, C.panel)
  ui.fill(x, y + 2, floor(barW * (1 - t.reload / t.reloadFull) + 0.5), 3, ready and C.ok or C.hi)
  ui.small("HP " .. t.hp, x + barW + 3, y + 2, t.hp <= LOW_HP and C.warn or C.text, C.bg, "left")
end

function view.layout(W, H)
  return base.actionLayout(W, H, COLS, ROWS)
end

function view.draw(L, s, player)
  local screen = ui.screen()
  ui.fill(L.x0, L.y0, L.bw, L.bh, SKY)
  screen:push(L.x0, L.y0, L.bw, L.bh, true)
  drawWind(L, s, player)
  drawGround(L, s, player)
  drawSlabs(L, s, player)
  for _, crate in ipairs(s.crates) do drawCrate(L, crate, player) end
  for i, t in ipairs(s.tanks) do drawTank(L, t, i, player) end
  for i, t in ipairs(s.tanks) do
    if i == player then drawArc(L, t, player) end
  end
  drawShells(L, s, player)
  drawBlasts(L, s, player)
  for i, t in ipairs(s.tanks) do
    if t.hp > 0 then drawLabel(L, s, t, i, player) end
  end
  drawNews(L, s, player)
  screen:pop()
  drawStrip(L, s, player)
end

--- A tap beside your own tank drives, and a tap anywhere else aims. Both come out in world terms, whichever wall it's on.
function view.actionAt(L, s, px, py, player)
  if py >= L.y0 + L.bh then return nil end
  local col = max(0, min(px - L.x0, L.bw - 1))
  if player == 2 then col = L.bw - 1 - col end
  return rules.tapAction(s, player, (col + 0.5) * CELL_W, (max(py, L.y0) - L.y0 + 0.5) * CELL_H)
end

--- The view isn't told who's playing, so it learns the names from the shell when the match starts ticking.
local function learnNames(app, s)
  local match = app.S and app.S.versus
  if s.names or not match or not match.seats[2] then return end
  s.names = { match.seats[1].name, match.seats[2].name }
end

--- A busy step can hold many of one thing: one sound of each is plenty.
function view.onEvents(app, s, events)
  learnNames(app, s)
  local heard = {}
  local function once(name, ...)
    if not heard[name] then
      heard[name] = true
      app.audio.play(name, ...)
    end
  end
  for _, ev in ipairs(events) do
    if ev.type == "fire" then once("placeRed", 0.9, ev.kind == "nuke" and 0.6 or 0.8) end
    if ev.type == "sight" or ev.type == "stuck" then once("placeBlue", 0.3, 1.4) end
    if ev.type == "dig" or ev.type == "pile" then once("placeBlue", 0.9, 0.6) end
    if ev.type == "blast" then once("captureBlue", ev.kind == "nuke" and 1.6 or 1, ev.kind == "nuke" and 0.5 or 0.8) end
    if ev.type == "hit" then once("captureRed", 1, 0.8) end
    if ev.type == "crateDown" then once("placeBlue", 0.5, 1) end
    if ev.type == "pickup" then once("capture", 1, 1.3) end
    if ev.type == "sudden" then once("captureRed", 1, 0.5) end
    if ev.type == "kill" then once("captureBlue", 1.6, 0.5) end
    if ev.type == "round" then app.audio.later("capture", 200, 1, ev.winner == 0 and 0.7 or 1.2) end
  end
end

return base.fill({
  id = "moag", title = "MOAG", blurb = "Two tanks, one hill, and less of it every shot", color = "warn",
  versus = true, tickMs = 100, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Blow up the other tank. Your tank is always on the left of your wall. First to five rounds wins, with new ground every round.",
    "",
    "Tap the sky to fire at that spot. The shell flies up and over and comes down through where you tapped, and the wind pushes it off line: watch the arrow at the top, and aim upwind. Your arc shows for a moment after each tap.",
    "",
    "Reloading takes about two seconds, and the bar under the field shows how long. A tap while it loads fires nothing, but it still shows you the arc, so you can line up the next shot.",
    "",
    "Tap beside your tank to drive that way. Tap again to go further, or the other way to stop. A tank only climbs gentle slopes.",
    "",
    "Shells blow craters, and dirt falls in. A hit costs more the closer it is, and your own shells hurt you too. If you get buried, tap the sky to blow yourself out.",
    "",
    "Crates drop in: drive over one for BIG shells, a CLUSTER that splits in the air, a DIRT bomb that piles up a hill or buries a tank, a TUNNELLER that digs straight through the ground, or a NUKE. A round that goes on too long ends in sudden death.",
  },
})
