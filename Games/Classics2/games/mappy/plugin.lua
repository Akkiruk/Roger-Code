-- games/mappy/plugin.lua
-- Mappy as an Arcade classic. The whole mansion fits the wall, one rules cell to one wall cell, so nothing has to scroll and
-- a cat three floors away can be seen coming. Sides of the wall walk and jump, top and bottom stop, the middle works doors.

local base = require("lib.arcade.base")
local rules = require("games.mappy.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local WIDTH, HEIGHT, FLOOR_Y = rules.WIDTH, rules.HEIGHT, rules.FLOOR_Y
local SHAFT_X, SHAFT_W = rules.SHAFT_X, rules.SHAFT_W
local ROOM_H = 9

local INK = {
  ["h"] = C.hi, ["w"] = C.text, ["b"] = C.blue, ["k"] = C.bg, ["o"] = C.warn, ["r"] = C.red, ["g"] = C.ok,
  ["s"] = C.soft, ["l"] = C.line, ["p"] = C.panel, ["a"] = C.accent, ["c"] = C.info,
}

-- Sprites, one string for each row, drawn facing right. A letter is a colour from INK; "." is left as it is.
local MAPPY = {
  { ".bbbb..", "bbhbbb.", ".wwkww.", ".wwwwwk", ".bbbbb.", ".w...w." },
  { ".bbbb..", "bbhbbb.", ".wwkww.", ".wwwwwk", ".bbbbb.", "..w.w.." },
}
local MAPPY_AIR = { "wbbbb.w", "bbhbbbw", ".wwkww.", ".wwwwwk", ".bbbbb.", "..w.w.." }
local MEOWKIE = {
  { ".a...a.", ".aaaaa.", ".wkawka", ".aaaaa.", "a.aaa..", ".a...a." },
  { ".a...a.", ".aaaaa.", ".wkawka", ".aaaaa.", "a.aaa..", "..a.a.." },
}
local GORO = {
  { ".r.....r.", ".rrrrrrr.", ".rwkrrwkr", "rrrrrhrrr", "rrrrrrrrr", ".rrrrrrr.", ".rr...rr." },
  { ".r.....r.", ".rrrrrrr.", ".rwkrrwkr", "rrrrrhrrr", "rrrrrrrrr", ".rrrrrrr.", "..rr.rr.." },
}
local GHOST = {
  { "..wwwww..", ".wwwwwww.", "wwkwwwkww", "wwwwwwwww", "wwwkkkwww", "wwwwwwwww", "w.ww.ww.w" },
  { "..wwwww..", ".wwwwwww.", "wwkwwwkww", "wwwwwwwww", "wwwkkkwww", "wwwwwwwww", ".ww.ww.w." },
}
local GOODS = {
  radio = { "...l...", "lllllll", "lkkklwl", "lkkklrl", "lllllll" },
  tv = { "..l.l..", "wwwwwww", "wcccccw", "wcccccw", "wwwwwww" },
  computer = { ".lllll.", ".lgggl.", ".lgggl.", ".lllll.", "sssssss" },
  safe = { "hhhhhhh", "hkkkkkh", "hkkwkkh", "hkkkkkh", "hhhhhhh" },
  balloon = { ".rrr.", "rrwrr", "rrrrr", ".rrr.", "..r..", "..w.." },
}
local BELL = { "..h..", ".hhh.", ".hhh.", "hhhhh" }

-- A trampoline's colour by bounces in a row: green, blue, yellow, red, and the next one goes through.
local WEAR = { [0] = C.ok, [1] = C.ok, [2] = C.blue, [3] = C.hi, [4] = C.red }

local function mirrored(sprite)
  local out = {}
  for i, line in ipairs(sprite) do out[i] = line:reverse() end
  return out
end

local function upsideDown(sprite)
  local out = {}
  for i, line in ipairs(sprite) do out[#sprite - i + 1] = line end
  return out
end

local function bothWays(frames)
  local out = { right = frames, left = {} }
  for i, frame in ipairs(frames) do out.left[i] = mirrored(frame) end
  return out
end

local MAPPY_WAYS = bothWays(MAPPY)
local MAPPY_AIR_WAYS = { right = MAPPY_AIR, left = mirrored(MAPPY_AIR) }
local MEOWKIE_WAYS = bothWays(MEOWKIE)
local GORO_WAYS = bothWays(GORO)

--- A sprite whose feet stand on row y, centred on x, in board cells. One that has run off the board isn't drawn at all.
local function drawSprite(L, sprite, x, y)
  local w, h = #sprite[1], #sprite
  local left, top = floor(x + 0.5) - floor(w / 2), floor(y + 0.5) - h
  if left < 0 or left + w > WIDTH or top < 0 then return end
  for row, line in ipairs(sprite) do
    local from = 1
    while from <= #line do
      local ink = line:sub(from, from)
      local to = from
      while line:sub(to + 1, to + 1) == ink do to = to + 1 end
      if ink ~= "." then ui.fill(L.x0 + left + from - 1, L.y0 + top + row - 1, to - from + 1, 1, INK[ink]) end
      from = to + 1
    end
  end
end

--- The roof, with the clock along it: it runs down, and goes red for the warning.
local function drawRoof(L, s)
  ui.fill(L.x0, L.y0, WIDTH, 2, C.redTint)
  local width = floor(WIDTH * math.max(0, s.time) / s.timeMax)
  local late = s.time <= rules.HURRY_TICKS
  local color = s.bonus and C.info or C.ok
  if late then color = s.frame % 2 == 0 and C.red or C.warn end
  if s.ghost then width, color = WIDTH, s.frame % 2 == 0 and C.red or C.text end
  ui.fill(L.x0, L.y0, width, 1, color)
end

--- Rooms, floors and shafts, one stretch of each at a time. The clear board is what shows in the shafts.
local function drawMansion(L)
  for i = 1, #SHAFT_X - 1 do
    local from, to = rules.sectionEnds(i)
    local w = to - from + 1
    for f, y in ipairs(FLOOR_Y) do
      ui.fill(L.x0 + from, L.y0 + y - ROOM_H, w, ROOM_H, C.blueTint)
      ui.fill(L.x0 + from, L.y0 + y, w, 1, C.warn)
      for x = from + (f % 2) * 2, to, 5 do ui.fill(L.x0 + x, L.y0 + y, 1, 1, C.redTint) end
      if f % 2 == i % 2 then
        -- a window in every other room, so a floor can be told from the one above
        ui.fill(L.x0 + from + 3, L.y0 + y - 7, 4, 3, C.bg)
        ui.fill(L.x0 + from + 4, L.y0 + y - 7, 1, 3, C.panel)
        ui.fill(L.x0 + to - 6, L.y0 + y - 7, 4, 3, C.bg)
        ui.fill(L.x0 + to - 5, L.y0 + y - 7, 1, 3, C.panel)
      end
    end
    ui.fill(L.x0 + from, L.y0 + FLOOR_Y[#FLOOR_Y] + 1, w, HEIGHT - FLOOR_Y[#FLOOR_Y] - 1, C.redTint)
  end
end

local function drawTrampolines(L, s)
  for i, tramp in ipairs(s.tramps) do
    local x, y = L.x0 + SHAFT_X[i], L.y0 + rules.TRAMPOLINE_Y
    ui.fill(x, y, 1, 2, C.line)
    ui.fill(x + SHAFT_W - 1, y, 1, 2, C.line)
    if tramp.broken then
      ui.fill(x + 1, y, 2, 1, C.line)
      ui.fill(x + SHAFT_W - 3, y, 2, 1, C.line)
    else
      ui.fill(x + 1, y, SHAFT_W - 2, 1, WEAR[math.min(tramp.hits, 4)])
    end
  end
end

--- A closed door shows its knob on the side it swings to. An open one stands out on that side.
local function drawDoor(L, s, d)
  local x, y = L.x0 + d.x, L.y0 + FLOOR_Y[d.floor]
  local way = rules.DIRS[d.swing]
  local panel = d.power and (s.frame % 2 == 0 and C.accent or C.info) or C.warn
  if d.open then
    ui.fill(x, y - 8, 1, 8, C.redTint)
    for i = 1, 5 do
      local inset = floor(i / 2)
      ui.fill(x + i * way, y - 8 + inset, 1, 8 - 2 * inset, i == 5 and panel or C.redTint)
    end
    return
  end
  ui.fill(x - 1, y - 8, 3, 8, panel)
  ui.fill(x - 1, y - 8, 3, 1, C.redTint)
  ui.fill(x + way, y - 5, 1, 2, C.bg)
end

local function drawBells(L, s)
  for _, b in ipairs(s.bells) do
    local top = FLOOR_Y[b.floor] - ROOM_H + #BELL
    local y = top
    if b.state == "fall" then
      y = top + (ROOM_H - #BELL) * (rules.BELL_TICKS - b.t + 1) / rules.BELL_TICKS
    elseif b.state == "rest" then
      y = FLOOR_Y[b.floor]
    end
    if b.state == "hang" then ui.fill(L.x0 + b.x, L.y0 + top - #BELL, 1, 1, C.line) end
    drawSprite(L, BELL, b.x, y)
  end
end

--- Goods stand on the floor, and balloons float. What would make a pair with the last pick-up has a glint along its top.
local function drawGoods(L, s)
  for _, good in ipairs(s.goods) do
    local sprite = GOODS[good.kind]
    local y = good.shaft and good.y or FLOOR_Y[good.floor]
    drawSprite(L, sprite, good.x, y)
    if good.kind == s.lastKind then ui.fill(L.x0 + good.x - 3, L.y0 + y - #sprite - 1, 7, 1, s.frame % 4 < 2 and C.hi or C.text) end
    if good.goro and s.frame % 8 < 5 then
      -- Goro's ears, over the top of what he's hiding in
      ui.fill(L.x0 + good.x - 3, L.y0 + y - #sprite - 1, 1, 1, C.red)
      ui.fill(L.x0 + good.x + 3, L.y0 + y - #sprite - 1, 1, 1, C.red)
    end
  end
end

local function drawWaves(L, s)
  for _, w in ipairs(s.waves) do
    local y = L.y0 + FLOOR_Y[w.floor]
    local left, right = math.max(0, w.left), math.min(WIDTH - 1, w.right)
    ui.fill(L.x0 + left, y - 4, right - left + 1, 2, s.frame % 2 == 0 and C.info or C.text)
    ui.fill(L.x0 + left, y - 7, 2, 7, C.text)
    ui.fill(L.x0 + right - 1, y - 7, 2, 7, C.text)
  end
end

local function drawCat(L, s, c)
  if c.mode == "out" or c.mode == "hide" then return end
  local ways = c.kind == "goro" and GORO_WAYS or MEOWKIE_WAYS
  local still = c.stun > 0 or c.wait > 0 or c.mode == "air"
  local frame = ways[c.dir][(not still and s.frame % 4 < 2) and 2 or 1]
  if c.stun > 0 or (c.mode == "fly" and s.frame % 2 == 0) then frame = upsideDown(frame) end
  drawSprite(L, frame, c.x, c.y)
  if c.stun > 0 then
    -- stars going round its head
    local spin = s.frame % 3 * 2
    ui.fill(L.x0 + c.x - 3 + spin, L.y0 + c.y - #frame - 1, 1, 1, C.hi)
  end
end

--- Mappy, or the short flash that follows a catch.
local function drawMappy(L, s)
  local p = s.player
  if s.after == "life" then
    if s.frame % 2 == 0 then drawSprite(L, upsideDown(MAPPY_WAYS[p.dir][1]), p.x, p.y) end
    return
  end
  if p.mode == "air" then
    drawSprite(L, MAPPY_AIR_WAYS[p.dir], p.x, p.y)
  else
    drawSprite(L, MAPPY_WAYS[p.dir][(s.want and s.frame % 4 < 2) and 2 or 1], p.x, p.y)
  end
end

local function drawNotes(L, s)
  for _, n in ipairs(s.popups) do
    local half = floor(#n.text / 2)
    local x = math.max(half, math.min(n.x, WIDTH - #n.text + half))
    local y = math.max(2, math.min(n.y - 8, HEIGHT - 1))
    ui.small(n.text, L.x0 + x, L.y0 + y, C.text, C.bg, "center")
  end
  local cx, cy = L.x0 + floor(WIDTH / 2), L.y0 + 6
  if s.ready then
    ui.small("  " .. (s.bonus and "BONUS ROUND" or ("LEVEL " .. s.level)) .. " - READY!  ", cx, cy, C.hi, C.bg, "center")
  elseif s.after == "level" then
    ui.small(s.bonus and "  BONUS OVER!  " or "  ALL RECOVERED!  ", cx, cy, C.hi, C.bg, "center")
  elseif s.ghost then
    ui.small("  THE GHOST!  ", cx, cy, C.red, C.bg, "center")
  elseif s.time <= rules.HURRY_TICKS and not s.bonus then
    ui.small("  HURRY UP!  ", cx, cy, C.warn, C.bg, "center")
  end
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, WIDTH, HEIGHT)
end

function view.draw(L, s)
  ui.fill(L.x0, L.y0, L.bw, L.bh, C.bg)
  drawRoof(L, s)
  drawMansion(L)
  drawTrampolines(L, s)
  for _, d in ipairs(s.doors) do drawDoor(L, s, d) end
  drawBells(L, s)
  drawGoods(L, s)
  drawWaves(L, s)
  for _, c in ipairs(s.cats) do drawCat(L, s, c) end
  drawMappy(L, s)
  if s.ghost then drawSprite(L, GHOST[s.frame % 4 < 2 and 1 or 2], s.ghost.x, s.ghost.y) end
  drawNotes(L, s)
  base.drawMiddle(L, C.text)
end

--- The whole wall steers: tap the side you want. The middle of the wall is DOOR.
function view.actionAt(L, _, px, py)
  if base.inMiddle(L, px, py) then return { kind = "door" } end
  return base.splitAction(L, px, py)
end

--- A busy step can hold many of one thing: one sound of each is plenty.
-- What each event sounds like. Names are in lib/sound_picks.lua.
local SFX = {
  hop = "hop", good = "pickup", balloon = "pop", allBalloons = "coin", goro = "capture",
  doorOpen = "door_open", doorShut = "door_shut", knock = "knock", belled = "knock", wave = "zap",
  flying = "swish", bell = "bell", clang = "clang", hurry = "ui_warning", ghost = "telegraph",
  death = "death", clear = "level_clear", level = "level_clear", bonus = "level_clear",
  bounce = function(ev) return "bounce", 1, 0.8 + 0.2 * ev.hits end, -- higher as the trampoline wears out
}

function view.onEvents(app, _, events)
  base.sfx(app, events, SFX)
end

return base.fill({
  id = "mappy", title = "Mappy", blurb = "Bounce, slam doors, get the goods back", color = "info",
  action = true, split = true, splitMiddle = "DOOR", tickMs = 140, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "You are Mappy, a police mouse. Get every stolen radio, TV, computer and safe back from the Meowkies' mansion. Get them all to finish the round. You have three lives.",
    "",
    "Tap the side of the wall you want to go: left or right, and he keeps walking. The top or the bottom of the wall stops him. The wall is split corner to corner, so you never have to look away.",
    "",
    "Floors only join up through the trampolines. Walk off the end of a floor and you bounce. While you bounce, tap left or right and he jumps off at the next floor he passes. Tap up or down to call it off.",
    "",
    "Five bounces in a row breaks a trampoline, and it changes colour on the way: green, blue, yellow, red. It heals when you jump off.",
    "",
    "Cats catch you on a floor, or at your height going your way on a trampoline. Passing one in mid-bounce is safe.",
    "",
    "The middle of the wall, between the four marks, is DOOR: it opens or shuts the nearest door you're facing. A closed door stops everyone. It swings to the side its knob is on, and flattens any cat there.",
    "",
    "A flashing door fires a wave along its floor, and every cat on that floor goes flying out of the house for big points. Walk under a bell and it drops behind you, on whatever is chasing you.",
    "",
    "Two of the same goods in a row are worth double, and the next match glints. Goro, the big boss, hides in treasure: pick it up while his ears show for a bonus.",
    "",
    "Take too long and a fast ghost comes for you, through everything. Every fourth round from the third is a bonus round of balloons, with no cats.",
  },
})
