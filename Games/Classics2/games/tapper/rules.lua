-- games/tapper/rules.lua
-- Tapper. Pure: no screen, sound or files. See "Classics" in games/README.md.
-- Four bars, one above the other. The door is at x = DOOR_X and the taps at x = TAP_X, so customers walk right and beers
-- slide left. x and y are monitor cells on the board. A customer's x is their left edge, and their front is CUSTOMER_W on.
-- A tap on a bar is an order: the bartender runs there and pours. Orders wait in a short line, so fast fingers never lose
-- one. Going for an empty mug or a tip is an order too, the kind that doesn't pour, because a pour with no customer on
-- that bar smashes. Everything that smashes costs a life, as in the original.

local M = {
  WIDTH = 120, HEIGHT = 66, BARS = 4, STAGE_H = 10, LANE_H = 14,
  DOOR_X = 2, TAP_X = 104, CUSTOMER_W = 8, MAX_ORDERS = 3,
  SERVE = 50, CATCH = 100, TIP = 1500, CLEAR = 1000,
}

local BARS, DOOR_X, TAP_X, CUSTOMER_W, MAX_ORDERS = M.BARS, M.DOOR_X, M.TAP_X, M.CUSTOMER_W, M.MAX_ORDERS
local END_X = TAP_X - CUSTOMER_W    -- a customer's x here is at the taps, and that smashes the game
local DOOR_EDGE = DOOR_X + 6        -- a beer gets this far with nobody to drink it, and goes through the door
local STEP = 3                      -- cells in one of a customer's shuffling steps

local LIVES = 3
local WALK = 7                     -- cells a step along a bar
local POUR_TICKS = 3                -- steps to fill a mug
local REACH = 2                     -- how close the bartender has to get to take a mug or a tip
local BEER_SPEED = 7                -- cells a step
local MUG_SPEED = 3
local SHOVE_SPEED = 5
local START_WALK = 1.1              -- a customer's cells a step at level 1: under nine seconds down the bar
local WALK_STEP = 0.16              -- added each level
local MAX_WALK = 2.6
local START_SHOVE = 34              -- how far a beer pushes a customer back
local MIN_SHOVE = 22
local SHOVE_STEP = 2
local START_DRINK = 14              -- steps a customer drinks for
local MIN_DRINK = 6
local START_CUSTOMERS = 8           -- customers in the first wave
local MORE_CUSTOMERS = 3            -- and how many more each wave
local START_GAP = 18                -- steps between arrivals
local MIN_GAP = 6
local GAP_STEP = 2
local TIP_ODDS = 0.15               -- the chance a customer leaves a tip on taking a beer
local TIP_TICKS = 60                -- how long a tip stays on the bar
local DANCE_TICKS = 25              -- how long the dancers hold the customers' eyes
local READY_TICKS = 12
local LIFE_TICKS = 16               -- the wreck stays on show this long
local CLEAR_TICKS = 16
local NOTE_TICKS = 8
local LOOKS = 4                     -- kinds of customer, for the view

local BOT_REST = 1                  -- steps the bot waits after each order, as a hand has to
local BOT_LAPSE = 0.012             -- the chance per order, per level, that its mind wanders
local BOT_LAPSE_TICKS = 18          -- and for how long, so sooner or later a bar gets away from it
local BOT_SPARE = 2                 -- extra steps it leaves itself to get to a mug
local TIP_SAFE = 40                 -- steps every customer must be from the taps before the bot goes for a tip

M.END_X, M.DOOR_EDGE, M.STEP, M.LIVES, M.WALK = END_X, DOOR_EDGE, STEP, LIVES, WALK
M.POUR_TICKS, M.REACH, M.BEER_SPEED, M.MUG_SPEED, M.SHOVE_SPEED = POUR_TICKS, REACH, BEER_SPEED, MUG_SPEED, SHOVE_SPEED
M.TIP_TICKS, M.DANCE_TICKS, M.READY_TICKS, M.LIFE_TICKS, M.CLEAR_TICKS = TIP_TICKS, DANCE_TICKS, READY_TICKS, LIFE_TICKS, CLEAR_TICKS
M.MAX_WALK, M.MIN_SHOVE, M.MIN_GAP, M.LOOKS = MAX_WALK, MIN_SHOVE, MIN_GAP, LOOKS

--- A customer's cells a step at this level, before their own pace.
function M.walkFor(level) return math.min(MAX_WALK, START_WALK + WALK_STEP * (level - 1)) end

--- How far a beer pushes a customer back at this level.
function M.shoveFor(level) return math.max(MIN_SHOVE, START_SHOVE - SHOVE_STEP * (level - 1)) end

function M.drinkFor(level) return math.max(MIN_DRINK, START_DRINK - (level - 1)) end

function M.customersFor(level) return START_CUSTOMERS + MORE_CUSTOMERS * (level - 1) end

function M.gapFor(level) return math.max(MIN_GAP, START_GAP - GAP_STEP * (level - 1)) end

--- Clear the bars. The bartender keeps his bar, back at the taps.
local function clearBars(s)
  s.customers, s.beers, s.mugs, s.tips, s.orders = {}, {}, {}, {}, {}
  s.man = { bar = s.man and s.man.bar or 2, x = TAP_X, dir = 0 }
  s.pouring, s.dance, s.nextIn, s.crash = 0, 0, 1, nil
end

--- A fresh game, with a moment to get ready.
function M.new()
  local s = {
    score = 0, level = 1, lives = LIVES, over = false, frame = 0,
    waiting = M.customersFor(1), pause = READY_TICKS, after = "ready", notes = {},
  }
  clearBars(s)
  return s
end

--- A player's input: { kind = "pour", bar = n }, or { kind = "go", bar = n, x = x } to fetch without pouring. Each one joins
-- the line of orders. Taps made during READY count, and taps made while the wreck is on show don't.
function M.input(s, action)
  if s.over or s.after == "life" or s.after == "level" then return end
  if #s.orders >= MAX_ORDERS then return end
  local bar = action.bar
  if type(bar) ~= "number" or bar < 1 or bar > BARS or bar ~= math.floor(bar) then return end
  if action.kind == "pour" then
    s.orders[#s.orders + 1] = { kind = "pour", bar = bar }
  elseif action.kind == "go" and type(action.x) == "number" then
    s.orders[#s.orders + 1] = { kind = "go", bar = bar, x = math.max(DOOR_EDGE, math.min(TAP_X, action.x)) }
  end
end

--- The thing to go and fetch on this bar at this x, if a tap there is aimed at one: the nearest mug or tip within hit.
function M.fetchAt(s, bar, x, hit)
  local best, bestGap
  local function consider(list)
    for _, item in ipairs(list) do
      local gap = math.abs(item.x - x)
      if item.bar == bar and gap <= hit and (not best or gap < bestGap) then best, bestGap = item, gap end
    end
  end
  consider(s.mugs)
  consider(s.tips)
  return best
end

local function note(s, text, bar, x)
  s.notes[#s.notes + 1] = { text = text, bar = bar, x = x, left = NOTE_TICKS }
end

--- Something smashed. One life a time: whatever else breaks during the same step is part of the same wreck.
local function smash(s, events, what, bar, x)
  if s.after or s.over then return end
  s.lives = s.lives - 1
  s.crash = { what = what, bar = bar, x = x }
  events[#events + 1] = { type = "smash", what = what, bar = bar, x = x }
  if s.lives <= 0 then
    s.over = true
  else
    s.after, s.pause = "life", LIFE_TICKS
  end
end

local function catchMug(s, events, m)
  s.score = s.score + M.CATCH
  note(s, "+" .. M.CATCH, m.bar, m.x)
  events[#events + 1] = { type = "catch", bar = m.bar }
end

local function takeTip(s, events, tip)
  s.score = s.score + M.TIP
  s.dance = DANCE_TICKS
  note(s, "+" .. M.TIP, tip.bar, tip.x)
  events[#events + 1] = { type = "tip", bar = tip.bar }
end

--- Take every mug and tip on the bartender's bar between lo and hi, the stretch he just covered.
local function collect(s, events, lo, hi)
  local bar = s.man.bar
  local mugs, tips = {}, {}
  for _, m in ipairs(s.mugs) do
    if m.bar == bar and m.x >= lo - REACH and m.x <= hi + REACH then catchMug(s, events, m) else mugs[#mugs + 1] = m end
  end
  for _, tip in ipairs(s.tips) do
    if tip.bar == bar and tip.x >= lo - REACH and tip.x <= hi + REACH then takeTip(s, events, tip) else tips[#tips + 1] = tip end
  end
  s.mugs, s.tips = mugs, tips
end

local function fillMug(s, events, order)
  s.pouring = s.pouring + 1
  if s.pouring < POUR_TICKS then return end
  s.pouring = 0
  s.beers[#s.beers + 1] = { bar = order.bar, x = TAP_X }
  table.remove(s.orders, 1)
  events[#events + 1] = { type = "pour", bar = order.bar }
end

--- The bartender works on the order at the head of the line, and anything he passes on the way he takes.
local function moveMan(s, _, events)
  local man = s.man
  local order = s.orders[1]
  man.dir = 0
  if not order then
    collect(s, events, man.x, man.x)
    return
  end
  if man.bar ~= order.bar then
    man.bar = man.bar + (order.bar > man.bar and 1 or -1)
    man.x = TAP_X
    s.pouring = 0
    collect(s, events, man.x, man.x)
    return
  end
  local want = order.kind == "pour" and TAP_X or order.x
  if man.x ~= want then
    local from = man.x
    man.dir = want > from and 1 or -1
    man.x = want > from and math.min(want, from + WALK) or math.max(want, from - WALK)
    collect(s, events, math.min(from, man.x), math.max(from, man.x))
    if man.x == want and order.kind == "go" then table.remove(s.orders, 1) end
    return
  end
  collect(s, events, man.x, man.x)
  if order.kind == "pour" then fillMug(s, events, order) else table.remove(s.orders, 1) end
end

--- Pushed out of the door: served, and gone.
local function serve(s, events, c)
  s.score = s.score + M.SERVE
  note(s, "+" .. M.SERVE, c.bar, DOOR_EDGE)
  events[#events + 1] = { type = "served", bar = c.bar }
end

--- A customer finishes drinking: the empty goes back down the bar, and they want another.
local function finishDrink(s, events, c)
  c.state, c.budget = "walk", 0
  s.mugs[#s.mugs + 1] = { bar = c.bar, x = c.x + CUSTOMER_W }
  events[#events + 1] = { type = "empty", bar = c.bar }
end

--- One customer's step. Returns false if they've left.
local function moveCustomer(s, events, c)
  if c.state == "shoved" then
    c.x = c.x - SHOVE_SPEED
    c.shove = c.shove - SHOVE_SPEED
    if c.x <= DOOR_X then
      serve(s, events, c)
      return false
    end
    if c.shove <= 0 then c.state, c.left = "drink", M.drinkFor(s.level) end
  elseif c.state == "drink" then
    c.left = c.left - 1
    if c.left <= 0 then finishDrink(s, events, c) end
  elseif s.dance <= 0 then
    c.budget = c.budget + M.walkFor(s.level) * c.pace
    if c.budget >= STEP then
      c.budget = c.budget - STEP
      c.x = c.x + STEP
      c.stride = not c.stride
    end
    if c.x >= END_X then smash(s, events, "customer", c.bar, TAP_X) end
  end
  return true
end

local function moveCustomers(s, _, events)
  local kept = {}
  for _, c in ipairs(s.customers) do
    if moveCustomer(s, events, c) then kept[#kept + 1] = c end
  end
  s.customers = kept
end

--- The customer a beer gets to as it goes from x to nx: the first one walking, the nearest to the taps. A customer can
-- have just stepped past a beer's old x, so a step's worth is allowed behind it.
local function drinkerFor(s, bar, x, nx)
  local best
  for _, c in ipairs(s.customers) do
    local front = c.x + CUSTOMER_W
    if c.bar == bar and c.state == "walk" and front >= nx and front <= x + STEP and (not best or c.x > best.x) then best = c end
  end
  return best
end

--- A beer reaches a customer: they stop, it shoves them back, and perhaps they leave a tip where they stood.
local function takeBeer(s, events, c, rng)
  c.state, c.shove = "shoved", M.shoveFor(s.level)
  events[#events + 1] = { type = "drink", bar = c.bar }
  if rng() < TIP_ODDS then
    s.tips[#s.tips + 1] = { bar = c.bar, x = c.x + CUSTOMER_W, left = TIP_TICKS }
    events[#events + 1] = { type = "tipLeft", bar = c.bar }
  end
end

local function moveBeers(s, rng, events)
  local kept = {}
  for _, b in ipairs(s.beers) do
    local nx = b.x - BEER_SPEED
    local c = drinkerFor(s, b.bar, b.x, nx)
    if c then
      takeBeer(s, events, c, rng)
    elseif nx <= DOOR_EDGE then
      smash(s, events, "beer", b.bar, DOOR_EDGE)
    else
      b.x = nx
      kept[#kept + 1] = b
    end
  end
  s.beers = kept
end

--- Empties come back slower than beers go out. The bartender has to be on the bar to take one, and it passes behind him if
-- he's walked out past it.
local function moveMugs(s, _, events)
  local man = s.man
  local kept = {}
  for _, m in ipairs(s.mugs) do
    local nx = m.x + MUG_SPEED
    if man.bar == m.bar and man.x + REACH >= m.x and man.x - REACH <= nx then
      catchMug(s, events, m)
    elseif nx >= TAP_X then
      smash(s, events, "mug", m.bar, TAP_X)
    else
      m.x = nx
      kept[#kept + 1] = m
    end
  end
  s.mugs = kept
end

local function ageTips(s)
  local kept = {}
  for _, tip in ipairs(s.tips) do
    tip.left = tip.left - 1
    if tip.left > 0 then kept[#kept + 1] = tip end
  end
  s.tips = kept
  s.dance = math.max(0, s.dance - 1)
end

--- A bar with room at its door, starting from a random one, so two customers don't come through as one.
local function freeBar(s, rng)
  local start = rng(BARS)
  for i = 0, BARS - 1 do
    local bar = (start + i - 1) % BARS + 1
    local free = true
    for _, c in ipairs(s.customers) do
      if c.bar == bar and c.x < DOOR_X + CUSTOMER_W + 2 then free = false end
    end
    if free then return bar end
  end
  return start
end

--- The door lets in the next customer when it's time. Nobody comes in while the dancers are on.
local function letIn(s, rng, events)
  if s.waiting <= 0 or s.dance > 0 then return end
  s.nextIn = s.nextIn - 1
  if s.nextIn > 0 then return end
  s.waiting = s.waiting - 1
  s.nextIn = math.max(2, math.floor(M.gapFor(s.level) * (0.6 + 0.8 * rng())))
  s.customers[#s.customers + 1] = {
    bar = freeBar(s, rng), x = DOOR_X, state = "walk", budget = 0, pace = 0.85 + 0.3 * rng(), look = rng(LOOKS), stride = false,
  }
  events[#events + 1] = { type = "enter" }
end

local function checkClear(s, _, events)
  if s.waiting > 0 or #s.customers > 0 then return end
  s.score = s.score + M.CLEAR
  s.after, s.pause = "level", CLEAR_TICKS
  events[#events + 1] = { type = "clear", level = s.level }
end

local PHASES = { moveMan, moveCustomers, moveBeers, moveMugs, letIn, checkClear }

--- A pause ends: the game carries on from what it was waiting for.
local function resume(s, events)
  local after = s.after
  s.after = nil
  if after == "life" then
    s.waiting = s.waiting + #s.customers
    clearBars(s)
    events[#events + 1] = { type = "again" }
  elseif after == "level" then
    s.level = s.level + 1
    s.waiting = M.customersFor(s.level)
    clearBars(s)
    s.after, s.pause = "ready", READY_TICKS
    events[#events + 1] = { type = "level", level = s.level }
  end
end

local function ageNotes(s)
  local kept = {}
  for _, n in ipairs(s.notes) do
    n.left = n.left - 1
    if n.left > 0 then kept[#kept + 1] = n end
  end
  s.notes = kept
end

--- One step of the clock. Returns what happened, for sound.
function M.tick(s, rng)
  if s.over then return {} end
  s.frame = s.frame + 1
  ageNotes(s)
  local events = {}
  if s.pause > 0 then
    s.pause = s.pause - 1
    if s.pause == 0 then resume(s, events) end
    return events
  end
  ageTips(s)
  for _, phase in ipairs(PHASES) do
    phase(s, rng, events)
    if s.after or s.over then break end
  end
  return events
end

-- ---------------------------------------------------------------- the bot

--- Steps until the bartender could be standing at the taps of this bar. He runs a bar a step.
local function stepsTo(s, bar)
  local bars = math.abs(s.man.bar - bar)
  if bars > 0 then return bars end
  return math.ceil((TAP_X - s.man.x) / WALK)
end

--- The empty that needs him soonest, if one needs him now: he'd miss it after one more pour. He only has to wait for one
-- that's coming to his own bar, ahead of him.
local function urgentMug(s)
  local best, bestLeft
  for _, m in ipairs(s.mugs) do
    local left = (TAP_X - m.x) / MUG_SPEED
    local waiting = m.bar == s.man.bar and m.x <= s.man.x
    if left <= stepsTo(s, m.bar) + POUR_TICKS + BOT_SPARE and (not best or left < bestLeft) then
      if not waiting or left <= POUR_TICKS + BOT_SPARE then best, bestLeft = m, left end
    end
  end
  return best
end

--- The bar most in need of a beer, and how many steps its customer has left. A beer already on its way is counted against
-- the customers it will reach, so a bar is never sent one it can't use.
local function thirstiestBar(s)
  local walking, sent = {}, {}
  for bar = 1, BARS do walking[bar], sent[bar] = {}, 0 end
  for _, c in ipairs(s.customers) do
    if c.state == "walk" then table.insert(walking[c.bar], c.x) end
  end
  for _, b in ipairs(s.beers) do sent[b.bar] = sent[b.bar] + 1 end
  for _, order in ipairs(s.orders) do
    if order.kind == "pour" then sent[order.bar] = sent[order.bar] + 1 end
  end
  local best, bestLeft
  for bar = 1, BARS do
    table.sort(walking[bar], function(a, b) return a > b end)
    local x = walking[bar][sent[bar] + 1]
    if x then
      local left = (END_X - x) / M.walkFor(s.level)
      if not best or left < bestLeft then best, bestLeft = bar, left end
    end
  end
  return best, bestLeft
end

--- The best order right now, or nil. This is the bot with nothing wrong with it. It never pours onto a bar that can't drink.
function M.plan(s)
  if s.over or s.after == "life" or s.after == "level" or #s.orders > 0 then return nil end
  local mug = urgentMug(s)
  if mug then
    if mug.bar == s.man.bar and mug.x <= s.man.x then return nil end
    return { kind = "go", bar = mug.bar, x = TAP_X }
  end
  local bar, left = thirstiestBar(s)
  local tip = s.tips[1]
  if tip and (not bar or left > TIP_SAFE) then return { kind = "go", bar = tip.bar, x = tip.x } end
  if bar then return { kind = "pour", bar = bar } end
  if s.man.x ~= TAP_X then return { kind = "go", bar = s.man.bar, x = TAP_X } end
  return nil
end

--- A plain player for the idle screen and tests: the plan, with a hand that takes a moment and a mind that wanders more
-- each level, so sooner or later a bar gets away from it and the idle screen moves on.
function M.bot(s, rng)
  if (s.botRest or 0) > 0 then
    s.botRest = s.botRest - 1
    return nil
  end
  local action = M.plan(s)
  if not action then return nil end
  if rng() < BOT_LAPSE * s.level then
    s.botRest = BOT_LAPSE_TICKS
    return nil
  end
  s.botRest = BOT_REST
  return action
end

return M
