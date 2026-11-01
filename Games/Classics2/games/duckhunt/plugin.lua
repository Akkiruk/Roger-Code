-- games/duckhunt/plugin.lua
-- Duck Hunt as an Arcade classic. No buttons: a tap is the gun, and the sky is the target.

local base = require("lib.arcade.base")
local rules = require("games.duckhunt.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local WIDTH, HEIGHT, GRASS_Y, DUCKS = rules.WIDTH, rules.HEIGHT, rules.GRASS_Y, rules.DUCKS

local DIRT_Y = GRASS_Y + 14   -- where the grass ends and the ground under the score boxes begins
local DOG_DOWN = GRASS_Y + 6  -- the top of the dog when he's out of sight
local DOG_UP = GRASS_Y - 13   -- and when he's up
local TEXT_Y = 12             -- the top of a banner, on the board: under TOUCH TO PLAY, and clear of the final GAME OVER

-- Sprites, one letter to a monitor cell, with a dot for nothing. A cell is taller than it's wide, so these look squarer
-- than this. All face right. Each letter is a colour: see DUCK_PAINT and DOG_PAINT.
local DUCK_FLAP = {
  {
    "...WWW.......",
    "...WWWW......",
    "....WWWW..HH.",
    ".....WWW.HEHY",
    "BB..BBWWBRHH.",
    ".BBBBBBBBBR..",
    "..BBBBBBBB...",
    "....BBBB.....",
  },
  {
    ".............",
    ".............",
    "..........HH.",
    "...WWWWW.HEHY",
    "BB.WWWWWBRHH.",
    ".BBBBBBBBBR..",
    "..BBBBBBBB...",
    "....BBBB.....",
  },
  {
    ".............",
    ".............",
    "..........HH.",
    ".........HEHY",
    "BB..BBBBBRHH.",
    ".BBBWWWWBBR..",
    "..BBWWWWBB...",
    "....WWWW.....",
  },
}

local DUCK_HIT = {
  ".W.........W.",
  ".WW.HHHHH.WW.",
  ".WWWHEHEHWWW.",
  "..WWHHYHHWW..",
  "...WWBBBWW...",
  "....BBBBB....",
  ".....BBB.....",
  ".....F.F.....",
}

local DUCK_FALL = {
  "....F...F....",
  ".....BBB.....",
  "...WBBBBBW...",
  "...WBBBBBW...",
  "....BBBBB....",
  ".....HHH.....",
  ".....HEH.....",
  "......Y......",
}

local DUCK_AWAY = {
  {
    "W....HHH....W",
    "WW...HHH...WW",
    ".WW.BBBBB.WW.",
    "..WWBBBBBWW..",
    "....BBBBB....",
    ".....BBB.....",
    ".....F.F.....",
  },
  {
    ".....HHH.....",
    ".....HHH.....",
    "....BBBBB....",
    "..WWBBBBBWW..",
    ".WW.BBBBB.WW.",
    "WW...BBB...WW",
    ".....F.F.....",
  },
}

local DOG_HAPPY = {
  "...DD.......DD...",
  "..DDDDTTTTTDDDD..",
  ".DDDDTTTTTTTDDDD.",
  ".DDDTTNTTTNTTDDD.",
  ".DD.TTNTTTNTT.DD.",
  ".D..TTTTTTTTT..D.",
  ".....WWWNWWW.....",
  ".....WWWWWWW.....",
  ".....WDDDDDW.....",
  "......WWWWW......",
  "......TTTTT......",
  ".....TTTTTTT.....",
  "....TTTWWWTTT....",
  "....TTTWWWTTT....",
  "....TTTTTTTTT....",
  "....TTTTTTTTT....",
}

local DOG_LAUGH = {
  "...DD.......DD...",
  "..DDDDTTTTTDDDD..",
  ".DDDDTTTTTTTDDDD.",
  ".DDDTTTTTTTTTDDD.",
  ".DD.TNNTTTNNT.DD.",
  ".D..TTTTTTTTT..D.",
  ".....WWWNWWW.....",
  "....WDDDDDDDW....",
  "....WDRRRRRDW....",
  ".....WDRRRDW.....",
  "......WWWWW......",
  ".....TTTTTTT.....",
  "....TTTWWWTTT....",
  "...TTTTWWWTTTT...",
  "...TT.TTTTT.TT...",
  "....TTTTTTTTT....",
}

local DOG_RUN = {
  {
    "............DD...",
    "T..........DDTTT.",
    ".T.........DTNTTN",
    "..TTTTTTTTTTTTTT.",
    "..TTTTTTTTTTTTD..",
    "..TTT......TTT...",
    ".TT.TT.....T.TT..",
    ".T...T.....T..T..",
  },
  {
    "............DD...",
    "T..........DDTTT.",
    ".T.........DTNTTN",
    "..TTTTTTTTTTTTTT.",
    "..TTTTTTTTTTTTD..",
    "..TTT......TTT...",
    "..T.TT...TT.T....",
    ".T...T..T....T...",
  },
}

local TALLY_ICON = {
  "..##",
  "###.",
}

--- A sprite as runs of one colour, facing either way, so a row with one solid stretch is one fill.
local function runs(lines, flip)
  local out = { w = #lines[1], h = #lines }
  for y, line in ipairs(lines) do
    local x = 1
    while x <= #line do
      local key = line:sub(x, x)
      local stop = x
      while line:sub(stop + 1, stop + 1) == key do stop = stop + 1 end
      if key ~= "." then
        local left = flip and (#line - stop) or (x - 1)
        out[#out + 1] = { x = left, y = y - 1, w = stop - x + 1, key = key }
      end
      x = stop + 1
    end
  end
  return out
end

--- Both ways round: [1] faces right, [2] faces left.
local function bothWays(lines)
  return { runs(lines), runs(lines, true) }
end

for i, frame in ipairs(DUCK_FLAP) do DUCK_FLAP[i] = bothWays(frame) end
for i, frame in ipairs(DUCK_AWAY) do DUCK_AWAY[i] = runs(frame) end
for i, frame in ipairs(DOG_RUN) do DOG_RUN[i] = runs(frame) end
DUCK_HIT, DUCK_FALL = runs(DUCK_HIT), bothWays(DUCK_FALL)
DOG_HAPPY, DOG_LAUGH = runs(DOG_HAPPY), runs(DOG_LAUGH)
TALLY_ICON = runs(TALLY_ICON)

local FLAP_ORDER = { 1, 2, 3, 2 } -- wing up, level, down, level

local DUCK_PAINT = {
  { B = C.bg, W = C.line, H = C.ok, R = C.text, E = C.text, Y = C.hi, F = C.warn },
  { B = C.blue, W = C.blueTint, H = C.blueTint, R = C.text, E = C.text, Y = C.hi, F = C.warn },
  { B = C.red, W = C.redTint, H = C.redTint, R = C.text, E = C.text, Y = C.hi, F = C.warn },
}

local DOG_PAINT = { T = C.warn, D = C.redTint, W = C.text, N = C.bg, R = C.red }

-- How far each column of grass stops short of the top, repeating, so its edge is blades and not a line.
local BLADES = { 2, 0, 1, 3, 1, 0, 2, 4, 3, 1, 0, 1, 3, 2, 0, 2, 4 }

--- Draw a sprite with its top left at a board position. Anything above the board is left off, so the header stays clear.
local function sprite(L, shape, x, y, paint)
  x, y = floor(x), floor(y)
  for _, run in ipairs(shape) do
    if y + run.y >= 0 then
      ui.fill(L.x0 + x + run.x, L.y0 + y + run.y, run.w, 1, paint[run.key] or paint)
    end
  end
end

local function drawSky(L, s)
  ui.fill(0, L.y0, L.W, DIRT_Y, s.fled and C.warn or C.info)
  local x, y = L.x0, L.y0
  -- the tree
  ui.fill(x + 19, y + 20, 7, 32, C.redTint)
  ui.fill(x + 17, y + 46, 11, 6, C.redTint)
  ui.ellipse(x + 2, y + 1, 26, 19, C.ok)
  ui.ellipse(x + 18, y, 26, 21, C.ok)
  ui.ellipse(x + 8, y + 12, 32, 16, C.ok)
  ui.fill(x + 12, y + 8, 3, 1, C.hiTint)
  ui.fill(x + 30, y + 6, 4, 1, C.hiTint)
  ui.fill(x + 22, y + 14, 3, 1, C.hiTint)
  ui.fill(x + 14, y + 19, 4, 1, C.hiTint)
  ui.fill(x + 32, y + 18, 3, 1, C.hiTint)
  -- the bush
  ui.ellipse(x + 86, y + 33, 28, 22, C.ok)
  ui.ellipse(x + 80, y + 40, 16, 14, C.ok)
  ui.fill(x + 94, y + 39, 4, 1, C.hiTint)
  ui.fill(x + 103, y + 43, 3, 1, C.hiTint)
end

local function drawDuck(L, d)
  local left, top = d.x - 6, d.y - 4
  local paint = DUCK_PAINT[d.kind]
  local way = d.vx >= 0 and 1 or 2
  if d.state == "fly" then
    sprite(L, DUCK_FLAP[FLAP_ORDER[floor(d.frame / 2) % 4 + 1]][way], left, top, paint)
  elseif d.state == "hit" then
    sprite(L, DUCK_HIT, left, top, paint)
  elseif d.state == "fall" then
    sprite(L, DUCK_FALL[floor(d.frame / 2) % 2 + 1], left, top, paint)
  else
    sprite(L, DUCK_AWAY[floor(d.frame / 2) % 2 + 1], left, top, paint)
  end
  -- what it paid, by the duck until it lands
  if d.points then
    ui.small(d.points, L.x0 + floor(d.x), L.y0 + math.max(0, floor(d.y) - 6), C.text, C.bg, "center")
  end
end

--- A duck held up by the feet, on a raised arm to one side of the dog.
local function drawHeld(L, duck, dogX, top, side)
  local armX = dogX + (side > 0 and 7 or -8)
  ui.fill(L.x0 + armX, L.y0 + top + 3, 2, 10, C.warn)
  ui.fill(L.x0 + armX + (side > 0 and -1 or 1), L.y0 + top + 11, 2, 2, C.warn)
  sprite(L, DUCK_FALL[1], armX - 5, top - 5, DUCK_PAINT[duck.kind])
end

local function drawDog(L, s)
  local dog = s.dog
  if not dog then return end
  local rise = rules.DOG_RISE
  local up = math.min(1, math.min(dog.t, dog.steps - dog.t) / rise)
  local top = DOG_DOWN + (DOG_UP - DOG_DOWN) * up
  if dog.kind == "laugh" then
    local bob = dog.t % 4 < 2 and 0 or 1
    sprite(L, DOG_LAUGH, dog.x - 8 + bob, top + bob, DOG_PAINT)
  else
    sprite(L, DOG_HAPPY, dog.x - 8, top, DOG_PAINT)
    if dog.ducks[1] then drawHeld(L, dog.ducks[1], dog.x, floor(top), 1) end
    if dog.ducks[2] then drawHeld(L, dog.ducks[2], dog.x, floor(top), -1) end
  end
end

--- At the start of a round the dog runs in along the grass and leaps into it. Past that point he's behind the grass.
local function runningDog(s)
  if s.phase ~= "intro" then return nil end
  local t = 1 - s.wait / rules.INTRO_STEPS
  local run = math.min(1, t / 0.7)
  local leap = math.max(0, (t - 0.7) / 0.3)
  return 2 + run * 44 + leap * 16, GRASS_Y + 4 - 18 * leap * (1 - leap) * 2 - leap * 4, leap > 0.5
end

local function drawRunner(L, s, behind)
  local x, y, isBehind = runningDog(s)
  if x and isBehind == behind then sprite(L, DOG_RUN[floor(s.wait / 2) % 2 + 1], x, y, DOG_PAINT) end
end

local function drawGrass(L)
  local top = L.y0 + GRASS_Y
  for x = 0, L.W - 1 do
    local cut = BLADES[x % #BLADES + 1]
    ui.fill(x, top + cut, 1, DIRT_Y - GRASS_Y - cut, C.ok)
    ui.fill(x, top + cut, 1, 1, C.soft)
    local tuft = BLADES[(x + 6) % #BLADES + 1]
    ui.fill(x, top + 6 + tuft, 1, 2, C.soft)
  end
  ui.fill(0, L.y0 + DIRT_Y, L.W, HEIGHT - DIRT_Y, C.redTint)
end

--- Where the last shot went off, for a moment, so a tap can be seen to have landed.
local function drawFlash(L, s)
  local flash = s.flash
  if not flash or s.clock - flash.at > 2 then return end
  local x, y = L.x0 + floor(flash.x), L.y0 + floor(flash.y)
  local color = flash.hit and C.hi or C.text
  ui.fill(x - 2, y, 5, 1, color)
  ui.fill(x, y - 1, 1, 3, color)
end

local function box(x, y, w, label)
  ui.fill(x, y, w, 8, C.bg)
  ui.small(label, x + floor(w / 2), y + 1, C.line, C.bg, "center")
end

--- The round's ten ducks, marked as they go, with bars under the ones the quota needs.
local function drawTally(s, x, y)
  for i = 1, DUCKS do
    local mark = s.tally[i]
    local color = C.panel
    if mark == "hit" then
      color = C.ok
    elseif mark == "miss" then
      color = C.red
    elseif mark == "fly" then
      color = s.clock % 4 < 2 and C.text or C.line
    end
    local left = x + (i - 1) * 5
    for _, run in ipairs(TALLY_ICON) do ui.fill(left + run.x, y + run.y, run.w, 1, color) end
    if i <= s.quota then ui.fill(left, y + 3, 4, 1, C.info) end
  end
end

--- The strip along the bottom, as the original has it: round, shots, the tally, and what's needed. It stops short of QUIT.
local function drawStrip(L, s)
  local y = L.y0 + HEIGHT - 9
  box(2, y, 11, "ROUND")
  ui.small(s.level, 7, y + 4, C.text, C.bg, "center")
  box(14, y, 16, "SHOT")
  for i = 1, rules.SHOTS do
    ui.fill(12 + i * 4, y + 3, 3, 3, i <= s.shots and C.hi or C.panel)
  end
  box(31, y, 56, "HIT")
  drawTally(s, 34, y + 3)
  box(88, y, 17, "NEED")
  ui.small(s.quota .. " OF " .. DUCKS, 96, y + 4, C.text, C.bg, "center")
end

local function banner(L, big, small, color)
  local cx = L.x0 + floor(WIDTH / 2) + 8
  local y = L.y0 + TEXT_Y
  local w = math.max(ui.textWidth(big), #(small or "")) + 8
  ui.fill(cx - floor(w / 2), y, w, small and 13 or 10, C.bg)
  ui.text(big, cx, y + 2, color, "center")
  if small then ui.small(small, cx, y + 10, C.text, C.bg, "center") end
end

local function drawBanner(L, s)
  if s.phase == "intro" then
    banner(L, "ROUND " .. s.level, "GET " .. s.quota .. " OF " .. DUCKS, C.hi)
  elseif s.fled then
    banner(L, "FLY AWAY", nil, C.warn)
  elseif s.phase == "tally" then
    local r = s.result
    local line = r.hits .. " HIT, NEEDED " .. r.quota
    if r.perfect then
      banner(L, "PERFECT!", "BONUS " .. rules.PERFECT_BONUS, C.hi)
    elseif r.passed then
      banner(L, "ROUND CLEAR", line, C.ok)
    else
      banner(L, "NOT ENOUGH", line, C.red)
    end
  end
end

local view = {}

--- The board takes the wall. TOUCH TO PLAY has no room under it, so on the idle screen it goes at the top of the sky.
function view.layout(W, H)
  local L = base.actionLayout(W, H, WIDTH, HEIGHT)
  L.statusY = L.y0 + 2
  return L
end

function view.draw(L, s)
  drawSky(L, s)
  for _, d in ipairs(s.ducks) do drawDuck(L, d) end
  drawDog(L, s)
  drawRunner(L, s, true)
  drawGrass(L)
  drawRunner(L, s, false)
  drawFlash(L, s)
  drawStrip(L, s)
  drawBanner(L, s)
end

--- No buttons: every tap is a shot, so there's nothing else to reach for.
function view.controls()
  return {}
end

--- A tap on the board goes to the rules, which decide whether it's in the sky.
function view.actionAt(L, _, px, py)
  if px < L.x0 or px >= L.x0 + L.bw or py < L.y0 or py >= L.y0 + L.bh then return nil end
  return { kind = "shoot", x = px - L.x0, y = py - L.y0 }
end

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    if ev.type == "shot" then app.audio.play("placeBlue", 1, 0.7) end
    if ev.type == "hit" then app.audio.play("capture", 1, 0.9 + 0.15 * ev.kind) end
    if ev.type == "flyaway" then app.audio.play("placeRed", 1, 0.55) end
    if ev.type == "fetch" then app.audio.play("captureRed", 0.7) end
    if ev.type == "laugh" then
      app.audio.play("placeRed", 0.8, 1.4)
      app.audio.later("placeRed", 160, 0.8, 1.2)
      app.audio.later("placeRed", 320, 0.8, 1.4)
    end
    if ev.type == "clear" then
      app.audio.play("captureBlue")
      app.audio.later("capture", 130)
      app.audio.later("captureRed", 260)
    end
    if ev.type == "perfect" then app.audio.later("captureRed", 400, 1, 1.4) end
    if ev.type == "short" then app.audio.play("placeBlue", 1, 0.55) end
  end
end

return base.fill({
  id = "duckhunt", title = "Duck Hunt", blurb = "Three shots, and the dog is watching", color = "info", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 118, h = 81 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Tap a duck to shoot it. Your finger is the gun, and you don't need to lead: tap where you see it.",
    "",
    "A round is ten ducks, sent up one or two at a time. Each time you get three shots. Out of shots, or too slow, and they fly away.",
    "",
    "A tap on the grass or the ground fires nothing and costs nothing. Taps while ducks fall or the dog is up don't count either.",
    "",
    "Black ducks are worth 500, blue 1000 and red 1500, and the faster the duck the more it pays. A perfect ten pays 10000.",
    "",
    "The bars under the tally show how many hits you need, from 6 of 10 up to 9. Miss that and the run is over.",
  },
})
