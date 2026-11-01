-- games/oregon/plugin.lua
-- The Oregon Trail as an Arcade classic, saved between visits. Every screen is a picture and some words above a block of
-- buttons, which the shell draws from view.controls; the hunt alone takes taps on the board, as shots.
-- The wagon heads west, so it faces left and the country goes by to the right.

local base = require("lib.arcade.base")
local rules = require("games.oregon.rules")
local text = require("games.oregon.text")
local ui = require("lib.arcade.ui")

local C = ui.C
local floor, max, min = math.floor, math.max, math.min
local HUNT_H, HUNT_SKY = rules.HUNT_H, rules.HUNT_SKY

local BOARD_H = 66     -- rows 7 to 72. QUIT sits under it
local TEXT_W = 113     -- a line of body text
local BUTTON_H, BUTTON_GAP = 8, 1
local BOTTOM = 73      -- the row under the lowest button
local SCENE_H = 27     -- the picture over the trail
local PICTURE_H = 23   -- the shorter one over anything with more to say
local STORE_ROW = 7    -- rows to a line of the store
local NOTICE_Y = 74    -- a remark, on the strip beside QUIT

-- buttons to a row, by screen. Any other screen has one to a row
local ROWS = {
  trail = { 2, 3, 4 }, river = { 2, 2 }, month = { 3, 2 }, pace = { 2, 2 }, rations = { 2, 2 }, rest = { 2, 2 }, trade = { 2 },
}

-- Sprites, one letter to a monitor cell, with a dot for nothing. All face right.
local WAGON = {
  "....WWWWWWWWWWWWW.....",
  "..WWWWWWWWWWWWWWWWW...",
  ".WWWWWWWWWWWWWWWWWWW..",
  ".WWLWWWLWWWLWWWLWWWW..",
  ".WWWWWWWWWWWWWWWWWWW..",
  "BBBBBBBBBBBBBBBBBBBBBB",
  "BBBBBBBBBBBBBBBBBBBBBB",
}

local OX = { "............HH", "..TTTTTTTTTTT.", "TTTTTTTTTTTTTE", "TTTTTTTTTTTT..", ".T.T....T.T...", ".T.T....T.T..." }
local OX_STEP = { OX[1], OX[2], OX[3], OX[4], "..T.T..T.T....", "..T.T..T.T...." }

local BEASTS = {
  bison = {
    "..........DDDD....",
    "........DDDDDDD.H.",
    "..BBBBBBDDDDDDDDH.",
    ".BBBBBBBBDDDDDDDDD",
    "BBBBBBBBBDDDDDDEDD",
    "BBBBBBBBBBDDDDDDD.",
    ".BBBBBBBBBBDDDDD..",
    ".BB..BB....BB.BB..",
    ".BB..BB....BB.BB..",
  },
  bear = {
    "..........NN..",
    "....NNNNNNNNN.",
    "..NNNNNNNNNNNE",
    ".NNNNNNNNNNNNN",
    "NNNNNNNNNNNNN.",
    "NNNNNNNNNNN...",
    ".NNN.NN.NNN...",
    ".NN...N..NN...",
  },
  deer = {
    ".........H.H",
    ".........HH.",
    ".........TTT",
    "........TTTE",
    ".TTTTTTTTTT.",
    "TTTTTTTTTTT.",
    ".TTTTTTTTT..",
    ".T.T...T.T..",
    ".T.T...T.T..",
  },
  rabbit = {
    "...L.L",
    "...LLL",
    "LLLLLE",
    ".L..L.",
  },
  squirrel = {
    "TT.TT",
    ".TTTE",
    ".T.T.",
  },
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
        out[#out + 1] = { x = flip and (#line - stop) or (x - 1), y = y - 1, w = stop - x + 1, key = key }
      end
      x = stop + 1
    end
  end
  return out
end

local WAGON_LEFT = runs(WAGON, true)
local OX_LEFT = { runs(OX, true), runs(OX_STEP, true) }
local BEAST_WAYS = {}
for name, lines in pairs(BEASTS) do BEAST_WAYS[name] = { runs(lines), runs(lines, true) } end

local PAINT = {
  W = C.text, L = C.line, B = C.redTint, T = C.warn, H = C.line, E = C.bg, D = C.bg, N = C.redTint,
}
local SNOW_PAINT = { W = C.hi, L = C.warn, B = C.redTint }
local DEAD_PAINT = { B = C.red, D = C.red, N = C.red, T = C.red, L = C.red, H = C.red, E = C.red }

local sceneTop = 7 -- the top of the picture being drawn: anything taller is cut off there, clear of the header

--- Fill that keeps to the wall and the picture, for shapes that slide in from the side or stand tall.
local function box(x, y, w, h, color)
  local right, bottom = min(x + w, 121), y + h
  x, y = max(x, 0), max(y, sceneTop)
  ui.fill(x, y, right - x, bottom - y, color)
end

local function sprite(shape, x, y, paint)
  x, y = floor(x), floor(y)
  for _, run in ipairs(shape) do box(x + run.x, y + run.y, run.w, 1, paint and paint[run.key] or PAINT[run.key]) end
end

--- Wrapped text: each entry of a list is its own paragraph, with a gap after. Stops at lastY. Returns the next free row.
local function para(lines, x, y, lastY, fg, bg)
  if type(lines) == "string" then lines = { lines } end
  for _, piece in ipairs(lines) do
    for _, line in ipairs(ui.wrap(piece, TEXT_W)) do
      if y > lastY then return y end
      ui.small(line, x, y, fg or C.text, bg or C.bg)
      y = y + 1
    end
    y = y + 1
  end
  return y
end

-- ---------------------------------------------------------------- the country

--- The colours of the land the wagon is in: far hills and near ground.
local function country(s)
  local elevation = rules.elevation(s)
  if s.snow > 2 then return C.line, C.text, "pine" end
  if elevation >= 5000 then return C.tie, C.line, "rock" end
  if s.miles < 554 then return C.ok, C.soft, "bush" end
  if s.miles < 1654 then return C.redTint, C.hi, "sage" end
  return C.hiTint, C.ok, "pine"
end

local function skyColor(s)
  local sky = s.weather.sky
  if sky == "clear" then return C.info end
  return (sky == "rain") and C.panel or C.line
end

local function hills(top, height, far, road, tall)
  for x = 0, 120 do
    local at = x - road / 3
    local rise = 3 + 2 * math.sin(at / 11) + 1.5 * math.sin(at / 5)
    if tall then rise = rise + 4 + 3 * math.sin(at / 19) end
    local y = top + height - floor(rise)
    ui.fill(x, y, 1, top + height - y, far)
  end
end

local function thing(kind, x, y)
  if kind == "bush" then
    box(x, y - 2, 4, 2, C.ok)
    box(x + 1, y - 3, 2, 1, C.ok)
  elseif kind == "rock" then
    box(x, y - 2, 5, 2, C.tie)
    box(x + 1, y - 3, 3, 1, C.tie)
  elseif kind == "sage" then
    box(x, y - 1, 3, 1, C.hiTint)
    box(x + 1, y - 2, 1, 1, C.hiTint)
  else
    box(x + 2, y - 2, 1, 2, C.redTint)
    box(x, y - 4, 5, 2, C.hiTint)
    box(x + 1, y - 6, 3, 2, C.hiTint)
    box(x + 2, y - 7, 1, 1, C.hiTint)
  end
end

--- Things beside the road, which slide past as it rolls.
local function roadside(kind, y0, y1, road)
  for i = 1, 8 do
    local x = (i * 31 + road) % 140 - 10
    thing(kind, x, (i % 2 == 0) and y0 or y1)
  end
end

--- Rows of a tapering shape, wide at the foot: mountains, rocks and domes are all made of this.
local function peak(cx, foot, halfW, height, color, cap)
  for row = 0, height - 1 do
    local half = floor(halfW * (1 - row / height))
    box(cx - half, foot - row - 1, half * 2 + 1, 1, (cap and row >= height - cap) and C.text or color)
  end
end

local function drawFort(cx, foot)
  box(cx - 15, foot - 8, 30, 8, C.redTint)
  for x = -15, 14, 2 do box(cx + x, foot - 9, 1, 1, C.redTint) end
  box(cx - 17, foot - 11, 5, 11, C.redTint)
  box(cx + 12, foot - 11, 5, 11, C.redTint)
  box(cx - 2, foot - 5, 5, 5, C.bg)
  box(cx, foot - 15, 1, 7, C.bg)
  box(cx + 1, foot - 15, 5, 2, C.red)
end

local function drawTown(cx, foot)
  box(cx - 14, foot - 7, 9, 7, C.redTint)
  peak(cx - 10, foot - 7, 6, 3, C.tie)
  box(cx - 3, foot - 9, 10, 9, C.tie)
  peak(cx + 2, foot - 9, 7, 3, C.redTint)
  box(cx + 9, foot - 6, 8, 6, C.redTint)
  box(cx + 12, foot - 3, 2, 3, C.bg)
end

local function drawValley(cx, foot)
  peak(cx + 8, foot - 2, 20, 15, C.tie, 5)
  for i = -2, 2 do
    local x = cx + i * 12
    box(x, foot - 3, 1, 3, C.redTint)
    peak(x, foot - 2, 4, 9, C.hiTint)
  end
end

local function drawSpring(cx, foot)
  box(cx - 10, foot - 2, 21, 2, C.info)
  for i = -1, 1 do box(cx + i * 6, foot - 5 + i % 2, 1, 3, C.text) end
end

--- A landmark standing on the ground at foot. Chimney Rock is mostly spire; a river leaves nothing on the skyline.
local function drawLandmark(kind, cx, foot)
  if kind == "fort" then
    drawFort(cx, foot)
  elseif kind == "town" then
    drawTown(cx, foot)
  elseif kind == "spire" then
    peak(cx, foot, 11, 6, C.warn)
    box(cx - 1, foot - 15, 3, 10, C.warn)
    box(cx, foot - 17, 1, 2, C.warn)
  elseif kind == "rock" then
    for row = 0, 7 do
      local half = 18 - floor(row * row / 3)
      box(cx - half, foot - row - 1, half * 2 + 1, 1, C.line)
    end
  elseif kind == "pass" then
    peak(cx - 10, foot, 16, 15, C.tie, 5)
    peak(cx + 12, foot, 14, 12, C.tie, 4)
  elseif kind == "spring" then
    drawSpring(cx, foot)
  elseif kind == "valley" then
    drawValley(cx, foot)
  end
end

local function fallingWeather(s, top, height)
  local sky = s.weather.sky
  if sky == "clear" then return end
  local color = sky == "rain" and C.blue or C.text
  local count = sky == "blizzard" and 90 or 36
  for i = 1, count do
    local x = (i * 37 + s.clock * (sky == "rain" and 1 or 2)) % 121
    local y = top + (i * i * 7 + i * 3 + s.clock * (sky == "rain" and 3 or 1)) % height
    ui.fill(x, y, 1, 1, color)
  end
end

--- A spoked wheel, 7 by 5, with the spoke turned one way or the other to show it rolling.
local function wheel(x, y, spin)
  box(x + 1, y, 5, 1, C.bg)
  box(x, y + 1, 7, 3, C.bg)
  box(x + 1, y + 4, 5, 1, C.bg)
  box(x + 1, y + 1, 5, 3, C.redTint)
  if spin then box(x + 3, y + 1, 1, 3, C.hi) else box(x + 1, y + 2, 5, 1, C.hi) end
end

--- The wagon with its two oxen out in front, its feet on foot.
local function drawWagon(s, x, foot)
  local spin = s.road % 8 < 4
  sprite(OX_LEFT[spin and 1 or 2], x - 16, foot - 6)
  sprite(OX_LEFT[spin and 2 or 1], x - 31, foot - 6)
  box(x - 3, foot - 4, 4, 1, C.bg)
  sprite(WAGON_LEFT, x, foot - 10, s.snow > 2 and SNOW_PAINT or nil) -- a white cover would vanish against the drifts
  wheel(x + 2, foot - 5, spin)
  wheel(x + 13, foot - 5, not spin)
end

local function water(y, height, road)
  ui.fill(0, y, 121, height, C.blue)
  for i = 1, 14 do
    local x = (i * 29 + road) % 121
    box(x, y + i % max(1, height), 5, 1, C.info)
  end
end

--- A picture of where the party is. kind: a landmark to show, or nil for whatever's coming over the horizon.
local function drawScene(s, top, height, kind)
  sceneTop = top
  local road = s.road
  local horizon = top + floor(height * 0.42)
  local far, ground, small = country(s)
  local tall = small == "rock"
  ui.fill(0, top, 121, horizon - top, skyColor(s))
  if s.weather.sky == "clear" then
    ui.ellipse(12 + floor(road / 10) % 96, top + 1, 14, 3, C.text)
    ui.ellipse(70 + floor(road / 7) % 40, top + 3, 10, 3, C.text)
  end
  hills(top, horizon - top, far, road, tall)
  ui.fill(0, horizon, 121, top + height - horizon, ground)
  local foot = top + height - 2
  if kind == "river" then
    water(horizon + 1, max(2, foot - 11 - horizon), road)
  elseif kind then
    drawLandmark(kind, 92, horizon + 6)
  elseif s.leg and s.leg.left <= 60 then
    drawLandmark(rules.ROUTE[s.leg.to].kind, 34 - s.leg.left, horizon + 1)
  end
  if kind ~= "river" then roadside(small, horizon + 4, foot + 1, road) end
  drawWagon(s, 44, foot)
  fallingWeather(s, top, height)
end

-- ---------------------------------------------------------------- the screens

--- A heading, in capitals: the small letters of the big font are the hard ones to read.
local function title(str, y, color)
  ui.text(str:upper(), 60, y, color or C.hi, "center", 117)
end

local function notice(s)
  if s.notice then
    for i, line in ipairs(ui.wrap(s.notice, 100)) do ui.small(line, 2, NOTICE_Y + (i - 1), C.warn, C.bg) end
  end
end

local function stat(x, y, label, value, color)
  ui.small(label, x, y, C.line, C.bg)
  ui.small(value, x + #label + 1, y, color or C.text, C.bg)
end

--- What matters most on the road.
local function drawStatus(s, y)
  local word = rules.healthWord(s.health)
  local hurting = word == "poor" or word == "very poor"
  local w = s.weather
  local skyWord = w.sky == "clear" and "" or (", " .. w.sky)
  stat(2, y, "Date:", rules.dateText(s.date))
  stat(2, y + 2, "Weather:", w.word .. " (" .. w.temp .. " F)" .. skyWord)
  stat(2, y + 4, "Health:", word, hurting and C.warn or C.text)
  stat(2, y + 6, "Food:", rules.commas(s.goods.food) .. " pounds", s.goods.food < 100 and C.warn or C.text)
  local x = 60
  if s.leg then
    stat(x, y, "Next:", rules.ROUTE[s.leg.to].name .. ", " .. s.leg.left .. " miles")
  else
    stat(x, y, "At:", rules.ROUTE[s.at].name)
  end
  stat(x, y + 2, "Miles traveled:", rules.commas(s.miles))
  stat(x, y + 4, "Pace:", rules.PACE[s.pace].label)
  stat(x, y + 6, "Rations:", rules.RATIONS[s.rations].label)
  local sick = rules.sickList(s)
  if #sick > 0 then ui.small("Sick: " .. table.concat(sick, ", "), 2, y + 8, C.warn, C.bg, "left", 117) end
end

local function drawTrail(s)
  drawScene(s, 7, SCENE_H)
  drawStatus(s, 35)
  notice(s)
end

--- The miles so far, across the width of the wall, with the wagon on the line.
local function drawProgress(s, y)
  local w = floor(113 * min(1, s.miles / rules.TOTAL_MILES))
  ui.fill(4, y, 113, 3, C.panel)
  ui.fill(4, y, w, 3, C.ok)
  ui.small("Independence", 4, y + 4, C.line, C.bg)
  ui.small("Oregon", 116, y + 4, C.line, C.bg, "right")
end

local function drawRoll(s)
  drawScene(s, 7, SCENE_H)
  drawStatus(s, 35)
  if s.roll and not s.roll.moving then
    title("RESTING", 50, C.ok)
    ui.small("The oxen graze. Nobody complains, much.", 60, 59, C.line, C.bg, "center")
  else
    title(s.leg and rules.ROUTE[s.leg.to].name or "", 47, C.hi)
    drawProgress(s, 57)
  end
end

local function drawProfession(s)
  title("THE OREGON TRAIL", 8, C.hi)
  local names = {}
  for i = 2, #s.party do names[#names + 1] = s.party[i].name end
  local y = para("Independence, Missouri, 1848. Your wagon holds you, " .. table.concat(names, ", ", 1, 3) .. " and " .. names[4] .. ". All that's wanting is the money.", 4, 16, 44)
  y = para("A banker has plenty and scores nothing extra. A carpenter has less, mends a wagon better and scores double. A farmer has little, keeps oxen better and scores triple.", 4, y, 44, C.line)
  drawScene(s, y, 44 - y)
end

local function drawMonth(s)
  title("WHEN WILL YOU LEAVE?", 9, C.hi)
  local y = para("Two thousand miles must be done before the snow closes the mountains. Leave too early and there's no grass on the prairie. Leave too late and you'll meet winter on the Blue Mountains. Matt's store comes next.", 4, 18, 30)
  drawScene(s, y, 53 - y)
end

local function storeRowY(i)
  return 15 + (i - 1) * STORE_ROW
end

local function drawStore(s)
  local fort = s.fort and rules.ROUTE[s.fort]
  ui.text(fort and fort.name:upper() or "MATT'S STORE", 2, 8, C.hi, "left", 84)
  ui.text("$" .. rules.commas(s.money), 118, 8, C.ok, "right")
  for i, item in ipairs(rules.ITEMS) do
    local y = storeRowY(i)
    ui.text(item.label, 2, y, C.text)
    ui.small("$" .. rules.price(s, item.id) .. " " .. item.per, 40, y + 2, C.line, C.bg)
    ui.text(rules.commas(s.goods[item.id]), 79, y, C.hi, "right")
  end
  notice(s)
end

local function drawSupplies(s)
  title("SUPPLIES", 8, C.hi)
  local y = 16
  for _, item in ipairs(rules.ITEMS) do
    ui.text(item.label, 2, y, C.line)
    ui.text(rules.commas(s.goods[item.id]), 66, y, s.goods[item.id] == 0 and C.warn or C.text, "right")
    y = y + 7
  end
  ui.text("CASH", 2, y, C.line)
  ui.text("$" .. rules.commas(s.money), 66, y, C.ok, "right")
  y = 16
  for _, p in ipairs(s.party) do
    ui.text(p.name:upper(), 72, y, p.alive and C.text or C.line, "left", 47)
    ui.small(p.alive and (p.ill or "well") or "at rest", 72, y + 6, (p.ill and C.warn) or (p.alive and C.ok or C.line), C.bg, "left", 47)
    y = y + 9
  end
  stat(72, y, "Party health:", rules.healthWord(s.health))
end

--- A menu that explains itself: the options as a list, with the one in force marked.
local function drawExplained(s, heading, lines, current, intro)
  title(heading, 8, C.hi)
  para(intro, 4, 16, 22)
  local y = 20
  for _, row in ipairs(lines) do
    local on = row.id == current
    ui.small((on and "> " or "  ") .. row.line, 4, y, on and C.hi or C.text, C.bg)
    y = y + 3
  end
  drawScene(s, y, 53 - y)
end

local PACE_LINES = {
  { id = "steady", line = "Steady: up to 16 miles a day. Hard on nobody." },
  { id = "strenuous", line = "Strenuous: up to 21 miles a day, and tired people." },
  { id = "grueling", line = "Grueling: up to 27 miles a day, and a good many stones." },
}

local RATION_LINES = {
  { id = "filling", line = "Filling: 3 pounds a head each day, and no complaints." },
  { id = "meager", line = "Meager: 2 pounds a head. Health suffers slowly." },
  { id = "bare", line = "Bare bones: 1 pound a head. Health suffers at once." },
}

local function drawPace(s)
  drawExplained(s, "CHANGE PACE", PACE_LINES, s.pace, "How hard will you drive them? Every extra mile comes out of somebody.")
end

local function drawRations(s)
  drawExplained(s, "CHANGE RATIONS", RATION_LINES, s.rations, "The party has " .. rules.commas(s.goods.food) .. " pounds of food. How much will they eat?")
end

local function drawRest(s)
  title("REST", 8, C.hi)
  local sick = rules.sickList(s)
  local y = para({
    "How long will you stop? Rest heals the sick twice as fast and eases the party's health, but they go on eating.",
    #sick > 0 and ("Sick: " .. table.concat(sick, ", ") .. ".") or "Nobody's sick. Yet.",
  }, 4, 16, 30)
  drawScene(s, y, 53 - y)
end

local function drawTrade(s)
  drawScene(s, 7, SCENE_H)
  title("A TRADER", 35, C.hi)
  local o = s.offer
  local y = para("He offers you " .. rules.quantity(o.get, o.getN) .. " for your " .. rules.quantity(o.want, o.wantN) .. ".", 4, 44, 54)
  para("You have " .. rules.quantity(o.want, s.goods[o.want]) .. ", and " .. rules.quantity(o.get, s.goods[o.get]) .. ". A day goes by, whatever you say.", 4, y, 63, C.line)
end

local function drawReport(s)
  local r = s.report
  drawScene(s, 7, PICTURE_H, r.scene)
  title(r.title, 31, C.hi)
  para(r.lines, 4, 39, 63)
end

local function drawRiver(s)
  local r = s.river
  drawScene(s, 7, PICTURE_H, "river")
  title(r.name, 31, C.info)
  ui.text(r.depth .. " FEET DEEP, " .. r.width .. " WIDE", 60, 39, C.text, "center", 117)
  local line = r.ferry and ("A ferry runs here for $" .. r.ferry .. ".") or "No ferry on this river."
  para(line .. " Over 2.5 feet a ford wets the goods, and over 3 it may take them. A caulked wagon floats, in water deep enough for it. It's " .. s.weather.word .. " today.", 4, 47, 52, C.line)
  notice(s)
end

local function drawFork(s)
  local node = rules.ROUTE[s.fork]
  drawScene(s, 7, PICTURE_H, node.kind)
  title(text.FORK_TITLE[s.fork], 31, C.hi)
  para(text.FORK_SAY[s.fork], 4, 39, 50)
  stat(4, 52, "You stand at", node.name .. ", " .. rules.dateText(s.date))
end

--- A stone with the top rounded off.
local function stone(x, y, w, h)
  local top = min(4, floor(h / 3))
  for row = 0, top - 1 do
    local inset = (top - row) * 3
    ui.fill(x + inset, y + row, w - inset * 2, 1, C.line)
  end
  ui.fill(x, y + top, w, h - top, C.line)
end

--- Sky, down to a strip of grass from y to stop.
local function drawGround(y, stop)
  ui.fill(0, 7, 121, y - 7, C.info)
  ui.fill(0, y, 121, stop - y, C.soft)
  for x = 0, 120, 7 do ui.fill(x + (x % 3), y, 2, 1, C.ok) end
end

local function drawTomb(s)
  local t = s.tomb
  local cx = 60
  drawGround(48, 65)
  stone(26, 9, 69, 45)
  local bg = C.line
  ui.small("HERE LIES", cx, 15, C.bg, bg, "center")
  ui.text(t.name:upper(), cx, 18, C.bg, "center", 65)
  ui.small(rules.dateText(t.date), cx, 27, C.bg, bg, "center")
  ui.small(rules.commas(t.miles) .. " miles from Independence", cx, 29, C.bg, bg, "center")
  ui.small(t.line, cx, 35, C.bg, bg, "center")
  local y = 42
  for _, line in ipairs(ui.wrap(t.epitaph, 60)) do
    ui.small(line, cx, y, C.bg, bg, "center")
    y = y + 1
  end
end

local function drawArrive(s)
  local tally = s.tally
  drawScene(s, 7, SCENE_H, "valley")
  title("YOU HAVE REACHED OREGON", 35, C.ok)
  ui.small("The Willamette Valley, " .. rules.dateText(s.date), 60, 42, C.line, C.bg, "center")
  local y = 48
  for _, row in ipairs(tally.rows) do
    ui.small(row.label, 8, y, C.text, C.bg)
    ui.small(rules.commas(row.points), 112, y, C.text, C.bg, "right")
    y = y + 1
  end
  local pro = rules.PROFESSIONS[s.profession].label
  ui.small(rules.commas(tally.subtotal) .. " x " .. tally.mult .. " for a " .. pro:lower() .. " = ", 8, y + 1, C.hi, C.bg)
  ui.small(rules.commas(tally.total), 112, y + 1, C.hi, C.bg, "right")
end

local function drawLost(s)
  drawGround(30, 34)
  for i = 1, #s.graves do
    local x = 8 + (i - 1) * 23
    stone(x, 15, 13, 15)
    ui.fill(x + 6, 19, 1, 6, C.bg)
    ui.fill(x + 4, 20, 5, 1, C.bg)
  end
  title("NOBODY REACHED OREGON", 35, C.warn)
  ui.small("The trail ended " .. rules.commas(s.miles) .. " miles out, on " .. rules.dateText(s.date), 60, 42, C.line, C.bg, "center")
  local y = 48
  for _, g in ipairs(s.graves) do
    ui.small(g.name, 8, y, C.text, C.bg)
    ui.small(g.cause, 30, y, C.line, C.bg)
    ui.small(rules.dateText(g.date), 112, y, C.line, C.bg, "right")
    y = y + 2
  end
end

local function drawHunt(s)
  local h = s.hunt
  local far, top = C.ok, 7
  local bottom = top + HUNT_H
  sceneTop = top
  ui.fill(0, top, 121, HUNT_SKY, C.info)
  hills(top, HUNT_SKY, far, 40, rules.elevation(s) >= 4500)
  ui.fill(0, top + HUNT_SKY, 121, HUNT_H - HUNT_SKY, s.snow > 2 and C.text or C.soft)
  for i = 1, 14 do thing("bush", (i * 37) % 118, top + HUNT_SKY + 4 + (i * 17) % (HUNT_H - HUNT_SKY - 6)) end
  for _, a in ipairs(h.animals) do
    local ways = BEAST_WAYS[a.kind]
    sprite(ways[a.vx >= 0 and 1 or 2], a.x, top + a.y, a.dead and DEAD_PAINT or nil)
    if a.dead then
      ui.small(rules.SPECIES[a.kind].pounds .. " lb", floor(a.x + a.w / 2), max(top, top + a.y - 2), C.text, C.bg, "center")
    end
  end
  if h.flash then
    local x, y = floor(h.flash.x), top + floor(h.flash.y)
    local color = h.flash.hit and C.hi or C.text
    box(x - 2, y, 5, 1, color)
    box(x, y - 1, 1, 3, color)
  end
  local carried = min(h.bag, rules.CARRY_LIMIT)
  ui.text(s.goods.ammo .. " BULLETS", 2, bottom + 1, C.text)
  ui.text(carried .. " LB", 62, bottom + 1, carried >= rules.CARRY_LIMIT and C.ok or C.hi)
end

local DRAW = {
  profession = drawProfession, month = drawMonth, store = drawStore, trail = drawTrail, roll = drawRoll, report = drawReport,
  supplies = drawSupplies, pace = drawPace, rations = drawRations, rest = drawRest, trade = drawTrade, river = drawRiver,
  fork = drawFork, tomb = drawTomb, arrive = drawArrive, lost = drawLost, hunt = drawHunt,
}

-- ---------------------------------------------------------------- the view

local view = {}

function view.layout(W, H)
  return base.actionLayout(W, H, W, BOARD_H)
end

function view.draw(_, s)
  DRAW[s.screen](s)
end

local function pickAction(s, id)
  return { kind = "pick", id = id, seq = s.seq }
end

--- The store's lines: a - and a + beside each good, and the way out under them.
local function storeControls(L, s)
  local out = {}
  local choices = rules.choices(s)
  for i = 1, #rules.ITEMS do
    local y = storeRowY(i)
    local sell, add = choices[i * 2 - 1], choices[i * 2]
    out[#out + 1] = { label = sell.label, x = 82, y = y - 1, w = 18, h = STORE_ROW - 1, action = pickAction(s, sell.id) }
    out[#out + 1] = { label = add.label, x = 101, y = y - 1, w = 18, h = STORE_ROW - 1, action = pickAction(s, add.id) }
  end
  out[#out + 1] = { label = "LEAVE STORE", x = 2, y = BOTTOM - BUTTON_H, w = L.W - 4, h = BUTTON_H, action = pickAction(s, "leave") }
  return out
end

--- A block of big buttons sitting on the bottom row of the board.
function view.controls(L, s)
  if s.over then return {} end
  if s.screen == "store" then return storeControls(L, s) end
  local choices = rules.choices(s)
  if s.screen == "hunt" then
    return { { label = "DONE", x = L.W - 34, y = BOTTOM - BUTTON_H, w = 32, h = BUTTON_H, action = pickAction(s, "done") } }
  end
  local sizes = ROWS[s.screen]
  local rows, used = {}, 0
  while used < #choices do
    local count = sizes and sizes[#rows + 1] or 1
    rows[#rows + 1] = min(count, #choices - used)
    used = used + rows[#rows]
  end
  local out = {}
  local y = BOTTOM - #rows * (BUTTON_H + BUTTON_GAP) + BUTTON_GAP
  local at = 0
  for _, count in ipairs(rows) do
    local room = L.W - 4 - (count - 1) * BUTTON_GAP
    for col = 1, count do
      at = at + 1
      local choice = choices[at]
      -- the division's remainder is spread along the row, so every row ends level
      local left = floor(room * (col - 1) / count)
      local w = floor(room * col / count) - left
      out[at] = { label = choice.label, x = 2 + left + (col - 1) * BUTTON_GAP, y = y, w = w, h = BUTTON_H, action = pickAction(s, choice.id) }
    end
    y = y + BUTTON_H + BUTTON_GAP
  end
  return out
end

--- Only the hunt reads the board, and every tap on the field is a shot.
function view.actionAt(L, s, px, py)
  if s.screen ~= "hunt" then return nil end
  local x, y = px - L.x0, py - L.y0
  if x < 0 or x >= L.bw or y < 0 or y >= HUNT_H then return nil end
  return { kind = "shoot", x = x, y = y, seq = s.seq }
end

--- The idle screen has no shell buttons, so the demo paints the faces of them to show what's being chosen.
function view.drawBoard(L, match)
  local s = match.state
  view.draw(L, s)
  for _, c in ipairs(view.controls(L, s)) do
    ui.fill(c.x, c.y, c.w, c.h, C.panel)
    ui.small(c.label, c.x + floor(c.w / 2), c.y + floor((c.h - 1) / 2), C.text, C.panel, "center", c.w - 1)
  end
end

--- The line for the saved-game list.
function view.saveSummary(s)
  return rules.summary(s)
end

-- one sound for each plain event: id, volume and pitch
local SOUND = {
  pick = { "placeBlue", 0.5, 1.2 }, buy = { "capture", 0.7, 1.1 }, shot = { "placeBlue", 1, 0.7 }, hit = { "capture", 1, 0.9 },
  good = { "captureRed", 1, 1 }, ill = { "placeRed", 1, 0.6 }, ["break"] = { "placeRed", 0.9, 0.75 }, splash = { "placeBlue", 1, 0.5 },
}

function view.onEvents(app, _, events)
  for _, ev in ipairs(events) do
    local sound = SOUND[ev.type]
    if sound then app.audio.play(sound[1], sound[2], sound[3]) end
    if ev.type == "death" then
      app.audio.play("captureBlue", 1, 0.6)
      app.audio.later("captureBlue", 300, 1, 0.5)
    end
    if ev.type == "landmark" then
      app.audio.play("capture")
      app.audio.later("captureRed", 150)
    end
    if ev.type == "arrive" then
      app.audio.play("captureBlue")
      app.audio.later("capture", 130)
      app.audio.later("captureRed", 260)
      app.audio.later("captureRed", 400, 1, 1.4)
    end
  end
end

return base.fill({
  id = "oregon", title = "Oregon Trail", blurb = "You have died of dysentery", color = "hi", accent = 0xE8C872,
  action = true, tickMs = rules.TICK_MS, minSize = { w = 118, h = 81 }, saves = true, livesName = "PARTY",
  rules = rules, view = view, sounds = base.SOUNDS,
  help = {
    "It is 1848. Take your family of five from Independence, Missouri to the Willamette Valley, 2,040 miles, before the food, the oxen or the snow give out.",
    "",
    "Pick a trade. A banker starts rich and a farmer poor, but a farmer's final score counts triple. Pick a month. Then spend your money at Matt's store: + buys and - puts back.",
    "",
    "On the trail, CONTINUE rolls on for a few days. Set the pace and rations with care: both wear the party down. REST heals. At forts you can BUY, at higher prices the farther west you go.",
    "",
    "At a river, ford it if it's shallow, caulk the wagon and float if it's deep, or pay for a ferry where there is one. Waiting can drop the water.",
    "",
    "HUNT is the one fast thing: tap the animals as they cross. Every tap is a bullet, wherever it lands, and you can only carry 100 pounds back.",
    "",
    "Survivors score by their health, and the goods you bring in count too, then your trade's multiplier. A run that dies on the way keeps a point for every ten miles.",
  },
})
