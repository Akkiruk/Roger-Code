-- games/cookie/rules.lua
-- Cookie Clicker: tap the big cookie, buy buildings that bake for you, buy upgrades, catch golden cookies, earn
-- achievements, and in the end ascend for heavenly chips that make every later run faster.
--
-- The state is plain data, so the save holds the whole bakery. The rules never touch the screen or the clock: a tick is
-- always a quarter of a second of baking, which makes a run the same every time from the same seed and taps. Real time
-- comes in only through M.wake(s, now), which the plugin calls with os.epoch("utc") after every tick. It stamps
-- s.lastSeen, and when the gap since the last stamp is long (a save loaded after a visit away, on this cabinet or
-- another, or after a reboot), it bakes for the time gone at half speed, up to a day, and leaves a greeting in s.away.

local data = require("games.cookie.data")

local M = {}

local floor, max, min = math.floor, math.max, math.min

M.TICK_MS = 250
local DT = M.TICK_MS / 1000
local PRICE_RISE = 1.15
local MODES = { 1, 10, 100 }
M.MODES = MODES

M.AWAY_MIN_MS = 15000            -- a gap shorter than this is just a slow tick, baked already
M.AWAY_CAP_MS = 24 * 3600 * 1000 -- a day at most is baked while away
M.AWAY_RATE = 0.5                -- at half speed, as the original's offline baking

local GOLDEN_WAIT_MIN, GOLDEN_WAIT_MAX = 2 * 60 * 4, 6 * 60 * 4 -- ticks between golden cookies
local GOLDEN_FIRST = 90 * 4                                      -- the first comes sooner, so a new baker sees one
local GOLDEN_LIFE = 13 * 4                                       -- ticks a golden cookie waits to be tapped
local FRENZY_TICKS, FRENZY_TIMES = 77 * 4, 7
local CLICK_TICKS, CLICK_TIMES = 13 * 4, 777
local TOAST_TICKS = 16
local NOTE_TICKS = 14
local POP_TICKS = 6
local POPS_KEPT = 6
local CONFIRM_TICKS = 16
local ACH_EVERY = 4              -- achievements are looked at once a second, and after every tap
local CHIP_UNIT = 1e12           -- heavenly chips: the cube root of all-time cookies in trillions
local LARGEST = 1e300            -- nothing grows past this, so nothing ever becomes infinite
local MILK_PER_ACH = 0.04

M.BUILDINGS, M.UPGRADES, M.ACHIEVEMENTS = data.BUILDINGS, data.UPGRADES, data.ACHIEVEMENTS
M.UPGRADE_BY_ID, M.ACH_BY_ID = data.UPGRADE_BY_ID, data.ACH_BY_ID
local BUILDINGS, UPGRADES, ACHIEVEMENTS = data.BUILDINGS, data.UPGRADES, data.ACHIEVEMENTS
local NB = #BUILDINGS

-- ---------------------------------------------------------------- numbers for people

-- Names of the powers of a thousand, from a million up past the largest number Lua can hold.
local NAMES, SHORT = {}, {}
do
  local first = { "million", "billion", "trillion", "quadrillion", "quintillion", "sextillion", "septillion", "octillion", "nonillion" }
  local firstShort = { "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No" }
  local units = { "un", "duo", "tre", "quattuor", "quin", "sex", "septen", "octo", "novem" }
  local unitsShort = { "U", "D", "T", "Qa", "Qi", "Sx", "Sp", "O", "N" }
  local tens = { "dec", "vigint", "trigint", "quadragint", "quinquagint", "sexagint", "septuagint", "octogint", "nonagint" }
  local tensShort = { "Dc", "Vg", "Tg", "Qag", "Qig", "Sxg", "Spg", "Ocg", "Nog" }
  for i = 1, 9 do NAMES[i], SHORT[i] = first[i], firstShort[i] end
  for i = 10, 99 do
    local u, t = i % 10, floor(i / 10)
    NAMES[i] = (u > 0 and units[u] or "") .. tens[t] .. "illion"
    SHORT[i] = (u > 0 and unitsShort[u] or "") .. tensShort[t]
  end
  NAMES[100], SHORT[100] = "centillion", "Ce"
  NAMES[101], SHORT[101] = "uncentillion", "UCe"
  NAMES[102], SHORT[102] = "duocentillion", "DCe"
end
M.NUMBER_NAMES = NAMES

local function commas(n)
  local text = string.format("%.0f", floor(n))
  local out = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

--- The mantissa and the name's place for a number of a million or more: 1234567 gives 1.235, 1 (million).
local function split(n)
  local k = floor(math.log(n) / math.log(10) / 3 + 1e-9) -- 2 for millions
  local mant = n / 10 ^ (k * 3)
  if mant < 1 then k, mant = k - 1, mant * 1000 end
  if mant >= 999.9995 then k, mant = k + 1, mant / 1000 end -- 999.9996 million would print as 1000.000
  return mant, k - 1
end

--- A number as a person reads it: 12,345 or 1.235 million or 4.560 quattuordecillion. Never scientific notation.
function M.fmt(n, places)
  n = tonumber(n) or 0
  if n ~= n then return "0" end
  if n < 0 then return "-" .. M.fmt(-n, places) end
  if n == math.huge then return "infinity" end
  if n < 1e6 then return commas(n) end
  local mant, i = split(n)
  local name = NAMES[i]
  if not name then return "infinity" end
  return string.format("%." .. (places or 3) .. "f", mant) .. " " .. name
end

--- The same without trailing zeros, for prices and goals: 20 million, 1.5 billion.
function M.fmtNice(n)
  local text = M.fmt(n)
  return (text:gsub("%.?0+ ", " "))
end

--- The same, short: 1.23M, 4.56B, 7.89Qa. For tight spaces.
function M.fmtShort(n)
  n = tonumber(n) or 0
  if n ~= n then return "0" end
  if n < 0 then return "-" .. M.fmtShort(-n) end
  if n == math.huge then return "inf" end
  if n < 1e6 then return commas(n) end
  local mant, i = split(n)
  if mant >= 999.5 then mant, i = mant / 1000, i + 1 end -- 999.6M would print as 1000M
  if not SHORT[i] then return "inf" end
  return string.format(mant >= 100 and "%.0f" or (mant >= 10 and "%.1f" or "%.2f"), mant) .. SHORT[i]
end

--- A rate, which can be a fraction: 0.1, 2.5, 1,234, 1.235 million.
function M.fmtRate(n, short)
  n = tonumber(n) or 0
  if n ~= n or n <= 0 then return "0" end
  if n < 100 and n ~= floor(n) then
    local text = string.format("%.1f", n)
    if text:sub(-2) == ".0" then text = text:sub(1, -3) end
    return text
  end
  return short and M.fmtShort(n) or M.fmt(n)
end

--- "3 hours 12 min", "45 seconds", "2 days 1 hour".
function M.duration(ms)
  local secs = floor((ms or 0) / 1000)
  if secs < 60 then return secs .. (secs == 1 and " second" or " seconds") end
  local mins = floor(secs / 60)
  if mins < 60 then return mins .. " min" end
  local hours = floor(mins / 60)
  local days = floor(hours / 24)
  if days > 0 then
    local h = hours % 24
    return days .. (days == 1 and " day" or " days") .. (h > 0 and (" " .. h .. (h == 1 and " hour" or " hours")) or "")
  end
  local m = mins % 60
  return hours .. (hours == 1 and " hour" or " hours") .. (m > 0 and (" " .. m .. " min") or "")
end

-- ---------------------------------------------------------------- a new bakery

local function newRun(s)
  s.cookies, s.baked, s.runTaps, s.runTicks = 0, 0, 0, 0
  s.owned = {}
  for i = 1, NB do s.owned[i] = 0 end
  s.ups = {}
  s.buff = nil
  s.gold = { wait = GOLDEN_FIRST }
  s.ui = { screen = "bake", page = 1, mode = 1, list = 1, confirm = 0 }
end

function M.new(_)
  local s = {
    v = 1, score = 0, level = 1, over = false, won = false, rev = 0,
    allTime = 0, hand = 0, taps = 0, goldenClicks = 0, upsBought = 0, ticks = 0, bestAway = 0,
    chips = 0, ascensions = 0, ach = {}, achCount = 0,
    toasts = {}, toastLeft = 0, away = nil, lastSeen = nil, heard = {},
    fx = { press = 0, pops = {}, note = nil, noteLeft = 0, popSeq = 0 },
  }
  newRun(s)
  return s
end

-- ---------------------------------------------------------------- what everything is worth

local function has(s, id) return s.ups[id] == true end

--- How many of a building's doubling tiers are bought.
local function tiers(s, i)
  local id, n = BUILDINGS[i].id, 0
  for tier = 1, 10 do
    if s.ups[id .. tier] then n = n + 1 end
  end
  return n
end

local function totalOwned(s)
  local n = 0
  for i = 1, NB do n = n + s.owned[i] end
  return n
end
M.totalOwned = totalOwned

--- Thousand fingers: what each cursor and each tap gains from every building that isn't a cursor.
local function fingers(s)
  if not has(s, "fingers1") then return 0 end
  local gain = 0.1
  for _, id in ipairs({ "fingers2", "fingers3", "fingers4" }) do
    if has(s, id) then gain = gain * data.UPGRADE_BY_ID[id].times end
  end
  return gain * (totalOwned(s) - s.owned[1])
end

function M.milk(s) return s.achCount * MILK_PER_ACH end

--- Everything that multiplies all production: flavours, heavenly chips and kittens.
function M.multiplier(s)
  local pct, kitten = 0, 1
  local milk = M.milk(s)
  for id in pairs(s.ups) do
    local u = data.UPGRADE_BY_ID[id]
    if u then
      if u.kind == "flavour" then pct = pct + u.pct end
      if u.kind == "kitten" then kitten = kitten * (1 + milk * u.per) end
    end
  end
  return (1 + pct / 100) * (1 + s.chips / 100) * kitten
end

--- What one of a building makes each second, before the multiplier.
local function eachBase(s, i)
  local b = BUILDINGS[i]
  local each = b.cps * 2 ^ tiers(s, i)
  if i == 1 then each = each + fingers(s) end
  return each
end

--- What one of building i makes each second, everything counted but a golden cookie's frenzy.
function M.eachCps(s, i)
  return eachBase(s, i) * M.multiplier(s)
end

--- Cookies per second without any frenzy: what the bakery bakes while you're away.
function M.rawCps(s)
  local total = 0
  for i = 1, NB do
    if s.owned[i] > 0 then total = total + s.owned[i] * eachBase(s, i) end
  end
  return min(LARGEST, total * M.multiplier(s))
end

--- Cookies per second right now, with a frenzy if one is on.
function M.cps(s)
  local rate = M.rawCps(s)
  if s.buff and s.buff.kind == "frenzy" then rate = rate * FRENZY_TIMES end
  return min(LARGEST, rate)
end

--- One tap of the big cookie.
function M.tapValue(s)
  local base = 2 ^ min(3, tiers(s, 1)) + fingers(s)
  local pct = 0
  for i = 1, 8 do
    if s.ups["mouse" .. i] then pct = pct + 1 end
  end
  local value = base * (1 + s.chips / 100) + M.cps(s) * pct / 100
  if s.buff and s.buff.kind == "click" then value = value * CLICK_TIMES end
  return min(LARGEST, value)
end

--- The price of the next n of building i.
function M.cost(s, i, n)
  n = n or 1
  local first = BUILDINGS[i].cost * PRICE_RISE ^ s.owned[i]
  if n == 1 then return math.ceil(first) end
  return math.ceil(first * (PRICE_RISE ^ n - 1) / (PRICE_RISE - 1))
end

--- How many buildings show in the store: every one up to the one after the best you own, and that one shows as ???.
function M.shownBuildings(s)
  local top = 0
  for i = 1, NB do
    if s.owned[i] > 0 then top = i end
  end
  return min(NB, max(2, top + 2))
end

--- Is building i still a mystery: shown, but neither owned nor ever within reach?
function M.mystery(s, i)
  if s.owned[i] > 0 or i == 1 then return false end
  return s.owned[i - 1] == 0 and s.baked < BUILDINGS[i].cost
end

local function unlocked(s, u)
  local k = u.kind
  if k == "building" or k == "tap" or k == "fingers" then return s.owned[u.of] >= u.needOwned end
  if k == "mouse" then return s.hand >= u.needHand end
  if k == "flavour" then return s.baked >= u.needBaked end
  if k == "kitten" then return s.achCount >= u.needAch end
  if k == "golden" then return s.goldenClicks >= u.needGolden end
  return false
end
M.unlocked = unlocked

--- Upgrades that can be bought now or once there's money for them, cheapest first.
function M.available(s)
  local out = {}
  for _, u in ipairs(UPGRADES) do
    if not s.ups[u.id] and unlocked(s, u) then out[#out + 1] = u end
  end
  table.sort(out, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.index < b.index
  end)
  return out
end

-- ---------------------------------------------------------------- heavenly chips

--- Chips earned by this many cookies, all time: the cube root of the trillions, exactly.
function M.chipsFor(allTime)
  local v = (allTime or 0) / CHIP_UNIT
  if v < 1 then return 0 end
  local c = floor(v ^ (1 / 3) + 0.5)
  if c > 2 ^ 40 then return c end -- past where a cube can be told from its neighbours, the root is as good as it gets
  while (c + 1) ^ 3 <= v do c = c + 1 end
  while c > 0 and c ^ 3 > v do c = c - 1 end
  return c
end

--- Chips an ascension now would bring.
function M.pendingChips(s)
  return max(0, M.chipsFor(s.allTime) - s.chips)
end

--- Cookies still to bake (all time) for one more chip.
function M.nextChipIn(s)
  local have = max(M.chipsFor(s.allTime), s.chips)
  return max(0, (have + 1) ^ 3 * CHIP_UNIT - s.allTime)
end

-- ---------------------------------------------------------------- baking

local function bake(s, amount)
  if amount ~= amount or amount <= 0 then return end
  s.cookies = min(LARGEST, s.cookies + amount)
  s.baked = min(LARGEST, s.baked + amount)
  s.allTime = min(LARGEST, s.allTime + amount)
  s.score = floor(s.allTime)
end

local function toast(s, title, text, color)
  s.toasts[#s.toasts + 1] = { title = title, text = text, color = color }
  if #s.toasts == 1 then s.toastLeft = TOAST_TICKS end
  while #s.toasts > 8 do table.remove(s.toasts, 2) end
end

local function note(s, text, color)
  s.fx.note, s.fx.noteColor, s.fx.noteLeft = text, color, NOTE_TICKS
end

--- The number an achievement counts.
local function stat(s, a)
  local k = a.kind
  if k == "baked" then return s.allTime end
  if k == "rate" then return M.rawCps(s) end
  if k == "hand" then return s.hand end
  if k == "taps" then return s.taps end
  if k == "golden" then return s.goldenClicks end
  if k == "owned" then return s.owned[a.of] end
  if k == "total" then return totalOwned(s) end
  if k == "ups" then return s.upsBought end
  if k == "ascend" then return s.ascensions end
  if k == "away" then return s.bestAway end
  if k == "neverclick" then return s.runTaps <= 15 and s.baked or 0 end
  return 0
end

--- What an achievement asks, in words.
function M.achText(a)
  if a.says:find("%%s") then return string.format(a.says, M.fmtNice(a.need)) end
  return a.says
end

local function checkAchievements(s, events)
  for _, a in ipairs(ACHIEVEMENTS) do
    if not s.ach[a.id] and stat(s, a) >= a.need then
      s.ach[a.id] = true
      s.achCount = s.achCount + 1
      toast(s, "ACHIEVEMENT UNLOCKED", a.name)
      events[#events + 1] = { type = "achievement", id = a.id }
    end
  end
end

local function goldenWait(s, rng)
  local wait = GOLDEN_WAIT_MIN + floor((GOLDEN_WAIT_MAX - GOLDEN_WAIT_MIN) * rng())
  if has(s, "lucky1") then wait = floor(wait / 2) end
  if has(s, "lucky2") then wait = floor(wait / 2) end
  return wait
end

local function goldenLife(s)
  local life = GOLDEN_LIFE
  if has(s, "lucky1") then life = life * 2 end
  if has(s, "lucky2") then life = life * 2 end
  return life
end

local function effectTicks(s, ticks)
  return has(s, "lucky3") and ticks * 2 or ticks
end

--- A golden cookie appears somewhere on the wall: x and y are shares of the room the view gives it.
local function spawnGolden(s, rng)
  local roll = rng()
  local effect = roll < 0.45 and "frenzy" or (roll < 0.9 and "lucky" or "click")
  s.gold.live = { x = rng(), y = rng(), left = goldenLife(s), effect = effect, life = goldenLife(s) }
end

--- A quarter second of baking. Returns the events for sounds.
function M.tick(s, rng)
  local events = {}
  if s.over then return events end
  s.ticks, s.runTicks = s.ticks + 1, s.runTicks + 1
  bake(s, M.cps(s) * DT)

  local buff = s.buff
  if buff then
    buff.left = buff.left - 1
    if buff.left <= 0 then
      s.buff = nil
      events[#events + 1] = { type = "buff_end", kind = buff.kind }
    end
  end

  local gold = s.gold
  if gold.live then
    gold.live.left = gold.live.left - 1
    if gold.live.left <= 0 then
      gold.live = nil
      gold.wait = goldenWait(s, rng)
      events[#events + 1] = { type = "golden_gone" }
    end
  elseif not gold.wait then
    gold.wait = goldenWait(s, rng)
  else
    gold.wait = gold.wait - 1
    if gold.wait <= 0 then
      spawnGolden(s, rng)
      events[#events + 1] = { type = "golden_spawn" }
    end
  end

  local fx = s.fx
  if fx.press > 0 then fx.press = fx.press - 1 end
  for i = #fx.pops, 1, -1 do
    local p = fx.pops[i]
    p.age = p.age + 1
    if p.age >= POP_TICKS then table.remove(fx.pops, i) end
  end
  if fx.noteLeft > 0 then
    fx.noteLeft = fx.noteLeft - 1
    if fx.noteLeft == 0 then fx.note = nil end
  end
  if #s.toasts > 0 then
    s.toastLeft = s.toastLeft - 1
    if s.toastLeft <= 0 then
      table.remove(s.toasts, 1)
      s.toastLeft = #s.toasts > 0 and TOAST_TICKS or 0
    end
  end
  if s.ui.confirm > 0 then s.ui.confirm = s.ui.confirm - 1 end

  if s.ticks % ACH_EVERY == 0 then checkAchievements(s, events) end
  s.score = floor(s.allTime)
  s.level = s.ascensions + 1
  return events
end

--- The clock from outside. now is the real time in ms (os.epoch("utc")): the plugin passes it after every tick. A long
-- gap since the last call bakes for the time away, at half speed and a day at most, and leaves s.away for the greeting.
function M.wake(s, now)
  local events = {}
  if type(now) ~= "number" or now ~= now then return events end
  local last = s.lastSeen
  s.lastSeen = now
  if type(last) ~= "number" then return events end
  local gap = now - last
  if gap < M.AWAY_MIN_MS then return events end
  local ms = min(gap, M.AWAY_CAP_MS)
  local earned = M.rawCps(s) * ms / 1000 * M.AWAY_RATE
  bake(s, earned)
  if earned > 0 then s.bestAway = max(s.bestAway, floor(ms / 1000)) end -- an empty bakery wasn't baking
  if gap >= 60000 or earned > 0 then
    local before = s.away
    s.away = {
      cookies = (before and before.cookies or 0) + earned, ms = (before and before.ms or 0) + gap,
      capped = gap > M.AWAY_CAP_MS or (before and before.capped) or false,
    }
  end
  events[#events + 1] = { type = "away", cookies = earned, ms = gap }
  checkAchievements(s, events)
  return events
end

-- ---------------------------------------------------------------- taps

local function tapCookie(s, action, events)
  local value = M.tapValue(s)
  bake(s, value)
  s.hand = min(LARGEST, s.hand + value)
  s.taps, s.runTaps = s.taps + 1, s.runTaps + 1
  local fx = s.fx
  fx.press = 1
  fx.popSeq = (fx.popSeq + 1) % 1000
  fx.pops[#fx.pops + 1] = { value = value, dx = tonumber(action.dx) or 0, dy = tonumber(action.dy) or 0, age = 0, seq = fx.popSeq }
  while #fx.pops > POPS_KEPT do table.remove(fx.pops, 1) end
  events[#events + 1] = { type = "tap", value = value }
  checkAchievements(s, events)
end

local function buyBuilding(s, i, n, events)
  if not BUILDINGS[i] or M.mystery(s, i) or i > M.shownBuildings(s) then return end
  local price = M.cost(s, i, n)
  if price ~= price or price == math.huge or s.cookies < price then
    events[#events + 1] = { type = "nope" }
    return
  end
  s.cookies = s.cookies - price
  s.owned[i] = s.owned[i] + n
  events[#events + 1] = { type = "buy", i = i, n = n }
  checkAchievements(s, events)
end

local function buyUpgrade(s, id, events)
  local u = data.UPGRADE_BY_ID[id]
  if not u or s.ups[id] or not unlocked(s, u) then return end
  if s.cookies < u.cost then
    events[#events + 1] = { type = "nope" }
    return
  end
  s.cookies = s.cookies - u.cost
  s.ups[id] = true
  s.upsBought = s.upsBought + 1
  events[#events + 1] = { type = "upgrade", id = id }
  checkAchievements(s, events)
end

local function catchGolden(s, events)
  local live = s.gold.live
  if not live then return end
  s.gold.live = nil
  s.gold.wait = nil -- input has no dice: the next tick rolls the wait for the next one
  s.goldenClicks = s.goldenClicks + 1
  local effect = live.effect
  if effect == "frenzy" then
    local ticks = effectTicks(s, FRENZY_TICKS)
    s.buff = { kind = "frenzy", left = ticks, total = ticks }
    note(s, "FRENZY! x" .. FRENZY_TIMES .. " cookies for " .. floor(ticks / 4) .. "s", "hi")
  elseif effect == "click" then
    local ticks = effectTicks(s, CLICK_TICKS)
    s.buff = { kind = "click", left = ticks, total = ticks }
    note(s, "CLICK FRENZY! taps x" .. CLICK_TIMES .. " for " .. floor(ticks / 4) .. "s", "hi")
  else
    local gain = min(s.cookies * 0.15, M.cps(s) * 900) + 13
    bake(s, gain)
    note(s, "LUCKY! +" .. M.fmtNice(gain) .. " cookies", "hi")
  end
  events[#events + 1] = { type = "golden", effect = effect }
  checkAchievements(s, events)
end

--- Start over with heavenly chips. Achievements, all-time counts and the chips stay.
local function ascend(s, events)
  local gain = M.pendingChips(s)
  if gain < 1 then
    events[#events + 1] = { type = "nope" }
    return
  end
  if s.ui.confirm <= 0 then
    s.ui.confirm = CONFIRM_TICKS
    events[#events + 1] = { type = "ask" }
    return
  end
  s.chips = s.chips + gain
  s.ascensions = s.ascensions + 1
  newRun(s)
  s.level = s.ascensions + 1
  toast(s, "ASCENDED", "+" .. M.fmt(gain) .. " heavenly chips: +" .. M.fmt(s.chips) .. "% forever")
  events[#events + 1] = { type = "ascend", chips = gain }
  checkAchievements(s, events)
end

local SCREENS = { bake = true, stats = true, ach = true, ascend = true, upgrades = true }

--- A tap, already turned into an action by the view.
function M.input(s, action)
  local events = {}
  if s.over or type(action) ~= "table" then return events end
  s.rev = (s.rev or 0) + 1
  local kind = action.kind
  if s.away then
    -- the greeting is up: any tap puts it away, and does nothing else
    s.away = nil
    s.heard[#s.heard + 1] = "dismiss"
    events[#events + 1] = { type = "dismiss" }
    return events
  end
  if kind == "tap" then
    tapCookie(s, action, events)
  elseif kind == "golden" then
    catchGolden(s, events)
  elseif kind == "buy" then
    local n = tonumber(action.n) or 1
    if n ~= 1 and n ~= 10 and n ~= 100 then n = 1 end
    buyBuilding(s, tonumber(action.i) or 0, n, events)
  elseif kind == "upgrade" then
    buyUpgrade(s, action.id, events)
  elseif kind == "mode" then
    local n = tonumber(action.n)
    for i, m in ipairs(MODES) do
      if m == n then s.ui.mode = i end
    end
    events[#events + 1] = { type = "ui" }
  elseif kind == "page" then
    s.ui.page = max(1, floor(tonumber(action.to) or 1))
    events[#events + 1] = { type = "page" }
  elseif kind == "list" then
    s.ui.list = max(1, floor(tonumber(action.to) or 1))
    events[#events + 1] = { type = "page" }
  elseif kind == "screen" then
    if SCREENS[action.name] then
      s.ui.screen, s.ui.list, s.ui.confirm, s.ui.inspect = action.name, 1, 0, nil
      events[#events + 1] = { type = "ui" }
    end
  elseif kind == "inspect" then
    if data.ACH_BY_ID[action.id] then
      s.ui.inspect = action.id
      events[#events + 1] = { type = "ui" }
    end
  elseif kind == "ascend" then
    ascend(s, events)
  end
  -- the shell drops what input returns, so the plugin hears these at the next tick; the cookie's own tap it plays at once
  for _, ev in ipairs(events) do
    if ev.type == "golden" then
      s.heard[#s.heard + 1] = "golden_" .. ev.effect
    elseif ev.type ~= "tap" then
      s.heard[#s.heard + 1] = ev.type
    end
  end
  while #s.heard > 8 do table.remove(s.heard, 1) end
  return events
end

--- What input did since the plugin last asked: event types, for sounds. Taking them clears them.
function M.takeHeard(s)
  local out = s.heard
  s.heard = {}
  return out
end

-- ---------------------------------------------------------------- the bot

--- How long a building takes to pay for itself, for the bot.
local function payback(s, i)
  local gain = M.eachCps(s, i)
  if gain <= 0 then return math.huge end
  return M.cost(s, i, 1) / gain
end

--- A simple baker: closes the greeting, catches golden cookies, buys upgrades, buys the building that pays back
-- soonest, ascends when that would at least double its chips, and otherwise taps the cookie.
function M.bot(s, rng)
  if s.over then return nil end
  if s.away then return { kind = "dismiss" } end
  if s.gold.live then return { kind = "golden" } end
  local pending = M.pendingChips(s)
  if pending >= max(1, s.chips) and s.allTime > 1e12 then
    if s.ui.screen ~= "ascend" then return { kind = "screen", name = "ascend" } end
    return { kind = "ascend" }
  end
  if s.ui.screen ~= "bake" then return { kind = "screen", name = "bake" } end
  if s.ui.mode ~= 1 then return { kind = "mode", n = 1 } end
  local ups = M.available(s)
  if ups[1] and ups[1].cost <= s.cookies then return { kind = "upgrade", id = ups[1].id } end
  local best, bestTime = nil, math.huge
  for i = 1, M.shownBuildings(s) do
    if not M.mystery(s, i) then
      local time = payback(s, i)
      if time < bestTime then best, bestTime = i, time end
    end
  end
  if best and M.cost(s, best, 1) <= s.cookies then return { kind = "buy", i = best, n = 1 } end
  local scatter = rng and rng() or 0.5
  return { kind = "tap", dx = floor(scatter * 9) - 4, dy = 0 }
end

-- ---------------------------------------------------------------- summaries

function M.summary(s)
  return M.fmt(s.cookies) .. " cookies, " .. M.fmtRate(M.rawCps(s)) .. " per second"
end

return M
