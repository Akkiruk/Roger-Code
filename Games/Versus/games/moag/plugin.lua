-- games/moag/plugin.lua
-- MOAG as a versus game, taken in turns. Both players watch one battlefield, but each has their own tank on the left, so
-- player 2's field is a mirror of player 1's, taps included. Under the field is a panel: on your turn it holds the controls
-- (drive, angle, power, weapon, FIRE) and the time left; on theirs it says they're aiming.
-- The rules work in world units; this file turns them into monitor cells, each 2 units wide and 3 tall.

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
local WIND_ARROW_MOST = 12  -- the longest the wind arrow gets, in cells
local FLECKS = 95           -- stones in the dirt
local YOUR_TURN_TICKS = 12  -- how long YOUR TURN stays up across the sky
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

local function nameOf(s, i)
  return tostring((s.names and s.names[i]) or SEAT_NAMES[i])
end

-- ---------------------------------------------------------------- the panel's buttons

--- Every control under the field, as boxes on the wall: id, x, y, w, h. The same on both walls, and only ever live for the
--- player whose turn it is. QUIT has the bottom right corner.
local function controls(L)
  local y1, y2 = L.panelY + 2, L.panelY + 10
  return {
    { id = "moagLeft", x = 1, y = y1, w = 9, h = 7 },
    { id = "moagRight", x = 11, y = y1, w = 9, h = 7 },
    { id = "moagAngleDown", x = 23, y = y1, w = 7, h = 7 },
    { id = "moagAngleUp", x = 46, y = y1, w = 7, h = 7 },
    { id = "moagPowerDown", x = 56, y = y1, w = 7, h = 7 },
    { id = "moagPowerUp", x = 79, y = y1, w = 7, h = 7 },
    { id = "moagFire", x = 89, y = y1, w = 31, h = 7 },
    { id = "moagWeapon", x = 23, y = y2, w = 63, h = 7 },
  }
end
view.controls = controls

--- What a control does, for this player. Drive buttons go the way they point on this wall.
local function controlAction(id, player)
  local back = player == 2 and 1 or -1
  if id == "moagLeft" then return { kind = "drive", dir = back } end
  if id == "moagRight" then return { kind = "drive", dir = -back } end
  if id == "moagAngleDown" then return { kind = "angle", by = -1 } end
  if id == "moagAngleUp" then return { kind = "angle", by = 1 } end
  if id == "moagPowerDown" then return { kind = "power", by = -1 } end
  if id == "moagPowerUp" then return { kind = "power", by = 1 } end
  if id == "moagFire" then return { kind = "fire" } end
  if id == "moagWeapon" then return { kind = "weapon", step = 1 } end
  return nil
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

--- A name and a bar of health over a tank, kept on the wall, and the hit it just took floating over that.
local function drawLabel(L, s, t, i, player)
  local top = max(L.y0 + 1, L.y0 + tankTop(s, t) - 4)
  local x = wallX(L, colOf(t.x) - floor(HP_BAR / 2), HP_BAR, player)
  x = max(L.x0, min(x, L.x0 + L.bw - HP_BAR - 4))
  local name = nameOf(s, i):sub(1, NAME_MOST)
  if t.buried then name = "BURIED" end
  local nameX = max(L.x0, min(x + floor(HP_BAR / 2) - floor(#name / 2), L.x0 + L.bw - #name))
  ui.small(name, nameX, top, SEAT_COLORS[i], SKY, "left")
  ui.fill(x, top + 1, HP_BAR, 1, C.bg)
  ui.fill(x, top + 1, max(t.hp > 0 and 1 or 0, floor(HP_BAR * t.hp / rules.HP + 0.5)), 1, t.hp <= LOW_HP and C.warn or C.ok)
  ui.small(tostring(t.hp), x + HP_BAR + 1, top + 1, t.hp <= LOW_HP and C.warn or C.text, SKY, "left")
  for _, pop in ipairs(s.pops) do
    if pop.player == i then
      local rise = floor((20 - pop.left) / 5)
      ui.small(pop.text, x + floor(HP_BAR / 2), max(L.y0, top - 1 - rise), C.hi, SKY, "center")
    end
  end
end

local function drawTank(L, s, t, i, player)
  if t.hp <= 0 then return end
  local col, row = colOf(t.x) - floor(#TANK[1] / 2), rowOf(t.y) - #TANK
  local x, y = wallX(L, col, #TANK[1], player), L.y0 + row
  local inks = { c = SEAT_COLORS[i], l = C.line, k = C.bg }
  -- the barrel first, so it comes out of the turret
  local ux, uy = rules.direction(i, t.angle)
  local fromX, fromY = cellOf(L, t.x, t.y - rules.TURRET_H, player)
  local toX, toY = cellOf(L, t.x + ux * rules.BARREL, t.y - rules.TURRET_H + uy * rules.BARREL, player)
  ui.line(fromX, fromY, toX, toY, (s.phase == "aim" and s.turn == i) and C.hi or C.text)
  for r, line in ipairs(TANK) do
    for at = 1, #line do
      local ink = inks[line:sub(at, at)]
      if ink then ui.fill(x + at - 1, y + r - 1, 1, 1, ink) end
    end
  end
end

--- The start of your arc while you aim, on your own wall only: enough to see where it's headed, not where it lands.
local function drawPreview(L, s, player)
  if s.phase ~= "aim" or s.turn ~= player or s.tanks[player].buried then return end
  for i, dot in ipairs(rules.preview(s, player)) do
    if dot.y >= 0 then drawSpot(L, dot.x, dot.y, i % 2 == 1 and C.text or C.hi, player) end
  end
end

--- Shells in flight. One gone up past the top of the sky shows as a mark on the edge, so it can be followed.
local function drawShells(L, s, player)
  for _, b in ipairs(s.shells) do
    local color = SHELL_COLORS[b.kind] or C.text
    if b.y < 0 then
      local x = wallX(L, colOf(b.x), 1, player)
      if x >= L.x0 and x < L.x0 + L.bw then ui.small("^", x, L.y0, color, SKY, "left") end
    else
      drawSpot(L, b.x, b.y, color, player)
    end
  end
end

--- A crate on a parachute shows nothing of what's in it. On the ground it has a letter.
local function drawCrate(L, crate, player)
  local x, y = wallX(L, colOf(crate.x) - 2, 5, player), L.y0 + rowOf(crate.y) - 2
  if crate.y < 0 then return end
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

--- Which way the wind blows on this wall, and how hard: a number, and an arrow that grows with it.
local function drawWind(L, s, player)
  local cx, y = L.x0 + floor(L.bw / 2), L.y0 + 1
  local level = s.windLevel or 0
  if s.phase == "hold" then return end
  if level == 0 then
    ui.small("NO WIND", cx, y + 1, C.text, SKY, "center")
    return
  end
  local dir = (player == 2 and -level or level) > 0 and 1 or -1
  local size = floor(abs(level) / rules.WIND_MOST * WIND_ARROW_MOST + 0.5)
  ui.small("WIND " .. abs(level), cx, y, C.text, SKY, "center")
  local tip = cx + dir * (floor(size / 2) + 3)
  local tail = cx - dir * (floor(size / 2) + 3)
  ui.fill(min(tip, tail), y + 3, abs(tip - tail) + 1, 1, C.text)
  ui.fill(tip - dir, y + 2, 1, 3, C.text)
  ui.fill(tip - 2 * dir, y + 1, 1, 5, C.text)
end

--- A box across the sky for the news of the round.
local function banner(L, text, color)
  local cx, y = L.x0 + floor(L.bw / 2), L.y0 + 9
  local w = ui.textWidth(text) + 6
  ui.fill(cx - floor(w / 2), y, w, 9, C.panel)
  ui.frame(cx - floor(w / 2), y, w, 9, color, 1)
  ui.text(text, cx, y + 2, color, "center")
end

local function drawNews(L, s, player)
  if s.over then return end
  if s.phase == "hold" then
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
  elseif s.phase == "aim" and s.turnClock < YOUR_TURN_TICKS then
    if s.turn == player then
      banner(L, "YOUR TURN", SEAT_COLORS[player])
    else
      banner(L, string.upper(nameOf(s, s.turn)):sub(1, NAME_MOST) .. "'S TURN", SEAT_COLORS[s.turn])
    end
  end
  if s.sudden and not s.result then
    ui.small("SUDDEN DEATH", L.x0 + L.bw - 2, L.y0 + 1, C.warn, SKY, "right")
  end
end

-- ---------------------------------------------------------------- the panel

--- The time left in this turn, as a bar across the top of the panel in the colour of whoever's turn it is.
local function drawTimer(L, s)
  local y = L.panelY
  ui.fill(0, y, L.W, 1, C.panel)
  if s.phase ~= "aim" then return end
  local share = max(0, s.timer) / rules.TURN_TICKS
  ui.fill(0, y, floor(L.W * share + 0.5), 1, s.timer <= rules.HURRY and C.warn or SEAT_COLORS[s.turn])
end

local function weaponLabel(t)
  local w = rules.WEAPONS[t.weapon]
  if t.weapon == "shell" then return w.name, "" end
  return w.name, "x" .. (t.ammo[t.weapon] or 0)
end

--- How many kinds of weapon a tank carries, plain shells included.
local function carried(t)
  local n = 1
  for _, kind in ipairs(rules.ORDER) do
    if kind ~= "shell" and (t.ammo[kind] or 0) > 0 then n = n + 1 end
  end
  return n
end

--- A number with its name over it, between its - and + buttons.
local function drawValue(x, y, w, name, value)
  ui.fill(x, y, w, 7, C.bg)
  ui.small(name, x + floor(w / 2), y, C.line, C.bg, "center")
  ui.text(tostring(value), x + floor(w / 2), y + 2, C.text, "center")
end

--- A solid arrow in the middle of a button, pointing left (-1) or right (1).
local function drawArrow(b, dir, color)
  local cx, cy = b.x + floor(b.w / 2), b.y + floor(b.h / 2)
  for i = 0, 2 do
    ui.fill(cx + dir * i, cy - (2 - i), 1, (2 - i) * 2 + 1, color)
  end
  ui.fill(dir > 0 and cx - 2 or cx + 1, cy, 2, 1, color)
end

--- Your turn: every control, live.
local function drawControls(L, s, player)
  local t = s.tanks[player]
  local byId = {}
  for _, b in ipairs(controls(L)) do byId[b.id] = b end
  local function button(id, label, color, opts)
    local b = byId[id]
    ui.button(id, b.x, b.y, b.w, b.h, label, color, opts)
    return b
  end
  local canDrive = not t.buried and t.fuel > 0
  local ink = canDrive and C.text or C.panel
  drawArrow(button("moagLeft", "", canDrive and C.panel or C.bg, { frame = canDrive and C.line or C.panel }), -1, ink)
  drawArrow(button("moagRight", "", canDrive and C.panel or C.bg, { frame = canDrive and C.line or C.panel }), 1, ink)
  button("moagAngleDown", "-", C.panel)
  button("moagAngleUp", "+", C.panel)
  button("moagPowerDown", "-", C.panel)
  button("moagPowerUp", "+", C.panel)
  drawValue(30, byId.moagAngleDown.y, 16, "ANGLE", t.angle)
  drawValue(63, byId.moagPowerDown.y, 16, "POWER", t.power)
  button("moagFire", t.buried and "DIG OUT" or "FIRE", t.buried and C.warn or C.red, { fg = C.text })
  -- the weapon: tap to go on to the next one carried
  local name, count = weaponLabel(t)
  local wb = button("moagWeapon", "", C.panel, { frame = t.weapon ~= "shell" and C.hi or nil })
  local many = carried(t) > 1
  if many then
    ui.small("<", wb.x + 2, wb.y + 3, C.line, C.panel, "left")
    ui.small(">", wb.x + wb.w - 3, wb.y + 3, C.line, C.panel, "left")
  end
  local text = name .. (count ~= "" and (" " .. count) or "")
  if ui.textWidth(text) <= wb.w - 10 then
    ui.text(text, wb.x + floor(wb.w / 2), wb.y + 1, t.weapon == "shell" and C.text or C.hi, "center")
  else
    ui.small(text, wb.x + floor(wb.w / 2), wb.y + 3, t.weapon == "shell" and C.text or C.hi, C.panel, "center")
  end
  if many then ui.small("TAP FOR NEXT", wb.x + floor(wb.w / 2), wb.y + 6, C.line, C.panel, "center") end
  -- the fuel gauge, under the drive buttons
  local y = byId.moagWeapon.y
  ui.small(t.buried and "BURIED" or "FUEL", 10, y, t.buried and C.warn or C.line, C.bg, "center")
  ui.fill(1, y + 2, 19, 3, C.panel)
  ui.fill(1, y + 2, floor(19 * t.fuel / rules.FUEL + 0.5), 3, t.fuel > 0 and C.ok or C.panel)
  -- the seconds left, beside QUIT
  local secs = math.ceil(max(0, s.timer) / 10)
  ui.small("TIME", 97, y, C.line, C.bg, "center")
  ui.text(tostring(secs), 97, y + 2, s.timer <= rules.HURRY and C.warn or C.text, "center")
end

--- Not your turn: what's going on instead.
local function drawWaiting(L, s, player)
  local cx, y = floor(L.W / 2) - 6, L.panelY + 3
  local other = 3 - player
  local t = s.tanks[s.turn]
  if s.phase == "aim" and s.turn ~= player then
    ui.text("OPPONENT IS AIMING", cx, y, SEAT_COLORS[other], "center", L.W - 16)
    local name = weaponLabel(t)
    ui.small(nameOf(s, other) .. " has " .. name .. "  -  " .. math.ceil(max(0, s.timer) / 10) .. "s left", cx, y + 8,
      C.line, C.bg, "center", L.W - 16)
  elseif s.phase == "fly" then
    ui.text("SHOT IN THE AIR", cx, y, C.text, "center", L.W - 16)
    ui.small("Next: " .. (s.turn == player and nameOf(s, other) or "you"), cx, y + 8, C.line, C.bg, "center", L.W - 16)
  elseif s.phase == "hold" then
    local first = s.turn == player and "YOU GO FIRST" or (string.upper(nameOf(s, s.turn)) .. " GOES FIRST")
    ui.text(first, cx, y, SEAT_COLORS[s.turn], "center", L.W - 16)
    ui.small("Round " .. s.round .. " - first to " .. rules.ROUNDS_TO_WIN .. " rounds wins", cx, y + 8, C.line, C.bg, "center", L.W - 16)
  elseif s.phase == "pause" then
    ui.text("ROUND OVER", cx, y, C.hi, "center", L.W - 16)
  end
end

local function drawPanel(L, s, player)
  ui.fill(0, L.panelY, L.W, L.H - L.panelY, C.bg)
  drawTimer(L, s)
  if s.over then return end
  if s.phase == "aim" and s.turn == player then
    drawControls(L, s, player)
  else
    drawWaiting(L, s, player)
  end
end

-- ---------------------------------------------------------------- the view

function view.layout(W, H)
  local L = base.actionLayout(W, H, COLS, ROWS)
  L.panelY = L.y0 + L.bh
  L.statusY = L.y0 + 22 -- the idle screen's TOUCH TO PLAY goes across the sky, clear of the panel
  return L
end

function view.draw(L, s, player)
  player = player == 2 and 2 or 1
  local screen = ui.screen()
  ui.fill(L.x0, L.y0, L.bw, L.bh, SKY)
  screen:push(L.x0, L.y0, L.bw, L.bh, true)
  drawWind(L, s, player)
  drawGround(L, s, player)
  drawSlabs(L, s, player)
  for _, crate in ipairs(s.crates) do drawCrate(L, crate, player) end
  for i, t in ipairs(s.tanks) do drawTank(L, s, t, i, player) end
  drawShells(L, s, player)
  drawBlasts(L, s, player)
  for i, t in ipairs(s.tanks) do
    if t.hp > 0 then drawLabel(L, s, t, i, player) end
  end
  drawPreview(L, s, player)
  drawNews(L, s, player)
  screen:pop()
  drawPanel(L, s, player)
end

--- On your turn a tap in the sky points the barrel at that spot, harder the further off, and the panel's buttons do what
--- they say. On the other player's turn a tap means nothing.
function view.actionAt(L, s, px, py, player)
  player = player == 2 and 2 or 1
  if s.over or s.phase ~= "aim" or s.turn ~= player then return nil end
  if py >= L.y0 and py < L.y0 + L.bh then
    local col = max(0, min(px - L.x0, L.bw - 1))
    if player == 2 then col = L.bw - 1 - col end
    return { kind = "aim", x = (col + 0.5) * CELL_W, y = (py - L.y0 + 0.5) * CELL_H }
  end
  for _, b in ipairs(controls(L)) do
    if px >= b.x and px < b.x + b.w and py >= b.y and py < b.y + b.h then return controlAction(b.id, player) end
  end
  return nil
end

--- The view isn't told who's playing, so it learns the names from the shell when the match starts ticking.
local function learnNames(app, s)
  local match = app.S and app.S.versus
  if s.names or not match or not match.seats[2] then return end
  s.names = { match.seats[1].name, match.seats[2].name }
end

-- What each event sounds like, one of each a step. Names are in lib/sound_picks.lua.
local SFX = {
  fire = "cannon", dig = "dig", pile = "dig", hit = "ship_hit", stuck = "ui_error", noFuel = "ui_error",
  crate = "swish", crateDown = "lock_in", pickup = "pickup", sudden = "ui_warning", kill = "death",
  turn = "ui_hint", hurry = "ui_warning", timeout = "ui_timeout",
  blast = function(ev) return ev.kind == "nuke" and "boom_big" or "boom_small" end,
  round = function(ev) return ev.winner == 0 and "draw" or "win_small" end,
}
view.SFX = SFX

function view.onEvents(app, s, events)
  learnNames(app, s)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "moag", title = "MOAG", blurb = "Two tanks, one hill, a shot each in turn", color = "warn",
  versus = true, tickMs = 100, minSize = { w = 120, h = 78 },
  cpuLevels = { "easy", "normal", "hard" },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Blow up the other tank. You take turns: one shot each. Your tank is always on the left of your wall. First to three rounds wins, with new ground every round.",
    "",
    "On your turn, tap the sky to point the barrel: it aims at the spot, and the further from your tank you tap, the harder it fires. ANGLE - + and POWER - + fine-tune it. The dotted line shows how the shot leaves, not where it lands.",
    "",
    "Watch the wind at the top: it changes every turn, and it pushes every shot the way the arrow points. The bigger the number, the harder the push.",
    "",
    "< and > drive your tank, as far as the fuel bar lets you this turn. Then press FIRE. The shot plays out before the other player's turn. You have 45 seconds: when the time runs out, a shot you lined up fires by itself, and if you did nothing the turn passes.",
    "",
    "Shells blow craters, and dirt falls in. A hit costs more the closer it is, and your own shells hurt you too. If you're buried, FIRE becomes DIG OUT, and that's your turn.",
    "",
    "Crates parachute in between turns. Drive onto one for BIG shells, a CLUSTER that splits at the top of its flight, a DIRT bomb that piles up a hill or buries a tank, a TUNNELLER that digs straight through the ground, or a NUKE. Tap the weapon bar to pick what you fire. A round that goes on too long ends in sudden death.",
  },
})
