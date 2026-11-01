-- games/digdug/plugin.lua
-- Dig Dug as an Arcade classic. A tap sets a direction, by the arrows or on the board, and it stays set. PUMP stops the
-- digger, fires the harpoon and inflates what it hooks. Tiles are 8 wide and 5 tall, which looks nearly square on a monitor.

local base = require("lib.arcade.base")
local rules = require("games.digdug.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local COLS, ROWS = rules.COLS, rules.ROWS
local CELL_W, CELL_H = 8, 5
local PUMP_X, PUMP_W = 76, 44 -- right of UP, and clear of QUIT because it stays in the top row of buttons

-- Dirt by layer, with the flecks that give it some grain.
local LAYERS = { C.hi, C.warn, C.red, C.redTint }
local FLECKS = { C.warn, C.red, C.redTint, C.hiTint }

local INK = {
  ["h"] = C.hi, ["w"] = C.text, ["b"] = C.blue, ["k"] = C.bg, ["o"] = C.warn, ["r"] = C.red, ["g"] = C.ok,
  ["s"] = C.soft, ["l"] = C.line, ["p"] = C.panel, ["a"] = C.accent, ["c"] = C.info,
}

-- Sprites, one string for each row, drawn facing right. A letter is a colour from INK; "." is left as it is.
local DIGGER = {
  { "..hhhh..", ".hhhhhh.", "..wkwk..", ".bbbbooo", ".b...b.." },
  { "..hhhh..", ".hhhhhh.", "..wkwk..", ".bbbbooo", "..b.b..." },
}
local DIGGER_UP = {
  { "..hhhh..", ".hhhhhh.", ".bhhhhb.", "..bbbb..", "..b..b.." },
  { "..hhhh..", ".hhhhhh.", ".bhhhhb.", "..bbbb..", ".b....b." },
}
local DIGGER_DOWN = {
  { "..hhhh..", ".hhhhhh.", "..kwwk..", ".bbbbbb.", "..b..b.." },
  { "..hhhh..", ".hhhhhh.", "..kwwk..", ".bbbbbb.", ".b....b." },
}
local POOKA = {
  { ".a.aa.a.", ".aaaaaa.", "hwkhhwkh", ".aaaaaa.", "..a..a.." },
  { ".a.aa.a.", ".aaaaaa.", "hwkhhwkh", ".aaaaaa.", ".a....a." },
}
local FYGAR = {
  { "..b..cc.", ".bbcckcc", "c.ccccwc", ".cccccc.", "..c..c.." },
  { ".b...cc.", ".bbcckcc", "c.ccccwc", ".cccccc.", ".c....c." },
}
local FYGAR_GLOW = {
  { "..b..oo.", ".boooko.", "o.oooohh", ".oooooo.", "..o..o.." },
  { "..b..rr.", ".brrrkr.", "r.rrrroo", ".rrrrrr.", "..r..r.." },
}
local ROCK = { "..lllw..", ".lllllw.", "lllllllw", ".plllll.", "..pppp.." }
local RUBBLE = { "........", "..l..w..", ".l.pl...", "ll.pl.l.", "plpllpl." }
local VEGETABLE = { "...gg...", "..sgg...", ".oooooo.", "..oooo..", "...oo..." }

local function mirrored(sprite)
  local out = {}
  for i, line in ipairs(sprite) do out[i] = line:reverse() end
  return out
end

local function bothWays(frames)
  local out = { right = frames, left = {} }
  for i, frame in ipairs(frames) do out.left[i] = mirrored(frame) end
  return out
end

local DIGGER_WAYS = bothWays(DIGGER)
local POOKA_WAYS = bothWays(POOKA)
local FYGAR_WAYS = bothWays(FYGAR)
local GLOW_WAYS = bothWays(FYGAR_GLOW)

local function tileX(L, x) return L.x0 + (x - 1) * CELL_W end
local function tileY(L, y) return L.y0 + (y - 1) * CELL_H end

--- Where an actor shows: on its way from the last tile, so a step of the clock can show half a tile.
local function actorAt(L, a)
  local t = 1
  if a.speed and (a.px ~= a.x or a.py ~= a.y) then t = math.min(1, (a.budget + a.speed) / 100) end
  return floor(tileX(L, a.px + (a.x - a.px) * t) + 0.5), floor(tileY(L, a.py + (a.y - a.py) * t) + 0.5)
end

local function drawSprite(sprite, x, y)
  for row, line in ipairs(sprite) do
    local from = 1
    while from <= #line do
      local ink = line:sub(from, from)
      local to = from
      while line:sub(to + 1, to + 1) == ink do to = to + 1 end
      if ink ~= "." then ui.fill(x + from - 1, y + row - 1, to - from + 1, 1, INK[ink]) end
      from = to + 1
    end
  end
end

--- Sky above a strip of grass, and a flower for each level at the far end, as on a real field.
local function drawSky(L, s)
  ui.fill(L.x0, L.y0, L.bw, CELL_H, C.blueTint)
  ui.fill(L.x0, L.y0 + CELL_H - 1, L.bw, 1, C.ok)
  for i = 1, math.min(s.level, 6) do
    local x = L.x0 + L.bw - i * 4
    ui.fill(x, L.y0 + CELL_H - 2, 1, 1, C.ok)
    ui.fill(x - 1, L.y0 + CELL_H - 3, 3, 1, i % 2 == 0 and C.accent or C.text)
    ui.fill(x, L.y0 + CELL_H - 3, 1, 1, C.hi)
  end
end

--- Dirt in runs along each row. The rest of the board was cleared to black, which is what makes a tunnel.
local function drawDirt(L, s)
  for y = 2, ROWS do
    local layer = rules.layerOf(y)
    local row = s.dirt[y]
    local x = 1
    while x <= COLS do
      if row[x] then
        local from = x
        while row[x + 1] do x = x + 1 end
        ui.fill(tileX(L, from), tileY(L, y), (x - from + 1) * CELL_W, CELL_H, LAYERS[layer])
      end
      x = x + 1
    end
    for tx = 1, COLS do
      if row[tx] then
        local seed = tx * 7 + y * 13
        ui.fill(tileX(L, tx) + seed % 6, tileY(L, y) + seed % 4, 2, 1, FLECKS[layer])
        ui.fill(tileX(L, tx) + (seed * 3) % 7, tileY(L, y) + (seed * 5) % 5, 1, 1, FLECKS[layer])
      end
    end
  end
end

local function drawRocks(L, s)
  for _, r in ipairs(s.rocks) do
    local x, y = tileX(L, r.x), tileY(L, r.y)
    if r.state == "crumble" then
      drawSprite(RUBBLE, x, y)
    else
      -- until it moves, a rock sits in the dirt around it, not in a black hole of its own
      if r.state == "still" then ui.fill(x, y, CELL_W, CELL_H, LAYERS[rules.layerOf(r.y)]) end
      if r.state == "wobble" then x = x + (s.frame % 2 == 0 and -1 or 1) end
      x = math.max(L.x0, math.min(x, L.x0 + L.bw - CELL_W))
      drawSprite(ROCK, x, y)
    end
  end
end

local function drawVegetable(L, s)
  if not s.veg then return end
  -- it flashes for its last two seconds
  if s.veg.left > 20 or s.frame % 2 == 0 then
    drawSprite(VEGETABLE, tileX(L, rules.START[1]), tileY(L, rules.START[2]))
  end
end

--- A line from the digger to the harpoon's tip.
local function drawHarpoon(L, s)
  local pump = s.pump
  if not pump then return end
  local p = s.player
  local d = rules.DIRECTIONS[pump.dir]
  local cx, cy = tileX(L, p.x) + 3, tileY(L, p.y) + 2
  local tipX = cx + d[1] * (pump.len * CELL_W - 2)
  local tipY = cy + d[2] * (pump.len * CELL_H - 2)
  ui.line(cx, cy, tipX, tipY, C.text)
  ui.fill(tipX, tipY, 1, 1, pump.hook and s.frame % 2 == 0 and C.red or C.hi)
end

--- A blown-up enemy, bigger at each stage, kept on the board.
local function drawInflated(L, g)
  local w, h = 8 + g.inflate * 2, 5 + g.inflate
  local x = tileX(L, g.x) + 4 - w / 2
  local y = tileY(L, g.y) + floor(CELL_H / 2) - floor(h / 2)
  x = math.max(L.x0, math.min(x, L.x0 + L.bw - w))
  y = math.max(L.y0, math.min(y, L.y0 + L.bh - h))
  local pooka = g.kind == "pooka"
  base.disc(x, y, w, h, pooka and C.accent or C.info)
  local eyeY = y + floor(h / 3)
  ui.fill(x + floor(w / 4) - 1, eyeY, 3, 1, pooka and C.text or C.hi)
  ui.fill(x + w - floor(w / 4) - 2, eyeY, 3, 1, pooka and C.text or C.hi)
  ui.fill(x + floor(w / 4), eyeY, 1, 1, C.bg)
  ui.fill(x + w - floor(w / 4) - 1, eyeY, 1, 1, C.bg)
end

--- A ghost is only its eyes, on a dark patch, so it shows up on any dirt.
local function drawGhost(x, y, s, g)
  local eye = (g.kind == "pooka" or s.frame % 2 == 0) and C.text or C.soft
  ui.fill(x + 1, y + 1, 6, 3, C.bg)
  ui.fill(x + 1, y + 2, 2, 1, eye)
  ui.fill(x + 5, y + 2, 2, 1, eye)
end

local function drawFlames(L, s, g)
  local d = rules.DIRECTIONS[g.face]
  for i, at in ipairs(rules.flameTiles(s, g)) do
    local x, y = tileX(L, at[1]), tileY(L, at[2])
    local inset = i - 1
    ui.fill(x, y + floor(inset / 2), CELL_W, CELL_H - inset, C.warn)
    ui.fill(x + (d[1] > 0 and 0 or 3), y + 2, 5, 1, C.hi)
    if (s.frame + i) % 2 == 0 then ui.fill(x + 2, y + 1, 3, 1, C.red) end
  end
end

--- The fire's short warning: a glowing body, and sparks growing at its mouth.
local function drawWindup(L, s, g, x, y)
  drawSprite(GLOW_WAYS[g.face][s.frame % 2 + 1], x, y)
  local d = rules.DIRECTIONS[g.face]
  local grown = rules.WINDUP_TICKS - g.t + 1
  local reach = math.min(CELL_W - 1, grown)
  local from = d[1] > 0 and x + CELL_W or x - reach
  if from >= L.x0 and from + reach <= L.x0 + L.bw then ui.fill(from, y + 2, reach, 1, s.frame % 2 == 0 and C.hi or C.warn) end
end

local function drawEnemy(L, s, g)
  if g.inflate > 0 then
    drawInflated(L, g)
    return
  end
  local x, y = actorAt(L, { x = g.x, y = g.y, px = g.px, py = g.py, budget = g.budget, speed = rules.enemySpeed(s.level) })
  local inDirt = s.dirt[g.y] and s.dirt[g.y][g.x]
  if g.mode == "windup" then
    drawWindup(L, s, g, x, y)
  elseif g.mode == "ghost" or inDirt then
    drawGhost(x, y, s, g)
  else
    local moving = s.frame % 4 < 2 and 1 or 2
    drawSprite((g.kind == "pooka" and POOKA_WAYS or FYGAR_WAYS)[g.face][moving], x, y)
  end
end

local function drawBursts(L, s)
  for _, b in ipairs(s.bursts) do
    local x, y = tileX(L, b.x), tileY(L, b.y)
    local spread = 4 - b.left
    local color = b.kind == "pooka" and C.accent or C.info
    ui.fill(x + 3 - spread, y + 2, 1, 1, color)
    ui.fill(x + 4 + spread, y + 2, 1, 1, color)
    ui.fill(x + 3, y + math.max(0, 2 - spread), 2, 1, C.text)
    ui.fill(x + 3, y + math.min(CELL_H - 1, 2 + spread), 2, 1, C.text)
  end
end

--- The digger, or the short spin down that follows a death.
local function drawDigger(L, s)
  local p = s.player
  local x, y = actorAt(L, p)
  if s.after == "life" then
    x, y = tileX(L, p.x), tileY(L, p.y)
    local squash = math.min(4, floor((rules.DEATH_TICKS - s.pause) / 3))
    ui.fill(x + 1, y + squash, 6, CELL_H - squash, s.frame % 2 == 0 and C.text or C.hi)
    return
  end
  local frame = s.frame % 4 < 2 and 1 or 2
  if s.pump or not s.want then frame = 1 end
  if p.dir == "up" then
    drawSprite(DIGGER_UP[frame], x, y)
  elseif p.dir == "down" then
    drawSprite(DIGGER_DOWN[frame], x, y)
  else
    drawSprite(DIGGER_WAYS[p.dir][frame], x, y)
  end
end

local function drawNotes(L, s)
  for _, n in ipairs(s.popups) do
    local x = tileX(L, n.x) + 4
    x = math.max(L.x0 + floor(#n.text / 2), math.min(x, L.x0 + L.bw - math.ceil(#n.text / 2)))
    ui.small(n.text, x, tileY(L, n.y) + 2, C.text, C.bg, "center")
  end
  local cx, cy = L.x0 + floor(L.bw / 2), tileY(L, 3) + 1
  if s.ready then
    ui.small("  LEVEL " .. s.level .. " - READY!  ", cx, cy, C.hi, C.bg, "center")
  elseif s.after == "level" then
    ui.small("  LEVEL CLEAR!  ", cx, cy, C.hi, C.bg, "center")
  end
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, COLS * CELL_W, ROWS * CELL_H)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawSky(L, s)
  drawDirt(L, s)
  drawVegetable(L, s)
  drawRocks(L, s)
  if s.after ~= "level" then
    drawHarpoon(L, s)
    for _, g in ipairs(s.enemies) do
      if not g.carried then
        drawFlames(L, s, g)
        drawEnemy(L, s, g)
      end
    end
  end
  drawDigger(L, s)
  drawBursts(L, s)
  drawNotes(L, s)
end

function view.controls(L)
  local list = base.dpad(L)
  local up = list[1]
  list[#list + 1] = { label = "PUMP", x = PUMP_X, y = up.y, w = PUMP_W, h = up.h, action = { kind = "pump" } }
  return list
end

--- A tap on the board picks the way from the digger to the tap, whichever is further on the screen.
function view.actionAt(L, s, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  local dx = px - (tileX(L, s.player.x) + CELL_W / 2 - 0.5)
  local dy = py - (tileY(L, s.player.y) + CELL_H / 2 - 0.5)
  if math.abs(dx) < CELL_W / 2 and math.abs(dy) < CELL_H / 2 then return nil end
  -- cells are taller than wide, so a cell of height counts for more than a cell of width
  if math.abs(dx) * CELL_H >= math.abs(dy) * CELL_W then
    return { kind = "turn", dir = dx < 0 and "left" or "right" }
  end
  return { kind = "turn", dir = dy < 0 and "up" or "down" }
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
    if ev.type == "dig" then once("placeBlue", 0.25, 0.7) end
    if ev.type == "fire" then once("placeRed", 0.6) end
    if ev.type == "hook" then once("placeBlue", 0.8, 1.2) end
    if ev.type == "inflate" then once("placeRed", 0.8, 0.9 + 0.2 * ev.stage) end
    if ev.type == "pop" then once("capture", 1, 1.3) end
    if ev.type == "wobble" then once("placeBlue", 0.6, 0.6) end
    if ev.type == "land" then once("placeBlue", 1, 0.5) end
    if ev.type == "crush" then once("captureRed", 1, 0.8 + 0.2 * math.min(ev.count, 4)) end
    if ev.type == "windup" then once("captureBlue", 0.5, 0.6) end
    if ev.type == "flame" then once("captureBlue", 0.8, 0.5) end
    if ev.type == "vegOut" then once("captureRed", 0.7) end
    if ev.type == "veg" then once("captureRed", 1, 1.4) end
    if ev.type == "flee" then once("placeRed", 0.7, 1.5) end
    if ev.type == "death" then once("captureBlue", 1, 0.5) end
    if ev.type == "clear" or ev.type == "level" then app.audio.later("capture", 120, 1, 1.5) end
  end
end

return base.fill({
  -- the accent paints the yellow slot, and the top layer of dirt needs that slot to stay yellow
  id = "digdug", title = "Dig Dug", blurb = "Dig, pump, drop the rocks", color = "warn", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Dig through the ground and get rid of every enemy to reach the next level. You have three lives.",
    "",
    "Use the arrows, or tap the board: a tap above, below or to either side of the digger sends him that way. He keeps going, so PUMP is how you stop.",
    "",
    "PUMP fires a short harpoon the way you face. It stops at dirt. If it hooks an enemy, keep tapping PUMP: four more taps pop it. Stop, or tap an arrow to let go, and the enemy shrinks back and gets free.",
    "",
    "Dig under a rock and move away: it wobbles, then falls. It crushes anything below, for big points, and more for each one it takes down. It will crush you too.",
    "",
    "Pops are worth more the deeper they are, and a blue Fygar is worth double from the side. Watch for eyes in the dirt: that's a ghost coming straight at you. When a Fygar stops and glows, get off its row.",
    "",
    "Drop two rocks and a vegetable grows at the centre, for a while. The last enemy runs for the surface: if it gets away, the level still ends, but you lose the points.",
  },
})
