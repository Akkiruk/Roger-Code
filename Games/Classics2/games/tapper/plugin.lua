-- games/tapper/plugin.lua
-- Tapper as an Arcade classic. There are no buttons: the wall is the four bars. A tap on a bar pours on it, and a tap on an
-- empty mug or a tip goes to fetch it. Above the bars is the stage, where the dancers come out.

local base = require("lib.arcade.base")
local rules = require("games.tapper.rules")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor = math.floor
local WIDTH, HEIGHT, BARS, STAGE_H, LANE_H = rules.WIDTH, rules.HEIGHT, rules.BARS, rules.STAGE_H, rules.LANE_H
local TAP_X = rules.TAP_X

local SPRITE_Y = 1       -- on a lane, where a figure's head starts
local ITEM_Y = 6         -- where a mug or a beer stands
local COUNTER_Y = 9      -- the top edge of the bar
local COUNTER_H = 4
local KEG_X = 112
local FETCH_HIT = 8      -- how near a mug or a tip a tap must land to go for it instead of pouring
local TIP_WARN = 20      -- a tip flashes for its last two seconds
local DOOR_W = 6
local STAGE_W = 68       -- how far the curtains open

local INK = {
  ["w"] = C.text, ["k"] = C.bg, ["s"] = C.warn, ["y"] = C.hi, ["l"] = C.line, ["r"] = C.red, ["p"] = C.accent,
  ["c"] = C.info, ["g"] = C.ok, ["b"] = C.blue, ["t"] = C.redTint,
}

-- Sprites, one string for each row. A letter is a colour from INK; "." is left as it is. H is the hat, B the shirt: they
-- change with the customer's look.
local CUSTOMER = {
  { "..HHHH..", ".HHHHHH.", ".ssssks.", ".ssssss.", ".BBBBBs.", "sBBBBBs.", ".BBBBB..", ".BBBBB.." },
  { "..HHHH..", ".HHHHHH.", ".ssssks.", ".ssssss.", "sBBBBB..", ".BBBBBss", ".BBBBB..", ".BBBBB.." },
}
local CUSTOMER_DRINK = { "..HHHH..", ".HHHHHH.", ".ssssks.", ".ssssswww", ".BBBBsyy", "sBBBBsyy", ".BBBBB..", ".BBBBB.." }
local CUSTOMER_SHOVED = { "..HHHH..", ".HHHHHH.", ".skssks.", ".ssssss.", ".BBBBBww", "sBBBBsyy", ".BBBBsyy", ".BBBBB.." }
local LOOK_COLORS = {
  { C.redTint, C.ok }, { C.blue, C.info }, { C.text, C.accent }, { C.ok, C.red },
}

local BARMAN = {
  { "..kkkk..", ".kkkkkk.", ".skssk..", ".kkkss..", ".wwwwww.", "swwrrwws", ".wwwwww.", ".wwwwww." },
  { "..kkkk..", ".kkkkkk.", ".skssk..", ".kkkss..", "swwwwww.", ".wwrrwws", ".wwwwww.", ".wwwwww." },
}
local BARMAN_POUR = { "..kkkk..", ".kkkkkk.", "..sskss.", "..sskkk.", ".wwwwww.", ".wwrrwss", ".wwwwww.", ".wwwwww." }

local DANCER = {
  { "..yy...", "..ss...", "s.pp.s.", ".pppp..", "..pp...", ".ss.ss.", "s.....s" },
  { "..yy...", "..ss...", ".spps..", "..pp...", ".pppp..", "..s.ss.", "..s...s" },
  { "...yy..", "...ss..", ".spps..", "...pp..", "..pppp.", ".ss.s..", "s...s.." },
}

local BEER = { "www.", "yyyl", "yyyl" }
local MUG = { "wlw.", "wlww", "www." }

local function laneY(L, bar) return L.y0 + STAGE_H + (bar - 1) * LANE_H end

local function drawSprite(sprite, x, y, paint)
  for row, line in ipairs(sprite) do
    local from = 1
    while from <= #line do
      local ink = line:sub(from, from)
      local to = from
      while line:sub(to + 1, to + 1) == ink do to = to + 1 end
      if ink ~= "." then ui.fill(x + from - 1, y + row - 1, to - from + 1, 1, paint and paint[ink] or INK[ink]) end
      from = to + 1
    end
  end
end

--- The dancers kick in turn while they're on. The curtain says how many are left to serve when they aren't.
local function drawStage(L, s)
  ui.fill(L.x0, L.y0, L.bw, STAGE_H, C.redTint)
  ui.fill(L.x0, L.y0 + STAGE_H - 1, L.bw, 1, C.warn)
  for x = 4, WIDTH - 2, 8 do ui.fill(L.x0 + x, L.y0, 2, STAGE_H - 1, C.red) end
  if s.dance > 0 then
    local mid = L.x0 + floor(WIDTH / 2)
    ui.fill(mid - STAGE_W / 2, L.y0, STAGE_W, STAGE_H - 1, C.bg)
    for i = -2, 1 do
      local frame = (floor(s.frame / 2) + i) % #DANCER + 1
      drawSprite(DANCER[frame], mid + i * 14 + 3, L.y0 + 2)
    end
  end
end

local function drawLane(L, bar)
  local y = laneY(L, bar)
  ui.fill(L.x0, y, L.bw, COUNTER_Y, C.panel)
  ui.fill(L.x0, y + COUNTER_Y, L.bw, 1, C.warn)
  ui.fill(L.x0, y + COUNTER_Y + 1, L.bw, COUNTER_H - 1, C.redTint)
  for x = 10, TAP_X, 12 do ui.fill(L.x0 + x, y + COUNTER_Y + 1, 1, COUNTER_H - 1, C.bg) end
  ui.fill(L.x0, y + COUNTER_Y + COUNTER_H, L.bw, LANE_H - COUNTER_Y - COUNTER_H, C.bg)
end

--- The swing doors go on top, so a customer comes through them.
local function drawDoor(L, bar)
  local y = laneY(L, bar)
  ui.fill(L.x0, y, DOOR_W, COUNTER_Y + 1, C.bg)
  ui.fill(L.x0 + DOOR_W - 1, y, 1, COUNTER_Y + 1, C.warn)
  ui.fill(L.x0 + 1, y + 3, DOOR_W - 2, 4, C.warn)
  ui.fill(L.x0 + 2, y + 4, 1, 2, C.redTint)
end

--- The keg behind the bartender, with its spout over the bar.
local function drawKeg(L, bar)
  local y = laneY(L, bar)
  local x = L.x0 + KEG_X
  ui.fill(x, y + 2, 7, COUNTER_Y - 2, C.warn)
  ui.fill(x + 1, y + 1, 5, 1, C.warn)
  ui.fill(x, y + 3, 7, 1, C.redTint)
  ui.fill(x, y + 7, 7, 1, C.redTint)
  ui.fill(x - 1, y + 5, 2, 1, C.line)
end

local function drawCustomer(L, s, c)
  local x, y = L.x0 + floor(c.x), laneY(L, c.bar) + SPRITE_Y
  local look = LOOK_COLORS[c.look]
  local paint = { H = look[1], B = look[2], s = C.warn, k = C.bg, w = C.text, y = C.hi }
  if c.state == "shoved" then
    drawSprite(CUSTOMER_SHOVED, x, y, paint)
  elseif c.state == "drink" then
    drawSprite(CUSTOMER_DRINK, x, y, paint)
  else
    local frame = c.stride and 2 or 1
    -- they turn to watch the dancers
    if s.dance > 0 then frame = floor(s.frame / 3) % 2 + 1 end
    drawSprite(CUSTOMER[frame], x, y, paint)
  end
end

local function drawBarman(L, s)
  local man = s.man
  local x, y = L.x0 + floor(man.x), laneY(L, man.bar) + SPRITE_Y
  if s.pouring > 0 then
    drawSprite(BARMAN_POUR, x, y)
    -- the mug fills under the spout
    local full = math.min(2, s.pouring)
    ui.fill(x + 6, laneY(L, man.bar) + ITEM_Y, 3, 3, C.line)
    ui.fill(x + 6, laneY(L, man.bar) + ITEM_Y + 3 - full, 3, full, C.hi)
  else
    drawSprite(BARMAN[man.dir ~= 0 and floor(s.frame / 2) % 2 + 1 or 1], x, y)
  end
end

local function drawTip(L, s, tip)
  if tip.left <= TIP_WARN and s.frame % 2 == 0 then return end
  local x, y = L.x0 + floor(tip.x), laneY(L, tip.bar) + COUNTER_Y - 2
  ui.fill(x - 2, y, 5, 2, C.ok)
  ui.small("$", x, y, C.bg, C.ok)
end

local function drawCrash(L, s)
  local c = s.crash
  if not c then return end
  local x, y = L.x0 + floor(c.x), laneY(L, c.bar) + ITEM_Y
  local spread = s.frame % 2 == 0 and 2 or 3
  ui.fill(x - 4, y, 9, 3, C.red)
  ui.fill(x - 2 - spread, y + 1, 5 + spread * 2, 1, C.hi)
  ui.fill(x - 1, y - 1 - spread, 3, 5 + spread * 2, C.hi)
  ui.fill(x, y, 1, 3, C.text)
end

local function drawNotes(L, s)
  for _, n in ipairs(s.notes) do
    local x = math.max(L.x0 + 2, math.min(L.x0 + floor(n.x), L.x0 + WIDTH - 8))
    ui.small(n.text, x, laneY(L, n.bar) + 1, C.hi, C.panel, "center")
  end
end

local SMASHES = { customer = "A CUSTOMER GOT TO THE TAPS", beer = "A BEER WENT OUT THE DOOR", mug = "YOU MISSED A MUG" }

--- Messages go on the stage, so they never cover a bar.
local function drawBanner(L, s)
  local cx, y = L.x0 + floor(WIDTH / 2), L.y0 + 1
  local word, color, line
  if s.after == "ready" then
    word, color, line = "READY", C.hi, "LEVEL " .. s.level .. " - TAP A BAR TO POUR"
  elseif s.after == "life" or (s.over and s.crash) then
    word, color, line = "SMASH!", C.warn, SMASHES[s.crash.what]
  elseif s.after == "level" then
    word, color, line = "CLEAR", C.ok, "ALL SERVED +" .. rules.CLEAR
  end
  if not word then return end
  ui.fill(cx - STAGE_W / 2, L.y0, STAGE_W, STAGE_H - 1, C.bg)
  ui.text(word, cx, y, color, "center")
  ui.small(line, cx, L.y0 + STAGE_H - 3, C.text, C.bg, "center")
end

--- How many are left to serve, at the end of the stage.
local function drawLeft(L, s)
  ui.small(" LEFT " .. (s.waiting + #s.customers) .. " ", L.x0 + 1, L.y0 + 1, C.text, C.bg)
end

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, WIDTH, HEIGHT)
end

function view.draw(L, s)
  drawStage(L, s)
  for bar = 1, BARS do drawLane(L, bar) end
  for _, c in ipairs(s.customers) do drawCustomer(L, s, c) end
  for bar = 1, BARS do
    drawDoor(L, bar)
    drawKeg(L, bar)
  end
  for _, tip in ipairs(s.tips) do drawTip(L, s, tip) end
  for _, b in ipairs(s.beers) do drawSprite(BEER, L.x0 + floor(b.x), laneY(L, b.bar) + ITEM_Y) end
  for _, m in ipairs(s.mugs) do drawSprite(MUG, L.x0 + floor(m.x), laneY(L, m.bar) + ITEM_Y) end
  drawBarman(L, s)
  drawNotes(L, s)
  drawCrash(L, s)
  drawLeft(L, s)
  drawBanner(L, s)
end

--- The bar under a tap. The stage counts as the top bar and the strip under the board as the bottom one, so every tap on the
-- wall lands somewhere.
local function barAt(L, py)
  local bar = floor((py - L.y0 - STAGE_H) / LANE_H) + 1
  return math.max(1, math.min(BARS, bar))
end

--- A tap on a mug or a tip goes for it. Anywhere else on a bar, it pours. QUIT is a button, so the shell takes that first.
function view.actionAt(L, s, px, py)
  local bar = barAt(L, py)
  local item = rules.fetchAt(s, bar, px - L.x0, FETCH_HIT)
  if item then return { kind = "go", bar = bar, x = item.x } end
  return { kind = "pour", bar = bar }
end

function view.controls()
  return {}
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
    if ev.type == "pour" then once("placeBlue", 0.7, 1.2) end
    if ev.type == "drink" then once("placeRed", 0.5, 0.8) end
    if ev.type == "served" then once("capture", 0.8, 1.2) end
    if ev.type == "empty" then once("placeBlue", 0.4, 0.6) end
    if ev.type == "catch" then once("captureBlue", 0.9, 1.1) end
    if ev.type == "tip" then once("captureRed", 1, 1.4) end
    if ev.type == "smash" then app.audio.play("captureBlue", 1, 0.5) end
    if ev.type == "clear" then app.audio.later("capture", 120, 1, 1.5) end
  end
end

return base.fill({
  id = "tapper", title = "Tapper", blurb = "Keep the beer sliding, catch every mug", color = "warn", accent = 0xFFD257,
  action = true, tickMs = 100, minSize = { w = 120, h = 78 },
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "Four bars, and thirsty customers coming down all of them. Tap a bar: the bartender runs there and slides a beer down it. Tap the same bar and he pours again. Taps wait their turn, so tap as fast as you like.",
    "",
    "A beer stops a customer and pushes them back toward the door. Push them out and they're served. If not, they drink, slide the empty mug back to you, and come on again.",
    "",
    "Tap an empty mug to go and catch it without pouring. If it reaches the taps with you on another bar, it smashes.",
    "",
    "A customer who reaches the taps smashes the game. So does a beer that gets to the door with nobody to drink it. A mug, a beer or a customer: each one costs a life, and you have three.",
    "",
    "Customers sometimes leave a tip on the bar. Tap it and he walks out for it: big points, and the dancers come out and hold the customers still for a moment.",
    "",
    "Serve everyone to clear the level. Each level brings more customers, faster.",
  },
})
