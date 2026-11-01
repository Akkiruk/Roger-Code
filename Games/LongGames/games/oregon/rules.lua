-- games/oregon/rules.lua
-- The Oregon Trail, after the 1985 version. Pure: no screen, sound or files. See "Classics" in Games/Arcade/games/README.md.
-- Play is by choices. Every screen but two is a menu: M.choices lists what it offers, and a tap sends { kind = "pick", id, seq }.
-- seq names the screen the tap was aimed at, so a tap that lands after the screen has moved on does nothing.
-- The two that aren't: roll (days go by on the clock) and hunt (animals cross, every tap is a shot).
-- A run goes: profession, month, store, then trail <-> roll, with whatever a stage turned up in between, and flow() deciding
-- what comes next. It ends at arrive (Oregon) or lost (nobody left), each of which waits for one tap and then sets over.
-- The state is saved between visits, so it's plain data throughout, and textutils.serialise writes numbers to 14 digits:
-- every fraction here is rounded to two places, or is a sum of quarters, so a saved game plays on exactly.

local text = require("games.oregon.text")

local M = {
  TICK_MS = 100, TOTAL_MILES = 2040, CARRY_LIMIT = 100,
  HUNT_W = 121, HUNT_H = 58, HUNT_TICKS = 200, HUNT_SKY = 13,
}

local DAY_TICKS = 3       -- clock steps to a day on the road
local STAGE_DAYS = 5      -- days a Continue covers, if nothing stops it
local EVENT_CHANCE = 0.1  -- the chance a day on the road brings something
local BOT_WAIT = 8        -- steps the bot looks at a screen, so the idle demo can be read
local BOT_SHOP_WAIT = 2   -- and at a store, where it taps a lot
local INBOX_MAX = 4       -- taps held for the next steps

local floor, ceil, min, max = math.floor, math.ceil, math.min, math.max

local PROFESSIONS = {
  banker = { label = "Banker", money = 1600, mult = 1 },
  carpenter = { label = "Carpenter", money = 800, mult = 2, repair = true },
  farmer = { label = "Farmer", money = 400, mult = 3, oxenCare = true },
}

local MONTHS = {
  { id = "mar", label = "MARCH", date = 60 },
  { id = "apr", label = "APRIL", date = 91 },
  { id = "may", label = "MAY", date = 121 },
  { id = "jun", label = "JUNE", date = 152 },
  { id = "jul", label = "JULY", date = 182 },
}

-- Matt's prices, by the lot a tap buys. ammo counts bullets and oxen counts animals
local ITEMS = {
  { id = "oxen", label = "OXEN", per = "a yoke of 2", price = 40, lot = 2, max = 20 },
  { id = "food", label = "FOOD", per = "per 100 lb", price = 20, lot = 100, max = 2000 },
  { id = "clothes", label = "CLOTHES", per = "a set", price = 10, lot = 1, max = 30 },
  { id = "ammo", label = "BULLETS", per = "a box of 20", price = 2, lot = 20, max = 1000 },
  { id = "wheel", label = "WHEELS", per = "each", price = 10, lot = 1, max = 3 },
  { id = "axle", label = "AXLES", per = "each", price = 10, lot = 1, max = 3 },
  { id = "tongue", label = "TONGUES", per = "each", price = 10, lot = 1, max = 3 },
}
local ITEM = {}
for _, item in ipairs(ITEMS) do ITEM[item.id] = item end

local PACE = {
  steady = { label = "steady", miles = 16, strain = 0 },
  strenuous = { label = "strenuous", miles = 21, strain = 1 },
  grueling = { label = "grueling", miles = 27, strain = 3 },
}

-- pounds a head each day
local RATIONS = {
  filling = { label = "filling", food = 3, strain = 0 },
  meager = { label = "meager", food = 2, strain = 2 },
  bare = { label = "bare bones", food = 1, strain = 4 },
}

-- The route. miles leads to next; a fork has choices instead. price makes it a fort, by what its store charges against Matt's.
local ROUTE = {
  independence = { name = "Independence", elev = 750, kind = "town", next = "kansas", miles = 102 },
  kansas = { name = "Kansas River", elev = 900, kind = "river", river = { depth = 2.4, width = 620, swift = 0.05, ferry = 5 }, next = "bigblue", miles = 83 },
  bigblue = { name = "Big Blue River", elev = 1200, kind = "river", river = { depth = 2.2, width = 300, swift = 0.05 }, next = "kearney", miles = 119 },
  kearney = { name = "Fort Kearney", elev = 2100, kind = "fort", price = 1.25, next = "chimney", miles = 250 },
  chimney = { name = "Chimney Rock", elev = 3900, kind = "spire", next = "laramie", miles = 86 },
  laramie = { name = "Fort Laramie", elev = 4200, kind = "fort", price = 1.5, next = "rock", miles = 190 },
  rock = { name = "Independence Rock", elev = 5900, kind = "rock", next = "southpass", miles = 102 },
  southpass = { name = "South Pass", elev = 7400, kind = "pass", fork = { "bridger", "sublette" } },
  bridger = { name = "Fort Bridger", elev = 6600, kind = "fort", price = 1.75, next = "green", miles = 100 },
  green = { name = "Green River", elev = 6200, kind = "river", river = { depth = 4.2, width = 400, swift = 0.12, ferry = 7 }, next = "soda", miles = 144 },
  soda = { name = "Soda Springs", elev = 5800, kind = "spring", next = "hall", miles = 57 },
  hall = { name = "Fort Hall", elev = 4400, kind = "fort", price = 2, next = "snake", miles = 182 },
  snake = { name = "Snake River", elev = 2500, kind = "river", river = { depth = 5.5, width = 1000, swift = 0.2, ferry = 10 }, next = "boise", miles = 114 },
  boise = { name = "Fort Boise", elev = 2300, kind = "fort", price = 2.25, next = "blue", miles = 120 },
  blue = { name = "Blue Mountains", elev = 4900, kind = "pass", fork = { "wallawalla", "dalles" } },
  wallawalla = { name = "Fort Walla Walla", elev = 950, kind = "fort", price = 2.5, next = "dalles", miles = 111 },
  dalles = { name = "The Dalles", elev = 100, kind = "town", fork = { "raft", "barlow" } },
  willamette = { name = "Willamette Valley", elev = 150, kind = "valley", final = true },
}

local FORKS = {
  bridger = { label = "FORT BRIDGER", to = "bridger", miles = 125 },
  sublette = { label = "SUBLETTE CUTOFF", to = "green", miles = 160, dry = true },
  wallawalla = { label = "FORT WALLA WALLA", to = "wallawalla", miles = 55 },
  dalles = { label = "THE DALLES", to = "dalles", miles = 120 },
  raft = { label = "COLUMBIA RAFT", to = "willamette", miles = 100, raft = true },
  barlow = { label = "BARLOW ROAD $15", to = "willamette", miles = 100, peak = 4100, toll = 15 },
}

-- die: the chance a day of dying of it, for a party in good health
local SICK = {
  dysentery = { die = 0.025, weight = 4 },
  typhoid = { die = 0.02, weight = 2 },
  cholera = { die = 0.03, weight = 2 },
  measles = { die = 0.012, weight = 1 },
  snakebite = { die = 0.03 },
  ["broken arm"] = { die = 0.003 },
}
local ILLNESSES = { "dysentery", "typhoid", "cholera", "measles" }

-- how a death reads, where it isn't simply "died of" the cause
local DEATHS = { snakebite = "died of a snakebite", ["broken arm"] = "died of a broken arm", cold = "frozen to death", drowned = "drowned" }

-- what game a hunter finds, by the kind of country. Sizes are the sprite's, in cells; speed is cells a step, in quarters
local SPECIES = {
  bison = { label = "bison", pounds = 900, speed = 1.25, w = 18, h = 9 },
  bear = { label = "bear", pounds = 300, speed = 1.75, w = 14, h = 8 },
  deer = { label = "deer", pounds = 100, speed = 2.5, w = 12, h = 9 },
  rabbit = { label = "rabbit", pounds = 5, speed = 2.75, w = 6, h = 4 },
  squirrel = { label = "squirrel", pounds = 2, speed = 2, w = 5, h = 3 },
}
local GAME_PLAINS = { "bison", "bison", "deer", "rabbit", "rabbit", "squirrel" }
local GAME_HIGH = { "bear", "deer", "deer", "rabbit", "squirrel", "squirrel" }

-- what a trader will swap, one for the other
local OFFERS = {
  { want = "food", wantN = 100, get = "ammo", getN = 60 },
  { want = "food", wantN = 150, get = "wheel", getN = 1 },
  { want = "food", wantN = 150, get = "axle", getN = 1 },
  { want = "food", wantN = 150, get = "tongue", getN = 1 },
  { want = "food", wantN = 100, get = "clothes", getN = 2 },
  { want = "clothes", wantN = 2, get = "food", getN = 120 },
  { want = "clothes", wantN = 3, get = "oxen", getN = 1 },
  { want = "ammo", wantN = 60, get = "food", getN = 100 },
  { want = "oxen", wantN = 1, get = "food", getN = 200 },
  { want = "oxen", wantN = 1, get = "wheel", getN = 2 },
}

M.PROFESSIONS, M.MONTHS, M.ITEMS, M.PACE, M.RATIONS, M.ROUTE, M.FORKS = PROFESSIONS, MONTHS, ITEMS, PACE, RATIONS, ROUTE, FORKS
M.SPECIES, M.OFFERS, M.SICK = SPECIES, OFFERS, SICK

-- ---------------------------------------------------------------- small things

--- Two decimal places: exact through a save.
local function round2(v)
  return floor(v * 100 + 0.5) / 100
end

--- 1234 as "1,234".
function M.commas(n)
  local str = tostring(floor(n))
  while true do
    local swapped, count = str:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
    str = swapped
    if count == 0 then return str end
  end
end

local function hasWord(name) return name == "You" and "You have" or (name .. " has") end
local function wasWord(name) return name == "You" and "You were" or (name .. " was") end
local function isWord(name) return name == "You" and "You are" or (name .. " is") end

--- "You have died of dysentery." The cause is a key of DEATHS.
function M.deathLine(name, cause)
  return hasWord(name) .. " " .. (DEATHS[cause] or ("died of " .. cause)) .. "."
end

--- An amount of a good, in words.
function M.quantity(id, n)
  if id == "food" then return M.commas(n) .. " pounds of food" end
  if id == "ammo" then return n .. " bullets" end
  if id == "oxen" then return n == 1 and "1 ox" or (n .. " oxen") end
  if id == "clothes" then return n == 1 and "1 set of clothing" or (n .. " sets of clothing") end
  local name = id == "wheel" and "wagon wheel" or (id == "axle" and "wagon axle" or "wagon tongue")
  return n == 1 and ("1 " .. name) or (n .. " " .. name .. "s")
end

local function say(s, line)
  s.notes[#s.notes + 1] = line
end

local function emit(s, kind)
  s.ev[#s.ev + 1] = { type = kind }
end

--- Move to a screen. A new seq means taps aimed at the old one are thrown away.
local function go(s, screen)
  s.screen, s.seq, s.idle, s.notice = screen, s.seq + 1, 0, nil
end

-- ---------------------------------------------------------------- the calendar and the sky

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local MONTH_NAMES = {
  "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December",
}
local FIRST_YEAR = 1848

local function yearDays(year)
  return year % 4 == 0 and 366 or 365
end

--- Day 0 is the first of January 1848. Returns year, month, day of the month, and the day of the year from 0.
local function calendar(date)
  local year = FIRST_YEAR
  while date >= yearDays(year) do
    date = date - yearDays(year)
    year = year + 1
  end
  local dayOfYear = date
  for month, days in ipairs(MONTH_DAYS) do
    if month == 2 and year % 4 == 0 then days = 29 end
    if date < days then return year, month, date + 1, dayOfYear end
    date = date - days
  end
  return year, 12, 31, dayOfYear
end

--- "May 3, 1848".
function M.dateText(date)
  local year, month, day = calendar(date)
  return MONTH_NAMES[month] .. " " .. day .. ", " .. year
end

--- Height of the wagon, in feet: between the last landmark and the next, in a straight line, or over a road's summit.
function M.elevation(s)
  local leg = s.leg
  if not leg then return ROUTE[s.at].elev end
  local from, to = ROUTE[s.at].elev, ROUTE[leg.to].elev
  local done = (leg.miles - leg.left) / leg.miles
  if leg.peak then
    if done < 0.5 then return floor(from + (leg.peak - from) * done * 2) end
    return floor(leg.peak + (to - leg.peak) * (done - 0.5) * 2)
  end
  return floor(from + (to - from) * done)
end

--- A day's usual temperature in Fahrenheit: a year's curve, peaking in the third week of July, and 3.3 degrees colder for
--- every thousand feet.
function M.temperature(dayOfYear, elevation)
  return floor(52 + 30 * math.cos((dayOfYear - 200) / 365 * 2 * math.pi) - elevation * 0.0033 + 0.5)
end

function M.weatherWord(temp)
  if temp >= 95 then return "very hot" end
  if temp >= 80 then return "hot" end
  if temp >= 60 then return "warm" end
  if temp >= 40 then return "cool" end
  if temp >= 20 then return "cold" end
  return "very cold"
end

--- How often a day brings rain or snow: wet in spring, and wetter up high.
function M.wetChance(dayOfYear, elevation)
  local chance = (dayOfYear >= 60 and dayOfYear < 170) and 0.25 or 0.12
  return elevation >= 4500 and chance + 0.05 or chance
end

--- The chance of a blizzard on a day on the road. It takes height and cold together.
function M.blizzardChance(elevation, temp)
  if elevation < 4500 or temp > 30 then return 0 end
  return min(0.45, 0.1 + (30 - temp) * 0.02)
end

local function setWeather(s, rng)
  local _, _, _, dayOfYear = calendar(s.date)
  local elevation = M.elevation(s)
  local temp = M.temperature(dayOfYear, elevation) + rng(13) - 7
  local sky = "clear"
  if rng() < M.wetChance(dayOfYear, elevation) then sky = temp <= 34 and "snow" or "rain" end
  s.weather = { temp = temp, word = M.weatherWord(temp), sky = sky }
  if sky == "snow" then s.snow = s.snow + 2 elseif temp > 40 then s.snow = max(0, s.snow - 1) end
  if sky == "rain" then
    s.wet, s.dry = min(30, s.wet + 3), 0
  else
    s.wet = max(0, s.wet - 1)
    if sky == "clear" then s.dry = s.dry + 1 end
  end
end

-- ---------------------------------------------------------------- health

--- The party's health is one number that climbs with hardship and falls away by itself, as the original's did.
function M.healthWord(health)
  if health < 35 then return "good" end
  if health < 79 then return "fair" end
  if health < 105 then return "poor" end
  return "very poor"
end

local function livingCount(s)
  local n = 0
  for _, p in ipairs(s.party) do
    if p.alive then n = n + 1 end
  end
  return n
end

--- A day's hardship.
local function strainOf(s, moving)
  local w = s.weather
  local cost = RATIONS[s.rations].strain
  if moving then cost = cost + PACE[s.pace].strain end
  if s.goods.food <= 0 then cost = cost + 13 end
  if w.temp >= 95 then cost = cost + 2 elseif w.temp >= 85 then cost = cost + 1 end
  if w.temp < 40 then
    local short = 1 - min(1, s.goods.clothes / max(1, livingCount(s) * 2))
    cost = cost + (40 - w.temp) / 10 * (0.3 + short)
  end
  if s.foul > 0 then cost = cost + 2 end
  if s.leg and s.leg.dry and moving then cost = cost + 2 end
  for _, p in ipairs(s.party) do
    if p.alive and p.ill then cost = cost + 1 end
  end
  return cost
end

local function bury(s, index, cause, rng)
  local p = s.party[index]
  local line = M.deathLine(p.name, cause)
  p.alive, p.ill = false, nil
  s.lives = s.lives - 1
  say(s, line)
  s.tombs[#s.tombs + 1] = {
    name = p.name, cause = text.CAUSES[cause], line = line, date = s.date, miles = s.miles,
    epitaph = text.EPITAPHS[rng(#text.EPITAPHS)],
  }
  s.graves[#s.graves + 1] = { name = p.name, cause = text.CAUSES[cause], date = s.date }
  s.stop = true
  emit(s, "death")
end

--- Someone at random among the living, or nil.
local function anyone(s, rng)
  local living = {}
  for i, p in ipairs(s.party) do
    if p.alive then living[#living + 1] = i end
  end
  if #living == 0 then return nil end
  return living[rng(#living)]
end

local function fallIll(s, person, rng)
  local weights = 0
  for _, name in ipairs(ILLNESSES) do weights = weights + SICK[name].weight end
  local roll = rng(weights)
  for _, name in ipairs(ILLNESSES) do
    roll = roll - SICK[name].weight
    if roll <= 0 then
      person.ill = name
      say(s, hasWord(person.name) .. " " .. name .. ".")
      s.stop = true
      emit(s, "ill")
      return
    end
  end
end

--- The chance a well person takes ill today. Foul water makes it three times likelier.
function M.illChance(s)
  return 0.0045 * (1 + s.health / 30) * (s.foul > 0 and 3 or 1)
end

--- A day for each of the party: the sick mend or don't, and the well may not stay so.
local function tendParty(s, rng, resting)
  for i, p in ipairs(s.party) do
    if p.alive then
      if p.ill then
        local die = SICK[p.ill].die * (1 + s.health / 40) * (resting and 0.5 or 1)
        local roll = rng()
        if roll < die then
          bury(s, i, p.ill, rng)
        elseif roll < die + (resting and 0.2 or 0.1) then
          p.ill = nil
          say(s, isWord(p.name) .. " well again.")
        end
      elseif rng() < M.illChance(s) then
        fallIll(s, p, rng)
      end
    end
  end
  if s.health < 105 then return end
  -- past very poor, hardship kills on its own
  for i, p in ipairs(s.party) do
    if p.alive and rng() < (s.health - 100) / 500 then
      local cause = "exhaustion"
      if s.goods.food <= 0 then cause = "starvation" elseif s.weather.temp < 20 then cause = "cold" end
      bury(s, i, cause, rng)
    end
  end
end

-- ---------------------------------------------------------------- what the road brings

local function loseDays(s, rng, days)
  for _ = 1, days do
    if s.lives > 0 then M.passDay(s, rng, false, false) end
  end
end

--- Part of everything goes overboard. Returns a list of what, in words.
local function loseGoods(s, rng, lo, hi)
  local share = lo + (hi - lo) * rng()
  local lost = {}
  for _, item in ipairs(ITEMS) do
    if item.id ~= "oxen" then
      local have = s.goods[item.id]
      local gone = have > 3 and floor(have * share) or (rng() < share and min(have, 1) or 0)
      if item.id == "ammo" then gone = gone - gone % 10 end
      if gone > 0 then
        s.goods[item.id] = have - gone
        lost[#lost + 1] = M.quantity(item.id, gone)
      end
    end
  end
  return lost
end

local function sayLost(s, lost)
  if #lost > 0 then say(s, "Lost: " .. table.concat(lost, ", ") .. ".") end
end

local function breakPart(s, rng, part, name)
  s.stop = true
  emit(s, "break")
  say(s, "A " .. name .. " broke.")
  if s.goods[part] > 0 then
    s.goods[part] = s.goods[part] - 1
    say(s, "You fit a spare and press on.")
    return
  end
  local handy = PROFESSIONS[s.profession].repair
  if rng() < (handy and 0.8 or 0.4) then
    local days = rng(2)
    say(s, "No spare. You mend it after a fashion, and lose " .. days .. (days == 1 and " day." or " days."))
    loseDays(s, rng, days)
  else
    local days = 3 + rng(4)
    say(s, "No spare. You lose " .. days .. " days whittling a new one, and it shows.")
    loseDays(s, rng, days)
  end
end

local EVENTS = {}
M.EVENTS = EVENTS

function EVENTS.wheel(s, rng) breakPart(s, rng, "wheel", "wagon wheel") end
function EVENTS.axle(s, rng) breakPart(s, rng, "axle", "wagon axle") end
function EVENTS.tongue(s, rng) breakPart(s, rng, "tongue", "wagon tongue") end

--- Something worth stopping the wagon for.
local function halt(s, line, sound)
  s.stop = true
  say(s, line)
  if sound then emit(s, sound) end
end

function EVENTS.wander(s, rng)
  if s.goods.oxen == 0 then return end
  local days = rng(3)
  local spent = days .. (days == 1 and " day" or " days")
  if rng() < 0.3 then
    s.goods.oxen = s.goods.oxen - 1
    halt(s, "An ox wandered off. After " .. spent .. " of looking, you stop looking.")
  else
    halt(s, "The oxen wandered off. You lose " .. spent .. " rounding them up.")
  end
  loseDays(s, rng, days)
end

function EVENTS.oxdies(s)
  if s.goods.oxen == 0 then return end
  s.goods.oxen = s.goods.oxen - 1
  halt(s, "An ox has died. The rest look at you.", "break")
end

function EVENTS.thieves(s, rng)
  local id = ({ "food", "ammo", "clothes" })[rng(3)]
  local have = s.goods[id]
  local gone = id == "food" and floor(have * (0.1 + 0.02 * rng(5))) or ceil(have * 0.25)
  if id == "ammo" then gone = gone - gone % 10 end
  if gone <= 0 then
    halt(s, "Thieves came in the night, looked over what you own, and left.", "break")
    return
  end
  s.goods[id] = have - gone
  halt(s, "Thieves came in the night. You are short " .. M.quantity(id, gone) .. ".", "break")
end

function EVENTS.badwater(s)
  s.foul = 4
  halt(s, "Bad water. Everyone's insides have taken note.")
end

function EVENTS.wrongtrail(s, rng)
  local days = 1 + rng(3)
  halt(s, "Wrong trail. You lose " .. days .. " days, and no one will say whose idea it was.")
  loseDays(s, rng, days)
end

function EVENTS.snakebite(s, rng)
  local i = anyone(s, rng)
  if not i then return end
  local p = s.party[i]
  p.ill = "snakebite"
  halt(s, wasWord(p.name) .. " bitten by a snake.", "ill")
end

function EVENTS.brokenarm(s, rng)
  local i = anyone(s, rng)
  if not i then return end
  local p = s.party[i]
  p.ill = "broken arm"
  halt(s, p.name .. " broke an arm.", "ill")
end

function EVENTS.fruit(s)
  s.goods.food = min(ITEM.food.max, s.goods.food + 20)
  halt(s, "Wild fruit by the trail. 20 pounds of food, and nobody has to shoot it.", "good")
end

function EVENTS.abandoned(s, rng)
  local id = ({ "wheel", "axle", "tongue", "clothes", "ammo" })[rng(5)]
  local n = id == "ammo" and 40 or (id == "clothes" and 2 or 1)
  s.goods[id] = min(ITEM[id].max, s.goods[id] + n)
  halt(s, "An abandoned wagon. Its owners are past needing " .. M.quantity(id, n) .. ". You are not.", "good")
end

--- How likely each event is today. A snake wants warmth, fruit a summer, and foul water a dry spell.
local function eventWeights(s)
  local _, month = calendar(s.date)
  local temp = s.weather.temp
  return {
    { "wheel", 3 }, { "axle", 2 }, { "tongue", 2 }, { "wander", 2 }, { "oxdies", s.goods.oxen > 0 and (PROFESSIONS[s.profession].oxenCare and 1 or 2) or 0 },
    { "thieves", 2 }, { "badwater", s.dry > 8 and 3 or 1 }, { "wrongtrail", 2 }, { "snakebite", temp >= 55 and 2 or 0 },
    { "brokenarm", s.pace == "grueling" and 3 or 1 }, { "fruit", (month >= 6 and month <= 9) and 2 or 0 }, { "abandoned", 2 },
  }
end

local function roadEvent(s, rng)
  local weights = eventWeights(s)
  local total = 0
  for _, pair in ipairs(weights) do total = total + pair[2] end
  local roll = rng(total)
  for _, pair in ipairs(weights) do
    roll = roll - pair[2]
    if roll <= 0 then
      EVENTS[pair[1]](s, rng)
      return
    end
  end
end

--- Miles the wagon makes today.
function M.speed(s)
  if s.leg and s.leg.raft then return 30 end
  if s.goods.oxen == 0 then return 3 end -- the family in the traces
  local miles = PACE[s.pace].miles * min(1, (s.goods.oxen + 2) / 6)
  if s.weather.sky == "rain" then miles = miles * 0.85 end
  if s.snow > 2 then miles = miles * 0.6 end
  if M.elevation(s) >= 5000 then miles = miles * 0.8 end
  return max(3, floor(miles))
end

--- The wagon's day on the road, and what it ran into.
local function driveOn(s, rng)
  local leg = s.leg
  local miles = min(leg.left, M.speed(s))
  leg.left = leg.left - miles
  s.miles = s.miles + miles
  s.score = max(s.score, floor(s.miles / 10))
  if leg.left <= 0 then
    s.arriving, s.stop = true, true
    return
  end
  if leg.raft then
    if rng() < 0.2 then
      s.stop = true
      emit(s, "splash")
      say(s, "Rapids! The raft spins and ships water.")
      sayLost(s, loseGoods(s, rng, 0.05, 0.2))
      if rng() < 0.25 then
        local i = anyone(s, rng)
        if i then bury(s, i, "drowned", rng) end
      end
    end
    return
  end
  if rng() < M.blizzardChance(M.elevation(s), s.weather.temp) then
    local days = 1 + rng(3)
    s.stop = true
    s.snow = s.snow + 6
    emit(s, "break")
    say(s, "A blizzard. " .. days .. " days lost in the drifts.")
    loseDays(s, rng, days)
    s.weather.sky = "blizzard"
    return
  end
  if leg.dry and s.goods.oxen > 0 and rng() < 0.03 then
    EVENTS.oxdies(s)
    return
  end
  if rng() < EVENT_CHANCE then roadEvent(s, rng) end
end

--- One day. moving rolls the wagon, and resting is a real rest: it heals faster than a day merely lost.
function M.passDay(s, rng, moving, resting)
  s.date = s.date + 1
  if s.departed then s.day = s.day + 1 end
  setWeather(s, rng)
  s.goods.food = max(0, s.goods.food - RATIONS[s.rations].food * s.lives)
  s.foul = max(0, s.foul - 1)
  local cost = strainOf(s, moving)
  if resting then
    s.health = round2(s.health * 0.8 + cost * 0.5)
  else
    s.health = round2(s.health * 0.9 + cost)
  end
  tendParty(s, rng, resting)
  if moving and s.lives > 0 then driveOn(s, rng) end
end

-- ---------------------------------------------------------------- what comes next

local function setLeg(s, to, miles, extra)
  extra = extra or {}
  s.leg = { to = to, miles = miles, left = miles, dry = extra.dry, raft = extra.raft, peak = extra.peak }
end

--- A river's depth on the day you reach it: higher in spring melt, lower by late summer, and higher after rain.
function M.riverDepth(s, rng, usual)
  local _, month = calendar(s.date)
  local season = 0
  if month >= 4 and month <= 6 then season = 0.6 elseif month >= 8 then season = -0.7 end
  return max(0.8, floor((usual + season + s.wet * 0.04 + rng(9) * 0.1 - 0.5) * 10 + 0.5) / 10)
end

--- The score for reaching Oregon: the original's table.
function M.tally(s)
  local g = s.goods
  local rows = {}
  local subtotal = 0
  local function add(label, points)
    rows[#rows + 1] = { label = label, points = points }
    subtotal = subtotal + points
  end
  local word = M.healthWord(s.health)
  local each = ({ good = 500, fair = 400, poor = 300, ["very poor"] = 200 })[word]
  local alive = livingCount(s)
  add(alive .. (alive == 1 and " soul" or " souls") .. " in " .. word .. " health, " .. each .. " each", alive * each)
  add("The wagon", 50)
  add(g.oxen .. " oxen, 4 each", g.oxen * 4)
  local spares = g.wheel + g.axle + g.tongue
  add(spares .. " spare parts, 2 each", spares * 2)
  add(g.clothes .. " sets of clothing, 2 each", g.clothes * 2)
  add(g.ammo .. " bullets, 1 per 50", floor(g.ammo / 50))
  add(M.commas(g.food) .. " pounds of food, 1 per 25", floor(g.food / 25))
  add("$" .. M.commas(s.money) .. " cash, 1 per $5", floor(s.money / 5))
  local mult = PROFESSIONS[s.profession].mult
  return { rows = rows, subtotal = subtotal, mult = mult, total = subtotal * mult }
end

--- Reach the place the leg was heading for. Returns true if the run has reached the end of the road.
local function reach(s, rng)
  local id = s.leg.to
  local node = ROUTE[id]
  s.arriving, s.at, s.leg = false, id, nil
  s.level = s.level + 1
  s.visited[#s.visited + 1] = id
  s.camped, s.rests, s.waits = 0, 0, 0
  if node.final then
    s.tally = M.tally(s)
    s.score = max(s.score, s.tally.total)
    go(s, "arrive")
    emit(s, "arrive")
    return true
  end
  s.fort = node.price and id or nil
  emit(s, "landmark")
  if node.river then
    local r = node.river
    s.river = { id = id, name = node.name, depth = M.riverDepth(s, rng, r.depth), width = r.width, swift = r.swift, ferry = r.ferry }
  else
    s.noteTitle, s.noteScene = node.name, node.kind
    say(s, text.ARRIVE[id])
  end
  if node.fork then
    s.fork = id
  else
    setLeg(s, node.next, node.miles)
  end
  return false
end

--- Decide the next screen, from whatever a stage left waiting.
local function flow(s, rng)
  while true do
    if s.notes[1] then
      s.report = { title = s.noteTitle or "On the trail", lines = s.notes, scene = s.noteScene }
      s.notes, s.noteTitle, s.noteScene = {}, nil, nil
      go(s, "report")
      return
    end
    if s.tombs[1] then
      s.tomb = table.remove(s.tombs, 1)
      go(s, "tomb")
      return
    end
    if s.lives <= 0 then
      go(s, "lost")
      return
    end
    if s.river then
      go(s, "river")
      return
    end
    if s.fork then
      go(s, "fork")
      return
    end
    if s.arriving then
      if reach(s, rng) then return end
    else
      go(s, "trail")
      return
    end
  end
end

-- ---------------------------------------------------------------- rivers

--- The water takes part of the goods and, sometimes, someone.
local function swamped(s, rng, lo, hi, drownChance)
  sayLost(s, loseGoods(s, rng, lo, hi))
  emit(s, "splash")
  if rng() < drownChance then
    local i = anyone(s, rng)
    if i then bury(s, i, "drowned", rng) end
  end
end

--- Wade it. Up to 2.5 feet is safe, up to 3 mires the wagon, and past that the river has a vote.
local function ford(s, r, rng)
  if r.depth <= 2.5 then
    say(s, "You ford the river at " .. r.depth .. " feet, with wet boots and nothing worse.")
  elseif r.depth <= 3 then
    say(s, "The wagon bogs down in midstream. It costs you a day, and the goods get damp.")
    loseDays(s, rng, 1)
  elseif rng() < min(0.95, 0.25 + (r.depth - 3) * 0.3) then
    say(s, "Too deep. The wagon swamps and rolls.")
    swamped(s, rng, 0.15, 0.4, min(0.8, (r.depth - 3) / 4))
  else
    say(s, "Too deep, but you reach the far bank, by luck and no other means.")
  end
end

--- Float it. Too shallow grounds it. Deep water is what it's for, though a fast river can still turn it over.
local function caulk(s, r, rng)
  if r.depth < 1.5 then
    say(s, "Too shallow to float. The wagon grounds and you lose a day hauling it off.")
    loseDays(s, rng, 1)
  elseif rng() < 0.08 + r.swift + r.width / 10000 then
    say(s, "The current turns the wagon over.")
    swamped(s, rng, 0.1, 0.35, 0.3)
  else
    say(s, "You caulk the wagon and float across, bailing all the way.")
  end
end

local function ferry(s, r, rng)
  local days = rng(3)
  s.money = s.money - r.ferry
  say(s, "The ferry takes $" .. r.ferry .. " and " .. days .. (days == 1 and " day" or " days") .. " of waiting in line. It lands you dry.")
  loseDays(s, rng, days)
end

local function crossRiver(s, id, rng)
  local r = s.river
  if id == "wait" then
    s.waits = s.waits + 1
    M.passDay(s, rng, false, false)
    r.depth = M.riverDepth(s, rng, ROUTE[r.id].river.depth)
    flow(s, rng)
    if s.screen == "river" then s.notice = "A day goes by. The river stands at " .. r.depth .. " feet." end
    return
  end
  s.noteTitle, s.noteScene = r.name, "river"
  if id == "ford" then
    ford(s, r, rng)
  elseif id == "caulk" then
    caulk(s, r, rng)
  else
    ferry(s, r, rng)
  end
  s.river = nil
  flow(s, rng)
end

-- ---------------------------------------------------------------- the store

--- What a lot costs here.
function M.price(s, id)
  local fort = s.fort and ROUTE[s.fort]
  return ceil(ITEM[id].price * (fort and fort.price or 1))
end

local function buy(s, id)
  local item = ITEM[id]
  local cost = M.price(s, id)
  if s.money < cost then
    s.notice = "You can't afford it."
  elseif s.goods[id] + item.lot > item.max then
    s.notice = "That's all the wagon will take."
  else
    s.money = s.money - cost
    s.goods[id] = s.goods[id] + item.lot
    s.cart[id] = (s.cart[id] or 0) + 1
    s.notice = nil
    emit(s, "buy")
  end
end

--- Put back something bought on this visit. Nothing else: this is a store, not a pawn shop.
local function putBack(s, id)
  if (s.cart[id] or 0) <= 0 then
    s.notice = "You bought none of that here."
    return
  end
  s.money = s.money + M.price(s, id)
  s.goods[id] = s.goods[id] - ITEM[id].lot
  s.cart[id] = s.cart[id] - 1
  s.notice = nil
  emit(s, "buy")
end

local function leaveStore(s, rng)
  if s.departed then
    s.shopped = s.at
    s.cart = {}
    flow(s, rng)
    return
  end
  if s.goods.oxen < 2 then
    s.notice = "\"You can't pull that wagon yourself,\" says Matt. Buy a yoke."
    return
  end
  s.departed, s.cart = true, {}
  setLeg(s, ROUTE.independence.next, ROUTE.independence.miles)
  setWeather(s, rng)
  s.noteTitle, s.noteScene = "Independence, Missouri", "town"
  say(s, "It is " .. M.dateText(s.date) .. ". The wagons roll at first light, and two thousand miles lie between you and Oregon.")
  flow(s, rng)
end

-- ---------------------------------------------------------------- the hunt

local function startHunt(s)
  s.hunt = { left = M.HUNT_TICKS, wait = 5, bag = 0, shots = 0, animals = {} }
  go(s, "hunt")
end

local function endHunt(s, rng)
  local h = s.hunt
  local carried = min(h.bag, M.CARRY_LIMIT)
  s.goods.food = min(ITEM.food.max, s.goods.food + carried)
  s.hunt = nil
  s.camped = s.camped + 1
  s.noteTitle = "The hunt"
  if h.bag > M.CARRY_LIMIT then
    say(s, "You shot " .. h.bag .. " pounds of meat, but could only carry " .. M.CARRY_LIMIT .. " back to the wagon.")
  elseif h.bag > 0 then
    say(s, "You shot " .. h.bag .. " pounds of meat and carried it back.")
  else
    say(s, "You fired " .. h.shots .. (h.shots == 1 and " shot" or " shots") .. " and brought back an appetite.")
  end
  M.passDay(s, rng, false, false)
  flow(s, rng)
end

local function spawnAnimal(s, h, rng)
  local kinds = M.elevation(s) >= 4500 and GAME_HIGH or GAME_PLAINS
  local kind = kinds[rng(#kinds)]
  local sp = SPECIES[kind]
  local right = rng(2) == 1
  h.animals[#h.animals + 1] = {
    kind = kind, w = sp.w, h = sp.h, y = M.HUNT_SKY + rng(M.HUNT_H - M.HUNT_SKY - sp.h - 2),
    x = right and M.HUNT_W or -sp.w, vx = right and -sp.speed or sp.speed,
  }
end

local function huntStep(s, rng)
  local h = s.hunt
  h.left = h.left - 1
  for i = #h.animals, 1, -1 do
    local a = h.animals[i]
    if a.dead then
      a.dead = a.dead - 1
      if a.dead <= 0 then table.remove(h.animals, i) end
    else
      a.x = a.x + a.vx
      if a.x < -a.w or a.x > M.HUNT_W then table.remove(h.animals, i) end
    end
  end
  h.wait = h.wait - 1
  if h.wait <= 0 and h.left > 20 and #h.animals < 4 then
    spawnAnimal(s, h, rng)
    h.wait = 8 + rng(10)
  end
  if h.left <= 0 or s.goods.ammo <= 0 then endHunt(s, rng) end
end

--- A tap in the field: one bullet, wherever it lands, and the nearest animal under it falls.
local function shoot(s, x, y)
  local h = s.hunt
  if s.goods.ammo <= 0 then return end
  s.goods.ammo = s.goods.ammo - 1
  h.shots = h.shots + 1
  local hit = false
  for i = #h.animals, 1, -1 do
    local a = h.animals[i]
    if not a.dead and x >= a.x - 1 and x < a.x + a.w + 1 and y >= a.y - 1 and y < a.y + a.h + 1 then
      a.dead = 8
      h.bag = h.bag + SPECIES[a.kind].pounds
      hit = true
      break
    end
  end
  h.flash = { x = x, y = y, hit = hit, left = 2 }
  emit(s, hit and "hit" or "shot")
end

-- ---------------------------------------------------------------- menus

--- Who is sick right now, as "Mary (cholera)".
function M.sickList(s)
  local out = {}
  for _, p in ipairs(s.party) do
    if p.alive and p.ill then out[#out + 1] = p.name .. " (" .. p.ill .. ")" end
  end
  return out
end

local function entries(list)
  local out = {}
  for i = 1, #list, 2 do out[#out + 1] = { id = list[i], label = list[i + 1] } end
  return out
end

local MENUS = {}

function MENUS.month()
  local out = {}
  for _, month in ipairs(MONTHS) do out[#out + 1] = { id = month.id, label = month.label } end
  return out
end

function MENUS.store()
  local out = {}
  for _, item in ipairs(ITEMS) do
    out[#out + 1] = { id = "sell_" .. item.id, label = "-" }
    out[#out + 1] = { id = "buy_" .. item.id, label = "+" }
  end
  out[#out + 1] = { id = "leave", label = "LEAVE STORE" }
  return out
end

function MENUS.trail(s)
  local out = entries({
    "continue", "CONTINUE", "supplies", "SUPPLIES", "pace", "PACE", "rations", "RATIONS", "rest", "REST",
    "trade", "TRADE", "talk", "TALK", "hunt", "HUNT",
  })
  if s.fort then out[#out + 1] = { id = "buy", label = "BUY" } end
  return out
end

-- screens that always offer the same
for screen, list in pairs({
  report = { "ok", "CONTINUE" }, tomb = { "ok", "CONTINUE" }, supplies = { "ok", "BACK TO THE WAGON" },
  arrive = { "finish", "FINISH" }, lost = { "finish", "FINISH" }, hunt = { "done", "DONE" }, trade = { "take", "TAKE IT", "refuse", "NO THANKS" },
  pace = { "steady", "STEADY", "strenuous", "STRENUOUS", "grueling", "GRUELING", "back", "BACK" },
  rations = { "filling", "FILLING", "meager", "MEAGER", "bare", "BARE BONES", "back", "BACK" },
  rest = { "1", "1 DAY", "3", "3 DAYS", "5", "5 DAYS", "back", "BACK" },
  profession = { "banker", "BANKER $1,600", "carpenter", "CARPENTER $800", "farmer", "FARMER $400" },
}) do
  MENUS[screen] = function() return entries(list) end
end

function MENUS.river(s)
  local r = s.river
  local out = entries({ "ford", "FORD", "caulk", "CAULK IT" })
  if r.ferry and s.money >= r.ferry then out[#out + 1] = { id = "ferry", label = "FERRY $" .. r.ferry } end
  out[#out + 1] = { id = "wait", label = "WAIT A DAY" }
  return out
end

function MENUS.fork(s)
  local out = {}
  for _, id in ipairs(ROUTE[s.fork].fork) do
    local fork = FORKS[id]
    if s.money >= (fork.toll or 0) then out[#out + 1] = { id = id, label = fork.label } end
  end
  return out
end

--- What the current screen offers, as a list of { id, label }.
function M.choices(s)
  local menu = MENUS[s.screen]
  return menu and menu(s) or {}
end

local PICK = {}

function PICK.profession(s, id)
  s.profession = id
  s.money = PROFESSIONS[id].money
  go(s, "month")
end

function PICK.month(s, id)
  for _, month in ipairs(MONTHS) do
    if month.id == id then s.date, s.month = month.date, id end
  end
  go(s, "store")
end

function PICK.store(s, id, rng)
  if id == "leave" then
    leaveStore(s, rng)
    return
  end
  local verb, what = id:match("^(%a+)_(%a+)$")
  if verb == "buy" then buy(s, what) else putBack(s, what) end
end

function PICK.trail(s, id, rng)
  if id == "continue" then
    s.fort, s.camped = nil, 0
    s.roll = { days = STAGE_DAYS, moving = true, t = 0 }
    go(s, "roll")
  elseif id == "buy" then
    s.cart = {}
    go(s, "store")
  elseif id == "talk" then
    local here, lines = text.TALK[s.at], text.TALK_ANY
    if here and rng() < 0.7 then lines = here end
    s.noteTitle = "You talk to some folks"
    say(s, lines[rng(#lines)])
    flow(s, rng)
  elseif id == "trade" then
    local open = {}
    for _, offer in ipairs(OFFERS) do
      if s.goods[offer.want] >= offer.wantN then open[#open + 1] = offer end
    end
    if #open == 0 then
      s.notice = "Nobody wants what little you have."
      return
    end
    local offer = open[rng(#open)]
    s.offer = { want = offer.want, wantN = offer.wantN, get = offer.get, getN = offer.getN }
    go(s, "trade")
  elseif id == "hunt" then
    if s.goods.ammo <= 0 then
      s.notice = "You have no bullets. The rabbits are aware of this."
      return
    end
    startHunt(s)
  else
    go(s, id)
  end
end

function PICK.report(s, _, rng) flow(s, rng) end
function PICK.tomb(s, _, rng) flow(s, rng) end
function PICK.supplies(s, _, rng) flow(s, rng) end
function PICK.arrive(s) s.over, s.won = true, true end
function PICK.lost(s) s.over = true end

function PICK.pace(s, id)
  if id ~= "back" then s.pace = id end
  go(s, "trail")
end

function PICK.rations(s, id)
  if id ~= "back" then s.rations = id end
  go(s, "trail")
end

function PICK.rest(s, id)
  if id == "back" then
    go(s, "trail")
    return
  end
  s.camped, s.rests = s.camped + 1, s.rests + 1
  s.roll = { days = tonumber(id), moving = false, t = 0 }
  go(s, "roll")
end

function PICK.trade(s, id, rng)
  local offer = s.offer
  if id == "take" then
    s.goods[offer.want] = s.goods[offer.want] - offer.wantN
    s.goods[offer.get] = min(ITEM[offer.get].max, s.goods[offer.get] + offer.getN)
    emit(s, "buy")
  end
  s.offer = nil
  s.camped = s.camped + 1
  M.passDay(s, rng, false, false)
  flow(s, rng)
end

function PICK.river(s, id, rng) crossRiver(s, id, rng) end

function PICK.fork(s, id, rng)
  local fork = FORKS[id]
  s.money = s.money - (fork.toll or 0)
  s.fork = nil
  setLeg(s, fork.to, fork.miles, fork)
  flow(s, rng)
end

function PICK.hunt(s, _, rng) endHunt(s, rng) end

local function offered(s, id)
  for _, choice in ipairs(M.choices(s)) do
    if choice.id == id then return true end
  end
  return false
end

--- Act on one tap. A tap from an older screen, or for a choice not on this one, is dropped.
local function apply(s, action, rng)
  if action.seq and action.seq ~= s.seq then return end
  if action.kind == "shoot" then
    if s.screen == "hunt" then shoot(s, action.x, action.y) end
  elseif action.kind == "pick" and offered(s, action.id) then
    if s.screen ~= "store" then emit(s, "pick") end
    PICK[s.screen](s, action.id, rng)
  end
end

local function rollStep(s, rng)
  local r = s.roll
  if r.moving then s.road = s.road + 2 end
  r.t = r.t + 1
  if r.t < DAY_TICKS then return end
  r.t, s.stop = 0, false
  M.passDay(s, rng, r.moving, not r.moving)
  r.days = r.days - 1
  if s.stop or r.days <= 0 then
    s.roll = nil
    flow(s, rng)
  end
end

-- ---------------------------------------------------------------- the contract

function M.new(opts)
  local rng = opts.rng
  local pool, party = {}, { { name = "You", alive = true } }
  for i, name in ipairs(text.NAMES) do pool[i] = name end
  for i = 2, 5 do party[i] = { name = table.remove(pool, rng(#pool)), alive = true } end
  local s = {
    score = 0, level = 1, over = false, lives = 5, screen = "profession", seq = 1, idle = 0, clock = 0, road = 0,
    inbox = {}, ev = {}, notes = {}, tombs = {}, graves = {}, visited = { "independence" }, cart = {},
    party = party, money = 0, at = "independence", date = 60, day = 0, miles = 0,
    goods = { oxen = 0, food = 0, clothes = 0, ammo = 0, wheel = 0, axle = 0, tongue = 0 },
    pace = "steady", rations = "filling", health = 0, snow = 0, wet = 0, dry = 0, foul = 0, camped = 0, rests = 0, waits = 0,
    departed = false,
  }
  s.weather = { temp = 50, word = M.weatherWord(50), sky = "clear" }
  return s
end

function M.input(s, action)
  if #s.inbox < INBOX_MAX then s.inbox[#s.inbox + 1] = action end
end

function M.tick(s, rng)
  if s.over then return {} end
  s.clock, s.idle = s.clock + 1, s.idle + 1
  local action = table.remove(s.inbox, 1)
  if action then apply(s, action, rng) end
  if s.hunt and s.hunt.flash then
    local flash = s.hunt.flash
    flash.left = flash.left - 1
    if flash.left <= 0 then s.hunt.flash = nil end
  end
  if s.screen == "roll" then
    rollStep(s, rng)
  elseif s.screen == "hunt" then
    huntStep(s, rng)
  end
  local events = s.ev
  s.ev = {}
  return events
end

--- A line for the saved-game list.
function M.summary(s)
  if not s.departed then return "Matt's store, Independence" end
  return "Day " .. s.day .. ", " .. ROUTE[s.at].name
end

-- ---------------------------------------------------------------- the bot

local function pick(id) return { kind = "pick", id = id } end

--- Spend sensibly at Matt's: enough to pull, wear and shoot, one of each spare, then food, keeping a little for ferries.
local function botStore(s)
  local g, money = s.goods, s.money
  local plan = {
    { "oxen", 4 }, { "clothes", 5 }, { "ammo", 40 }, { "wheel", 1 }, { "axle", 1 }, { "tongue", 1 }, { "oxen", 6 },
    { "clothes", 10 }, { "ammo", 100 },
  }
  if s.departed then plan = { { "ammo", 40 }, { "wheel", 1 }, { "axle", 1 }, { "tongue", 1 } } end
  for _, want in ipairs(plan) do
    if g[want[1]] < want[2] and money >= M.price(s, want[1]) + 20 then return pick("buy_" .. want[1]) end
  end
  if g.food + ITEM.food.lot <= ITEM.food.max and money >= M.price(s, "food") + 40 then return pick("buy_food") end
  return pick("leave")
end

--- The rations that will last the road ahead.
local function botRations(s)
  local need = s.lives * RATIONS.filling.food * (M.TOTAL_MILES - s.miles) / 13
  if s.goods.food >= need then return "filling" end
  return s.goods.food >= need * 0.6 and "meager" or "bare"
end

--- Late in the year, with the mountains still ahead, it hurries.
local function botPace(s)
  return (s.date > 235 and s.miles < 1400) and "strenuous" or "steady"
end

local function botTrail(s, rng)
  local g = s.goods
  if s.rations ~= botRations(s) then return pick("rations") end
  if s.pace ~= botPace(s) then return pick("pace") end
  if s.fort and s.shopped ~= s.fort and s.money >= 60 and g.food < 800 then return pick("buy") end
  if (#M.sickList(s) > 0 or s.health >= 70) and s.rests < 3 and g.food > 0 then return pick("rest") end
  if g.food < 500 and g.ammo >= 20 and s.camped < 2 then return pick("hunt") end
  if s.camped == 0 and rng() < 0.08 then return pick("talk") end
  return pick("continue")
end

local function botRiver(s)
  local r = s.river
  if r.depth <= 2.5 then return pick("ford") end
  if r.ferry and s.money >= r.ferry then return pick("ferry") end
  if r.depth > 4 and s.waits < 2 then return pick("wait") end
  if r.depth < 1.5 then return pick("ford") end
  return pick("caulk")
end

--- The nearest thing to the middle of the field that's still up, while there's meat worth having.
local function botHunt(s)
  local h = s.hunt
  if h.bag >= M.CARRY_LIMIT then return pick("done") end
  if s.clock % 3 ~= 0 then return nil end
  for _, a in ipairs(h.animals) do
    if not a.dead and a.x >= 0 and a.x + a.w <= M.HUNT_W then
      return { kind = "shoot", x = floor(a.x + a.w / 2), y = a.y + floor(a.h / 2) }
    end
  end
  return nil
end

function M.bot(s, rng)
  if s.over or s.inbox[1] then return nil end
  if s.screen == "hunt" then return botHunt(s) end
  if s.screen == "roll" then return nil end
  if s.idle < (s.screen == "store" and BOT_SHOP_WAIT or BOT_WAIT) then return nil end
  local screen = s.screen
  if screen == "profession" then return pick(({ "banker", "carpenter", "farmer" })[rng(3)]) end
  if screen == "month" then return pick(rng(2) == 1 and "apr" or "may") end
  if screen == "store" then return botStore(s) end
  if screen == "trail" then return botTrail(s, rng) end
  if screen == "river" then return botRiver(s) end
  if screen == "fork" then
    local choices = M.choices(s)
    return pick(choices[rng(#choices)].id)
  end
  if screen == "rest" then return pick(s.health >= 70 and "5" or "3") end
  if screen == "rations" then return pick(botRations(s)) end
  if screen == "pace" then return pick(botPace(s)) end
  if screen == "arrive" or screen == "lost" then return pick("finish") end
  if screen == "trade" then return pick("refuse") end
  return pick("ok")
end

return M
